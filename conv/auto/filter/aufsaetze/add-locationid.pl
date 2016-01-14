#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### aufsaetze Erweitere Titeldaten um Locationid aus 3330\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, 'aufsaetze';

    foreach my $field_ref (@{$title_ref->{fields}{'3330'}}){
        push @{$title_ref->{'locations'}}, $field_ref->{content};
    }
    
    print encode_json $title_ref, "\n";
}
