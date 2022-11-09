#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### lesesaal: Korrektur Indexierung\n";

while (<>){
    my $index_ref = decode_json $_;

    # Signaturen fuer die Anzeige auf Grundsignatur reduzieren und Ziffern vornullen

    if (defined $index_ref->{'record'}{'X0014'}){
	my @signaturen = ();

	foreach my $item_ref (@{$index_ref->{'record'}{'X0014'}}){
	    my $signatur = $item_ref->{content};

	    if ($signatur =~m{^LS/([A-Za-z]+)(\d+?)$}){ 
		$signatur = sprintf "LS/%s%06d",$1,$2;
		push @signaturen, $signatur;
	    }
	}
	
	if (@signaturen){
	    $index_ref->{'record'}{'X0014'} = [];
	    foreach my $signatur (uniq @signaturen){
		push @{$index_ref->{'record'}{'X0014'}}, {
		    content => $signatur,
		};
	    }
	}
    }

    
    print encode_json $index_ref, "\n";
}

