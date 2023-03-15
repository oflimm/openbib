#!/usr/bin/perl

my $pool=$ARGV[0];

print "### $pool: Metriken erstellen und cachen\n";
system("/opt/openbib/bin/gen_metrics.pl --database=$pool --type=16");

