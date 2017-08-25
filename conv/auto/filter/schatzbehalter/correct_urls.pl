#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0662'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0662'}}){
	    if ($item_ref->{content}=~m/aleki/){
		$item_ref->{content}=~s{http://www.aleki.uni-koeln.de/}{http://www.uni-koeln.de/phil-fak/deutsch/aleki/};
	    }
	}
    }

    
    print encode_json $title_ref, "\n";
}

