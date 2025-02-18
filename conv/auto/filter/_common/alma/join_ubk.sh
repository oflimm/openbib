#!/bin/bash

cd /alma/export

mmv "ubkfull_*_new_?.mrc" "ubkfull_#1_new_0#2.mrc"

cat /dev/null > /opt/openbib/autoconv/pools/uni/pool.mrc

for thisdate in `ls -1 ubkfull_*.mrc ubkelectronicfull_*.mrc|cut -d_ -f 2|sort -ru|xargs`;do
 echo "Joining ${thisdate}"
 cat `ls -1 ubkfull_${thisdate}_*delete*.mrc|xargs` >> /opt/openbib/autoconv/pools/uni/pool.mrc
 cat `ls -1 ubkfull_${thisdate}_*new*.mrc|xargs` >> /opt/openbib/autoconv/pools/uni/pool.mrc
 cat `ls -1 ubkelectronicfull_${thisdate}_*delete*.mrc|xargs` >> /opt/openbib/autoconv/pools/uni/pool.mrc
 cat `ls -1 ubkelectronicfull_${thisdate}_*new*.mrc|xargs` >> /opt/openbib/autoconv/pools/uni/pool.mrc
done
