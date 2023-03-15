#!/usr/bin/perl

my $pool=$ARGV[0];

print "### $pool: Metriken erstellen und cachen\n";
system("/opt/openbib/bin/gen_metrics.pl --database=$pool --type=15");

print "### $pool: Daten als CSV exportieren\n";
system("/opt/openbib/conv/dump_titles2csv.pl --database=$pool --outputfile=/opt/openbib/autoconv/pools/$pool/${pool}.csv");

