#!/usr/bin/perl

# Extract year(like) number from volume definition and add it as year for indexing and facetting
# eg 2022,SEP/OKT -> 2022

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

# year 'valid' beginning at 1890
my $min_year = 1890;

while (<>){
    my $record_ref = decode_json $_;
    
    my $fields_ref = $record_ref->{fields};

    my $volume2year = 0;
    
    # Is volume?
    if (defined $fields_ref->{'0773'}){
	foreach my $item_ref (@{$fields_ref->{'0245'}}){
	    if ($item_ref->{subfield} eq "n"){
		# Match possible year
		if ($item_ref->{content} =~m/(\d\d\d\d)/){
		    my $year = $1;

		    if ($year < $min_year){
			next;
		    }

		    $volume2year = $year;
		}
	    }
	}
    }

    my $year_enriched = 0;

    if ($volume2year && defined $fields_ref->{'0264'}){

	# Year already in 264$c?
	foreach my $item_ref (@{$fields_ref->{'0264'}}){
	    if ($item_ref->{subfield} eq "c"){
		$year_enriched = 1;
	    }
	}
	
	# If not: add it
	if (!$year_enriched){
	    unshift @{$fields_ref->{'0264'}}, {
		content  => $volume2year,
		mult     => 1,
		subfield => 'c',
	    };
	    $year_enriched = 1;
	}
    }

    # Year found but no 264, then create
    if ($volume2year && !$year_enriched){
	push @{$fields_ref->{'0264'}}, {
	    content  => $volume2year,
	    mult     => 1,
	    subfield => 'c',
	};
    }

    print encode_json $record_ref, "\n";
}
