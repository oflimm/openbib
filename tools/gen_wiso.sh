#!/bin/bash

cd /var/www.opendata/dumps/misc/
/opt/openbib/bin/get_titleid_by_subjectarea.pl --area=wiwi --excludelabel=wi
/opt/openbib/bin/get_titleid_by_subjectarea.pl --area=sowi --excludelabel=so
