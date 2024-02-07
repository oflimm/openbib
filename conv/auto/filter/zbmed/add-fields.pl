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

    my @rvks = ();
    
    # RVK aus 084$a in 4101 vereinheitlichen
    
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

