#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### inst413 Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "DE-38-413";
    push @{$title_ref->{'locations'}}, "DE-38-ENGPORTROM";
    
    print encode_json $title_ref, "\n";
}
