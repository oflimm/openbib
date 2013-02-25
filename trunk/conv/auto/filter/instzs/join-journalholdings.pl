#!/usr/bin/perl

use strict;
use warnings;

use JSON::XS;

while (<>){
    my $record_ref = decode_json $_;

    my $holdings = "";
    if (defined $record_ref->{'1200'}){
        $holdings = $record_ref->{'1200'}[0]{content};
    }

    if (defined $record_ref->{'1201'}){
        $holdings .= " ".$record_ref->{'1201'}[0]{content};
    }

    if ($holdings){
        $record_ref->{'1204'} = [ {
            content  => $holdings,
            subfield => '',
            mult     => 1,
        }];
    }

    print encode_json $record_ref, "\n";
}

