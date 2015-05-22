#!/bin/bash

set -u

n_load_tries=1
n_search_tries=3

script_dir=$(cd "$(dirname $0)"; pwd)
base_dir="${script_dir}/../.."
config_dir="${base_dir}/config/sql"
data_dir="${base_dir}/data/sql"
benchmark_dir="${base_dir}/benchmark"

run()
{
  "$@"
  if test $? -ne 0; then
    echo "Failed $@"
    exit 1
  fi
}

ensure_data()
{
  if [ -f "${data_dir}/ja-all-pages.sql" ]; then
    return
  fi

  if which rake > /dev/null 2>&1; then
    run rake data/sql/ja-all-pages.sql
  else
    run sudo -H yum install -y epel-release
    run sudo -H yum install -y xz
    run mkdir -p "${data_dir}"
    cd "${data_dir}"
    run wget http://packages.groonga.org/tmp/ja-all-pages.sql.xz
    run unxz ja-all-pages.sql.xz
    cd -
  fi
}

setup_postgresql_repository()
{
  os_version=$(run rpm -qf --queryformat="%{VERSION}" /etc/redhat-release)
  os_arch=$(run rpm -qf --queryformat="%{ARCH}" /etc/redhat-release)
  run sudo rpm -Uvh \
      http://yum.postgresql.org/9.4/redhat/rhel-${os_version}-${os_arch}/pgdg-centos94-9.4-1.noarch.rpm
}

setup_groonga_repository()
{
  run sudo rpm -ivh \
      http://packages.groonga.org/centos/groonga-release-1.1.0-1.noarch.rpm
}

install_pgroonga()
{
  run sudo yum makecache
  run sudo yum install -y postgresql94-pgroonga
  run sudo yum install -y groonga-tokenizer-mecab
}

install_pg_bigm()
{
  run sudo rpm -Uvh \
      http://jaist.dl.sourceforge.jp/pgbigm/59914/pg_bigm-1.1.20131122-1.pg94.el6.x86_64.rpm
}

setup_postgresql()
{
  run sudo -H /sbin/service postgresql-9.4 initdb
  run sudo -H /sbin/chkconfig postgresql-9.4 on
  run sudo -H /sbin/service postgresql-9.4 start
}

setup_benchmark_db()
{
  run sudo -u postgres -H psql \
      --command 'DROP DATABASE IF EXISTS benchmark'
  run sudo -u postgres -H psql \
      --command 'CREATE DATABASE benchmark'
  run sudo -u postgres -H psql -d benchmark \
      --command 'CREATE EXTENSION pgroonga'
  run sudo -u postgres -H psql -d benchmark \
      --command 'CREATE EXTENSION pg_bigm'
}

load_data()
{
  run sudo -u postgres -H psql -d benchmark < \
      "${config_dir}/schema.postgresql.sql"
  time run sudo -u postgres -H psql -d benchmark < \
       "${data_dir}/ja-all-pages.sql" > /dev/null
}

benchmark_load_pgroonga()
{
  for i in $(seq ${n_load_tries}); do
    echo "PGroonga: load: ${i}"
    run sudo -u postgres -H psql -d benchmark \
        --command 'DROP INDEX IF EXISTS wikipedia_index_pgroonga'
    time run sudo -u postgres -H psql -d benchmark < \
         "${config_dir}/indexes.pgroonga.sql"
    if [ ${i} -eq 1 ]; then
      echo "PGroonga: load: size"
      database_oid=$(sudo -u postgres -H psql -d benchmark \
                          --command "SELECT datid FROM pg_stat_database WHERE datname = 'benchmark'" | \
                        head -3 | \
                        tail -1 | \
                        sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/9.4/data/base/${database_oid}/pgrn*"
    fi
  done
}

benchmark_load_pg_bigm()
{
  for i in $(seq ${n_load_tries}); do
    echo "pg_bigm: load: ${i}"
    run sudo -u postgres -H psql -d benchmark \
        --command 'DROP INDEX IF EXISTS wikipedia_index_pg_bigm'
    time run sudo -u postgres -H psql -d benchmark < \
         "${config_dir}/indexes.pg_bigm.sql"
    if [ ${i} -eq 1 ]; then
      echo "pg_bigm: load: size"
      pg_bigm_data_path=$(sudo -u postgres -H psql -d benchmark \
                               --command "SELECT pg_relation_filepath(oid) FROM pg_class WHERE relname = 'wikipedia_index_pg_bigm'" | \
                             head -3 | \
                             tail -1 | \
                             sed -e 's/ *//g')
      run sudo -u postgres -H \
          sh -c "du -hsc /var/lib/pgsql/9.4/data/${pg_bigm_data_path}*"
    fi
  done
}

benchmark_search_pgroonga()
{
  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="text %% '${search_word}'"
      echo "PGroonga: search: ${where}: ${i}"
      time run sudo -u postgres -H psql -d benchmark \
           --command "SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search_pg_bigm()
{
  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="text LIKE '%${search_word}%'"
      where=$(echo $where | sed -e "s/ OR /%' OR text LIKE '%/g")
      echo "pg_bigm: search: ${where}: ${i}"
      time run sudo -u postgres -H psql -d benchmark \
           --command "SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

ensure_data

setup_postgresql_repository
setup_groonga_repository
install_pgroonga
install_pg_bigm

setup_postgresql
setup_benchmark_db
load_data

benchmark_load_pgroonga
benchmark_load_pg_bigm

benchmark_search_pgroonga
benchmark_search_pg_bigm
