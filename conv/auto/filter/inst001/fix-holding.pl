#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### inst001 Korrektur Exemplardaten\n";

while (<>){
    my $holding_ref = decode_json $_;

    foreach my $location_ref (@{$holding_ref->{fields}{'0016'}}){
        if ($location_ref->{content} =~m/Oppenheim-Stiftung/){
            if (!defined $holding_ref->{fields}{'3330'}){
                $holding_ref->{fields}{'3330'} = [];
            }
            push @{$holding_ref->{fields}{'3330'}},{
                content => '435',
                mult    => '1',
                subfield => '',
            };
        }
    }

    print encode_json $holding_ref, "\n";
}
