#!/usr/bin/perl

use JSON::XS;
use utf8;

#open(CHANGED,">./changed.json");

while (<>){
    my $title_ref = decode_json $_;

    ### KMB-Medientypen zusaetzlich vergeben

    my $is_kuenstlerbuch = 0;
    my $is_dossier = 0;
    my $is_bild = 0;
    my $is_auktionskatalog = 0;

    if (defined $title_ref->{fields}{'2083'}){
        foreach my $item (@{$title_ref->{fields}{'2083'}}){
            if ($item->{content} =~m/^Kn 3: Digitales Foto von Werk/){
                $is_bild = 1;
            }        
        }
    }
    
    if (defined $title_ref->{fields}{'4800'}){	
        foreach my $item (@{$title_ref->{fields}{'4800'}}){
            if ($item->{content} eq "yy"){
                $is_kuenstlerbuch = 1;
            }
	    
            if ($item->{content} =~m/^D[IKOPT]$/ || $item->{content} eq "DKG"){
                $is_dossier = 1;
            }        

            if ($item->{content} eq "BILD"){
                $is_bild = 1;
            }
	    
        }	
    }
    
    ### Auktionskatalog
    if (defined $title_ref->{fields}{'4801'}){
        foreach my $item (@{$title_ref->{fields}{'4801'}}){
            if ($item->{content} eq "91;00"){
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

    # if ($is_bild || $is_auktionskatalog || $is_dossier || $is_kuenstlerbuch){
    # 	print CHANGED encode_json $title_ref, "\n";

    # }
    ### Medientyp Digital/online zusaetzlich vergeben
    my $is_digital = 0;

    # 1) T0807 hat Inhalt 'g'
    if (defined $title_ref->{fields}{'0807'}){
        foreach my $item (@{$title_ref->{fields}{'0807'}}){
            if ($item->{content} eq "g"){
                $is_digital = 1;
            }        
        }
    }
    
    # 2) T2662  ist besetzt
    if (defined $title_ref->{fields}{'2662'}){
        $is_digital = 1;
    } 
    
    # 3) T0078 hat Inhalt 'ldd' oder 'fzo'
    if (defined $title_ref->{fields}{'0078'}){
        foreach my $item (@{$title_ref->{fields}{'0078'}}){
            if ($item->{content} eq "ldd" || $item->{content} eq "fzo"){
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
