#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    my $fields_ref = $record_ref->{fields};

    my $titleid = $record_ref->{id};
    
    # Uebertragung der URLs in andere Katagorie
    #
    # Link in content von 4662
    # Zugriffsstatus in subfield von 4662
    # Beschreibungstext in content von 4663
    #
    # Eintraege von 4662 und 4663 bilden eine Multgruppe (Zuordnung via mult)   
    #
    # Ausnahme Links zu Inhaltsvereichnissen
    # Link zum Inhaltsverzeichnis in content von 4110 analog
    # zu angereicherten Links zu Inhaltsverzeichnissen in E4110
    #
    # Zugriffstatus
    #
    # '' : Keine Ampel
    # ' ': Unbestimmt g oder y oder r
    # 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
    # 'g': Freier Zugriff (green)
    # 'y': Lizensierter Zugriff (yellow)
    # 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
    # 'r': Kein Zugriff (red)

    my $mult_ref = {};

    $mult_ref->{'4662'} = 1;

    # Links in 0662 gehen immer zum lizensierten Volltext
    if (defined $fields_ref->{'0662'}) {

	# Alle Links nacheinander durchgehen
	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    my $content = $item_ref->{content};
	    my $mult    = $mult_ref->{'4662'}++;

	    my $url         = $content;
	    my $description = "E-Book im Volltext";
	    my $access      = "y"; # yellow
	    
	    push @{$record_ref->{fields}{'4662'}}, {
		mult     => $mult,
		subfield => $access,
		content  => $content,
	    };
	    
	    push @{$record_ref->{fields}{'4663'}}, {
		mult     => $mult,
		subfield => '',
		content  => $description,
	    };
	}
	    
    }
    
    # Volltext-Links zusaetzlich in 4120 ablegen fuer direkte Verlinkung in Trefferliste

    if (defined $fields_ref->{'4662'}){
	foreach my $item_ref (@{$fields_ref->{'4662'}}){
	    if ($item_ref->{subfield} =~m/(g|y|f)/){
		$record_ref->{fields}{'4120'} = [{
		    mult     => 1,
		    subfield => $item_ref->{subfield},
		    content  => $item_ref->{content},
						 }];
	    }
	    last;
	}	
    }    
    
    print encode_json $record_ref, "\n";
}
