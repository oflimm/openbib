#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
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
    # 'y': Eingeschraenkter Zugriff (yellow)
    # 'r': Kein Zugriff (red)

    my $mult_ref = {};

    $mult_ref->{'4662'} = 1;

    my $fulltext_done = 0;

    if (defined $record_ref->{fields}{'0010'}) {
	my $fulltext_url = "";

	foreach my $item_ref (@{$record_ref->{fields}{'0010'}}){
	    if ($item_ref->{content} =~m/^DOI:\s+(.+)$/){
		$fulltext_url = "https://doi.org/$1";
	    }
	}

	if ($fulltext_url){
	    # Ab hier potentieller Link zum lizensierten E-Book im Volltext
	    my $description = "E-Book im Volltext";
	    my $access      = "g"; # green

	    my $mult        = $mult_ref->{'4662'}++;

	    push @{$record_ref->{fields}{'4662'}}, {
		mult     => $mult,
		subfield => $access,
		content  => $fulltext_url,
	    };
	    
	    push @{$record_ref->{fields}{'4663'}}, {
		mult     => $mult,
		subfield => '',
		content  => $description,
	    };

	    # Nur ersten Link als Volltext-Link verwenden.
	    if (!$fulltext_done) { 
		$record_ref->{fields}{'4120'} = [
		    {
			mult     => 1,
			subfield => $access,
			content  => $fulltext_url,
		    },
		    ];
		$fulltext_done = 1;
	    }
	}
    }
    
    if (defined $record_ref->{fields}{'0662'}) {
	
	foreach my $item_ref (@{$record_ref->{fields}{'0662'}}){
	    my $mult        = $mult_ref->{'4662'}++;
	    my $url         = $item_ref->{content};

	    next if ($url =~m/doabooks.org/);
	    
	    # Link zum Cover ggf. anhand URL erkennen.
	    if ($url =~m/cover/){
		my $description = "Umschlag";
		push @{$record_ref->{fields}{'4662'}}, {
		    mult     => $mult,
		    subfield => '',,
		    content  => $url,
		};
		
		push @{$record_ref->{fields}{'4663'}}, {
		    mult     => $mult,
		    subfield => '',
		    content  => $description,
		};
		
		next;
	    }

	    # Ab hier potentieller Link zum lizensierten E-Book im Volltext
	    my $description = "E-Book im Volltext";
	    my $access      = "g"; # green
	    
	    push @{$record_ref->{fields}{'4662'}}, {
		mult     => $mult,
		subfield => $access,
		content  => $url,
	    };
	    
	    push @{$record_ref->{fields}{'4663'}}, {
		mult     => $mult,
		subfield => '',
		content  => $description,
	    };

	    # Nur ersten Link als Volltext-Link verwenden.
	    if (!$fulltext_done) { 
		$record_ref->{fields}{'4120'} = [
		    {
			mult     => 1,
			subfield => $access,
			content  => $url,
		    },
		    ];
		$fulltext_done = 1;
	    }
	}
    }

    print encode_json $record_ref, "\n";
}
