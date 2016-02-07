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

setup_mysql_repository()
{
  os_version=$(run rpm -qf --queryformat="%{VERSION}" /etc/redhat-release)
  run sudo yum install -y \
       http://repo.mysql.com/mysql-community-release-el${os_version}-7.noarch.rpm
  run sudo yum install -y yum-utils
  run sudo yum-config-manager --disable mysql56-community
  run sudo yum-config-manager --enable mysql57-community
}

setup_groonga_repository()
{
  run sudo yum install -y \
      http://packages.groonga.org/centos/groonga-release-1.1.0-1.noarch.rpm
}

install_groonga_tokenizer_mecab()
{
  run sudo yum install -y groonga-tokenizer-mecab
}

install_mroonga()
{
  run sudo yum install -y mysql57-community-mroonga
  echo "log-bin" | run sudo tee --append /etc/my.cnf
  echo "character-set-server=utf8mb4" | run sudo tee --append /etc/my.cnf
  echo "validate-password=off" | run sudo tee --append /etc/my.cnf
  run sudo systemctl start mysqld
  tmp_password=$(sudo grep 'A temporary password' /var/log/mysqld.log | \
                    sed -e 's/^.*: //' | tail -1)
  run sudo mysql -u root "-p${tmp_password}" \
      --connect-expired-password \
      -e "ALTER USER user() IDENTIFIED BY ''; CREATE USER root@'%'; GRANT ALL ON *.* TO root@'%' WITH GRANT OPTION"
}

setup_benchmark_db_mroonga()
{
  run mysql -u root -e "DROP DATABASE IF EXISTS ${mroonga_db}"
  run mysql -u root -e "CREATE DATABASE ${mroonga_db}"
}

setup_benchmark_db_innodb()
{
  run mysql -u root -e "DROP DATABASE IF EXISTS ${innodb_db}"
  run mysql -u root -e "CREATE DATABASE ${innodb_db}"
}

setup_benchmark_db()
{
  setup_benchmark_db_mroonga
  setup_benchmark_db_innodb
}

load_data_mroonga()
{
  echo "Mroonga: data: load:"
  run mysql -u root ${mroonga_db} < \
      "${config_dir}/schema.mroonga.sql"
  time mysql -u root ${mroonga_db} \
       -e "LOAD DATA LOCAL INFILE '${data_dir}/ja-all-pages.csv' INTO TABLE wikipedia FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'"
  echo "Mroonga: data: load: size:"
  run sudo -u mysql -H \
      sh -c "du -hsc /var/lib/mysql/${mroonga_db}.mrn*"
}

load_data_innodb()
{
  echo "InnoDB: data: load:"
  run mysql -u root ${innodb_db} < \
      "${config_dir}/schema.innodb.sql"
  time mysql -u root ${innodb_db} \
       -e "LOAD DATA LOCAL INFILE '${data_dir}/ja-all-pages.csv' INTO TABLE wikipedia FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'"
  echo "InnoDB: data: load: size:"
  run sudo -u mysql -H \
      sh -c "du -hsc /var/lib/mysql/${innodb_db}/*"
}

load_data()
{
  load_data_mroonga
  load_data_innodb
}

benchmark_create_index_mroonga()
{
  for i in $(seq ${n_create_index_tries}); do
    echo "Mroonga: create index: ${i}:"
    mysql -u root ${mroonga_db} \
          -e "ALTER TABLE DROP INDEX fulltext_index"
    time mysql -u root ${mroonga_db} < \
         "${config_dir}/indexes.mroonga.sql"
    if [ ${i} -eq 1 ]; then
      echo "Mroonga: create index: size:"
      run sudo -u mysql -H \
          sh -c "du -hsc /var/lib/mysql/${mroonga_db}.mrn*"
    fi
  done
}

benchmark_create_index_innodb()
{
  for i in $(seq ${n_create_index_tries}); do
    echo "InnoDB: create index: ${i}:"
    mysql -u root ${innodb_db} \
          -e "ALTER TABLE DROP INDEX fulltext_index"
    time mysql -u root ${innodb_db} < \
         "${config_dir}/indexes.innodb.sql"
    if [ ${i} -eq 1 ]; then
      echo "InnoDB: create index: size:"
      run sudo -u mysql -H \
          sh -c "du -hsc /var/lib/mysql/${innodb_db}/*"
    fi
  done
}

benchmark_create_index()
{
  benchmark_create_index_mroonga
  benchmark_create_index_innodb
}

benchmark_search_mroonga()
{
  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="MATCH(title, text) AGAINST('*D+ ${search_word}' IN BOOLEAN MODE)"
      echo "Mroonga: search: ${where}: ${i}:"
      time run mysql -u root ${mroonga_db} \
           -e "SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search_innodb()
{
  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="MATCH(title, text) AGAINST('${search_word}' IN BOOLEAN MODE)"
      echo "InnoDB: search: ${where}: ${i}:"
      time run mysql -u root ${innodb_db} \
           -e "SELECT COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search()
{
  benchmark_search_mroonga
  benchmark_search_innodb
}

show_environment

ensure_data

setup_mysql_repository
setup_groonga_repository
install_mroonga

setup_benchmark_db

load_data
benchmark_create_index
benchmark_search
