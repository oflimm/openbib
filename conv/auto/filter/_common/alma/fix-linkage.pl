#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};
use OpenBib::Catalog::Subset;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

unlink "./linkage.db";

my %linkid2mmsid                = ();

tie %linkid2mmsid,             'MLDBM', "./linkage.db"
    or die "Could not tie linkage.\n";

print STDERR "### uni: Analysiere Titeldaten\n";

open(TITLE,"meta.title");

while (<TITLE>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    if (defined $title_ref->{fields}{'0035'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0035'}}){
	    if ($item_ref->{'subfield'} eq "a" ){		
		my $linkid = $item_ref->{'content'};

		# Eingrenzung auf ZDB und hbz
		next unless ($linkid =~m/(DE-600|DE-605)/);
		
		if (defined $linkid2mmsid{$linkid}){
		    print STDERR "### uni: Fremd-ID $linkid doppelt fuer MMSID (bisher ".$linkid2mmsid{$linkid}.", jetzt auch $titleid)\n";
		}
		else {
		    $linkid2mmsid{$linkid} = $titleid;
		}
	    }
	}
    }
}

close(TITLE);

print STDERR "### uni: Verknuepfungs-ID in 773\$w, 776\$w und 830\$w von Fremd-ID auf MMSID aendern\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    foreach my $field ('0773','0776','0830'){
	if (defined $title_ref->{fields}{$field}){
	    foreach my $item_ref (@{$title_ref->{fields}{$field}}){
		if ($item_ref->{'subfield'} eq "w"){
		    my $linkid = $item_ref->{'content'};
		    
		    # MMSIDs als linkid wollen wir, also ignorieren
		    next if ($linkid =~m/^\d+$/);
		    
		    # Eingrenzung auf ZDB und hbz
		    unless ($linkid =~m/(DE-600|DE-605)/) {
			print STDERR "### uni: Fremd-ID $linkid nicht unterstuetzt bei MMSID $titleid\n";
			next;
		    }

		    # Umstellung der linkid auf MMSID - falls vorhanden
		    if (defined $linkid2mmsid{$linkid}){
			$item_ref->{'content'} = $linkid2mmsid{$linkid};
		    }
		    else {
			print STDERR "### uni: Fremd-ID $linkid nicht vorhanden bei MMSID $titleid\n";
		    }
		}
	    }
	}
    }
    
    print encode_json $title_ref, "\n";
}
