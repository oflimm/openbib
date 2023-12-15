#!/bin/bash

cd /alma/export

cat `ls -r1 ubkfull*_delete*.mrc | xargs` `ls -r1 ubkelectronicfull*_delete*.mrc | xargs` `ls -r1 ubkfull*_new*.mrc | xargs` `ls -r1 ubkelectronicfull*_new*.mrc | xargs` > /opt/openbib/autoconv/pools/uni/pool.mrc
