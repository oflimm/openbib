#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use OpenBib::Config;

use warnings;
use strict;

my $config = new OpenBib::Config;

my $this_year = sprintf "%04d",((localtime)[5] +1900);

# Definition der Faktoren fuer Boost oder Throttle
my $boost_year_range1      = 2;   # Titel der letzten x Jahre werden geboostet
my $boost_year_factor1     = 1.5; # Boost-Faktor bzgl. urspruenglichem Weight
my $boost_year_range2      = 5;   # Titel der letzten z Jahre werden geboostet
my $boost_year_factor2     = 1.3; # Boost-Faktor bzgl. urspruenglichem Weight

my $boost_fulltext_factor  = 1.2; # Titel mit Volltexten werden geboostet

my $throttle_volume_factor = 0.6; # Throttle fuer Baende

my $searchfield_ref = $config->get('searchfield');

while (<>){
    my $record_ref = decode_json $_;

    my $index_ref = $record_ref->{index};
    my $data_ref  = $record_ref->{record};
    
    my $data_year;

    if (defined $data_ref->{'T0425'}){
	($data_year) = $data_ref->{'T0425'}[0]{'content'} =~m/(\d\d\d\d)/;
    }

    my $with_fulltext = 0;

    if (defined $data_ref->{'T4120'}){
	$with_fulltext = 1;
    }

    my $is_volume = 0;

    if (defined $data_ref->{'T0089'}){
	$is_volume = 1;
    }
    
    foreach my $field (keys %{$index_ref}){
	next unless (defined $searchfield_ref->{$field});
	
	foreach my $weight (keys %{$index_ref->{$field}}){
	    my $this_terms_ref = $index_ref->{$field}{$weight} ;

	    my $this_weight = $weight;
	    
	    my $new_weight  = 0;
	    
	    # Genereller Throttle fuer Baende
	    {
		if ($is_volume){
		    $new_weight = int($this_weight * $throttle_volume_factor);
		    $this_weight = $new_weight;
		}
	    }
	    
	    # Genereller Boost der letzten Erscheinungsjahre
	    {
		if (defined $data_year && $data_year >= $this_year - $boost_year_range1 ){
		    $new_weight = int($this_weight * $boost_year_factor1);
		    $this_weight = $new_weight;		    
		}
		elsif (defined $data_year && $data_year >= $this_year - $boost_year_range2 ){
		    $new_weight = int($this_weight * $boost_year_factor2);
		    $this_weight = $new_weight;
		}
	    }
	    
	    # Genereller Boost mit Links zum Volltext
	    {
		if ($with_fulltext){
		    $new_weight = int($this_weight * $boost_fulltext_factor);
		    $this_weight = $new_weight;
		}
	    }

	    # Genereller Boost mit Popularitaet
	    # Todo
	    	    
	    # Weight ggf neu setzen
	    if ($new_weight && $weight ne $new_weight){
		$index_ref->{$field}{$new_weight} = $this_terms_ref ;
		$index_ref->{$field}{$weight} = [];
		delete $index_ref->{$field}{$weight};
	    }
	}
    }
    
    print encode_json $record_ref, "\n";
}
