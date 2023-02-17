#!/usr/bin/perl

use utf8;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_journal = 0;

    if (defined $title_ref->{fields}{'0572'}){
	$is_journal = 1;
    }
    
    next unless ($is_journal);

    print encode_json $title_ref, "\n";
}
