#!/bin/bash

export exportbasepath="/exports/aperol/www/documents/export"
export localdatabasepath="/opt/openbib/autoconv/pools"

for i in `cat /opt/openbib/conf/retro-kataloge.txt|sort`
do
  if [ -d "$exportbasepath/$i" ]
  then
     /opt/git/openbib-current/conv/postgresql/fulldump_titles2csv.pl -retro --database=$i --configfile=/opt/git/openbib-current/conv/postgresql/conf/default.yml --outputfile="$exportbasepath/$i/$i.csv" --logfile=/tmp/titles2csv.log
  fi
done

for i in `cat /opt/openbib/conf/sonstige-kataloge.txt|sort`
do
  if [ -d "$exportbasepath/$i" ]
  then
     /opt/git/openbib-current/conv/postgresql/fulldump_titles2csv.pl --database=$i --configfile=/opt/git/openbib-current/conv/postgresql/conf/default.yml --outputfile="$exportbasepath/$i/$i.csv" --logfile=/tmp/titles2csv.log
  fi
done
