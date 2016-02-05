#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### wikisource_de Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "wikisource_de";
    push @{$title_ref->{'locations'}}, "DE-38-USBFB";
    
    print encode_json $title_ref, "\n";
}
