#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $holding_ref = decode_json $_;

    next unless ($holding_ref->{id} =~m/:DE-832:/);

    print encode_json $holding_ref, "\n";
}
