#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;
use YAML;

#open(CHANGED,">./changed.json");

open(DOIMAPPING,"/opt/openbib/autoconv/pools/inkunabeln/inkunabel_mapping.csv");

my $cdm2doi_ref = {};

while (<DOIMAPPING>){
    my ($doi,$cdmid,$collection,$mark)= split ',';
    print STDERR $_;
    $cdm2doi_ref->{$collection}{$cdmid} = $doi;    
}

close(DOIMAPPING);

print STDERR YAML::Dump($cdm2doai_ref);

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my ($collection,$cdmid) = $titleid =~m/^cdm_([a-z_]+)_(\d+)$/;

    if (defined $cdm2doi_ref->{$collection} && defined $cdm2doi_ref->{$collection}{$cdmid}){

	my $doi_id = $cdm2doi_ref->{$collection}{$cdmid};
        my $doi    = "10.58016/".$doi_id;
	# DOI setzen
	push @{$title_ref->{fields}{'0024'}}, {
	    mult     => 1,
	    subfield => 'a',
	    content  => $doi,
	    ind => '7 ',
	};

	push @{$title_ref->{fields}{'0024'}}, {
	    mult     => 1,
	    subfield => '2',
	    content  => 'doi',
	    ind => '7 ',
	};

	# Volltextlink setzen
	my $url = "https://digital.ub.uni-koeln.de/view/$doi_id";
	
	push @{$title_ref->{fields}{'4120'}}, {
	    mult     => 1,
	    subfield => 'g',
	    content  => $url,
	};
		
	# Digitalmarkierung setzen
	push @{$title_ref->{fields}{'4400'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => "online",
	};

	push @{$title_ref->{fields}{'4410'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => "Digital",
	};
    }
   
    print encode_json $title_ref, "\n";
}
#close(CHANGED);
