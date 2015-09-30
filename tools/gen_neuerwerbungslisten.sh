#!/bin/bash

export MONTH=`date +'%m'`
export YEAR=`date +'%Y'`
for i in inst006 inst103 inst123 inst128 inst136 inst301 inst302 inst406 inst420 inst425 inst428 inst431 inst434 inst445 inst514 inst526; do
/opt/openbib/bin/gen_neuerwerbungslisten.pl --configfile=/opt/openbib/conf/acq_${i}.yml --month=$MONTH --year=$YEAR
done
