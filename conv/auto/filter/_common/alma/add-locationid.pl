#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use JSON::XS;
use Encode qw(encode_utf8);

use List::MoreUtils qw{uniq};
use OpenBib::Catalog::Subset;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

unlink "./title_locationid.db";
unlink "./medianumber_locationid.db";
unlink "./title_has_children.db";

our %title_locationid             = ();
our %medianumber_locationid       = ();
our %title_has_children              = ();

tie %title_locationid,             'MLDBM', "./title_locationid.db"
    or die "Could not tie title_locationid.\n";

tie %medianumber_locationid,       'MLDBM', "./medianumber_locationid.db"
    or die "Could not tie medianumber_locationid.\n";

tie %title_has_children,             'MLDBM', "./title_has_children.db"
    or die "Could not tie title_has_children.\n";

print STDERR "### uni Analysiere Mediennummern mit ihren Standorten fuer Bindeeinheiten \n";

# Locations zu jeder Mediennummer bestimmen wg. Bindeeinheiten
open(TITLE,"meta.title");

while (<TITLE>){
    my $title_ref = decode_json $_;

    store_locationid_of_medianumber($title_ref);
    store_hierarchy($title_ref);
    
    # Locations zur Titelid merken
    $title_locationid{$title_ref->{id}} = extract_locationid($title_ref);
}

close(TITLE);

#print STDERR YAML::Dump(\%title_has_children),"\n";

print STDERR "### uni Analysiere Titeldaten und setze Standort-Markierungen\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $locations_ref             = extract_locationid($title_ref);
    my $bindingunit_locations_ref = extract_locationids_of_bindingunits($title_ref);
    my $locations_of_children_ref = [];

    # Titel hat selbst keine Locations. Dann aus Kindern bestimmen
    unless (@$locations_ref){
	my $titleids_of_children_ref = extract_titleids_of_children($titleid);

	# Locations zu den Titelids bestimmen
	my @new_locations = ();	
	foreach my $titleid (uniq @{$titleids_of_children_ref}){
	    push @{$locations_of_children_ref}, uniq @{$title_locationid{$titleid}} if (defined $title_locationid{$titleid});
	}
    }

    # Konnten Locations aus Bindeeinheiten bestimmt werden?
    push @{$locations_ref}, @{$bindingunit_locations_ref} if (@{$bindingunit_locations_ref});

    # Konnten Locations aus den abhaengigen Kind-Titeln bestimmt werden?
    push @{$locations_ref}, @{$locations_of_children_ref} if (@{$locations_of_children_ref});
    
    if (@$locations_ref){	
        my $mult = 1;
        foreach my $locationid (uniq @{$locations_ref}){
            push @{$title_ref->{'locations'}}, $locationid;
        }

    }

    print encode_json $title_ref, "\n";
}

sub extract_titleids_of_children {
    my $parentid        = shift;
    
    # Keine Kinder? Dann exit
    return [] unless (defined $title_has_children{$parentid});

    my $childrenids_ref           = [];
    my $grandchildrenids_ref      = [];
    my $grandgrandchildrenids_ref = [];    

    # 1. Kinder
    if (defined $title_has_children{$parentid}){
	foreach my $childrenid (uniq keys %{$title_has_children{$parentid}}){
	    push @{$childrenids_ref}, $childrenid;
	}
    }
    
    # 2. Enkelkinder
    foreach my $childrenid (uniq @{$childrenids_ref}){
	if (defined $title_has_children{$childrenid}){
	    foreach my $grandchildrenid (uniq keys %{$title_has_children{$childrenid}}){
		push @{$grandchildrenids_ref}, $grandchildrenid;
	    }
	}
    }

    # 3. Ur-Enkelkinder
    foreach my $grandchildrenid (uniq @{$grandchildrenids_ref}){
	if (defined $title_has_children{$grandchildrenid}){
	    foreach my $grandgrandchildrenid (uniq keys %{$title_has_children{$grandchildrenid}}){
		push @{$grandgrandchildrenids_ref}, $grandgrandchildrenid;
	    }
	}
    }

    push @{$childrenids_ref}, @{$grandchildrenids_ref};
    push @{$childrenids_ref}, @{$grandgrandchildrenids_ref};
    
    @{$childrenids_ref} = uniq @{$childrenids_ref};
    
    return $childrenids_ref;
}

sub extract_locationids_of_bindingunits {
    my $title_ref = shift;

    my $titleid = $title_ref->{id};

    my $locationids_ref = [];

    # Items vorhanden? Dann reorganizieren
    if (defined $title_ref->{fields}{'0773'}){
	my $fields_by_mult_ref = {};
    
	foreach my $item_ref (@{$title_ref->{fields}{'0773'}}){
	    my $mult     = $item_ref->{mult};
	    my $content  = $item_ref->{content};
	    my $subfield = $item_ref->{subfield};
	    
	    $fields_by_mult_ref->{$mult}{$subfield} = $content;
	}
	
	if (scalar %{$fields_by_mult_ref}){
	    foreach my $mult (keys %{$fields_by_mult_ref}){
		
		#  = libraryid
		if (defined $fields_by_mult_ref->{$mult}{'p'} && $fields_by_mult_ref->{$mult}{'p'} eq "AngebundenAn" && defined $fields_by_mult_ref->{$mult}{'g'}){
		    
		    my $medianumber = $fields_by_mult_ref->{$mult}{'g'};
		    $medianumber =~s/^no://;

		    # Verhindern von wide character Fehlern bei MLDBM
		    $medianumber = encode_utf8($medianumber);
			
		    if (defined $medianumber_locationid{$medianumber}){
			my $isils_ref = $medianumber_locationid{$medianumber};
			push @{$locationids_ref}, @{$isils_ref};
		    }
		}
	    }
	}
    }

    return $locationids_ref;
}

sub store_hierarchy {
    my $title_ref = shift;

    my $childid = $title_ref->{id};

    foreach my $field ('0773','0830'){
	if (defined $title_ref->{fields}{$field}){
	    foreach my $item_ref (@{$title_ref->{fields}{$field}}){
		if ($item_ref->{'subfield'} eq "w"){
		    my $parentid = $item_ref->{'content'};
		    
		    # MMSIDs als parentid wollen wir, alles andere ignorieren
		    next unless ($parentid =~m/^\d+$/);

		    my $title_children_ref = {};
		    if (defined $title_has_children{$parentid}){
			$title_children_ref = $title_has_children{$parentid};
		    }

		    $title_children_ref->{$childid} = 1;

		    $title_has_children{$parentid} = $title_children_ref;
		}
	    }
	}
    }

    return;
}

sub store_locationid_of_medianumber {
    my $title_ref = shift;

    # Items vorhanden? Dann reorganizieren
    if (defined $title_ref->{fields}{'1944'}){
	my $fields_by_mult_ref = {};
    
	foreach my $item_ref (@{$title_ref->{fields}{'1944'}}){
	    my $mult     = $item_ref->{mult};
	    my $content  = $item_ref->{content};
	    my $subfield = $item_ref->{subfield};
	    
	    $fields_by_mult_ref->{$mult}{$subfield} = $content;
	}
	
	if (scalar %{$fields_by_mult_ref}){
	    foreach my $mult (keys %{$fields_by_mult_ref}){
		
		# h = libraryid
		if ($fields_by_mult_ref->{$mult}{'a'} && $fields_by_mult_ref->{$mult}{'h'}){
		    my @isils       = alma2isil($fields_by_mult_ref->{$mult}{'h'});
		    my $medianumber = $fields_by_mult_ref->{$mult}{'a'};

		    # Verhindern von wide character Fehlern bei MLDBM
		    $medianumber = encode_utf8($medianumber);
		    
		    $medianumber_locationid{$medianumber} = \@isils;
		}
	    }
	}
    }
}

sub extract_locationid {
    my $title_ref = shift;

    my $titleid = $title_ref->{id};

    my $element_ref = [];

    # Items vorhanden? Dann analysieren
    if (defined $title_ref->{fields}{'1944'}){
	foreach my $location_ref (@{$title_ref->{fields}{'1944'}}){
	    next unless ($location_ref->{subfield} eq "k");

	    # k = locationid
	    push @{$element_ref}, alma2isil($location_ref->{content});
	}
    }
    
    # Holdings
    if (defined $title_ref->{fields}{'1943'}){
	foreach my $location_ref (@{$title_ref->{fields}{'1943'}}){
	    next unless ($location_ref->{subfield} eq "b");

	    push @{$element_ref}, alma2isil($location_ref->{content});
	}
    }

    # E-Medien ueber Anreicherung in 4120
    if (defined $title_ref->{fields}{'4120'}){
	foreach my $item_ref (@{$title_ref->{fields}{'4120'}}){
	    if ($item_ref->{subfield} =~m/(g|y|f|n)/){
		push @{$element_ref}, "emedien";		
	    }

	    if ($item_ref->{subfield} =~m/g/){
		push @{$element_ref}, "freemedia";		
	    }	    
	}
    }
    
    # Anpassung KMB und ZBKUNST
    if (defined $title_ref->{fields}{'0980'}){
        foreach my $item (@{$title_ref->{fields}{'0980'}}){
	    # Thematische Markierung fuer ZB-Kunst
	    if ($item->{subfield} eq "a" && $item->{content}=~/^zb-kunst$/){
		push @{$element_ref}, "DE-38-ZBKUNST";
	    }
	    # Markierung fuer Kn3 und damit ZB-Kunst
	    if ($item->{subfield} eq "a" && $item->{content}=~/^DE-Kn3$/){
		push @{$element_ref}, "DE-Kn3";
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

    return $element_ref;
}

sub alma2isil {
    my $content = shift;

    my @isils = ();

    if ($content =~m/^38$/){
        push @isils, "DE-38-USBFB";
        push @isils, "DE-38";
    }
    elsif ($content =~m/^(38-MAG|38-AWM)/){
	push @isils, "DE-38";
    }
    elsif ($content =~m/^38-HLS/){
	push @isils, "DE-38";
	push @isils, "DE-38-HLS";		
    }
    elsif ($content =~m/^38-HWA/){
	push @isils, "DE-38";
	push @isils, "DE-38-HWA";
    }
    elsif ($content =~m/^38-LBS$/){
	push @isils, "DE-38";
	push @isils, "DE-38-LBS";
    }
    elsif ($content =~m/^38-LS$/){
	push @isils, "DE-38";
	push @isils, "DE-38-LS";
    }
    elsif ($content =~m/^38-SAB$/){
	push @isils, "DE-38";
	push @isils, "DE-38-SAB";
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
    elsif ($content =~m/^KN3-SCHLAD/){
	push @isils, "DE-Kn3-SL";
	push @isils, "DE-38-ZBKUNST";
    }
    elsif ($content =~m/^KN3/){
        push @isils, "DE-Kn3";
        push @isils, "DE-38-ZBKUNST";
    }
    elsif ($content =~m/^38-(\d\d\d)/){
        push @isils, "DE-38-$1";
    }
    elsif ($content){
	push @isils, "DE-".$content;
    }
    
    return @isils;
}

