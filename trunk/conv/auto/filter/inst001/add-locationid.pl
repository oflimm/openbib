#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

my $title_locationid_ref = {};

print STDERR "### inst001 Analysiere Exemplardaten\n";

open(HOLDING,"meta.holding");

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid = $holding_ref->{fields}{'0004'}[0]{content};

    next unless ($titleid);

    foreach my $location_ref (@{$holding_ref->{fields}{'0016'}}){
        if ($location_ref->{content} =~m/Fachbibliothek Chemie/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-FBChemie";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek Versicherungswiss/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-FBVers";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek VWL/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-FBVWL";
        }
        elsif ($location_ref->{content} =~m/^Humanwiss. Abteilung/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-HWA";
        }
        elsif ($location_ref->{content} =~m/^Hauptabteilung \/ Lehrbuchsammlung/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-LBS";
        }
        elsif ($location_ref->{content} =~m/^Hauptabteilung \/ Lesesaal/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-LS";
        }
        
        if ($location_ref->{content} =~m/^Hauptabteilung/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38";
        }
    }

    foreach my $mark_ref (@{$holding_ref->{fields}{'0014'}}){
        if ($mark_ref->{content} =~m/^2[3-9]/ || $mark_ref->{content} =~m/^[3-9][0-9]A/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-SAB";
        }
    }

}

close(HOLDING);

print STDERR "### inst001 Analysiere und erweitere Titeldaten\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};
    
    if (defined $title_ref->{fields}{'4715'}){
        foreach my $item (@{$title_ref->{fields}{'4715'}}){
            if ($item->{content} eq "edz"){
                push @{$title_ref->{'locationid'}}, "DE-38-EDZ";
            }
        }
    }

    my %have_locationid = ();

    foreach my $locationid (@{$title_locationid_ref->{$titleid}}){
        next if (defined $have_locationid{$locationid});
        push @{$title_ref->{'locations'}}, $locationid;

        $have_locationid{$locationid} = 1;
    }
    
    print encode_json $title_ref, "\n";
}
