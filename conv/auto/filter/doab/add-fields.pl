#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    # ISBN-Feld besetzen
    if (defined $title_ref->{fields}{'0010'}){
        my $mult = 1;
        foreach my $item (@{$title_ref->{fields}{'0010'}}){
            if ($item->{content} =~/ISBN: (.+?)$/){
                push @{$title_ref->{fields}{'0540'}},
                    {
                        mult     => $mult++,
                        subfield => '',
                        content  => $1,
                    };
            }        
        }
    }  
   
    print encode_json $title_ref, "\n";
}
