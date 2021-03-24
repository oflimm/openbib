#!/usr/bin/perl

use JSON::XS;
use utf8;

while (<>){
    my $record_ref = decode_json $_;
    my $fields_ref = $record_ref->{fields};
    
    # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
    # der Kurztitelliste:
    #
    # 1. Fall: Es existiert ein HST
    #
    # Dann:
    #
    # Ist nichts zu tun
    #
    # 2. Fall: Es existiert kein HST(331)
    #
    # Dann:
    #
    # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
    #
    # Dann: Verwende diese Bandzahl
    #
    # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
    #                Bandzahl(455)
    #
    # Dann: Verwende diese Bandzahl
    #
    # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
    #                Gesamttitel(451)
    #
    # Dann: Verwende diesen GT
    #
    # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
    #                aber eine Zeitschriftensignatur(1204/USB-spezifisch)
    #
    # Dann: Verwende diese Zeitschriftensignatur
    #
    if (!defined $fields_ref->{'0331'}) {
	# UnterFall 2.1:
	if (defined $fields_ref->{'0089'}) {
	    $title_ref->{fields}{'0331'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $fields_ref->{'0089'}[0]{content},
		},
		];
	}
	# Unterfall 2.2:
	elsif (defined $fields_ref->{'0455'}) {
	    $title_ref->{fields}{'0331'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $fields_ref->{'0455'}[0]{content},
		},
		];
	}
	# Unterfall 2.3:
	elsif (defined $fields_ref->{'0451'}) {
	    $title_ref->{fields}{'0331'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $fields_ref->{'0451'}[0]{content},
		},
		];
	}
	# Unterfall 2.4:
	elsif (defined $fields_ref->{'1204'}) {
	    $title_ref->{fields}{'0331'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $fields_ref->{'1204'}[0]{content},
		},
		];
	}
    }

    print encode_json $fields_ref, "\n";
}
