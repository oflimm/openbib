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
        if ($location_ref->{content} eq "587"){
            push @{$title_locationid_ref->{$titleid}}, "DE-587";
        }
        elsif ($location_ref->{content} eq "101" || $location_ref->{content} eq "103" || $location_ref->{content} eq "106" || $location_ref->{content} eq "120" || $location_ref->{content} eq "121" || $location_ref->{content} eq "128" || $location_ref->{content} eq "146" || $location_ref->{content} eq "157"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-101";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "123"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-123";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-VERS";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "132"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-132";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "418"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-418";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "426"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-426";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ARCH";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }        
        elsif ($location_ref->{content} eq "427"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-427";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ARCH";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }        
        elsif ($location_ref->{content} eq "429"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-429";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-MEKUTH";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "438"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-438";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ARCH";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }        
        elsif ($location_ref->{content} eq "448"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-448";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-MEKUTH";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "450"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-450";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ASIEN";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }                
        elsif ($location_ref->{content} eq "459"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-459";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-ASIEN";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
        }                
        elsif ($location_ref->{content} eq "38"){
            push @{$title_locationid_ref->{$titleid}}, "DE-38";
            push @{$title_locationid_ref->{$titleid}}, "DE-38-USBFB";
	    foreach my $signatur_ref (@{$holding_ref->{fields}{'0014'}}){
		if ($signatur_ref->{content} =~m/^EWA-LS\s*:?\s*Z/ || $signatur_ref->{content} =~m/^EWA Z/ || $signatur_ref->{content} =~m/^EWA-LS-Theke Z/ || $signatur_ref->{content} =~m/^HP-LS B/){
		    push @{$title_locationid_ref->{$titleid}}, "DE-38-HWA";
		}
		
	    }
        }
        elsif ($location_ref->{content} =~/^\d\d\d$/){
            push @{$title_locationid_ref->{$titleid}}, "DE-38-".$location_ref->{content};
        }
        else {
            push @{$title_locationid_ref->{$titleid}}, $location_ref->{content};
        }

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
