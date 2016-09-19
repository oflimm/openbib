#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0025'}){
	$title_ref->{fields}{'4726'} = $title_ref->{fields}{'0025'};
	delete $title_ref->{fields}{'0025'};
    }
   
    print encode_json $title_ref, "\n";
}
