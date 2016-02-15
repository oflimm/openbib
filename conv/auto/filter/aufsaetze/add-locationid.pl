#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### aufsaetze Erweitere Titeldaten um Locationid aus 3330\n";

while (<>){
    my $title_ref = decode_json $_;

    push @{$title_ref->{'locations'}}, 'aufsaetze';

    foreach my $location_ref (@{$title_ref->{fields}{'3330'}}){

        if ($location_ref->{content} eq "DE-38-101" || $location_ref->{content} eq "DE-38-103" || $location_ref->{content} eq "DE-38-105" || $location_ref->{content} eq "DE-38-106" || $location_ref->{content} eq "DE-38-120" || $location_ref->{content} eq "DE-38-121" || $location_ref->{content} eq "DE-38-128" || $location_ref->{content} eq "DE-38-146" || $location_ref->{content} eq "DE-38-157"){
            push @{$title_ref->{'locations'}}, "DE-38-101";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "DE-38-123"){
            push @{$title_ref->{'locations'}}, "DE-38-123";
            push @{$title_ref->{'locations'}}, "DE-38-VERS";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "DE-38-132"){
            push @{$title_ref->{'locations'}}, "DE-38-132";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "DE-38-418"){
            push @{$title_ref->{'locations'}}, "DE-38-418";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "DE-38-426"){
            push @{$title_ref->{'locations'}}, "DE-38-426";
            push @{$title_ref->{'locations'}}, "DE-38-ARCH";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }        
        elsif ($location_ref->{content} eq "DE-38-427"){
            push @{$title_ref->{'locations'}}, "DE-38-427";
            push @{$title_ref->{'locations'}}, "DE-38-ARCH";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }        
        elsif ($location_ref->{content} eq "DE-38-429"){
            push @{$title_ref->{'locations'}}, "DE-429";
            push @{$title_ref->{'locations'}}, "DE-38-MEKUTH";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "DE-38-448"){
            push @{$title_ref->{'locations'}}, "DE-448";
            push @{$title_ref->{'locations'}}, "DE-38-MEKUTH";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }
        elsif ($location_ref->{content} eq "DE-38-450"){
            push @{$title_ref->{'locations'}}, "DE-38-450";
            push @{$title_ref->{'locations'}}, "DE-38-ASIEN";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }                
        elsif ($location_ref->{content} eq "DE-38-459"){
            push @{$title_ref->{'locations'}}, "DE-38-459";
            push @{$title_ref->{'locations'}}, "DE-38-ASIEN";
            push @{$title_ref->{'locations'}}, "DE-38-USBFB";
        }                
        elsif ($location_ref->{content} eq "DE-38"){
            push @{$title_ref->{'locations'}}, "DE-38";
        }
        else {        
            push @{$title_ref->{'locations'}}, $location_ref->{content};
        }
    }
    
    print encode_json $title_ref, "\n";
}
