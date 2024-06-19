#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    next if ($titleid < 70000);
    
    print encode_json $title_ref, "\n";
}
