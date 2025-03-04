#!/bin/bash

cd /alma/export

mmv "ubkfull_*_new_?.mrc" "ubkfull_#1_new_0#2.mrc"

cat `/opt/openbib/autoconv/filter/_common/alma/arrange_export_files.pl` > /opt/openbib/autoconv/pools/uni/pool.mrc
