#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### eupub Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "freemedia";
    push @{$title_ref->{'locations'}}, "emedien";
    
    print encode_json $title_ref, "\n";
}
