#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $subject        = $title_ref->{'0710'};
    my $classification = $title_ref->{'0700'};

    if (defined $classification){
        $title_ref->{'0710'} = $classification;
        $title_ref->{'0700'} = $subject if (defined $subject);
    }
    elsif (defined $subject){
        $title_ref->{'0710'} = $classification if (defined $classification);
        $title_ref->{'0700'} = $subject;
    }
    print encode_json $title_ref, "\n";
}

