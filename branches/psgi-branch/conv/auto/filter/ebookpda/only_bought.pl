#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use MediaWiki::API;
use JSON::XS qw/decode_json encode_json/;

my %positive_ids = ();

open(IDS,"/opt/openbib/autoconv/pools/ebookpda/ebookpda_ids.csv");

while (<IDS>){
    chomp;
    $positive_ids{$_}=1;
}

close(IDS);

while (<>){
    my $title_ref = decode_json $_;

    if (!defined $positive_ids{$title_ref->{id}}){
        print STDERR "Titel-ID $title_ref->{id} excluded\n";
        next;
    }
    
    print;
}
