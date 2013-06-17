#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $subject        = (defined $title_ref->{fields}{'0710'})?$title_ref->{fields}{'0710'}:undef;
    my $classification = (defined $title_ref->{fields}{'0700'})?$title_ref->{fields}{'0700'}:undef;

    if (defined $classification){
        $title_ref->{fields}{'0710'} = $classification;
        if (defined $subject){
            $title_ref->{fields}{'0700'} = $subject;
        }
        else {
            delete $title_ref->{fields}{'0700'};
        }
    }
    elsif (defined $subject){
        $title_ref->{fields}{'0700'} = $subject;
        delete $title_ref->{fields}{'0700'};
    }
    print encode_json $title_ref, "\n";
}

