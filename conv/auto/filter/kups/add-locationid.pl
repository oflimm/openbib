#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### kups Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "freemedia";
    push @{$title_ref->{'locations'}}, "emedien";
    push @{$title_ref->{'locations'}}, "DE-38-KUPS";
    
    print encode_json $title_ref, "\n";
}
