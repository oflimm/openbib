#!/bin/bash

function usage {
        printf "Usage: ${0##*/} DUMPDIR \n\n"
        exit 1
}

export DUMPDIR=$1

(( $# != 1 )) && usage

cd $DUMPDIR

for db in `/opt/openbib/bin/show_active_pools.pl | sort`;do
    echo "Removing pool package for $db"
    rm ${db}.opp
    echo "Building pool package for $db"
    /opt/openbib/bin/dump_pool.pl --database=$db
    echo "Done"
done
