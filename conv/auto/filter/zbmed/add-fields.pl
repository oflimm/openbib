#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};
    
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

