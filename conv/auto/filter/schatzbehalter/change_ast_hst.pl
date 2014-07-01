#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0310'}){
        $title_ref->{fields}{'0331'}[1] = {
            content  => $title_ref->{fields}{'0331'}[0]{content},
            mult     => '002',
            subfield => 'h',
        };
        
        $title_ref->{fields}{'0331'}[0] = {
            content  => $title_ref->{fields}{'0310'}[0]{content},
            mult     => '001',
            subfield => 'a',
        };

        delete $title_ref->{fields}{'0310'};
    }

    
    print encode_json $title_ref, "\n";
}

