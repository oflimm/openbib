#!/usr/bin/perl

use utf8;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_digital = 0;

    foreach my $item_ref (@{$title_ref->{fields}{'0300'}}){
        if ($item_ref->{subfield} =~m/a/ && ( $item_ref->{content} =~/online resource/i || $item_ref->{content} =~/online.ressource/i){
            $is_digital = 1;
        }
    }

    next if ($is_digital);

    print encode_json $title_ref, "\n";
}
