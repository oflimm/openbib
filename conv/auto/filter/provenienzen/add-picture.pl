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

my $provenienzen_ref = XMLin('/opt/openbib/autoconv/pools/provenienzen/provenienzen.xml', ForceArray => [ 'record' ]);

my $picture_to_cdmid_ref = {};

foreach my $item_ref (@{$provenienzen_ref->{record}}){
    $picture_to_cdmid_ref->{$item_ref->{title}} = $item_ref->{cdmid};
}

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    # Bildangaben mit CDMID anreichern

    if (defined $title_ref->{'fields'}{'4315'}){
	my $type_ref = [];
	foreach my $item_ref (@{$title_ref->{'fields'}{'4315'}}){
	    if ($item_ref->{subfield} eq "a"){
		if (defined $picture_to_cdmid_ref->{$item_ref->{content}}){
		    push @{$type_ref}, {
			subfield => 'c',
			content  => $picture_to_cdmid_ref->{$item_ref->{content}},
			ind => $item_ref->{ind},
			mult => $item_ref->{mult},
		    }
		}
	    }
	}
	
	if (@$type_ref){
	    push @{$title_ref->{fields}{'4315'}}, @{$type_ref};
	}
    }
    print encode_json $title_ref, "\n";
}
