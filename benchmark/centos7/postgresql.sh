#!/bin/bash

set -u

LANG=C

n_load_tries=1
n_create_index_tries=1
n_search_tries=5

script_dir=$(cd "$(dirname $0)"; pwd)
base_dir="${script_dir}/../.."
config_dir="${base_dir}/config/sql"
data_dir="${base_dir}/data/csv"
benchmark_dir="${base_dir}/benchmark"

pgroonga_db="benchmark_pgroonga"
pg_bigm_db="benchmark_pg_bigm"

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
  if [ -f "${data_dir}/ja-all-pages.csv" ]; then
    return
  fi

#  if which rake > /dev/null 2>&1; then
#    run rake data/sql/ja-all-pages.csv
#    return
#  fi

  run sudo -H yum install -y epel-release
  run sudo -H yum install -y wget xz
  run mkdir -p "${data_dir}"
  cd "${data_dir}"
  run wget --no-verbose http://packages.groonga.org/tmp/ja-all-pages.csv.xz
  run unxz ja-all-pages.csv.xz
  cd -
}

setup_postgresql_repository()
{
  os_version=$(run rpm -qf --queryformat="%{VERSION}" /etc/redhat-release)
  os_arch=$(run rpm -qf --queryformat="%{ARCH}" /etc/redhat-release)
  run sudo yum install -y \
      http://yum.postgresql.org/9.5/redhat/rhel-${os_version}-${os_arch}/pgdg-centos95-9.5-2.noarch.rpm
}

setup_groonga_repository()
{
  if ! rpm -q groonga-release > /dev/null 1>&2; then
    run sudo yum install -y \
        http://packages.groonga.org/centos/groonga-release-1.1.0-1.noarch.rpm
  fi
}

install_groonga_tokenizer_mecab()
{
  run sudo yum install -y groonga-tokenizer-mecab
}

install_pgroonga()
{
  run sudo yum install -y postgresql95-pgroonga
}

install_pg_bigm()
{
  run sudo yum install -y postgresql95-devel gcc
  run wget http://osdn.dl.osdn.jp/pgbigm/63792/pg_bigm-1.1-20150910.tar.gz
  run tar xvf pg_bigm-1.1-20150910.tar.gz
  run cd pg_bigm-1.1-20150910
  run env PATH=/usr/pgsql-9.5/bin:$PATH make USE_PGXS=1
  run sudo env PATH=/usr/pgsql-9.5/bin:$PATH make USE_PGXS=1 install
  run cd ..
}

setup_postgresql()
{
  run sudo -H /usr/pgsql-9.5/bin/postgresql95-setup initdb
  run sudo -H systemctl enable postgresql-9.5
  run sudo -H systemctl start postgresql-9.5
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

setup_benchmark_db_pg_bigm()
{
  run sudo -u postgres -H psql \
      --command "DROP DATABASE IF EXISTS ${pg_bigm_db}"
  run sudo -u postgres -H psql \
      --command "CREATE DATABASE ${pg_bigm_db}"
  run sudo -u postgres -H psql -d ${pg_bigm_db} \
      --command "CREATE EXTENSION pg_bigm"
}

setup_benchmark_db()
{
  setup_benchmark_db_pgroonga
  setup_benchmark_db_pg_bigm
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
  run sudo -H systemctl restart postgresql-9.5

  echo "PGroonga: data: load:"
  run sudo -u postgres -H psql -d ${pgroonga_db} < \
      "${config_dir}/schema.postgresql.sql"
  time run sudo -u postgres -H psql -d ${pgroonga_db} \
       --command "COPY wikipedia FROM '${data_dir}/ja-all-pages.csv' WITH CSV ENCODING 'utf8'"
  echo "PGroonga: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/9.5/data/base/$(database_oid ${pgroonga_db})/*"
}

load_data_pg_bigm()
{
  run sudo -H systemctl restart postgresql-9.5

  echo "pg_bigm: data: load:"
  run sudo -u postgres -H psql -d ${pg_bigm_db} < \
      "${config_dir}/schema.postgresql.sql"
  time run sudo -u postgres -H psql -d ${pg_bigm_db} \
       --command "COPY wikipedia FROM '${data_dir}/ja-all-pages.csv' WITH CSV ENCODING 'utf8'"
  echo "pg_biggm: data: load: size:"
  run sudo -u postgres -H \
      sh -c "du -hsc /var/lib/pgsql/9.5/data/base/$(database_oid ${pg_bigm_db})/*"
}

load_data()
{
  load_data_pgroonga
  load_data_pg_bigm
}

benchmark_create_index_pgroonga()
{
  run sudo -H systemctl restart postgresql-9.5

  for i in $(seq ${n_create_index_tries}); do
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

benchmark_create_index_pg_bigm()
{
  run sudo -H systemctl restart postgresql-9.5

  for i in $(seq ${n_create_index_tries}); do
    echo "pg_bigm: create index: ${i}:"
    run sudo -u postgres -H psql -d ${pg_bigm_db} \
        --command "DROP INDEX IF EXISTS wikipedia_index_pg_bigm"
    time run sudo -u postgres -H psql -d ${pg_bigm_db} < \
         "${config_dir}/indexes.pg_bigm.sql"
    if [ ${i} -eq 1 ]; then
      echo "pg_bigm: create index: size:"
      pg_bigm_data_path=$(sudo -u postgres -H psql -d ${pg_bigm_db} \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_pg_bigm'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/9.5/data/${pg_bigm_data_path}*"
    fi
  done
}

benchmark_create_index()
{
  benchmark_create_index_pgroonga
  benchmark_create_index_pg_bigm
}

benchmark_search_pgroonga()
{
  run sudo -H systemctl restart postgresql-9.5

  work_mem_size='10MB'
  work_mem="SET work_mem = '${work_mem_size}';"
  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="text @@ '${search_word}'"
      echo "PGroonga: search: ${where}: ${i}:"
      time run sudo -u postgres -H psql -d ${pgroonga_db} \
           --command "${work_mem} SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search_pg_bigm()
{
  run sudo -H systemctl restart postgresql-9.5

  work_mem_size='10MB'
  work_mem="SET work_mem = '${work_mem_size}';"
  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="text LIKE '%${search_word}%'"
      where=$(echo $where | sed -e "s/ OR /%' OR text LIKE '%/g")
      echo "pg_bigm: search: ${where}: ${i}:"
      time run sudo -u postgres -H psql -d ${pg_bigm_db} \
           --command "${work_mem} SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search()
{
  benchmark_search_pgroonga
  benchmark_search_pg_bigm
}

show_environment

ensure_data

setup_postgresql_repository
setup_groonga_repository
install_pgroonga
install_pg_bigm

setup_postgresql
setup_benchmark_db

load_data
benchmark_create_index
benchmark_search
