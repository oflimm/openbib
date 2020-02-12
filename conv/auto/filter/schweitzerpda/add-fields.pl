#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    $title_ref->{fields}{'4410'} = [
        {
            mult     => 1,
            subfield => '',
            content  => "Monographie",
        },
    ];

    print encode_json $title_ref, "\n";
}
