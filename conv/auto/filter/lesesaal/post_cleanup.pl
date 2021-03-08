#!/usr/bin/perl

my $pool=$ARGV[0];

system("/opt/openbib/conv/dump_titles2csv.pl --database=$pool --outputfile=/opt/openbib/autoconv/pools/$pool/${pool}.csv");
