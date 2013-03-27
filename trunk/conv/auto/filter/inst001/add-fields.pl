#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_digital = 0;

    # 1) T0807 hat Inhalt 'g'
    if (defined $title_ref->{'0807'}){
        foreach my $item (@{$title_ref->{'0807'}}){
            if ($item->{content} eq "g"){
                $is_digital = 1;
            }        
        }
    }
    
    # 2) T2662  ist besetzt
    if (defined $title_ref->{'2662'}){
        $is_digital = 1;
    } 
    
    # 3) T0078 hat Inhalt 'ldd'
    if (defined $title_ref->{'0078'}){
        foreach my $item (@{$title_ref->{'0078'}}){
            if ($item->{content} eq "ldd"){
                $is_digital = 1;
            }        
        }
    }

    if ($is_digital){
        $title_ref->{'4400'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "online",
            },
        ];
        
        $title_ref->{'4410'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "Digital",
            },
        ];
    }
   
    print encode_json $title_ref, "\n";
}
