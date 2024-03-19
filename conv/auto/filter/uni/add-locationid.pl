#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};
use OpenBib::Catalog::Subset;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

unlink "./title_locationid.db";
unlink "./title_has_parent.db";
unlink "./is_parent.db";
unlink "./title_with_no_children.db";

our %title_locationid       = ();
our %title_has_parent       = ();
our %is_parent              = ();
our %title_with_no_children = ();

tie %title_locationid,             'MLDBM', "./title_locationid.db"
    or die "Could not tie title_locationid.\n";

tie %title_has_parent,             'MLDBM', "./title_has_parent.db"
    or die "Could not tie title_has_parent.\n";

tie %is_parent,             'MLDBM', "./is_parent.db"
    or die "Could not tie is_parent.\n";

tie %title_with_no_children,'MLDBM', "./title_with_no_children.db"
    or die "Could not tie title_with_no_children.\n";

print STDERR "### uni Analysiere Hierarchie-Struktur der Titeldaten und setze titelspezifische Markierung\n";

print STDERR "### uni Einlesen der Titel\n";

my $count = 1;

open(TITLE,"meta.title");

while (<TITLE>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $fields_ref = $title_ref->{fields};
    
    my $element_ref = [];    

    # Ueberordnungen vorhanden? Dann merken
    if (defined $fields_ref->{'0773'}){
	foreach my $item_ref (@{$fields_ref->{'0773'}}){
	    if ($item_ref->{subfield} eq "w"){
		my $ids_ref = [];
		if (defined $title_has_parent{$titleid}){
		    $ids_ref = $title_has_parent{$titleid};
		}

		push @{$ids_ref}, $item_ref->{content};

		$title_has_parent{$titleid} = $ids_ref;
	    }
	}
    }

    if (defined $fields_ref->{'0830'}){
	foreach my $item_ref (@{$fields_ref->{'0830'}}){
	    if ($item_ref->{subfield} eq "w"){
		my $ids_ref = [];
		if (defined $title_has_parent{$titleid}){
		    $ids_ref = $title_has_parent{$titleid};
		}

		push @{$ids_ref}, $item_ref->{content};

		$title_has_parent{$titleid} = $ids_ref;
	    }
	}
    }
	
    # Items vorhanden? Dann analysieren
    if (defined $fields_ref->{'1944'}){
	foreach my $location_ref (@{$fields_ref->{'1944'}}){
	    next unless ($location_ref->{subfield} eq "k");
	    
	    if ($location_ref->{content} =~m/^38$/){
		push @{$element_ref}, "DE-38";
	    }
	    elsif ($location_ref->{content} =~m/^(38-MAG|38-AWM)/){
		push @{$element_ref}, "DE-38";
	    }
	    elsif ($location_ref->{content} =~m/^38-HLS/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-HLS";		
	    }
	    elsif ($location_ref->{content} =~m/^38-HWA/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-HWA";
	    }
	    elsif ($location_ref->{content} =~m/^38-LBS$/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-LBS";
	    }
	    elsif ($location_ref->{content} =~m/^38-LS$/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-LS";
	    }
	    elsif ($location_ref->{content} =~m/^38-SAB$/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-SAB";
	    }
	    elsif ($location_ref->{content} =~m/^(38-\d\d\d)/){
		push @{$element_ref}, alma2isil($1);
	    }
	    elsif ($location_ref->{content} =~m/^KN3-SCHLAD/){
		push @{$element_ref}, "DE-Kn3-SL";
		push @{$element_ref}, "DE-38-ZBKUNST";
	    }
	    elsif ($location_ref->{content} =~m/^KN3/){
		push @{$element_ref}, alma2isil("Kn 3");	    
	    }
	    elsif ($location_ref->{content}){
		push @{$element_ref}, "DE-".$location_ref->{content};
	    }
	}
    }
    
    # Holdings
    if (defined $fields_ref->{'1943'}){
	foreach my $location_ref (@{$fields_ref->{'1943'}}){
	    next unless ($location_ref->{subfield} eq "b");
	    
	    if ($location_ref->{content} =~m/^38$/){
		push @{$element_ref}, "DE-38";
	    }
	    elsif ($location_ref->{content} =~m/^(38-MAG|38-AWM)/){
		push @{$element_ref}, "DE-38";
	    }
	    elsif ($location_ref->{content} =~m/^38-HLS/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-HLS";		
	    }
	    elsif ($location_ref->{content} =~m/^38-HWA/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-HWA";
	    }
	    elsif ($location_ref->{content} =~m/^38-LBS$/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-LBS";
	    }
	    elsif ($location_ref->{content} =~m/^38-LS$/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-LS";
	    }
	    elsif ($location_ref->{content} =~m/^38-SAB$/){
		push @{$element_ref}, "DE-38";
		push @{$element_ref}, "DE-38-SAB";
	    }
	    elsif ($location_ref->{content} =~m/^(38-\d\d\d)/){
		push @{$element_ref}, alma2isil($1);
	    }
	    elsif ($location_ref->{content} =~m/^KN3/){
		push @{$element_ref}, alma2isil("Kn 3");	    
	    }
	    elsif ($location_ref->{content}){
		push @{$element_ref}, "DE-".$location_ref->{content};
	    }
	}
    }

    # Anpassung KMB und ZBKUNST
    if (defined $fields_ref->{'0980'}){
        foreach my $item (@{$fields_ref->{'0980'}}){
	    # Thematische Markierung fuer ZB-Kunst
	    if ($item->{subfield} eq "a" && $item->{content}=~/^zb-kunst$/){
		push @{$element_ref}, "DE-38-ZBKUNST";
	    }
	    # Schwarze Lade der KMB ueber 980$h	(falls noch nicht ueber 1944$k)
            if ($item->{subfield} eq "h" && $item->{content} eq "KMBEIG_88"){
	    	push @{$element_ref}, "DE-Kn3-SL";
	    	push @{$element_ref}, "DE-38-ZBKUNST";
            }
	    # KMB-Daten ohne Buchsaetze anhand 980$f	    
	    if ($item->{subfield} eq "f" && ($item->{content}=~/^KMBABR_E[BKZ]A?$/ || $item->{content}=~/^KMBABR_yk$/)){
		push @{$element_ref}, "DE-Kn3";
		push @{$element_ref}, "DE-38-ZBKUNST";
	    }
        }
    }

    if ($count % 100000 == 0){
	print STDERR "$count done\n";
    }

    $count++;
    
    $title_locationid{$titleid} = $element_ref if (@$element_ref);
}

close(TITLE);

print STDERR "### uni Bestimmung der Hierarchie-Struktur und Setzen titelspezifischer Markierungen\n";

# Eltern bestimmen
foreach my $child_id (keys %title_has_parent){
    foreach my $parent_id (@{$title_has_parent{$child_id}}){
	$is_parent{$parent_id} = 1;
    }
}

# Titel mit Parent, aber ohne Kinder bestimmen
foreach my $titleid (keys %title_has_parent){
    $title_with_no_children{$titleid} = 1 if (!defined $is_parent{$titleid});
}

my $titlecount = keys %title_with_no_children;

print STDERR "Zahl von Titeln mit Ueberordnung aber ohne Unterordnung: $titlecount\n";

$count = 1;

foreach my $leaf_titleid (keys %title_with_no_children){

    if ($count % 100000 == 0){
	print STDERR "$count done\n";
    }

    $count++;
    
    # Nur 'Blaetter' mit Markierungen verarbeiten
    next unless (defined $title_locationid{$leaf_titleid});
    
    my $level = 0;
    
    # this_titleid ist Ausgangspunkt, um sich hochzuarbeiten
    if (defined $title_has_parent{$leaf_titleid}){
	foreach my $parent_titleid (@{$title_has_parent{$leaf_titleid}}){
	    mark_parent($parent_titleid,$leaf_titleid,$level);
	}
    }    
}

print STDERR "### uni Erweitere Titeldaten anhand der bestimmten Markierungen\n";

#open(LOGGING,">location.log");

$count = 1;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    if (defined $title_locationid{$titleid}){
        my $mult = 1;
        foreach my $locationid (uniq @{$title_locationid{$titleid}}){
            push @{$title_ref->{'locations'}}, $locationid;
        }

#        print LOGGING "$titleid:",join(';',uniq @{$title_locationid{$titleid}}),"\n";
    }

    if ($count % 100000 == 0){
	print STDERR "$count done\n";
    }

    $count++;
    
    print encode_json $title_ref, "\n";
}

#close(LOGGING);

sub mark_parent {
    my ($parent_titleid, $leaf_titleid, $level) = @_;

    # Payload an Markierungen fuer alle Ueberordnungen
    my $element_ref = $title_locationid{$leaf_titleid} || [];
        
    # Ggf bereits bestehende Elternmarkierungen werden uebernommen.
    my $parent_element_ref = $title_locationid{$parent_titleid} || [];

    # Kind-Markierungen werden hinzugefuegt
    push @{$parent_element_ref}, @{$element_ref};
    
    # .. und Gesamt-Eltern-Markierung wieder zurueckgeschrieben
    $title_locationid{$parent_titleid} = $parent_element_ref;
    
    if (defined $title_has_parent{$parent_titleid} && $level < 10){
	$level++;
	foreach my $next_parent_titleid (@{$title_has_parent{$parent_titleid}}){
	    mark_parent($next_parent_titleid,$parent_element_ref,$level);
	}
    }
    elsif (defined $title_has_parent{$parent_titleid}){
	print STDERR "### Ueberordnungen - Abbbruch ! Ebene $level erreicht\n";
    }

    return;
}
    
sub alma2isil {
    my $content = shift;

    my @isils = ();
    
    if ($content =~m/^38$/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38";
    }
    elsif ($content =~m/38-101/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-101";
    }
    elsif ($content =~m/38-123/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-123";
    }
    elsif ($content =~m/38-132/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-132";
    }
    elsif ($content =~m/^38-418/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-418";
    }
    elsif ($content =~m/^38-426/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-426";
        push @isils, "DE-38-ARCH";
    }
    elsif ($content =~m/^38-427/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-427";
        push @isils, "DE-38-ARCH";
    }
    elsif ($content =~m/38-429/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-429";
        push @isils, "DE-38-MEKUTH";
    }
    elsif ($content =~m/38-448/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-448";
        push @isils, "DE-38-MEKUTH";
    }
    elsif ($content =~m/^38-450/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-450";
        push @isils, "DE-38-ASIEN";
    }
    elsif ($content =~m/^38-459/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-459";
        push @isils, "DE-38-ASIEN";
    }
    elsif ($content =~m/38-507/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38-507";
    }
    elsif ($content =~m/^Kn\s*3/){
        push @isils, "DE-Kn3";
        push @isils, "DE-38-ZBKUNST";
    }
    elsif ($content =~m/^38-(\d\d\d)/){
        push @isils, "DE-38-$1";
    }
    else {
	$content =~s/ //g;
        $content =~s/\//-/g;
        $content = "DE-$content";
        push @isils, $content;
    }

#    print STDERR "ZSST ISILs: ",join(';',@isils),"\n" if (@isils);
    
    return @isils;
}

