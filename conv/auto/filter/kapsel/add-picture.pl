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

my $zas_ref = XMLin('/opt/openbib/autoconv/pools/kapsel/zas.xml', ForceArray => [ 'record' ]);

my $mark_to_cdmid_ref = {};

foreach my $item_ref (@{$zas_ref->{record}}){
    next if ($item_ref->{signaturgruppe} =~m/Inhaltsverzeichnis/ );
    
    if ($item_ref->{signaturgruppe} =~m/^(\S+)\s+/){
	$item_ref->{signaturgruppe} = $1;
    }
    $mark_to_cdmid_ref->{$item_ref->{signaturgruppe}} = $item_ref->{cdmid};
}

my $titleid_to_cdmid_ref = {};

open(HOLDING,"./meta.holding");
while (<HOLDING>){
    my $record_ref = decode_json $_;

    my $titleid = $record_ref->{'fields'}{'0004'}[0]{content};    
    my $mark    = $record_ref->{'fields'}{'0014'}[0]{content};

    my $basemark = "";
    my $cdmid;
    if ($mark =~m/^ZTGSLG-(\d+)/){
	$basemark = $1;
	if (defined $mark_to_cdmid_ref->{$basemark}){
	    $cdmid = $mark_to_cdmid_ref->{$basemark};
	}
    }
    elsif ($mark =~m/^ZTGSLG-([IXVMC]+\.\d+)/){
	$basemark = $1;
	if (defined $mark_to_cdmid_ref->{$basemark}){
	    $cdmid = $mark_to_cdmid_ref->{$basemark};
	}
    }
    elsif ($mark =~m/^ZTGSLG-([A-Za-z0-9]+)/){
	$basemark = $1;
	if (defined $mark_to_cdmid_ref->{$basemark}){
	    $cdmid = $mark_to_cdmid_ref->{$basemark};
	}
    }
    
    if ($cdmid){
	$titleid_to_cdmid_ref->{$titleid} = $cdmid;
    }
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
