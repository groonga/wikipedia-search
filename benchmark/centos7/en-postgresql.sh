#!/bin/bash

set -u

LANG=C

n_load_tries=1
n_create_index_tries=1
n_search_tries=5

pg_version=9.6
pg_version_short=96

data=en-all-pages.csv

script_dir=$(cd "$(dirname $0)"; pwd)
base_dir="${script_dir}/../.."
config_dir="${base_dir}/config/sql"
data_dir="${base_dir}/data/csv"
benchmark_dir="${base_dir}/benchmark"

pgroonga_db="benchmark_pgroonga"
pg_trgm_db="benchmark_pg_trgm"
textsearch_db="benchmark_textsearch"

run()
{
  "$@"
  if test $? -ne 0; then
    echo "Failed $@"
    exit 1
  fi
}

show_environment()
{
  echo "CPU:"
  cat /proc/cpuinfo

  echo "Memory:"
  free
}

ensure_data()
{
  if [ -f "${data_dir}/${data}" ]; then
    return
  fi

  run sudo -H yum install -y epel-release
  run sudo -H yum install -y wget pxz
  run mkdir -p "${data_dir}"
  cd "${data_dir}"
  if [ ! -f "${data}.xz" ]; then
    run wget --no-verbose http://packages.groonga.org/tmp/${data}.xz
  fi
  run pxz --keep --decompress ${data}.xz
  cd -
}

setup_postgresql_repository()
{
  os_version=$(run rpm -qf --queryformat="%{VERSION}" /etc/redhat-release)
  os_arch=$(run rpm -qf --queryformat="%{ARCH}" /etc/redhat-release)
  run sudo rpm -Uvh \
      https://download.postgresql.org/pub/repos/yum/${pg_version}/redhat/rhel-7-x86_64/pgdg-centos${pg_version_short}-${pg_version}-3.noarch.rpm
}

setup_groonga_repository()
{
  run sudo rpm -Uvh \
      http://packages.groonga.org/centos/groonga-release-1.1.0-1.noarch.rpm
}

install_pgroonga()
{
  run sudo yum install -y postgresql${pg_version_short}-pgroonga
}

install_pg_trgm()
{
  run sudo yum install -y postgresql${pg_version_short}-contrib
}

install_textsearch()
{
  :
}

setup_postgresql()
{
  run sudo -H \
      env PGSETUP_INITDB_OPTIONS="--locale=C --encoding=UTF-8" \
      /usr/pgsql-${pg_version}/bin/postgresql${pg_version_short}-setup initdb
  run sudo -H systemctl enable postgresql-${pg_version}
  run sudo -H systemctl start postgresql-${pg_version}
}

setup_benchmark_db_pgroonga()
{
  run sudo -u postgres -H psql \
      --command "DROP DATABASE IF EXISTS ${pgroonga_db}"
  run sudo -u postgres -H psql \
      --command "CREATE DATABASE ${pgroonga_db}"
  run sudo -u postgres -H psql -d ${pgroonga_db} \
      --command "CREATE EXTENSION pgroonga"
}

setup_benchmark_db_pg_trgm()
{
  run sudo -u postgres -H psql \
      --command "DROP DATABASE IF EXISTS ${pg_trgm_db}"
  run sudo -u postgres -H psql \
      --command "CREATE DATABASE ${pg_trgm_db}"
  run sudo -u postgres -H psql -d ${pg_trgm_db} \
      --command "CREATE EXTENSION pg_trgm"
}

setup_benchmark_db_textsearch()
{
  run sudo -u postgres -H psql \
      --command "DROP DATABASE IF EXISTS ${textsearch_db}"
  run sudo -u postgres -H psql \
      --command "CREATE DATABASE ${textsearch_db}"
}

setup_benchmark_db()
{
  setup_benchmark_db_pgroonga
  setup_benchmark_db_pg_trgm
  setup_benchmark_db_textsearch
}

database_oid()
{
  sudo -u postgres -H psql \
       --command "SELECT datid FROM pg_stat_database WHERE datname = '$1'" | \
    head -3 | \
    tail -1 | \
    sed -e 's/ *//g'
}

load_data_pgroonga()
{
  run sudo -H systemctl restart postgresql-${pg_version}

  echo "PGroonga: data: load:"
  run sudo -u postgres -H psql -d ${pgroonga_db} < \
      "${config_dir}/schema.postgresql.sql"
  run sudo -u postgres -H psql -d ${pgroonga_db} \
      --command "\\timing" \
      --command "COPY wikipedia FROM '${data_dir}/${data}' WITH CSV ENCODING 'utf8'"

  run sudo -H systemctl restart postgresql-${pg_version}

  echo "PGroonga: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pgroonga_db})/*"
}

load_data_pg_trgm()
{
  run sudo -H systemctl restart postgresql-${pg_version}

  echo "pg_trgm: data: load:"
  run sudo -u postgres -H psql -d ${pg_trgm_db} < \
      "${config_dir}/schema.postgresql.sql"
  run sudo -u postgres -H psql -d ${pg_trgm_db} \
      --command "\\timing" \
      --command "COPY wikipedia FROM '${data_dir}/${data}' WITH CSV ENCODING 'utf8'"

  run sudo -H systemctl restart postgresql-${pg_version}

  echo "pg_trgm: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pg_trgm_db})/*"
}

load_data_textsearch()
{
  run sudo -H systemctl restart postgresql-${pg_version}

  echo "textsearch: data: load:"
  run sudo -u postgres -H psql -d ${textsearch_db} < \
      "${config_dir}/schema.postgresql.sql"
  run sudo -u postgres -H psql -d ${textsearch_db} \
      --command "\\timing" \
      --command "COPY wikipedia FROM '${data_dir}/${data}' WITH CSV ENCODING 'utf8'"

  run sudo -H systemctl restart postgresql-${pg_version}

  echo "textsearch: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${textsearch_db})/*"
}

load_data()
{
  load_data_pgroonga
  load_data_pg_trgm
  load_data_textsearch
}

benchmark_create_index_pgroonga()
{
  run sudo -H systemctl restart postgresql-${pg_version}

  for i in $(seq ${n_load_tries}); do
    echo "PGroonga: create index: ${i}:"
    run sudo -u postgres -H psql -d ${pgroonga_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_pgroonga"
    run sudo -u postgres -H psql -d ${pgroonga_db} \
        --command "\\timing" \
        --command "\\i ${config_dir}/indexes.pgroonga.sql"
    if [ ${i} -eq 1 ]; then
      run sudo -H systemctl restart postgresql-${pg_version}
      echo "PGroonga: create index: size:"
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pgroonga_db})/pgrn*"
    fi
  done
}

benchmark_create_index_pg_trgm()
{
  run sudo -H systemctl restart postgresql-${pg_version}

  for i in $(seq ${n_load_tries}); do
    echo "pg_trgm: create index: ${i}:"
    run sudo -u postgres -H psql -d ${pg_trgm_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_pg_trgm"
    run sudo -u postgres -H psql -d ${pg_trgm_db} \
        --command "\\timing" \
        --command "\\i ${config_dir}/indexes.pg_trgm.sql"
    if [ ${i} -eq 1 ]; then
      run sudo -H systemctl restart postgresql-${pg_version}
      echo "pg_trgm: create index: size:"
      pg_trgm_data_path=$(sudo -u postgres -H psql -d ${pg_trgm_db} \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_pg_trgm'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/${pg_trgm_data_path}"
    fi
  done
}

benchmark_create_index_textsearch()
{
  run sudo -H systemctl restart postgresql-${pg_version}

  for i in $(seq ${n_load_tries}); do
    echo "textsearch: create index: ${i}:"
    run sudo -u postgres -H psql -d ${textsearch_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_textsearch"
    run sudo -u postgres -H psql -d ${textsearch_db} \
        --command "\\timing" \
        --command "\\i ${config_dir}/indexes.textsearch.sql"
    if [ ${i} -eq 1 ]; then
      run sudo -H systemctl restart postgresql-${pg_version}
      echo "textsearch: create index: size:"
      textsearch_data_path=$(sudo -u postgres -H psql -d ${textsearch_db} \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_textsearch'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/${textsearch_data_path}"
    fi
  done
}

benchmark_create_index()
{
  benchmark_create_index_pgroonga
  benchmark_create_index_pg_trgm
  benchmark_create_index_textsearch
}

benchmark_search_pgroonga()
{
  work_mem_size='64MB'
  work_mem="SET work_mem = '${work_mem_size}';"
  enable_seqscan="SET enable_seqscan = no;"
  cat "${benchmark_dir}/en-search-words.list" | while read search_word; do
    commands=()
    commands+=("--command" "${work_mem}")
    commands+=("--command" "${enable_seqscan}")
    commands+=("--command" "\\timing")
    for i in $(seq ${n_search_tries}); do
      where="text @@ '${search_word}'"
      commands+=("--command" "SELECT COUNT(*) FROM wikipedia WHERE ${where}")
    done
    echo "PGroonga: search: work_mem(${work_mem_size}): ${where}:"
    run sudo -u postgres -H psql -d ${pgroonga_db} "${commands[@]}"
  done
}

benchmark_search_pg_trgm()
{
  work_mem_size='64MB'
  work_mem="SET work_mem = '${work_mem_size}';"
  enable_seqscan="SET enable_seqscan = no;"
  cat "${benchmark_dir}/en-search-words.list" | while read search_word; do
    commands=()
    commands+=("--command" "${work_mem}")
    commands+=("--command" "${enable_seqscan}")
    commands+=("--command" "\\timing")
    for i in $(seq ${n_search_tries}); do
      where="text LIKE '%${search_word}%'"
      where=$(echo $where | sed -e "s/ OR /%' OR text LIKE '%/g")
      commands+=("--command" "SELECT COUNT(*) FROM wikipedia WHERE ${where}")
    done
    echo "pg_trgm: search: work_mem(${work_mem_size}): ${where}"
    run sudo -u postgres -H psql -d ${pg_trgm_db} "${commands[@]}"
  done
}

benchmark_search_textsearch()
{
  work_mem_size='64MB'
  work_mem="SET work_mem = '${work_mem_size}';"
  enable_seqscan="SET enable_seqscan = no;"
  cat "${benchmark_dir}/en-search-words.list" | while read search_word; do
    commands=()
    commands+=("--command" "${work_mem}")
    commands+=("--command" "${enable_seqscan}")
    commands+=("--command" "\\timing")
    for i in $(seq ${n_search_tries}); do
      target="to_tsvector('english', text)"
      query="to_tsquery('english', '$(echo ${search_word} | sed -e 's/ OR / | /g')')"
      where="${target} @@ ${query}"
      commands+=("--command" "SELECT COUNT(*) FROM wikipedia WHERE ${where}")
    done
    echo "textsearch: search: work_mem(${work_mem_size}): ${where}"
    run sudo -u postgres -H psql -d ${textsearch_db} "${commands[@]}"
  done
}

benchmark_search()
{
  benchmark_search_pgroonga
  benchmark_search_pg_trgm
  benchmark_search_textsearch
}

show_environment

ensure_data

setup_postgresql_repository
setup_groonga_repository
install_pgroonga
install_pg_trgm
install_textsearch

setup_postgresql
setup_benchmark_db
load_data

benchmark_create_index

benchmark_search
