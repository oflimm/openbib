#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### philarchive Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "freemedia";
    
    print encode_json $title_ref, "\n";
}
