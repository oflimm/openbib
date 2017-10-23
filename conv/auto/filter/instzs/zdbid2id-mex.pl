#!/usr/bin/perl

use strict;
use warnings;

use YAML::Syck;
use JSON::XS;

my $id2zdbid_ref = LoadFile("/tmp/instzs-id2zdbid.yml");

while (<>){
    my $record_ref = decode_json $_;

    my $titleid = $record_ref->{fields}{'0004'}[0]{content};

    next unless ($titleid);

    next unless ($id2zdbid_ref->{$titleid});
    
    $record_ref->{fields}{'0004'}[0]{content} = $id2zdbid_ref->{$titleid};
    
    print encode_json $record_ref, "\n";
}

