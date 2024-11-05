#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### usblbs: Korrektur Indexierung\n";

while (<>){
    my $index_ref = decode_json $_;

    # Signaturen fuer die Anzeige auf Grundsignatur reduzieren und Ziffern vornullen

    if (defined $index_ref->{'record'}{'X0014'}){
	my @signaturen = ();

	foreach my $item_ref (@{$index_ref->{'record'}{'X0014'}}){
	    my $signatur = $item_ref->{content};

	    if ($signatur =~m/^([A-Z][A-Z])(\d+?)([a-z]*)\#$/){ 
		$signatur = sprintf "%s%04d%s",$1,$2,$3;
		push @signaturen, $signatur;
	    }
	}
	
	if (@signaturen){
	    $index_ref->{'record'}{'X0014'} = [];
	    foreach my $signatur (uniq @signaturen){
		push @{$index_ref->{'record'}{'X0014'}}, {
		    content  => $signatur,
		    subfield => 'a',
		};
	    }
	}
    }

    # Nur Signaturen fuer die Indexierung im Feld markstring verwenden, die die Form einer LBS-Signatur haben (AB123#2), um Kollisionen mit LBS-fremden Signaturen der gleichen Signaturgruppe zu vermeiden

    my $new_markstring = {};
    
    if (defined $index_ref->{'index'}{'markstring'}){
	foreach my $weight (keys %{$index_ref->{'index'}{'markstring'}}){

	    my @signaturen = ();

	    foreach my $item_ref (@{$index_ref->{'index'}{'markstring'}{$weight}}){
		my $signatur = $item_ref->[1] if ($item_ref->[0] eq "X0014");

		if ($signatur =~m/^[A-Z][A-Z]\d+?[a-z]*\#$/){ 
		    
		    push @signaturen, $item_ref;
		}
	    }

	    if (@signaturen){
		$new_markstring->{$weight} = \@signaturen;
	    }
	}
    }
    
    if  (keys %$new_markstring){
	$index_ref->{'index'}{'markstring'} = $new_markstring;
    }
    else {
	$index_ref->{'index'}{'markstring'} = {};
	delete $index_ref->{'index'}{'markstring'};
    }
    
    print encode_json $index_ref, "\n";
}

