#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### hathitrust Fehlerhafte Titel entfernen\n";

while (<>){
    my $title_ref = decode_json $_;

    next unless ($title_ref->{id} =~ m/oai/);
    
    print encode_json $title_ref, "\n";
}
