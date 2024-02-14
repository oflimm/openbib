#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $holding_ref = decode_json $_;
    
    next if ($holding_ref->{fields}{3330}[0]{content} =~m/BONN/);

    print encode_json $holding_ref, "\n";
}
