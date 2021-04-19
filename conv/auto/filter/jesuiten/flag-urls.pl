#!/usr/bin/perl

use JSON::XS;
use utf8;

while (<>){
    my $record_ref = decode_json $_;
    my $fields_ref = $record_ref->{fields};
    
    # Uebertragung der URLs in andere Katagorie
    #
    # Link zum Volltext:
    #
    # Uebertragen in Titelfeld fuer Inhaltsverzeichnisse T4120
    # Analog zu angereicherten Link zu Inhaltsverzeichnissen in E4120
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

	foreach my $item_ref (@${fields_ref->{'0663'}}){
	    $description_ref->{$item_ref->{mult}} = $item_ref->{content};
	}

	foreach my $item_ref (@${fields_ref->{'0662'}}){
	    if ($description_ref->{$item_ref->{mult}} =~/Inhaltsverzeichnis/){
	    $title_ref->{fields}{'4110'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $fields_ref->{'0662'}[0]{content},
		},
		];

	    }
	}
    }

    print encode_json $fields_ref, "\n";
}
