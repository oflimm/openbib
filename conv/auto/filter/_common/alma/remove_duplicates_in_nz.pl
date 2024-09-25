#!/usr/bin/perl

# Remove duplicates in combined published electronic titles of NZ for titles already in IZ
# Problem: combined published titles get NZ MMSID even when also in IZ!

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;

    my $mmsid_is_iz = 0;

    my $titleid = $record_ref->{'id'};

    if ($titleid=~m/6476$/){ # MMSID Suffix for UBK is 6476
	$mmsid_is_iz = 1;
    }

    my $remove_title = 0;
    
    if (!$mmsid_is_iz){

	my $fields_ref = $record_ref->{fields};
	
	if (defined $fields_ref->{'0035'}){
	    foreach my $item_ref (@{$fields_ref->{'0035'}}){
		if ($item_ref->{subfield} eq "a" && $item_ref->{content} =~m/49HBZ_UBK/){
		    $remove_title = 1;
		}
	    }
	}
    }

    next if ($remove_title);

    print encode_json $record_ref, "\n";
}
