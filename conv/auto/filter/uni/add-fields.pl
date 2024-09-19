#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;

#open(CHANGED,">./changed.json");

open(HOLDING,"./meta.holding");

my $ausstellungskatalog_regexp_ref = [
    '^KMB/YF ',
    '^KMB/!YF ',
    '^KMB/\+YF ',
    '^KMB/=YF ',
    '^KMB/!!YF ',
    '^KMB/YG ',
    '^KMB/!YG ',
    '^KMB/\+YG ',
    '^KMB/=YG ',
    '^KMB/!!YG ',
    '^KMB/YK ',
    '^KMB/!YK ',
    '^KMB/\+YK ',
    '^KMB/=YK ',
    '^KMB/!!YK ',
    '^KMB/YNL ', 
    '^KMB/!YNL ', 
    '^KMB/\+YNL ', 
    '^KMB/=YNL ',
    '^KMB/!!YNL ',
    '^KMB/YNK ', 
    '^KMB/!YNK ', 
    '^KMB/\+YNK ', 
    '^KMB/=YNK ',
    '^KMB/!!YNK ',
    '^KMB/!!K \w+ 7 ', 
    '^KMB/!K \w+ 7 ', 
    '^KMB/K \w+ 7 ', 
    '^KMB/\+K \w+ 7 ', 
    '^KMB/=K \w+ 7 '
    ];

my $sammlungskatalog_regexp_ref = [
    'KMB/!Y ',
    'KMB/!Y ',
    'KMB/Y ',
    'KMB/\+Y ',
    'KMB/=Y ',
    'KMB/!!YA ',
    'KMB/!YA ',
    'KMB/YA ',
    'KMB/\+YA ',
    'KMB/=YA ',
    'KMB/!!YU ',
    'KMB/!YU ',
    'KMB/YU ',
    'KMB/\+YU ',
    'KMB/=YU ',
    'KMB/!!YV ',
    'KMB/YV ',
    'KMB/\+YV ',
    'KMB/=YV ',
    ];

my $kunstmessekatalog_regexp_ref = [
    'KMB/!!YNM ',
    'KMB/!YNM ',
    'KMB/YNM ',
    'KMB/\+YNM ',
    'KMB/=YNM ',
    ];

unlink "./ausstellungskatalog.db";
unlink "./sammlungskatalog.db";
unlink "./kunstmessekatalog.db";
unlink "./kmbsystematik.db";

my %ausstellungskatalog = ();
my %sammlungskatalog = ();
my %kunstmessekatalog = ();
my %kmbsystematik = ();

tie %ausstellungskatalog,             'MLDBM', "./ausstellungskatalog.db"
    or die "Could not tie ausstellungskatalog.\n";

tie %sammlungskatalog,                'MLDBM', "./sammlungskatalog.db"
    or die "Could not tie ausstellungskatalog.\n";

tie %kunstmessekatalog,               'MLDBM', "./kunstmessekatalog.db"
    or die "Could not tie kunstmessekatalog.\n";

tie %kmbsystematik,                   'MLDBM', "./kmbsystematik.db"
    or die "Could not tie kmbsystematik.\n";


while (<HOLDING>){
    # Einschraenkung, um Verarbeitung zu minimieren
    
    next unless ($_ =~m/KMB/);
    
    my $holding_ref = decode_json $_;

    # Titelid bestimmen

    my $titleid = "";
    if (defined $holding_ref->{fields}{'0004'}){	
        foreach my $item (@{$holding_ref->{fields}{'0004'}}){
	    $titleid=$item->{content};
	}
    }

    ### KMB-Medientypen bestimmen
    
    if (defined $holding_ref->{fields}{'0014'}){	
        foreach my $item (@{$holding_ref->{fields}{'0014'}}){
	    # Ausstellungskatalog??

	    foreach my $regexp (@$ausstellungskatalog_regexp_ref){
		# print STDERR "Matching ".$item->{content}." with ".$regexp."\n";
		if ($item->{content} =~m{$regexp}){
		    $ausstellungskatalog{$titleid} = 1;
		    #print "Matched ",$item->{content},"\n";
		}
	    }

	    # Sammlungskatalog??

	    foreach my $regexp (@$sammlungskatalog_regexp_ref){
		# print STDERR "Matching ".$item->{content}." with ".$regexp."\n";
		if ($item->{content} =~m{$regexp}){
		    $sammlungskatalog{$titleid} = 1;
		    #print "Matched ",$item->{content},"\n";
		}
	    }

	    # Kunstmessekatalog??

	    foreach my $regexp (@$kunstmessekatalog_regexp_ref){
		# print STDERR "Matching ".$item->{content}." with ".$regexp."\n";
		if ($item->{content} =~m{$regexp}){
		    $kunstmessekatalog{$titleid} = 1;
		    #print "Matched ",$item->{content},"\n";
		}
	    }

	    # KMB Systematik

	    if ($item->{content} =~m{KMB/[=+!]*([A-Za-z]+ +\d+)}){
		$kmbsystematik{$titleid} = $1;
	    }
	    elsif ($item->{content} =~m{KMB/[=+!]*([A-Za-z]+)}){
		$kmbsystematik{$titleid} = $1;
	    }
        }	
    }


}

close(HOLDING);

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

    if ($year_from_26x && defined $title_ref->{fields}{'1008'}){
	foreach my $item_ref (@{$title_ref->{fields}{'1008'}}){
	    if ($item_ref->{subfield} eq 'a' && $item_ref->{content} !~m/\d\d\d\d/){
		$item_ref->{content} = $year_from_26x;
	    }
	}
    }
    elsif ($year_from_26x && !defined $title_ref->{fields}{'1008'}){
	push @{$title_ref->{fields}{'1008'}}, {
	    mult => 1,
	    subfield => 'a',
	    content => $year_from_26x,	    
	};
    }
    
    ### KMB-Medientypen zusaetzlich vergeben

    my $is_kuenstlerbuch = 0;
    my $is_dossier = 0;
    my $is_bild = 0;
    my $is_auktionskatalog = 0;

    # Auswertung von 0980$f
    if (defined $title_ref->{fields}{'0980'}){	
        foreach my $item (@{$title_ref->{fields}{'0980'}}){
	    next unless ($item->{subfield} eq 'f');
	    
            if ($item->{content} eq "KMBABR_yy"){
                $is_kuenstlerbuch = 1;
            }
	    
            if ($item->{content} =~m/^KMBABR_D[IKOPTXYZ]$/ || $item->{content} eq "KMBABR_DKG"){
                $is_dossier = 1;
            }        

            if ($item->{content} eq "KMBABR_BILD"){
                $is_bild = 1;
            }
	    
        }	
    }

    # KMB Systematik
    if (defined $kmbsystematik{$titleid}){
	push @{$title_ref->{fields}{'1004'}}, {
	    mult     => 1,
	    subfield => 'k',
	    content  => $kmbsystematik{$titleid},
	};	
    }
    
    ### Auktionskatalog
    # Auswertung von 0980$g
    if (defined $title_ref->{fields}{'0980'}){
        foreach my $item (@{$title_ref->{fields}{'0980'}}){
	    next unless ($item->{subfield} eq 'g');
            if ($item->{content} eq "KMBART_91;00"){
                $is_auktionskatalog = 1;
            }        
        }
    }
        
    if ($is_kuenstlerbuch){
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Künstlerbuch",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Künstlerbuch",
		},
		];
	}
    }
    
    if ($is_dossier){
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Dossier",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Dossier",
		},
		];
	}
    }
    
    if ($is_bild){
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Bild",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Bild",
		},
		];
	}
    }
    
    if ($is_auktionskatalog){
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Auktionskatalog",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Auktionskatalog",
	    },
		];
	}
    }

    if (defined $ausstellungskatalog{$titleid} && $ausstellungskatalog{$titleid}){
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Ausstellungskatalog",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Ausstellungskatalog",
		},
		];
	}

    }
    
    if (defined $sammlungskatalog{$titleid} && $sammlungskatalog{$titleid}){
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Sammlungskatalog",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Sammlungskatalog",
		},
		];
	}
    }


    if (defined $kunstmessekatalog{$titleid} && $kunstmessekatalog{$titleid}){
	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Kunstmessekatalog",
            };
	}
	else {
	    $title_ref->{fields}{'4410'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "Kunstmessekatalog",
		},
		];
	}
    }

    # if ($is_bild || $is_auktionskatalog || $is_dossier || $is_kuenstlerbuch){
    # 	print CHANGED encode_json $title_ref, "\n";

    # }

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
    
    # Alte RVKs von 38-503 aus 983$a in 4101 vereinheitlichen
    # Alte BKs aus 983$a in 4100 vereinheitlichen    
    if (defined $title_ref->{fields}{'0983'}){
        foreach my $item (@{$title_ref->{fields}{'0983'}}){
	    if ($item->{subfield} eq "a" && $item->{content} =~m{^38/503}){
		if ($item->{content} =~m{^38/503: ([A-Z][A-Z] \d+)}){
		    push @rvks, $1;
		}
	    }
	    if ($item->{subfield} eq "b" && $item->{content} =~m{^\d\d\.\d\d$}){
		push @bks, $item->{content};
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

    # if (@ddcs){
    # 	my $ddc_mult = 1;

    # 	foreach my $ddc (uniq @ddcs){
    # 	    push @{$title_ref->{fields}{'4102'}}, {
    # 		mult     => $ddc_mult++,
    # 		subfield => '',
    # 		content  => $ddc,
    # 	    };
    # 	}
    # }

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
#close(CHANGED);
