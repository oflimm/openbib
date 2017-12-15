#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'4400'}){
	delete $title_ref->{fields}{'4400'};
    }
    
    print encode_json $title_ref, "\n";
}
