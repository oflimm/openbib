#!/bin/bash

cd /var/www.opendata/dumps/misc/
/opt/openbib/bin/get_titleid_by_subjectarea.pl --area=wiwi --excludelabel=wi
/opt/openbib/bin/get_titleid_by_subjectarea.pl --area=sowi --excludelabel=so

cat wiwi.txt | egrep -v '6441$' > wiwi.txt.tmp
cat sowi.txt | egrep -v '6441$' > sowi.txt.tmp
mv -f wiwi.txt.tmp wiwi.txt
mv -f sowi.txt.tmp sowi.txt
