#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### inst218 Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "DE-38-218";
    push @{$title_ref->{'locations'}}, "DE-38-VERS";
    
    print encode_json $title_ref, "\n";
}
