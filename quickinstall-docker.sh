#!/bin/bash

echo "Getting Postgres"

docker pull postgres:13.10-alpine
docker volume create pgdata

echo "Getting Elasticsearch"

docker pull elasticsearch:7.17.9

echo "Building OpenBib base image for perl"

docker build -t openbib-base-perl -f Dockerfile.openbib-base-perl .

echo "Building OpenBib webapp image for perl"

docker build -t openbib-web-perl -f Dockerfile.openbib-web-perl .

echo "Building local mount bind directories in home-directory"

mkdir -p ~/openbib/conf

echo "Populating them"

cp -a portal/perl/conf/portal.psgi ~/openbib/conf/
cp -a portal/perl/conf/portal.yml-docker ~/openbib/conf/
cp -a portal/perl/conf/portal.log4perl ~/openbib/conf/
