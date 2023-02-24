#!/bin/bash

echo "Getting Postgres"

docker pull postgres:13.10-alpine
docker volume create pgdata

echo "Getting Elasticsearch"

docker pull docker.elastic.co/elasticsearch/elasticsearch:7.17.9
docker volume create esdata

echo "Building OpenBib base image for perl"

docker build -t openbib-base-perl -f Dockerfile.openbib-base-perl .

echo "Building OpenBib webapp image for perl"

docker build -t openbib-web-perl -f Dockerfile.openbib-web-perl .

echo "Building OpenBib conv for converting and importing data"

docker build -t openbib-conv -f Dockerfile.openbib-conv .
docker volume create xapiandata

echo "Building local mount bind directories in home-directory"

mkdir -p ~/openbib/conf

echo "Populating them"

cp -a portal/perl/conf/portal.psgi ~/openbib/conf/
cp -a portal/perl/conf/dispatch_rules.yml-dist ~/openbib/conf/dispatch_rules.yml
cp -a portal/perl/conf/portal.yml-docker ~/openbib/conf/
cp -a portal/perl/conf/portal.log4perl ~/openbib/conf/

echo "Please configure config files in ~/openbib/conf/ appropriately"

echo "To startup containers use"

echo docker-compose -f docker-compose.yml up -d

echo "To create default databases use"

echo docker exec -it openbib-master_openbib-web-perl_1 /opt/openbib/bin/createsystem.pl
echo docker exec -it openbib-master_openbib-web-perl_1 /opt/openbib/bin/createenrichmnt.pl
echo docker exec -it openbib-master_openbib-web-perl_1 /opt/openbib/bin/createstatistics.pl

echo "To start Webservice"

echo docker exec -it openbib-master_openbib-web-perl_1 /etc/init.d/starman restart
