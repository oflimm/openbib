#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    delete $title_ref->{'4400'} if (defined $title_ref->{'4400'});

    print encode_json $title_ref, "\n";
}
