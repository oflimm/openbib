#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### lynda URLs korrigieren\n";

while (<>){
    my $title_ref = decode_json $_;

    foreach my $field_ref (@{$title_ref->{fields}{'0662'}}){
	$field_ref->{content} =~s/org=uni-muenster.de/org=uni-koeln.de/;
    }
 
    print encode_json $title_ref, "\n";
}
