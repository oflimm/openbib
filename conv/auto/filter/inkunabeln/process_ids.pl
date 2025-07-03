#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    my $fields_ref = $record_ref->{fields};

    my $mult_ref = {};

    $mult_ref->{'1001'} = 1;

    if (defined $fields_ref->{'0035'}){
	foreach my $item_ref (@{$fields_ref->{'0035'}}){
	    if ($item_ref->{subfield} eq "a"){
		if ($item_ref->{content} =~m/^\(ISTC\)(.+?)$/){
		    my $istcid = $1;

		    my $mult    = $mult_ref->{'1001'}++;

		    push @{$record_ref->{fields}{'1001'}}, {
			mult     => $mult,
			subfield => 'i', # ISTC = Inkunablen
			content  => $istcid,
		    };
		}
		elsif ($item_ref->{content} =~m/^\(GW\)(.+?)$/){
		    my $gwid = $1;

		    my $mult    = $mult_ref->{'1001'}++;

		    push @{$record_ref->{fields}{'1001'}}, {
			mult     => $mult,
			subfield => 'w', # Gesamtverzeichnis Wiegendrucke
			content  => $gwid,
		    };
		}
	    }
	}
    }

    print encode_json $record_ref, "\n";
}
