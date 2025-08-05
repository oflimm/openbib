#!/usr/bin/perl

use HTML::Entities qw/decode_entities/;
use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

my $default_access = 'y';

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
    # Link zum Volltext in 4120 mit Zugriffsstatus in subfield
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

    my $url_done_ref = {};
        
    # Jetzt Analyse der URLs in 856
    
    if (defined $fields_ref->{'0856'}){

	# Umorganisieren nach Mult-Gruppe
	my $url_info_ref = {};
	
	foreach my $item_ref (@{$fields_ref->{'0856'}}){
	    my $content = $item_ref->{content};

	    if ($item_ref->{subfield} eq "u"){  # Fix Swisslex URLs
		$content=~s{http://https://}{https://};
		$item_ref->{content} = $content;
	    }
	    
	    $url_info_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $content;
	}

	foreach my $umult (sort keys %$url_info_ref){
	    if (defined $url_info_ref->{$umult}{'u'}){
		my $url      = $url_info_ref->{$umult}{'u'};
		my $note     = $url_info_ref->{$umult}{'z'};
		my $material = $url_info_ref->{$umult}{'3'};

		my $description = "E-Book im Volltext";

		$url=~s{http://https://}{https://}; # Fix Swisslex URLs
		
		my $mult = $mult_ref->{'4662'}++;

		# URL schon ueber Portfolios verarbeitet? Dann ignorieren
		next if (defined $url_done_ref->{$url} && $url_done_ref->{$url});

		push @{$record_ref->{fields}{'4662'}}, {
		    mult     => $mult,
		    subfield => $default_access,
		    content  => $url,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
		    mult     => $mult,
		    subfield => '',
		    content  => $description,
		};

		
		$url_done_ref->{$url} = 1;			
		
	    }
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
