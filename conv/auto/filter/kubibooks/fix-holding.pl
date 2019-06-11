#!/usr/bin/perl

use utf8;

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### kubibooks Korrektur Exemplardaten\n";

while (<>){
    my $holding_ref = decode_json $_;

    my $location_ref = [];
    my $isil_ref = [];
    foreach my $mark_ref (@{$holding_ref->{fields}{'0014'}}){
        if ($mark_ref->{content} =~m/KMB/){
	    my $new_location_ref = {};
	    my $new_isil_ref = {};
	    
	    if ($mark_ref->{content} =~m{^KMB/WRM/}){
		$new_location_ref = {
		    content => '<a href="https://www.wallraf.museum/" target="_blank">Wallraf-Richartz-Museum</a>',
		    mult    => $mark_ref->{mult},
		    subfield => $mark_ref->{subfield},
		};

		$new_isil_ref = {
		    content => "DE-MUS-079214",
		    mult    => $mark_ref->{mult},
		    subfield => $mark_ref->{subfield},
		};
		
	    }
	    elsif ($mark_ref->{content} =~m{^KMB/MAKK/}){
		$new_location_ref = {
		    content => '<a href="https://museenkoeln.de/museum-fuer-angewandte-kunst/" target="_blank">Museum für Angewandte Kunst Köln</a>',
		    mult    => $mark_ref->{mult},
		    subfield => $mark_ref->{subfield},
		};

		$new_isil_ref = {
		    content => "DE-MUS-078617",
		    mult    => $mark_ref->{mult},
		    subfield => $mark_ref->{subfield},
		};
		
	    }
	    else {
		$new_location_ref = {
		    content => '<a href="https://www.museenkoeln.de/kunst-und-museumsbibliothek/" target="_blank">Kunst und Musemsbibliothek K&ouml;ln',
		    mult    => $mark_ref->{mult},
		    subfield => $mark_ref->{subfield},
		};
		
		$new_isil_ref = {
		    content => "DE-Kn3",
		    mult    => $mark_ref->{mult},
		    subfield => $mark_ref->{subfield},
		};
	    }
	    
	    push @$location_ref, $new_location_ref;

	    push @$isil_ref, $new_isil_ref;

        }
    }

    $holding_ref->{fields}{'3330'} = $isil_ref if (@$isil_ref);
    $holding_ref->{fields}{'0016'} = $location_ref if (@$location_ref);

    print encode_json $holding_ref, "\n";
}

