# Wikipedia Search for Groonga family

It is a sample search system for Groonga family such as Groonga,
Droonga, Mroonga and PGroonga. It searches Wikipedia data.

You can use the search system for the following proposes:

  * Understanding how to implement Droonga system
  * Running benchmark for PGroonga versus pg\_bigm

## Usage

### For understanding how to implement Droonga system

TODO

### For running benchmark for PGroonga versus pg\_bigm

You need to set up clean CentOS environment. Run the following command
lines to run benchmark for PGroonga versus pg\_bigm:

```text
% sudo yum install -y git
% git clone https://github.com/groonga/wikipedia-search.git
% cd wikipedia-search
% benchmark/centos6/pgroonga.sh |& tee benchmark.log
```

The benchmark script does the followings:

  * Installs PostgreSQL.
  * Installs PGroonga.
  * Installs pg\_bigm.
  * Downloads Japanese Wikipedia data.
  * Loads the Japanese Wikipedia data into PostgreSQL. (measured)
  * Creates index by PGroonga. (measured)
  * Creates index by pg\_bigm. (measured)
  * Search by some queries by PGroonga. (measured)
  * Search by some queries by pg\_bigm. (measured)

## About chef cookbooks

If you use Ubuntu 12.04LTS, you need to install depending library via apt:

    % sudo apt-get install libgecode-dev

Then, install "berks":

    % cd chef
    % bundle install --path vendor/bundle
    % bundle exec berks

## License

CC0 1.0 Universal. See LICENSE.txt for details.
