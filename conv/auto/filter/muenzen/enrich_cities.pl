#!/usr/bin/perl

use warnings;
use strict;

use utf8;

use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS;
use Template;
use YAML;
use JSON::XS;
use DateTime;

use Encode qw/decode_utf8 encode decode/;

if ($#ARGV < 0){
    print << "HELP";
enrich_cities.pl - Aufrufsyntax

    enrich_cities.pl --inputfile=xxx

      --inputfile=                 : Name der Eingabedatei

      --loglevel=                  : Loglevel
HELP
exit;
}

our ($help,$inputfile,$loglevel,$logfile);

&GetOptions(
            "help"         => \$help,
            "inputfile=s"  => \$inputfile,
            "loglevel=s"   => \$loglevel,
            "logfile=s"    => \$logfile,
            );

if ($help){
    print_help();
}

if (!$inputfile && ! -f $inputfile){
  print "Inputfile nicht vorhanden.\n";
  exit;
}

$loglevel=($loglevel)?$loglevel:"INFO";
$logfile=($logfile)?$logfile:"./enrich_cities.log";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

my $csv_options = {
  'eol'         => "\n",
  'sep_char'    => "\t", 
  'quote_char'  => '"',
  'escape_char' => '"',
  'binary' => 1,
};

open my $in,   "<:encoding(utf8)",$inputfile;

my $csv = Text::CSV_XS->new($csv_options);

my @cols = @{$csv->getline ($in)};
my $row = {};
$csv->bind_columns (\@{$row}{@cols});

my $count = 0;

my $cities_ref = {};
while ($csv->getline ($in)){
    if ($row->{CONTENTDM_STADT}){
	my $thiscity_ref = {};
	
	foreach my $thislod (split('\|',$row->{LOD})){
	    if ($thislod=~/nomisma/){
		$thiscity_ref->{nomisma_id} = $thislod;
	    }
	    if ($thislod=~/geonames/){
		$thiscity_ref->{geonames_id} = $thislod;
	    }
	}

	$thiscity_ref->{ikmb_id} = $row->{uri};
	$thiscity_ref->{ikmb_type} = $row->{type};

	my $geo = $row->{description_de};
	$geo=~s/\s+\|\s+/,/;
	$thiscity_ref->{geo} = $geo;

	if ($row->{CONTENTDM_STADT} =~/\n/){
	    foreach my $thisname (split("\n",$row->{CONTENTDM_STADT})){
		$cities_ref->{$thisname} = $thiscity_ref;
	    }
	}
	else {
	    $cities_ref->{$row->{CONTENTDM_STADT}} = $thiscity_ref;
	}
    }
}

close($in);

while (<>){
   my $item_ref = decode_json $_; 

   my $name = $item_ref->{fields}{'0800'}[0]{content};

   if (defined $cities_ref->{$name}){
       my $thiscity_ref = $cities_ref->{$name};

       if ($thiscity_ref->{nomisma_id}){
	   push @{$item_ref->{'fields'}{'0010'}}, {
	       content  => $thiscity_ref->{nomisma_id},
	       mult     => 1,
	       subfield => '',
	   };
       }

       if ($thiscity_ref->{geonames_id}){
	   push @{$item_ref->{'fields'}{'0100'}}, {
	       content  => $thiscity_ref->{geonames_id},
	       mult     => 1,
	       subfield => '',
	   };
       }

       if ($thiscity_ref->{ikmb_id}){
	   push @{$item_ref->{'fields'}{'0110'}}, {
	       content  => $thiscity_ref->{ikmb_id},
	       mult     => 1,
	       subfield => '',
	   };
       }

       if ($thiscity_ref->{ikmb_type}){
	   push @{$item_ref->{'fields'}{'0111'}}, {
	       content  => $thiscity_ref->{ikmb_type},
	       mult     => 1,
	       subfield => '',
	   };
       }

       if ($thiscity_ref->{geo}){
	   push @{$item_ref->{'fields'}{'0200'}}, {
	       content  => $thiscity_ref->{geo},
	       mult     => 1,
	       subfield => '',
	   };
       }
       
       
   }
   
   print encode_json $item_ref, "\n";
}

