#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_ebook = 0;

    if (defined $title_ref->{fields}{"0540"}){
	foreach my $item_ref (@{$title_ref->{fields}{"0540"}}){
	    $is_ebook = 1;
	}
    }

    next if (!$is_ebook);
    
    print encode_json $title_ref, "\n";
}
