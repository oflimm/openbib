#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### inst117 Korrektur Exemplardaten\n";

my $broken_count = 0;

while (<>){
    my $holding_ref = decode_json $_;

    my $ignore_holding = 0;
    foreach my $location_ref (@{$holding_ref->{fields}{'0016'}}){
        if ($location_ref->{content} = '( )'){
            if (!defined $holding_ref->{fields}{'0014'}){
                $ignore_holding = 1;
		$broken_count++;
            }
	    else {
		$location_ref->{content}='';
	    }
        }
    }

    next if ($ignore_holding);

    print encode_json $holding_ref, "\n";
}

print STDERR "### inst117 Entfernte Exemplare: $broken_count\n";
