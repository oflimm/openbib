#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### nationallizenzen Titel ohne URL entfernen\n";

while (<>){
    my $title_ref = decode_json $_;

    next if (!defined $title_ref->{fields}{'0662'});
    
    print encode_json $title_ref, "\n";
}
