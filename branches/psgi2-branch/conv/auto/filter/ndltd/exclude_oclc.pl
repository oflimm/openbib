#!/usr/bin/perl

use utf8;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if ($title_ref->{id} !~m/oclc/i){
	print encode_json $title_ref, "\n";
    }
}
