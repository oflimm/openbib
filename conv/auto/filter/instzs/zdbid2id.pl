#!/usr/bin/perl

use strict;
use warnings;

use utf8;

use YAML::Syck;
use JSON::XS;

my %id2zdbid = ();

while (<>){
    my $record_ref = decode_json $_;

    my $id    = $record_ref->{id};
    my $zdbid = 0;

    if (defined $record_ref->{fields}{'0572'}){
        foreach my $item_ref (@{$record_ref->{fields}{'0572'}}){
            $zdbid = $item_ref->{content};
        }
        
        $record_ref->{id} = $zdbid;
        
        $id2zdbid{$id}=$zdbid;
        
        print encode_json $record_ref, "\n";
    }
}

unlink "/tmp/instzs-id2zdbid.yml";
DumpFile("/tmp/instzs-id2zdbid.yml",\%id2zdbid);
