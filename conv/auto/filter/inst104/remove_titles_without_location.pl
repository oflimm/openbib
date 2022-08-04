#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

open(HOLDING, "meta.holding");

my $valid_titles_ref = {};

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid  = $holding_ref->{fields}{'0004'}[0]{content};
    my $location = $holding_ref->{fields}{'0016'}[0]{content};

    if ($location && ($location =~m/^sfb/i || $location =~m/^fifo/i)){
	$valid_titles_ref->{$titleid} = 1;
    }
}


close(HOLDING);

print STDERR "### inst104 Titel ohne Standort entfernen\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};
    
    next if (!defined $valid_titles_ref->{$titleid});
    
    print encode_json $title_ref, "\n";
}
