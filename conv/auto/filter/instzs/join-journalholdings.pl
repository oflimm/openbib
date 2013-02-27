#!/usr/bin/perl

use strict;
use warnings;

use JSON::XS;

while (<>){
    my $record_ref = decode_json $_;

    my $holdings_ref = [];
    if (defined $record_ref->{'1202'}){
        push @$holdings_ref, $record_ref->{'1202'}[0]{content};
        delete $record_ref->{'1202'};
    }

    if (defined $record_ref->{'1200'}){
        push @$holdings_ref, $record_ref->{'1200'}[0]{content};
        delete $record_ref->{'1200'};
    }

    if (defined $record_ref->{'1201'}){
        push @$holdings_ref, $record_ref->{'1201'}[0]{content};
        delete $record_ref->{'1201'};
    }


    if (@$holdings_ref){
        $record_ref->{'1204'} = [ {
            content  => join (" ",@$holdings_ref),
            subfield => '',
            mult     => 1,
        }];
    }

    print encode_json $record_ref, "\n";
}

