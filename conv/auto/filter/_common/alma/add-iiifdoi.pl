#!/usr/bin/perl

use JSON::XS;
use utf8;

use Text::CSV_XS;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;

unlink "./iiifmapping.db";

my %mmsid2doi         = ();

tie %mmsid2doi,             'MLDBM', "./mmsid2doi.db"
    or die "Could not tie mmsid2doi.\n";

open $mapping,"<","/opt/openbib/autoconv/filter/_common/alma/db_export_mono.csv";

my $csv_options = {
  'eol'         => "\n",
  'sep_char'    => "\,", 
  'quote_char'  => '"',
  'escape_char' => '"',
  'binary' => 1,
};

my $csv = Text::CSV_XS->new($csv_options);

my @cols = @{$csv->getline ($mapping)};
my $row = {};
$csv->bind_columns (\@{$row}{@cols});

while ($csv->getline ($mapping)){
    my $identifier = $row->{identifier};
    my $mmsid = $row->{mms_id};

    $mmsid2doi{$mmsid} = $identifier if ($mmsid && $identifier);
}    

close $mapping;

open $mapping,"<","/opt/openbib/autoconv/filter/_common/alma/zdb_db_export_extended.csv";

my $csv2 = Text::CSV_XS->new($csv_options);

my @cols2 = @{$csv2->getline ($mapping)};
my $row2 = {};
$csv2->bind_columns (\@{$row2}{@cols2});

while ($csv2->getline ($mapping)){
    my $identifier = $row2->{identifier};
    my $mmsid = $row2->{mms_id_print};

    $mmsid2doi{$mmsid} = $identifier if ($mmsid && $identifier);
}    

close $mapping;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $fields_ref = $title_ref->{fields};

    if (defined $mmsid2doi{$titleid}){
	my $last024idx=0;
	
	if (defined $title_ref->{'fields'}{'0024'}){
	    foreach my $item_ref (@{$title_ref->{'fields'}{'0024'}}){
		if ($item_ref->{mult} > $last024idx){
		    $last024idx = $item_ref->{mult};
		}
	    }
	}
	
	my $mult   = $last024idx + 1;	
	my $doi_id = $mmsid2doi{$titleid};
        my $doi    = "10.58016/".$doi_id;
	
	# DOI setzen
	push @{$title_ref->{fields}{'0024'}}, {
	    mult     => $mult,
	    subfield => 'a',
	    content  => $doi,
	    ind => '7 ',
	};
	
	push @{$title_ref->{fields}{'0024'}}, {
	    mult     => $mult,
	    subfield => '2',
	    content  => 'doi',
	    ind => '7 ',
	};
	
	# Volltextlink setzen
	my $url = "https://doi.org/$doi_id";

	# $title_ref->{fields}{'4120'} = [{
	#     mult     => 1,
	#     subfield => 'g',
	#     content  => $url,
	# }];	
    }
   
    print encode_json $title_ref, "\n";
}
