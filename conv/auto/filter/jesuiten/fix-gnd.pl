#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $norm_ref = decode_json $_;

    # GND-Feld untersuchen
    if (defined $norm_ref->{fields}{'0010'}){

        my $have_gnd = 0;
        foreach my $item (@{$norm_ref->{fields}{'0010'}}){
            if ($item->{content} =~m/^.DE-588.(.+)$/){
                $item->{content} = $1;
                $have_gnd=1;
            }        
        }

        unless ($have_gnd == 1){
            delete $norm_ref->{fields}{'0010'};
        };
    }
   
    print encode_json $norm_ref, "\n";
}
