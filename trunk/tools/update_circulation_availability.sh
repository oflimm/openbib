#!/bin/bash

for i in inst006 inst132 inst155 inst302 inst328 inst406 inst420 inst426 inst431 inst526
do
 /opt/openbib/autoconv/bin/autoconv.pl --database=$i
 /opt/openbib/bin/update_circulation_availability.pl --database=$i --configfile=/opt/openbib/conf/acq_${i}.yml
done
