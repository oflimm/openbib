#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### kubibooks Korrektur Exemplardaten\n";

while (<>){
    my $holding_ref = decode_json $_;

    my $location_ref = [];
    foreach my $mark_ref (@{$holding_ref->{fields}{'0014'}}){
        if ($mark_ref->{content} =~m/KMB/){
	    my $new_location_ref = {
		content => "DE-Kn3",
		mult    => $mark_ref->{mult},
		subfield => $mark_ref->{subfield},
	    };
	    push $location_ref, $new_location_ref;
        }
    }

    $holding_ref->{fields}{'3330'} = $location_ref;

    print encode_json $holding_ref, "\n";
}

