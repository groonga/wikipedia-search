#!/bin/bash

set -u

if [ $# -ne 2 ]; then
  echo "Usage: $0 LANGUAGE DATA_SIZE"
  echo " e.g.: $0 en partial"
  echo " e.g.: $0 ja partial"
  echo " e.g.: $0 en all"
  echo " e.g.: $0 ja all"
  exit 1
fi

language="$1"
data_size="$2"

LANG=C

n_load_tries=1
n_create_index_tries=1
n_search_tries=5

work_mem_size='256MB'
maintenance_work_mem_size='2GB'

pg_version=9.6
pg_version_short=96

pg_bigm_version=1.2-20161011

data="${language}-${data_size}-pages.csv"
word_list="${language}-search-words.list"

script_dir=$(cd "$(dirname $0)"; pwd)
base_dir="${script_dir}/../.."
config_dir="${base_dir}/config/sql"
data_dir="${base_dir}/data/csv"
benchmark_dir="${base_dir}/benchmark"

pgroonga_db="benchmark_pgroonga_${language}"
pg_bigm_db="benchmark_pg_bigm_${language}"
pg_trgm_db="benchmark_pg_trgm_${language}"
textsearch_db="benchmark_textsearch_${language}"

targets=("pgroonga")
if [ "${language}" = "ja" ]; then
  targets+=("pg_bigm")
else
  targets+=("pg_trgm")
  targets+=("textsearch")
fi

run()
{
  "$@"
  if test $? -ne 0; then
    echo "Failed $@"
    exit 1
  fi
}

setup_kernel()
{
  run sudo sysctl -w vm.overcommit_memory=1
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

install_pg_bigm()
{
  run sudo yum install -y postgresql${pg_version_short}-devel gcc
  pg_bigm_base_name=pg_bigm-${pg_bigm_version}
  run wget -O ${pg_bigm_base_name}.tar.gz \
      https://ja.osdn.net/projects/pgbigm/downloads/66565/${pg_bigm_base_name}.tar.gz/
  run tar xvf ${pg_bigm_base_name}.tar.gz
  run cd ${pg_bigm_base_name}
  run env PATH=/usr/pgsql-${pg_version}/bin:$PATH make USE_PGXS=1
  run sudo env PATH=/usr/pgsql-${pg_version}/bin:$PATH make USE_PGXS=1 install
  run cd ..
}

install_textsearch()
{
  :
}

install_extensions()
{
  for target in "${targets[@]}"; do
    install_${target}
  done
}

restart_postgresql()
{
  if type systemctl 2>&1 > /dev/null; then
    run sudo -H systemctl restart postgresql-${pg_version}
  else
    run sudo -H service postgresql-${pg_version} restart
  fi
}

setup_postgresql()
{
  if type systemctl > /dev/null 2>&1; then
    run sudo -H \
        env PGSETUP_INITDB_OPTIONS="--locale=C --encoding=UTF-8" \
        /usr/pgsql-${pg_version}/bin/postgresql${pg_version_short}-setup initdb
    run sudo -H systemctl start postgresql-${pg_version}
  else
    run sudo -H service postgresql-${pg_version} initdb C
    run sudo -H service postgresql-${pg_version} start
  fi
}

setup_benchmark_db_pgroonga()
{
  run sudo -u postgres -H psql --echo-queries \
      --command "DROP DATABASE IF EXISTS ${pgroonga_db}"
  run sudo -u postgres -H psql --echo-queries \
      --command "CREATE DATABASE ${pgroonga_db}"
  run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} \
      --command "CREATE EXTENSION pgroonga"
}

setup_benchmark_db_pg_bigm()
{
  run sudo -u postgres -H psql --echo-queries \
      --command "DROP DATABASE IF EXISTS ${pg_bigm_db}"
  run sudo -u postgres -H psql --echo-queries \
      --command "CREATE DATABASE ${pg_bigm_db}"
  run sudo -u postgres -H psql --echo-queries -d ${pg_bigm_db} \
      --command "CREATE EXTENSION pg_bigm"
}

setup_benchmark_db_pg_trgm()
{
  run sudo -u postgres -H psql --echo-queries \
      --command "DROP DATABASE IF EXISTS ${pg_trgm_db}"
  run sudo -u postgres -H psql --echo-queries \
      --command "CREATE DATABASE ${pg_trgm_db}"
  run sudo -u postgres -H psql --echo-queries -d ${pg_trgm_db} \
      --command "CREATE EXTENSION pg_trgm"
}

setup_benchmark_db_textsearch()
{
  run sudo -u postgres -H psql --echo-queries \
      --command "DROP DATABASE IF EXISTS ${textsearch_db}"
  run sudo -u postgres -H psql --echo-queries \
      --command "CREATE DATABASE ${textsearch_db}"
}

setup_benchmark_db()
{
  for target in "${targets[@]}"; do
    setup_benchmark_db_${target}
  done
}

database_oid()
{
  sudo -u postgres -H psql --echo-queries \
       --command "SELECT datid FROM pg_stat_database WHERE datname = '$1'" | \
    head -3 | \
    tail -1 | \
    sed -e 's/ *//g'
}

load_data_pgroonga()
{
  restart_postgresql

  echo "PGroonga: data: load:"
  run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} < \
      "${config_dir}/schema.postgresql.sql"
  run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} \
      --command "\\timing" \
      --command "COPY wikipedia FROM '${data_dir}/${data}' WITH CSV ENCODING 'utf8'"

  restart_postgresql

  echo "PGroonga: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pgroonga_db})/*"

  echo "PGroonga: data: load: statistics"
select="SELECT
    AVG(char_length(title)) as title_char_length_avg,
    MIN(char_length(title)) as title_char_length_min,
    MAX(char_length(title)) as title_char_length_max,
    AVG(octet_length(title)) as title_byte_length_avg,
    MIN(octet_length(title)) as title_byte_length_min,
    MAX(octet_length(title)) as title_byte_length_max,
    AVG(char_length(text)) as text_char_length_avg,
    MIN(char_length(text)) as text_char_length_min,
    MAX(char_length(text)) as text_char_length_max,
    AVG(octet_length(text)) as text_byte_length_avg,
    MIN(octet_length(text)) as text_byte_length_min,
    MAX(octet_length(text)) as text_byte_length_max
  FROM
    wikipedia;"
  run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} \
      --command "\\timing" \
      --command "${select}"
}

load_data_pg_trgm()
{
  restart_postgresql

  echo "pg_trgm: data: load:"
  run sudo -u postgres -H psql --echo-queries -d ${pg_trgm_db} < \
      "${config_dir}/schema.postgresql.sql"
  run sudo -u postgres -H psql --echo-queries -d ${pg_trgm_db} \
      --command "\\timing" \
      --command "COPY wikipedia FROM '${data_dir}/${data}' WITH CSV ENCODING 'utf8'"

  restart_postgresql

  echo "pg_trgm: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pg_trgm_db})/*"
}

load_data_pg_bigm()
{
  restart_postgresql

  echo "pg_bigm: data: load:"
  run sudo -u postgres -H psql --echo-queries -d ${pg_bigm_db} < \
      "${config_dir}/schema.postgresql.sql"
  run sudo -u postgres -H psql --echo-queries -d ${pg_bigm_db} \
      --command "\\timing" \
      --command "COPY wikipedia FROM '${data_dir}/${data}' WITH CSV ENCODING 'utf8'"

  restart_postgresql

  echo "pg_bigm: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pg_bigm_db})/*"
}

load_data_textsearch()
{
  restart_postgresql

  echo "textsearch: data: load:"
  run sudo -u postgres -H psql --echo-queries -d ${textsearch_db} < \
      "${config_dir}/schema.postgresql.sql"
  run sudo -u postgres -H psql --echo-queries -d ${textsearch_db} \
      --command "\\timing" \
      --command "COPY wikipedia FROM '${data_dir}/${data}' WITH CSV ENCODING 'utf8'"

  restart_postgresql

  echo "textsearch: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${textsearch_db})/*"
}

load_data()
{
  for target in "${targets[@]}"; do
    load_data_${target}
  done
}

benchmark_create_index_pgroonga()
{
  restart_postgresql

  for i in $(seq ${n_load_tries}); do
    echo "PGroonga: create index: maintenance_work_mem(${maintenance_work_mem_size}): ${i}:"
    run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_pgroonga"
    run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} \
        --command "SET maintenance_work_mem = '${maintenance_work_mem_size}';" \
        --command "\\timing" \
        --command "\\i ${config_dir}/indexes.pgroonga.sql"
    if [ ${i} -eq 1 ]; then
      restart_postgresql
      echo "PGroonga: create index: size:"
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pgroonga_db})/pgrn*"
    fi
  done
}

benchmark_create_index_pg_bigm()
{
  restart_postgresql

  for i in $(seq ${n_load_tries}); do
    echo "pg_bigm: create index: maintenance_work_mem(${maintenance_work_mem_size}): ${i}:"
    run sudo -u postgres -H psql --echo-queries -d ${pg_bigm_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_pg_bigm"
    run sudo -u postgres -H psql --echo-queries -d ${pg_bigm_db} \
        --command "SET maintenance_work_mem = '${maintenance_work_mem_size}';" \
        --command "\\timing" \
        --command "\\i ${config_dir}/indexes.pg_bigm.sql"
    if [ ${i} -eq 1 ]; then
      restart_postgresql
      echo "pg_bigm: create index: size:"
      pg_bigm_data_path=$(sudo -u postgres -H psql -d ${pg_bigm_db} \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_pg_bigm'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/${pg_bigm_data_path}*"
      echo "pg_bigm: create index: size: total:"
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pg_bigm_db})/*"
    fi
  done
}

benchmark_create_index_pg_trgm()
{
  restart_postgresql

  for i in $(seq ${n_load_tries}); do
    echo "pg_trgm: create index: maintenance_work_mem(${maintenance_work_mem_size}): ${i}:"
    run sudo -u postgres -H psql --echo-queries -d ${pg_trgm_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_pg_trgm"
    run sudo -u postgres -H psql --echo-queries -d ${pg_trgm_db} \
        --command "SET maintenance_work_mem = '${maintenance_work_mem_size}';" \
        --command "\\timing" \
        --command "\\i ${config_dir}/indexes.pg_trgm.sql"
    if [ ${i} -eq 1 ]; then
      restart_postgresql
      echo "pg_trgm: create index: size:"
      pg_trgm_data_path=$(sudo -u postgres -H psql -d ${pg_trgm_db} \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_pg_trgm'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/${pg_trgm_data_path}*"
      echo "pg_trgm: create index: size: total:"
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${pg_trgm_db})/*"
    fi
  done
}

benchmark_create_index_textsearch()
{
  restart_postgresql

  for i in $(seq ${n_load_tries}); do
    echo "textsearch: create index: maintenance_work_mem(${maintenance_work_mem_size}): ${i}:"
    run sudo -u postgres -H psql --echo-queries -d ${textsearch_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_textsearch"
    run sudo -u postgres -H psql --echo-queries -d ${textsearch_db} \
        --command "SET maintenance_work_mem = '${maintenance_work_mem_size}';" \
        --command "\\timing" \
        --command "\\i ${config_dir}/indexes.textsearch.sql"
    if [ ${i} -eq 1 ]; then
      restart_postgresql
      echo "textsearch: create index: size:"
      textsearch_data_path=$(sudo -u postgres -H psql -d ${textsearch_db} \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_textsearch'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/${textsearch_data_path}*"
      echo "textsearch: create index: size: total:"
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/${pg_version}/data/base/$(database_oid ${textsearch_db})/*"
    fi
  done
}

benchmark_create_index()
{
  for target in "${targets[@]}"; do
    benchmark_create_index_${target}
  done
}

benchmark_search_pgroonga()
{
  work_mem="SET work_mem = '${work_mem_size}';"
  enable_seqscan="SET enable_seqscan = no;"
  cat "${benchmark_dir}/${word_list}" | while read search_word; do
    commands=()
    commands+=("--command" "${work_mem}")
    commands+=("--command" "${enable_seqscan}")
    commands+=("--command" "\\timing")
    for i in $(seq ${n_search_tries}); do
      where="text @@ '${search_word}'"
      commands+=("--command" "SELECT COUNT(*) FROM wikipedia WHERE ${where}")
    done
    echo "PGroonga: search: work_mem(${work_mem_size}): ${where}:"
    run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} \
        "${commands[@]}"
  done
}

benchmark_search_pgroonga_command()
{
  cat "${benchmark_dir}/${word_list}" | while read search_word; do
    commands=()
    commands+=("--command" "\\timing")
    commands+=("--command" "SELECT pgroonga.command('cache_limit 0')")
    for i in $(seq ${n_search_tries}); do
      commands+=("--command" "SELECT pgroonga.command('select ' || pgroonga.table_name('wikipedia_index_pgroonga') || ' --match_columns text --query \"${search_word}\" --limit 0 --output_columns _id')")
    done
    echo "PGroonga: command: search: ${search_word}:"
    run sudo -u postgres -H psql --echo-queries -d ${pgroonga_db} \
        "${commands[@]}"
  done
}

benchmark_search_pg_bigm()
{
  work_mem="SET work_mem = '${work_mem_size}';"
  enable_seqscan="SET enable_seqscan = no;"
  cat "${benchmark_dir}/${word_list}" | while read search_word; do
    commands=()
    commands+=("--command" "${work_mem}")
    commands+=("--command" "${enable_seqscan}")
    commands+=("--command" "\\timing")
    for i in $(seq ${n_search_tries}); do
      where="text LIKE '%${search_word}%'"
      where=$(echo $where | sed -e "s/ OR /%' OR text LIKE '%/g")
      commands+=("--command" "SELECT COUNT(*) FROM wikipedia WHERE ${where}")
    done
    echo "pg_bigm: search: work_mem(${work_mem_size}): ${where}"
    run sudo -u postgres -H psql --echo-queries -d ${pg_bigm_db} \
        "${commands[@]}"
  done
}

benchmark_search_pg_trgm()
{
  work_mem="SET work_mem = '${work_mem_size}';"
  enable_seqscan="SET enable_seqscan = no;"
  cat "${benchmark_dir}/${word_list}" | while read search_word; do
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
    run sudo -u postgres -H psql --echo-queries -d ${pg_trgm_db} \
        "${commands[@]}"
  done
}

benchmark_search_textsearch()
{
  work_mem="SET work_mem = '${work_mem_size}';"
  enable_seqscan="SET enable_seqscan = no;"
  cat "${benchmark_dir}/${word_list}" | while read search_word; do
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
    run sudo -u postgres -H psql --echo-queries -d ${textsearch_db} \
        "${commands[@]}"
  done
}

benchmark_search()
{
  for target in "${targets[@]}"; do
    benchmark_search_${target}
    if [ "${target}" = "pgroonga" ]; then
      benchmark_search_pgroonga_command
    fi
  done
}

setup_kernel

show_environment

ensure_data

setup_postgresql_repository
setup_groonga_repository

install_extensions

setup_postgresql
setup_benchmark_db
load_data

benchmark_create_index

benchmark_search
