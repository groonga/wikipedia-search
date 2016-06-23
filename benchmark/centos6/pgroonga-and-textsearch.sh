#!/bin/bash

set -u

LANG=C

n_load_tries=1
n_search_tries=5

script_dir=$(cd "$(dirname $0)"; pwd)
base_dir="${script_dir}/../.."
config_dir="${base_dir}/config/sql"
data_dir="${base_dir}/data/sql"
benchmark_dir="${base_dir}/benchmark"

pgroonga_db="benchmark_pgroonga"
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
  if [ -f "${data_dir}/en-all-pages.sql" ]; then
    return
  fi

  run sudo -H yum install -y epel-release
  run sudo -H yum install -y wget pxz
  run mkdir -p "${data_dir}"
  cd "${data_dir}"
  run wget --no-verbose http://packages.groonga.org/tmp/en-all-pages.sql.xz
  run pxz --keep --decompress en-all-pages.sql.xz
  cd -
}

setup_postgresql_repository()
{
  os_version=$(run rpm -qf --queryformat="%{VERSION}" /etc/redhat-release)
  os_arch=$(run rpm -qf --queryformat="%{ARCH}" /etc/redhat-release)
  run sudo rpm -Uvh \
      http://yum.postgresql.org/9.5/redhat/rhel-${os_version}-${os_arch}/pgdg-centos95-9.5-2.noarch.rpm
}

setup_groonga_repository()
{
  run sudo rpm -ivh \
      http://packages.groonga.org/centos/groonga-release-1.1.0-1.noarch.rpm
}

install_pgroonga()
{
  run sudo yum makecache
  run sudo yum install -y postgresql95-pgroonga
}

install_textsearch()
{
  :
}

setup_postgresql()
{
  run sudo -H /sbin/service postgresql-9.5 initdb
  run sudo -H /sbin/chkconfig postgresql-9.5 on
  run sudo -H /sbin/service postgresql-9.5 start
}

setup_benchmark_db()
{
  run sudo -u postgres -H psql \
      --command "DROP DATABASE IF EXISTS ${pgroonga_db}"
  run sudo -u postgres -H psql \
      --command "CREATE DATABASE ${pgroonga_db}"
  run sudo -u postgres -H psql -d ${pgroonga_db} \
      --command "CREATE EXTENSION pgroonga"

  run sudo -u postgres -H psql \
      --command "DROP DATABASE IF EXISTS ${textsearch_db}"
  run sudo -u postgres -H psql \
      --command "CREATE DATABASE ${textsearch_db}"
}

database_oid()
{
  sudo -u postgres -H psql \
       --command "SELECT datid FROM pg_stat_database WHERE datname = '$1'" | \
    head -3 | \
    tail -1 | \
    sed -e 's/ *//g'
}

load_data()
{
  echo "PGroonga: data: load:"
  run sudo -u postgres -H psql -d ${pgroonga_db} < \
      "${config_dir}/schema.postgresql.sql"
  time run sudo -u postgres -H psql -d ${pgroonga_db} < \
       "${data_dir}/en-all-pages.sql" > /dev/null
  echo "PGroonga: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/9.5/data/base/$(database_oid ${pgroonga_db})/*"

  echo "textsearch: data: load:"
  run sudo -u postgres -H psql -d ${textsearch_db} < \
      "${config_dir}/schema.postgresql.sql"
  time run sudo -u postgres -H psql -d ${textsearch_db} < \
       "${data_dir}/en-all-pages.sql" > /dev/null
  echo "pg_biggm: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/9.5/data/base/$(database_oid ${textsearch_db})/*"
}

benchmark_create_index_pgroonga()
{
  run sudo -H /sbin/service postgresql-9.5 restart

  for i in $(seq ${n_load_tries}); do
    echo "PGroonga: create index: ${i}:"
    run sudo -u postgres -H psql -d ${pgroonga_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_pgroonga"
    time run sudo -u postgres -H psql -d ${pgroonga_db} < \
         "${config_dir}/indexes.pgroonga.sql"
    if [ ${i} -eq 1 ]; then
      echo "PGroonga: create index: size:"
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/9.5/data/base/$(database_oid ${pgroonga_db})/pgrn*"
    fi
  done
}

benchmark_create_index_textsearch()
{
  run sudo -H /sbin/service postgresql-9.5 restart

  for i in $(seq ${n_load_tries}); do
    echo "textsearch: create index: ${i}:"
    run sudo -u postgres -H psql -d ${textsearch_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_textsearch"
    time run sudo -u postgres -H psql -d ${textsearch_db} < \
         "${config_dir}/indexes.textsearch.sql"
    if [ ${i} -eq 1 ]; then
      echo "textsearch: create index: size:"
      textsearch_data_path=$(sudo -u postgres -H psql -d ${textsearch_db} \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_textsearch'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/9.5/data/${textsearch_data_path}*"
    fi
  done
}

benchmark_search_pgroonga()
{
  work_mem_size='10MB'
  work_mem="SET work_mem = '${work_mem_size}';"
  cat "${benchmark_dir}/search-words-en.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="text @@ '${search_word}'"
      echo "PGroonga: search: work_mem(${work_mem_size}): ${where}: ${i}:"
      time run sudo -u postgres -H psql -d ${pgroonga_db} \
           --command "${work_mem} SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search_textsearch()
{
  work_mem_size='10MB'
  work_mem="SET work_mem = '${work_mem_size}';"
  cat "${benchmark_dir}/search-words-en.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="to_tsvector('english', text) @@ to_tsquery('${search_word}')"
      where=$(echo $where | sed -e "s/ OR / | /g")
      echo "textsearch: search: work_mem(${work_mem_size}): ${where}: ${i}:"
      time run sudo -u postgres -H psql -d ${textsearch_db} \
           --command "${work_mem} SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

show_environment

ensure_data

setup_postgresql_repository
setup_groonga_repository
install_pgroonga
install_textsearch

setup_postgresql
setup_benchmark_db
load_data

benchmark_create_index_pgroonga
benchmark_create_index_textsearch

benchmark_search_pgroonga
benchmark_search_textsearch
