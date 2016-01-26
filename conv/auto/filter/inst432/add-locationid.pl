#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use OpenBib::Catalog::Subset;

print STDERR "### inst432 Analysiere Exemplardaten\n";

open(HOLDING,"meta.holding");

my $title_locationid_ref = {};

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid = $holding_ref->{fields}{'0004'}[0]{content};

    next unless ($titleid);

    foreach my $location_ref (@{$holding_ref->{fields}{'0016'}}){
        if ($location_ref->{content} =~m/^a.r.t.e.s./){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ARTES";
        }
        else {
            push @{$title_locationid_ref->{$titleid}}, "DE-38-432";
        }
    }

    # Alternativ:
    #
    # Jeder Titel (auch Artes) soll weiterhin 432 zugeordnet sein
    # Das entspricht der Recherche ueber den Gesamtbestand
    
    # push @{$title_locationid_ref->{$titleid}}, "DE-38-432";
}

close(HOLDING);

print STDERR "### inst432 Analysiere und erweitere Titeldaten\n";

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
