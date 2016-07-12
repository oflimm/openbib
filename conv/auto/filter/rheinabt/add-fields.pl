#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_digital = 0;

    # T0662 hat Inhalt http://www.ub.uni-koeln.de/permalink*
    if (defined $title_ref->{fields}{'0662'}){
        foreach my $item (@{$title_ref->{fields}{'0662'}}){
            if ($item->{content} =~m{^http://www.ub.uni-koeln.de/permalink}){
                $is_digital = 1;
            }        
        }
    }
    
    if ($is_digital){
        $title_ref->{fields}{'4400'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "online",
            },
        ];
        
        $title_ref->{fields}{'4410'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "Digital",
            },
        ];
    }
   
    print encode_json $title_ref, "\n";
}
