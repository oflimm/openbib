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

    my $fulltext_url = "";
    if (defined $fields_ref->{'0010'}) {
	foreach my $item_ref (@{$fields_ref->{'0010'}}){
	    if ($item_ref->{content} =~m/^DOI:\s+(.+)$/){
		$fulltext_url = "https://doi.org/$1";
	    }
	}
    }
    
    if (!$fulltext_url && defined $fields_ref->{'0662'}) {
	my $new_ref = [];
	foreach my $item_ref (@{$fields_ref->{'0662'}}){
	    next if ($item_ref->{content} =~m/doabooks.org/);
	    $fulltext_url = $item_ref->{content};
	    push @$new_ref, $item_ref;
	    
	}	
	$fields_ref->{'0662'} = $new_ref if ($new_ref);
    }

    if ($fulltext_url){
	$record_ref->{fields}{'4120'} = [
	    {
		mult     => 1,
		subfield => 'a',
		content  => $fulltext_url,
	    },
	    ];
    }
    
    print encode_json $record_ref, "\n";
}
