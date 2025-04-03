#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;
use POSIX qw(strftime);
use YAML;
    
my $thisyear = strftime "%Y", localtime;

my $grenze_80 = 0;    
my $grenze_90 = 0;
my $grenze_100 = 0;
my $grenze_110 = 0;
my $grenze_120 = 0;
my $grenze_130 = 0;

my $count = 0;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    # Bestimmen des Publikationsjahres

    my $year_of_publication = 0;

    # Publikationsjahr aus angereicherter 1008$a
    if (defined $title_ref->{fields}{'1008'}){
	foreach my $item_ref (@{$title_ref->{fields}{'1008'}}){
	    if ($item_ref->{subfield} eq 'a'){
		$year_of_publication = $item_ref->{content};
	    }
	}
    }

    if (!$year_of_publication){
	my $year_from_26x = 0;
	
	if (defined $title_ref->{fields}{'0260'}){
	    foreach my $item_ref (@{$title_ref->{fields}{'0260'}}){
		if ($item_ref->{subfield} eq 'c' && $item_ref->{content} =~m/(\d\d\d\d)/){
		    $year_from_26x = $1;
		    last;
		}
	    }
	}
	
	if (!$year_from_26x && defined $title_ref->{fields}{'0264'}){
	    foreach my $item_ref (@{$title_ref->{fields}{'0264'}}){
		if ($item_ref->{subfield} eq 'c' && $item_ref->{content} =~m/(\d\d\d\d)/){
		    $year_from_26x = $1;
		    last;
		}
	    }
	}

	$year_of_publication = $year_from_26x if ($year_from_26x);
    }
    
    # Analyse von 100/700 $d wg. Urheberrechtsfreiheit (juengstes Sterbejahr plus 70 Jahre) und Anreicherung in 1008$o(penaccess)

    my $latest_year_of_death = 0;

    my $latest_year_of_death_ref = {};
    
    if (defined $title_ref->{fields}{'0100'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0100'}}){
	    $latest_year_of_death_ref->{'0100-'.$item_ref->{mult}} = 0;
	}
	
	foreach my $item_ref (@{$title_ref->{fields}{'0100'}}){
	    if ($item_ref->{subfield} eq "d" && $item_ref->{content}=~m/-(\d+)$/){
		my $year_of_death = $1;

		$latest_year_of_death_ref->{'0100-'.$item_ref->{mult}} = $year_of_death;		    
	    }
	}
    }

    if (defined $title_ref->{fields}{'0700'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0700'}}){
	    $latest_year_of_death_ref->{'0700-'.$item_ref->{mult}} = 0;
	}
	
	foreach my $item_ref (@{$title_ref->{fields}{'0700'}}){
	    if ($item_ref->{subfield} eq "d" && $item_ref->{content}=~m/-(\d\d\d\d)$/){
		my $year_of_death = $1;
		
		$latest_year_of_death_ref->{'0700-'.$item_ref->{mult}} = $year_of_death;		    
	    }
	}
    }
    
    # Fuer alle Verfasser muss ein Sterbejahr definiert sein!
    my $all_authors_with_year_of_death = 1;

    foreach my $key (keys %{$latest_year_of_death_ref}){
	# Ein undefiniertes Sterbejahr bei einem Verfasser verunmoeglicht Auswertung
	if (!$latest_year_of_death_ref->{$key}){
	    $all_authors_with_year_of_death = 0;
	}
	# sonst ggf. Hochsetzen des letzten Sterbejahrs
	elsif ($latest_year_of_death_ref->{$key} > $latest_year_of_death) {
	    $latest_year_of_death = $latest_year_of_death_ref->{$key};	    
	}
    }

    if ($all_authors_with_year_of_death && $latest_year_of_death && $latest_year_of_death + 70 <= $thisyear){
	$open_access_year = $latest_year_of_death + 70;

	if ($year_of_publication && $open_access_year){
	    my $differenz = $open_access_year - $year_of_publication;

	    if ($differenz > 0){
		if ($differenz <= 80){
		    $grenze_80++
		}
		
		if ($differenz <= 90){
		    $grenze_90++
		}
		
		if ($differenz <= 100){
		    $grenze_100++
		}
		
		if ($differenz <= 110){
		    $grenze_110++
		}
		
		if ($differenz <= 120){
		    $grenze_120++
		}

		if ($differenz <= 130){
		    $grenze_130++
		}
		
		$count++;
	    }
	}	
    }
}

print "Prozentsatz bis  80 Jahre: ".($grenze_80 * 100 / $count),"\n";
print "Prozentsatz bis  90 Jahre: ".($grenze_90 * 100 / $count),"\n";
print "Prozentsatz bis 100 Jahre: ".($grenze_100 * 100 / $count),"\n";
print "Prozentsatz bis 110 Jahre: ".($grenze_110 * 100 / $count),"\n";
print "Prozentsatz bis 120 Jahre: ".($grenze_120 * 100 / $count),"\n";
print "Prozentsatz bis 130 Jahre: ".($grenze_130 * 100 / $count),"\n";
