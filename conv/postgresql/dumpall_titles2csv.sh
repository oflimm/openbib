#!/bin/bash

export exportbasepath="/exports/aperol/www/documents/export"
export localdatabasepath="/opt/openbib/autoconv/pools"

for i in `/opt/openbib/bin/show_active_pools.pl|egrep '^inst[0-9][0-9][0-9]$'|egrep -v '(inst001|inst900)'|sort`
do
  if [ -d "$exportbasepath/$i" ]
  then
     /opt/git/openbib-current/conv/postgresql/fulldump_titles2csv.pl --database=$i --configfile=/opt/git/openbib-current/conv/postgresql/conf/default.yml --outputfile="$exportbasepath/$i/$i.csv" --logfile=/tmp/titles2csv.log
  fi
done

for i in inst104 inst120 inst155 inst158 inst159 inst136 inst170 inst171 inst202 inst220 inst229 inst307 inst327 inst402 inst509 inst519
do
  if [ -d "$exportbasepath/$i" ]
  then
     /opt/git/openbib-current/conv/postgresql/fulldump_titles2csv.pl --database=$i --configfile=/opt/git/openbib-current/conv/postgresql/conf/default.yml --outputfile="$exportbasepath/$i/$i.csv" --logfile=/tmp/titles2csv.log
  fi
done
