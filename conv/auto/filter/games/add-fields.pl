#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_digital = 0;
    my $is_digital_abo = 0;
    my $is_physical = 0;

    if (defined $title_ref->{fields}{'0800'}){
        foreach my $item (@{$title_ref->{fields}{'0800'}}){
            if ($item->{content} =~m{EPIC Download|GOG Download|Nintendo eShop|Origin Download|PSN Download|Steam Download|Uplay Download|Xbox Download}){
                $is_digital = 1;
            }        
	    elsif ($item->{content} =~m{PSN Plus Download|Xbox Gold Download}){
                $is_digital_abo = 1;
            }        
	    elsif ($item->{content} =~m{BluRay|CD|DVD|GCD|UMD}){
                $is_physical = 1;
            }        
        }
    }
    
    if ($is_digital){
        $title_ref->{fields}{'4410'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "Digital",
            },
        ];
    }
    elsif ($is_digital_abo){
        $title_ref->{fields}{'4410'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "Digital Abo",
            },
        ];
    }
    elsif ($is_physical){
        $title_ref->{fields}{'4410'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "Medium",
            },
        ];
    }
   
    print encode_json $title_ref, "\n";
}
