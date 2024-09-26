#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    # Anreichern von 1008 $a mit vierstelliger Jahreszahl aus 260/264 $c, wenn 1008 $a nicht mit Jahreszahl besetzt.

    my $year_from_26x = "";

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

    my $field_1008_has_a = 0;
    
    if ($year_from_26x && defined $title_ref->{fields}{'1008'}){
	foreach my $item_ref (@{$title_ref->{fields}{'1008'}}){
	    if ($item_ref->{subfield} eq 'a'){
		$field_1008_has_a = 1;
		if ($item_ref->{content} !~m/\d\d\d\d/){
		    $item_ref->{content} = $year_from_26x;
		}
	    }
	}
    }
    elsif ($year_from_26x && (!$field_1008_has_a || !defined $title_ref->{fields}{'1008'})){
	push @{$title_ref->{fields}{'1008'}}, {
	    mult => 1,
	    subfield => 'a',
	    content => $year_from_26x,	    
	};
    }
    
    my @bks  = (); # Fuer 4100    
    my @rvks = (); # Fuer 4101
    my @ddcs = (); # Fuer 4102
    
    # Auswertung von 082$ fuer DDC
    if (defined $title_ref->{fields}{'0082'}){
        foreach my $item (@{$title_ref->{fields}{'0082'}}){
	    if ($item->{subfield} eq "a"){
		push @ddcs, $item->{content};
	    }
	}
    }

    # BK, RVK und DDC aus 084$a in 4100ff vereinheitlichen
    
    # Auswertung von 084$
    if (defined $title_ref->{fields}{'0084'}){
	my $cln_ref = {};
        foreach my $item (@{$title_ref->{fields}{'0084'}}){
	    $cln_ref->{$item->{mult}}{$item->{subfield}} = $item->{content};
	}
	
	foreach my $mult (keys %{$cln_ref}){
	    next unless (defined $cln_ref->{$mult}{'2'} && defined $cln_ref->{$mult}{'a'});
	    if ($cln_ref->{$mult}{'2'} eq "rvk"){
		push @rvks, $cln_ref->{$mult}{'a'};
	    }
	    elsif ($cln_ref->{$mult}{'2'} eq "bkl"){
		push @bks, $cln_ref->{$mult}{'a'};
	    }
	    elsif ($cln_ref->{$mult}{'2'} eq "ddc"){
		push @ddcs, $cln_ref->{$mult}{'a'};
	    }
	}
    }
    
    if (@bks){
	my $bk_mult = 1;

	foreach my $bk (uniq @bks){
	    push @{$title_ref->{fields}{'4100'}}, {
		mult     => $bk_mult++,
		subfield => '',
		content  => $bk,
	    };
	}
    }
    
    if (@rvks){
	my $rvk_mult = 1;

	foreach my $rvk (uniq @rvks){
	    push @{$title_ref->{fields}{'4101'}}, {
		mult     => $rvk_mult++,
		subfield => '',
		content  => $rvk,
	    };
	}
    }

    # GNDs verarbeiten und in 1003$a prefix-los abspeichern
    my @gnds = ();

    foreach my $field ('0100', '0110', '0700', '0710'){
	if (defined $title_ref->{fields}{$field}){
	    foreach my $item (@{$title_ref->{fields}{$field}}){
		if ($item->{subfield} =~m{^(0|6)$} && $item->{content} =~m{DE-588}){
		    if ($item->{content} =~m{^\(DE-588\)(.+)}){
			push @gnds, $1;
		    }
		}
	    }
	}
    }

    if (@gnds){
	my $gnd_mult = 1;

	foreach my $gnd (uniq @gnds){
	    push @{$title_ref->{fields}{'1003'}}, {
		mult     => $gnd_mult++,
		subfield => 'a',
		content  => $gnd,
	    };
	}
    }
    
    ### Medientyp Digital/online zusaetzlich vergeben
    my $is_digital = 0;

    # 1) 0338$a = 'online resource' oder 0338$b = 'cr'
    if (defined $title_ref->{fields}{'0338'}){
        foreach my $item (@{$title_ref->{fields}{'0338'}}){
            if ($item->{subfield} eq "a" && $item->{content} eq "online resource"){
                $is_digital = 1;
            }        
            if ($item->{subfield} eq "b" && $item->{content} eq "cr"){
                $is_digital = 1;
            }        
        }
    }

    # 2) 0962$e hat Inhalt 'ldd' oder 'fzo'
    if (defined $title_ref->{fields}{'0962'}){
        foreach my $item (@{$title_ref->{fields}{'0962'}}){
            if ($item->{subfield} eq "e" && ($item->{content} eq "ldd" || $item->{content} eq "fzo")){
                $is_digital = 1;
            }        
        }
    }

    # 3) 007 beginnt mit cr
    if (defined $title_ref->{fields}{'0007'}){
        foreach my $item (@{$title_ref->{fields}{'0007'}}){
            if ($item->{content} =~m/^cr/){
                $is_digital = 1;
            }        
        }
    }

    if ($is_digital){
	if (@{$title_ref->{fields}{'4400'}}){
	    push @{$title_ref->{fields}{'4400'}}, {
                mult     => 1,
                subfield => '',
                content  => "online",
            };
	}
	else {
	    $title_ref->{fields}{'4400'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "online",
		},
		];
        }

	
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Digital",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Digital",
		},
		];
	}
    }
   
    print encode_json $title_ref, "\n";
}
