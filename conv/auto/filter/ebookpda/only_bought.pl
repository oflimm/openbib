#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use JSON::XS qw/decode_json encode_json/;

my %positive_ids = ();

open(IDS,"/opt/openbib/autoconv/pools/ebookpda/ebookpda_positive_ids.csv");

while (<IDS>){
    chomp;
    $positive_ids{$_}=1;
}

close(IDS);

while (<>){
    my $title_ref = decode_json $_;


    my $exclude = 1;

    if (defined $title_ref->{fields}{'0662'}){
	foreach my $field_ref (@{$title_ref->{fields}{'0662'}}){
	    my ($mil_id)=$field_ref->{content}=~m/id=(\d+)$/i;
	    next unless (defined $mil_id);
	    if (defined $positive_ids{$mil_id} && $positive_ids{$mil_id}){
		$exclude=0;
		$positive_ids{$mil_id}++;
	    }
	}
    }
    
    print if (!$exclude);
}

my @rest_ids = ();

foreach my $key (keys %positive_ids){
    push @rest_ids, $key if ($positive_ids{$key} < 2);
}

print STDERR join(';',@rest_ids),"\n";
