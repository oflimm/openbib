#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

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

my %ausstellungskatalog = ();
my %sammlungskatalog = ();
my %kunstmessekatalog = ();

tie %ausstellungskatalog,             'MLDBM', "./ausstellungskatalog.db"
    or die "Could not tie ausstellungskatalog.\n";

tie %sammlungskatalog,                'MLDBM', "./sammlungskatalog.db"
    or die "Could not tie ausstellungskatalog.\n";

tie %kunstmessekatalog,               'MLDBM', "./kunstmessekatalog.db"
    or die "Could not tie kunstmessekatalog.\n";


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
        }	
    }


}

close(HOLDING);

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};
    
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
