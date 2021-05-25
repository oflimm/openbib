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

    # Uebertragung der URLs in andere Katagorie
    #
    # Link zum Inhaltsverzeichnis:
    #
    # Uebertragen in Titelfeld fuer Inhaltsverzeichnisse T4110
    # Analog zu angereicherten Link zu Inhaltsverzeichnissen in E4110
    
    if (defined $fields_ref->{'0662'}) {
	my $description_ref = {};

	foreach my $item_ref (@{$fields_ref->{'0663'}}){
	    $description_ref->{$item_ref->{mult}} = $item_ref->{content};
	}

	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    # Inhaltsverzeichnisse
	    if (defined $description_ref->{$item_ref->{mult}} &&  $description_ref->{$item_ref->{mult}} =~m/Inhaltsverzeichnis/){
		$record_ref->{fields}{'4110'} = [
		    {
			mult     => 1,
			subfield => '',
			content  => $item_ref->{content},
		    },
		    ];
	    }

	    # Volltexte
	    #
	    # Kriterien fuer freie Volltextlinks:
	    #
	    # Inhalt von 0663 (.+? steht fuer einen beliebigen Inhalt dazwischen):
	    #
	    # - Interna: Verlag.+?Info: kostenfrei
	    # - Interna: Verlag.+?Info: Deutschlandweit zugänglich
	    # - Interna: Langzeitarchivierung.+?Info: kostenfrei
	    # - Interna: Digitalisierung.+?Info: kostenfrei
	    if (
		defined $description_ref->{$item_ref->{mult}} &&
		
		( $description_ref->{$item_ref->{mult}} =~m/Interna: Verlag.+?Info: kostenfrei/
		|| $description_ref->{$item_ref->{mult}} =~m/Interna: Verlag.+?Info: Deutschlandweit zugänglich/
		|| $description_ref->{$item_ref->{mult}} =~m/Interna: Langzeitarchivierung.+?Info: kostenfrei/
		|| $description_ref->{$item_ref->{mult}} =~m/Interna: Digitalisierung.+?Info: kostenfrei/ )
		){
		$record_ref->{fields}{'4120'} = [
		    {
			mult     => 1,
			subfield => 'a',
			content  => $item_ref->{content},
		    },
		    ];
	    }	    
	    # Kriterien fuer lizensierte Volltextlinks:
	    #
	    # Inhalt von 0663 (.+? steht fuer einen beliebigen Inhalt dazwischen):
	    #
	    # - Interna: Resolving-System
	    elsif (
		defined $description_ref->{$item_ref->{mult}} && 
		(  $description_ref->{$item_ref->{mult}} =~m/Interna: Resolving-System/
		   || $description_ref->{$item_ref->{mult}} =~m//
		)
		){
		$record_ref->{fields}{'4120'} = [
		    {
			mult     => 1,
			subfield => 'b',
			content  => $item_ref->{content},
		    },
		    ];
	    }
	    # Kriterien fuer lizensierte Volltextlinks:
	    #
	    # Inhalt von 0663 (.+? steht fuer einen beliebigen Inhalt dazwischen):
	    #
	    # - Interna: EZB
	    # Bemerkung: EZB-Bezeichnungen kommen in der Regel mit anderen oben schon genannten Inhalten
	    # zusammen. Deshalb sind sie nur 'zweite Wahl'
	    elsif (
		defined $description_ref->{$item_ref->{mult}} && $description_ref->{$item_ref->{mult}} =~m/Interna: EZB/		
		){
		$record_ref->{fields}{'4120'} = [
		    {
			mult     => 1,
			subfield => 'b',
			content  => $item_ref->{content},
		    },
		    ];
	    }
	}
    }

    print encode_json $record_ref, "\n";
}
