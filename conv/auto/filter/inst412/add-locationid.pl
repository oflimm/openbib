#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### inst412 Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "DE-38-412";
    push @{$title_ref->{'locations'}}, "DE-38-ENGPORTROM";
    
    print encode_json $title_ref, "\n";
}
