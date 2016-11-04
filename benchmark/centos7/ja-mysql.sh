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

mroonga_db="benchmark_mroonga"
innodb_ngram_db="benchmark_innodb_ngram"
innodb_mecab_db="benchmark_innodb_mecab"

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
  if ! rpm -q groonga-release > /dev/null 2>&1; then
    run sudo yum install -y \
        http://packages.groonga.org/centos/groonga-release-1.1.0-1.noarch.rpm
  fi
}

install_groonga_tokenizer_mecab()
{
  run sudo yum install -y groonga-tokenizer-mecab
}

install_mroonga()
{
  run sudo yum install -y mysql57-community-mroonga
}

setup_mysql()
{
  echo "log-bin" | run sudo tee --append /etc/my.cnf
  echo "server-id=1" | run sudo tee --append /etc/my.cnf
  echo "character-set-server=utf8mb4" | run sudo tee --append /etc/my.cnf
  echo "validate-password=off" | run sudo tee --append /etc/my.cnf
  echo "loose-mecab-rc-file=/usr/lib64/mysql/mecab/etc/mecabrc" | \
    run sudo tee --append /etc/my.cnf
  echo "innodb-ft-min-token-size=1" | \
    run sudo tee --append /etc/my.cnf
  echo "dicdir = /usr/lib64/mysql/mecab/dic/ipadic_utf-8" | \
    run sudo tee /usr/lib64/mysql/mecab/etc/mecabrc
  run sudo systemctl start mysqld
  tmp_password=$(sudo grep 'A temporary password' /var/log/mysqld.log | \
                    sed -e 's/^.*: //' | tail -1)
  run sudo mysql -u root "-p${tmp_password}" \
      --connect-expired-password \
      -e "ALTER USER user() IDENTIFIED BY ''; CREATE USER root@'%'; GRANT ALL ON *.* TO root@'%' WITH GRANT OPTION"
  run sudo mysql -u root -e "INSTALL PLUGIN mecab SONAME 'libpluginmecab.so'"
}

setup_benchmark_db_mroonga()
{
  run mysql -u root -e "DROP DATABASE IF EXISTS ${mroonga_db}"
  run mysql -u root -e "CREATE DATABASE ${mroonga_db}"
}

setup_benchmark_db_innodb_ngram()
{
  run mysql -u root -e "DROP DATABASE IF EXISTS ${innodb_ngram_db}"
  run mysql -u root -e "CREATE DATABASE ${innodb_ngram_db}"
}

setup_benchmark_db_innodb_mecab()
{
  run mysql -u root -e "DROP DATABASE IF EXISTS ${innodb_mecab_db}"
  run mysql -u root -e "CREATE DATABASE ${innodb_mecab_db}"
}

setup_benchmark_db()
{
  setup_benchmark_db_mroonga
  setup_benchmark_db_innodb_ngram
  setup_benchmark_db_innodb_mecab
}

load_data_mroonga()
{
  run sudo -H systemctl restart mysqld

  echo "Mroonga: data: load:"
  run mysql -u root ${mroonga_db} < \
      "${config_dir}/schema.mroonga.sql"
  time mysql -u root ${mroonga_db} \
       -e "LOAD DATA LOCAL INFILE '${data_dir}/ja-all-pages.csv' INTO TABLE wikipedia FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'"
  echo "Mroonga: data: load: size:"
  run sudo -u mysql -H \
      sh -c "du -hsc /var/lib/mysql/${mroonga_db}.mrn*"
}

load_data_innodb_ngram()
{
  run sudo -H systemctl restart mysqld

  echo "InnoDB: ngram: data: load:"
  run mysql -u root ${innodb_ngram_db} < \
      "${config_dir}/schema.innodb.sql"
  time mysql -u root ${innodb_ngram_db} \
       -e "LOAD DATA LOCAL INFILE '${data_dir}/ja-all-pages.csv' INTO TABLE wikipedia FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'"
  echo "InnoDB: ngram: data: load: size:"
  run sudo -u mysql -H \
      sh -c "du -hsc /var/lib/mysql/${innodb_ngram_db}/*"
}

load_data_innodb_mecab()
{
  run sudo -H systemctl restart mysqld

  echo "InnoDB: mecab: data: load:"
  run mysql -u root ${innodb_mecab_db} < \
      "${config_dir}/schema.innodb.sql"
  time mysql -u root ${innodb_mecab_db} \
       -e "LOAD DATA LOCAL INFILE '${data_dir}/ja-all-pages.csv' INTO TABLE wikipedia FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'"
  echo "InnoDB: mecab: data: load: size:"
  run sudo -u mysql -H \
      sh -c "du -hsc /var/lib/mysql/${innodb_mecab_db}/*"
}

load_data()
{
  load_data_mroonga
  load_data_innodb_ngram
  load_data_innodb_mecab
}

benchmark_create_index_mroonga()
{
  run sudo -H systemctl restart mysqld

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

benchmark_create_index_innodb_ngram()
{
  run sudo -H systemctl restart mysqld

  for i in $(seq ${n_create_index_tries}); do
    echo "InnoDB: ngram: create index: ${i}:"
    mysql -u root ${innodb_ngram_db} \
          -e "ALTER TABLE DROP INDEX fulltext_index"
    time mysql -u root ${innodb_ngram_db} < \
         "${config_dir}/indexes.innodb.ngram.sql"
    if [ ${i} -eq 1 ]; then
      echo "InnoDB: ngram: create index: size:"
      run sudo -u mysql -H \
          sh -c "du -hsc /var/lib/mysql/${innodb_ngram_db}/*"
    fi
  done
}

benchmark_create_index_innodb_mecab()
{
  run sudo -H systemctl restart mysqld

  for i in $(seq ${n_create_index_tries}); do
    echo "InnoDB: mecab: create index: ${i}:"
    mysql -u root ${innodb_mecab_db} \
          -e "ALTER TABLE DROP INDEX fulltext_index"
    time mysql -u root ${innodb_mecab_db} < \
         "${config_dir}/indexes.innodb.mecab.sql"
    if [ ${i} -eq 1 ]; then
      echo "InnoDB: mecab: create index: size:"
      run sudo -u mysql -H \
          sh -c "du -hsc /var/lib/mysql/${innodb_mecab_db}/*"
    fi
  done
}

benchmark_create_index()
{
  benchmark_create_index_mroonga
  benchmark_create_index_innodb_ngram
  benchmark_create_index_innodb_mecab
}

benchmark_search_mroonga()
{
  run sudo -H systemctl restart mysqld

  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      where="MATCH(title, text) AGAINST('*D+ ${search_word}' IN BOOLEAN MODE)"
      echo "Mroonga: search: ${where}: ${i}:"
      time run mysql --default-character-set=utf8mb4 \
           -u root ${mroonga_db} \
           -e "SELECT SQL_NO_CACHE COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search_innodb_ngram()
{
  run sudo -H systemctl restart mysqld

  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      query=$(echo ${search_word} | sed -e "s/ OR / /g")
      where="MATCH(title, text) AGAINST('${query}' IN BOOLEAN MODE)"
      echo "InnoDB: ngram: search: ${where}: ${i}:"
      time mysql --default-character-set=utf8mb4 \
           -u root ${innodb_ngram_db} \
           -e "SELECT SQL_NO_CACHE COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search_innodb_mecab()
{
  run sudo -H systemctl restart mysqld

  cat "${benchmark_dir}/search-words.list" | while read search_word; do
    for i in $(seq ${n_search_tries}); do
      query=$(echo ${search_word} | sed -e "s/ OR / /g")
      where="MATCH(title, text) AGAINST('${query}' IN BOOLEAN MODE)"
      echo "InnoDB: mecab: search: ${where}: ${i}:"
      time mysql --default-character-set=utf8mb4 \
           -u root ${innodb_mecab_db} \
           -e "SELECT SQL_NO_CACHE COUNT(*) FROM wikipedia WHERE ${where}"
    done
  done
}

benchmark_search()
{
  benchmark_search_mroonga
  benchmark_search_innodb_ngram
  benchmark_search_innodb_mecab
}

show_environment

ensure_data

setup_mysql_repository
setup_groonga_repository
install_mroonga
setup_mysql

setup_benchmark_db

load_data
benchmark_create_index
benchmark_search
