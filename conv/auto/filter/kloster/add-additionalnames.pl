#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;
use Text::CSV_XS;

unlink "./iiifmapping.db";

my %gnd2namen         = ();

tie %gnd2namen,             'MLDBM', "./gnd2namen.db"
    or die "Could not tie gnd2namen.\n";

open $mapping,"<","/opt/openbib/autoconv/filter/kloster/klosternamen.csv";

my $csv_options = {
  'eol'         => "\n",
  'sep_char'    => "\t", 
  'quote_char'  => '"',
  'escape_char' => '"',
  'binary' => 1,
};

my $csv = Text::CSV_XS->new($csv_options);

my @cols = @{$csv->getline ($mapping)};
my $row = {};
$csv->bind_columns (\@{$row}{@cols});

while ($csv->getline ($mapping)){
    my $identifier = $row->{'GND'};
    my $namen      = $row->{'Alternative Namen'};

    $gnd2namen{$identifier} = $namen;
}

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $mult = 1;
    if (defined $title_ref->{fields}{'0984'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0984'}}){
	    if ($item_ref->{subfield} eq "0"){
		if ($gnd2namen{$item_ref->{content}}){
		    foreach my $verweisung (split('\s*;\s*',$gnd2namen{$item_ref->{content}})){
			
			push @{$title_ref->{fields}{'1009'}}, {
			    mult     => $mult++,
			    subfield => 'a',
			    content => $verweisung,
			};
		    }
		}
	    }
	}
    }
    
    print encode_json $title_ref, "\n";
}

