#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

my $title_locationid_ref = {};

print STDERR "### instzs: Analysiere Exemplardaten\n";

open(HOLDING,"meta.holding");

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid = $holding_ref->{fields}{'0004'}[0]{content};

    next unless ($titleid);

    foreach my $location_ref (@{$holding_ref->{fields}{'3330'}}){
        push @{$title_locationid_ref->{$titleid}}, "DE-38-".$location_ref->{content};
    }
}

close(HOLDING);

print STDERR "### instzs: Erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};
    
    my %have_locationid = ();

    foreach my $locationid (@{$title_locationid_ref->{$titleid}}){
        next if (defined $have_locationid{$locationid});
        push @{$title_ref->{'locations'}}, $locationid;

        $have_locationid{$locationid} = 1;
    }
    
    print encode_json $title_ref, "\n";
}
