FROM centos:latest

RUN yum update -y
RUN yum install -y git sudo
RUN git clone https://github.com/groonga/wikipedia-search.git

ENTRYPOINT ["/wikipedia-search/benchmark/centos7/mysql-postgresql.sh"]
