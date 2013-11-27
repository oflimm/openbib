#!/bin/bash

for i in inst001 
do
 /opt/openbib/bin/update_circulation_availability.pl --database=$i --configfile=/opt/openbib/conf/acq_${i}.yml
done
