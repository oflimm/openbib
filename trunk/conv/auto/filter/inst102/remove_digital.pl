#!/usr/bin/perl

use utf8;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_digital = 0;

    foreach my $item_ref (@{$titles_ref->{fields}{'0334'}}){
        if ($item_ref->{content} =~/Elektronische Ressource/i){
            $is_digital = 1;
        }
    }

    # Digitale Inhalte aus dem initialen Import mit ZDB-Daten in den Katalog werden ausgefiltert
    next if ($is_digital && $title_ref->{id} < 10000);

    print encode_json $title_ref, "\n";
}
