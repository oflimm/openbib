#!/bin/bash

year=$(date +'%Y')
month=$(date +'%m')
day=$(date +'%d')

/opt/openbib/bin/import_occupancy_from_pva.pl  --year=${year} --day=${day} --month=${month} --basedir=/store/peoplecounter
