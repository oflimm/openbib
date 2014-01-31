#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### inst459 Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "DE-38-459";
    push @{$title_ref->{'locations'}}, "DE-38-ASIEN";
    
    print encode_json $title_ref, "\n";
}
