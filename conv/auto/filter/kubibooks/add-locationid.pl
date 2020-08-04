#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### kubibooks Erweitere Titeldaten fuer Kubi\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, "DE-Kn3";
    push @{$title_ref->{'locations'}}, "DE-38-ZBKUNST";
    
    print encode_json $title_ref, "\n";
}
