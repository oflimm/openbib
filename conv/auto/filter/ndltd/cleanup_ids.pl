#!/usr/bin/perl

use utf8;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    $title_ref->{id} =~s/[^0-9A-Za-z.:]/_/g;
    
    print encode_json $title_ref, "\n";
}
