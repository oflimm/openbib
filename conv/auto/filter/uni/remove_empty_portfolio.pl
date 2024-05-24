#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    if (defined $record_ref->{fields}{'1945'}){
	my $new_portfolio_ref = [];
	
	foreach my $item_ref (@{$record_ref->{fields}{'1945'}}){
	    if ($item_ref->{subfield} eq "b" && $item_ref->{content} eq "Not Available"){
		next;
	    }
	    
	    push @{$new_portfolio_ref}, $item_ref;
	}

	if (@{$new_portfolio_ref}){
	    $record_ref->{fields}{'1945'} = $new_portfolio_ref;
	}
	else {
	    $record_ref->{fields}{'1945'} = [];
	    delete $record_ref->{fields}{'1945'};
	}
    }
    
    print encode_json $record_ref, "\n";
}
