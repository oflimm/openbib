#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $have_005 = (defined $title_ref->{fields}{'0005'})?1:0;
    my $have_580 = (defined $title_ref->{fields}{'0580'})?1:0;

    if ($have_580 && !$have_005){
	$title_ref->{fields}{'0005'} = [];
	foreach my $part_ref (@{$title_ref->{fields}{'0580'}}){
	    push @{$title_ref->{fields}{'0005'}}, {
		content  => $part_ref->{content},
		mult     => $part_ref->{mult},
		subfield => "",
	    };
	}
	$title_ref->{fields}{'0580'} = [];
	delete $title_ref->{fields}{'0580'};
    }

    print encode_json $title_ref, "\n";
}
