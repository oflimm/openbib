#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;
use XML::Simple;
use YAML;

my $digitalis_ref = XMLin('/opt/openbib/autoconv/pools/digitalis/digitalis.xml', ForceArray => [ 'record' ]);

my $titleid_to_cdmid_ref = {};

foreach my $item_ref (@{$digitalis_ref->{record}}){
    $titleid_to_cdmid_ref->{$item_ref->{katkey}} = $item_ref->{cdmid};
}

while (<>){
    my $record_ref = decode_json $_;

    my $titleid = $record_ref->{id};

    if (defined $titleid_to_cdmid_ref->{$titleid}){
	
    	my $cdmid = $titleid_to_cdmid_ref->{$titleid};
	
	$record_ref->{'fields'}{'4114'} = [{
			subfield => 'c',
			content  => $cdmid,
			ind => '',
			mult => 1,
	}];
    }
    
    print encode_json $record_ref, "\n";
}
