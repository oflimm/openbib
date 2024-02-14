#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $holding_ref = decode_json $_;
    
    next unless ($holding_ref->{3330}[0]{content} =~m/KOELN/);

    print encode_json $holding_ref, "\n";
}
