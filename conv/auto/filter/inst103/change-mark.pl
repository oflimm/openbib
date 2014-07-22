#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $holding_ref = decode_json $_;

    foreach my $mark_ref (@{$holding_ref->{fields}{'0014'}}){
        $mark_ref->{content} = "VWL/103/".$mark_ref->{content};
    }

    print encode_json $holding_ref, "\n";
}
