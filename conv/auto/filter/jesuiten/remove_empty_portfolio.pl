#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    if (defined $record_ref->{fields}{'1945'}){
	my $tmp_portfolio_ref = {};
	
	foreach my $item_ref (@{$record_ref->{fields}{'1945'}}){
	    push @{$tmp_portfolio_ref->{$item_ref->{mult}}}, $item_ref;
	}

	my $new_portfolio_ref = [];
	
	foreach my $mult (keys %{$tmp_portfolio_ref}){
	    my $skip_mult = 0;
	    foreach my $item_ref (@{$tmp_portfolio_ref->{$mult}}){
		if ($item_ref->{subfield} eq "b" && $item_ref->{content} eq "Not Available"){
		    $skip_mult = 1;
		}
	    }

	    unless ($skip_mult){
		push @{$new_portfolio_ref}, @{$tmp_portfolio_ref->{$mult}};
	    }
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
