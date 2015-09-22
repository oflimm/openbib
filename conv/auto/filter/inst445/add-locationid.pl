#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### inst445 Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "DE-38-445";
    push @{$title_ref->{'locations'}}, "DE-38-ZBKUNST";
    
    print encode_json $title_ref, "\n";
}
