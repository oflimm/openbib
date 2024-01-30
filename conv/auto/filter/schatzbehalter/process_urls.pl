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
    
    # Uebertragung der URLs in andere Katagorie 4120
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

    if (defined $fields_ref->{'0662'}) {
	foreach my $item_ref (@{$fields_ref->{'0662'}}){	    
	    $record_ref->{fields}{'4120'} = [{
		mult     => 1,
		subfield => 'f',
		content  => $item_ref->{content},
					     }];
	    last;
	}
    }
    
    print encode_json $record_ref, "\n";
}
