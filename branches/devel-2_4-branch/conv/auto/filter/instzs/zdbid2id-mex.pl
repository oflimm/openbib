#!/usr/bin/perl

use YAML::Syck;

my @buffer  = ();
my $id      = 0;
my $localid = 0;

my $id2zdbid_ref = LoadFile("/tmp/instzs-id2zdbid.yml");

while (<>){
       
    if (/^0004:(.*)/){
        print "0004:".$id2zdbid_ref->{$1}."\n";
    }
    else {
        print;
    }
}

