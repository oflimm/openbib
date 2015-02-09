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
            push @{$title_locationid_ref->{$titleid}}, "DE-38-507";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek Versicherungswiss/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-123";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-VERS";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek VWL/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-101";
        }
        elsif ($location_ref->{content} =~m/Fachbibliothek Sozialwissenschaften/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-132";
        }
        elsif ($location_ref->{content} =~m/^Theaterwissenschaftliche Sammlung/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-429";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-MEKUTH";
        }
        elsif ($location_ref->{content} =~m/^Inst.*?Medienkultur u. Theater/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-448";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-MEKUTH";
        }
        elsif ($location_ref->{content} =~m/^Humanwiss. Abteilung/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-HWA";
        }
        elsif ($location_ref->{content} =~m/^Hauptabteilung\s*\/\s*Lehrbuchsammlung/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-LBS";
        }
        elsif ($location_ref->{content} =~m/^Hauptabteilung \/ Lesesaal/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-LS";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Asien \/ Japanologie/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-459";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Asien \/ China/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-450";
        }
        elsif ($location_ref->{content} =~m/^Fachbibliothek Arch.*?ologien \/ Arch.*?ologisches Institut/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-427";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ARCH";
        }

        if ($location_ref->{content} =~m/^Fachbibliothek Asien/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ASIEN";
        }

        if ($location_ref->{content} =~m/^Hauptabteilung/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38";
        }
    }

    foreach my $mark_ref (@{$holding_ref->{fields}{'0014'}}){
        if ($mark_ref->{content} =~m/^2[4-9]/ || $mark_ref->{content} =~m/^[3-9][0-9]A/){
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
                push @{$title_ref->{'locations'}}, "DE-38-EDZ";
            }
        }
    }

    # Online-Medien werden allen Standorten zugewiesen
    if (defined $title_ref->{fields}{'4400'}){
        foreach my $item (@{$title_ref->{fields}{'4400'}}){
            if ($item->{content} eq "online"){
                push @{$title_ref->{'locations'}}, "DE-38";
                push @{$title_ref->{'locations'}}, "DE-38-101";
                push @{$title_ref->{'locations'}}, "DE-38-123";
                push @{$title_ref->{'locations'}}, "DE-38-132";
                push @{$title_ref->{'locations'}}, "DE-38-448";
                push @{$title_ref->{'locations'}}, "DE-38-429";
                push @{$title_ref->{'locations'}}, "DE-38-507";
                push @{$title_ref->{'locations'}}, "DE-38-EDZ";
                push @{$title_ref->{'locations'}}, "DE-38-HWA";
                push @{$title_ref->{'locations'}}, "DE-38-ASIEN";
                push @{$title_ref->{'locations'}}, "DE-38-MEKUTH";
                push @{$title_ref->{'locations'}}, "DE-38-ARCH";
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
