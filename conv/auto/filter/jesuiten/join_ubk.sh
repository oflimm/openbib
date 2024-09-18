#!/bin/bash

cd /alma/export

mmv "ubkfull_*_new_?.mrc" "ubkfull_#1_new_0#2.mrc"

cat `ls -r1 ubkfull*_delete*.mrc | xargs` `ls -r1 ubkelectronicfull*_delete*.mrc | xargs` `ls -r1 ubkfull*_new*.mrc | xargs` `ls -r1 ubkelectronicfull*_new*.mrc | xargs` > /opt/openbib/autoconv/pools/uni/pool.mrc
