#!/usr/bin/perl

#####################################################################
#
#  fulldump_titles2csv.pl
#
#  Dieses File ist (C) 2015-2016 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################

use strict;
use warnings;
use utf8;

use Benchmark ':hireswallclock';
use OpenBib::Catalog::Factory;
use JSON::XS qw/decode_json/;
use Encode qw(decode_utf8 encode_utf8);
use Getopt::Long;
use List::MoreUtils qw/ uniq /;
use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS;

my ($database,$help,$logfile,$loglevel,$outputfile,$configfile);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
	    "loglevel=s"       => \$loglevel,
            "outputfile=s"    => \$outputfile,
	    "configfile=s"    => \$configfile,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:"/var/log/openbib/fulldump_titles2csv/${database}.log";
$loglevel=($loglevel)?$loglevel:'INFO';

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

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config();

my $atime  = new Benchmark;

if (!$database || !$configfile ){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt oder kein Config-File mit --configfile= spezifiziert.");
  exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

my @dest_fields = @{$convconfig->{'output_columns'}};

# Einlesen und Reorganisieren

my $outputencoding = ($convconfig->{outputencoding})?$convconfig->{outputencoding}:'utf8';

my $csv_options = {};

foreach my $csv_option (keys %{$convconfig->{csv}}){
    $csv_options->{$csv_option} = $convconfig->{csv}{$csv_option};
}

my $csv = Text::CSV_XS->new($csv_options);

$logger->info("### POOL $database");

my $out;

open $out, ">:encoding(utf8)", $outputfile;

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});

my $out_ref = [];

push @{$out_ref}, @dest_fields;

$csv->print($out,$out_ref);

my $titles = $catalog->get_schema->resultset('Title');

my $count = 0;

while (my $title=$titles->next){

#    last if ($count > 2);
    
    my $id = $title->id;

    my $record_ref = OpenBib::Record::Title->new({database => $database, id => $id})->load_full_record->to_hash;
    
    $out_ref = [];    

    my $output_fields_ref = {};

    # Init Content
    foreach my $thisfield  (@dest_fields){
	$output_fields_ref->{$thisfield} = [];
    }
    
    push @{$output_fields_ref->{'id'}}, $id;
    
    foreach my $thisfield (keys %{$convconfig->{mapping_title}}){
	if (defined $record_ref->{fields}{$thisfield}){
	    foreach my $thisitem_ref (@{$record_ref->{fields}{$thisfield}}){
		my $destfield = $convconfig->{mapping_title}{$thisfield};
		push @{$output_fields_ref->{$destfield}}, $thisitem_ref->{content};
	    }
	}
    }

    foreach my $thisholding_ref (@{$record_ref->{items}}){
	if ($logger->is_debug){
	    $logger->debug("Holding item: ".YAML::Dump($thisholding_ref));
	}
	foreach my $thisfield (keys %{$convconfig->{mapping_holding}}){
	    my $destfield = $convconfig->{mapping_holding}{$thisfield};
	    if (defined $thisholding_ref->{$thisfield}){
		push @{$output_fields_ref->{$destfield}}, $thisholding_ref->{$thisfield}{content};
	    }
	}
    }

    $logger->debug(YAML::Dump($output_fields_ref));
    
    my @output = ();
    foreach my $destfield  (@dest_fields){
	my @thisfield_content = @{$output_fields_ref->{$destfield}};
	$logger->debug("Field: $destfield - ".join(';',@thisfield_content)." - ".$#thisfield_content);

	# Keins
	if ($#thisfield_content < 0 ) {
	    push @output, "";
	}
	# Mehr
	elsif ($#thisfield_content >= 0){
	    push @output, join(' ; ',@{$output_fields_ref->{$destfield}});
	}
    }

    $logger->debug(YAML::Dump(\@output));
    
    push @{$out_ref}, @output;

    $csv->print($out,$out_ref);

    $count++;

    if ($count % 1000 == 0){
	$logger->info("$count done");
    }
}

close $out;

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

sub cleanup_content {
    my $content = shift;

    $content=~s/&lt;/</g;
    $content=~s/&gt;/>/g;
    $content=~s/&amp;/&/g;
    return $content;
}

sub print_help {
    print << "ENDHELP";
dump_title2csv.pl - Datenbank-Dump in CSV-Datei der Kurzlisten-Kategorien

   Optionen:
   -help                 : Diese Informationsseite
       
   --outputfile          : CSV-Ausgabedatei
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
