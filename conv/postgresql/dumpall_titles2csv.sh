#!/bin/bash

export exportbasepath="/exports/aperol/www/documents/export"
export localdatabasepath="/opt/openbib/autoconv/pools"

for i in `/opt/openbib/bin/show_active_pools.pl|sort`
do
  if [ -d "$exportbasepath/$i" ]
  then
     /opt/openbib/conv/dump_titles2csv.pl --database=$i --outputfile="$exportbasepath/$i/$i.csv" --logfile=/tmp/titles2csv.log
  fi
done

cd $localdatabasepath/$i/
rm inst001.csv.gz
/opt/openbib/conv/dump_titles2csv.pl --database=inst001 --outputfile="$localdatabasepath/inst001/inst001.csv" --logfile=/tmp/titles2csv.log
gzip inst001.csv
