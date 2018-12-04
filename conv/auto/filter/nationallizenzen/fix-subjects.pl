#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### nationallizenzen Korrigiere Schlagworte\n";

while (<>){
    my $record_ref = decode_json $_;

    my $gnd;

    foreach my $fields_ref (@{$record_ref->{fields}{'0800'}}){
	($gnd) = $fields_ref->{content} =~m/^\s+([0-9-]+)\s+/;
	$fields_ref->{content}=~s/^\s+[0-9-]*\s+\|*//g;
    }
    
    if ($gnd){
	push @{$record_ref->{fields}{'0010'}}, {
	    content => $gnd,
	    mult => 1,
	    subfield => '',
	};
    }
    
    print encode_json $record_ref, "\n";
}
