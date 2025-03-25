#!/usr/bin/perl

use JSON::XS;
use utf8;

use Text::CSV_XS;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;
use YAML;

unlink "./iiifmapping.db";

my %mmsid2doi         = ();

tie %mmsid2doi,             'MLDBM', "./mmsid2doi.db"
    or die "Could not tie mmsid2doi.\n";

open $mapping,"<","/opt/openbib/autoconv/filter/fotobuecher/doi_mapping.csv";

my $csv_options = {
  'eol'         => "\n",
  'sep_char'    => "\;", 
  'quote_char'  => '"',
  'escape_char' => '"',
  'binary' => 1,
};

my $csv = Text::CSV_XS->new($csv_options);

my @cols = @{$csv->getline ($mapping)};
my $row = {};
$csv->bind_columns (\@{$row}{@cols});

while ($csv->getline ($mapping)){
    my $identifier = $row->{doi};
    my $mmsid = $row->{iz_mms_id};
    my $nzmmsid = $row->{nz_mms_id};

    $mmsid =~s/\s+//g;
    $nzmmsid =~s/\s+//g;    
    
    $mmsid2doi{$mmsid}   = $identifier if ($mmsid && $identifier);
    $mmsid2doi{$nzmmsid} = $identifier if ($nzmmsid && $identifier);
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
        my $doi    = $doi_id;
	
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

	$title_ref->{fields}{'4120'} = [{
	    mult     => 1,
	    subfield => 'g',
	    content  => $url,
	}];	
    }
   
    print encode_json $title_ref, "\n";
}
