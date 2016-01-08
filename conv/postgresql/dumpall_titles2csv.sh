#!/bin/bash

export exportbasepath="/exports/aperol/www/documents/export"

for i in `/opt/openbib/bin/show_active_pools.pl|sort`
do
  if [ -d "$exportbasepath/$i" ]
  then
     /opt/openbib/conv/dump_titles2csv.pl --database=$i --outputfile="$exportbasepath/$i/$i.csv" --logfile=/tmp/titles2csv.log
  fi
done
