#!/usr/bin/perl

use strict;
use warnings;

use YAML::Syck;
use JSON::XS;

my $id2zdbid_ref = LoadFile("/tmp/instzs-id2zdbid.yml");

while (<>){
    my $record_ref = decode_json $_;

    if (defined $record_ref->{fields}{'0004'}){
        foreach my $item_ref (@{$record_ref->{fields}{'0004'}}){
            $item_ref->{content} = $id2zdbid_ref->{$item_ref->{content}};
        }
    }
    
    print encode_json $record_ref, "\n";
}

