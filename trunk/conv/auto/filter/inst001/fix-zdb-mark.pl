#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $holding_ref = decode_json $_;

    if (defined $holding_ref->{fields}{'0014'}){
        foreach my $item (@{$holding_ref->{fields}{'0014'}}){
            if ($item->{content} =~m/^(EWA |EWA-LS |FHM |HP |HP-LS |KS |LS )/g){
                $item->{content} =~s/^(EWA |EWA-LS |FHM |HP |HP-LS |KS |LS )//g;
            }        
        }
    }
   
    print encode_json $holding_ref, "\n";
}
