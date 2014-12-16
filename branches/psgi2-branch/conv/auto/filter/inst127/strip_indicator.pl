#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    foreach my $field (keys %{$title_ref->{fields}}){
        foreach my $field_ref (@{$title_ref->{fields}{$field}}){
            if (defined $field_ref->{content} && $field_ref->{content}=~m/^\$([a-z])\$/){
                my $subfield = $1;

                $field_ref->{content}=~s/^\$[a-z]\$\s+//;
                    
                $field_ref->{subfield} = $subfield;
            }
        }
        
    }

    print encode_json $title_ref, "\n";
}

