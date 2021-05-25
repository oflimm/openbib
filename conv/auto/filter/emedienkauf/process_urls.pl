#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    my $fields_ref = $record_ref->{fields};
    
    # Uebertragung der URLs in andere Katagorie
    #
    # Link zum Volltext:
    #
    # Uebertragen in Titelfeld fuer E-Medien T4120
    # Analog zu angereicherten Link zu E-Medien in E4120
    #
    # Markierung von URLs nach Typ in Subfield
    #
    #  : Unbekannt
    # a: Freier Zugriff    
    # b: Eingeschraenkter Zugriff
    # c: Kein Zugriff
    
    if (defined $fields_ref->{'0662'}) {
	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    $record_ref->{fields}{'4120'} = [
		{
		    mult     => 1,
		    subfield => 'b',
		    content  => $item_ref->{content},
		},
		];
	}
    }

    print encode_json $record_ref, "\n";
}
