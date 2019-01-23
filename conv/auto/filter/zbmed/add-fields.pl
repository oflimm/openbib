#!/usr/bin/perl

use JSON::XS;
use utf8;

#open(CHANGED,">./changed.json");

while (<>){
    my $title_ref = decode_json $_;


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
