#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    $title_ref->{fields}{'4400'} = [
        {
            mult     => 1,
            subfield => '',
            content  => "online",
        },
    ];

    print encode_json $title_ref, "\n";
}
