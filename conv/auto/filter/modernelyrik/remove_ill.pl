#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    my $is_ill = 0;
    
    if (defined $record_ref->{fields}{'1944'}){
	foreach my $item_ref (@{$record_ref->{fields}{'1944'}}){
	    if ($item_ref->{subfield} eq "m" && $item_ref->{content} eq "RES_ILL"){
		$is_ill = 1;
	    }
	}
    }

    next if ($is_ill);
    
    print encode_json $record_ref, "\n";
}
