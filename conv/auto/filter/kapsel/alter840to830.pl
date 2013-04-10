#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

while (<>){
    my $subject_ref = decode_json $_;

    if (defined $subject_ref->{'0840'}){
        $subject_ref->{'0830'} = $subject_ref->{'0840'};
        delete $subject_ref->{'0840'};
    }

    print encode_json $subject_ref, "\n";
}

