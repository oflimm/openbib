#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### usblbs Korrektur Exemplardaten\n";

while (<>){
    my $holding_ref = decode_json $_;

    my $ignore_holding = 0;
    foreach my $location_ref (@{$holding_ref->{fields}{'0016'}}){
        if ($location_ref->{content} ne '38-LBS'){
	    $ignore_holding = 1;
        }
    }

    next if ($ignore_holding);

    print encode_json $holding_ref, "\n";
}

