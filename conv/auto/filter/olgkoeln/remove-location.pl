#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $holding_ref = decode_json $_;

    if (defined $holding_ref->{fields}{'0016'} && $holding_ref->{fields}{'0016'}[0]{content} eq "USB-Magazin"){
        delete $holding_ref->{fields}{'0016'};
    }

    print encode_json $holding_ref, "\n";
}
