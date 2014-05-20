#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    foreach my $url_ref (@{$title_ref->{fields}{'0014'}}){
        $url_ref->{content} = "http://".$url_ref->{content};
    }

    print encode_json $title_ref, "\n";
}
