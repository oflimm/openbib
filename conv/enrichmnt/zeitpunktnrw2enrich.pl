#!/usr/bin/perl

#####################################################################
#
#  zeitpunktnrw2enrich.pl
#
#  Import von Volltextlinks zu IZ-MMSIDs
#
#  Dieses File ist (C) 2025 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

use strict;
use warnings;
use utf8;

use Encode 'decode';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS;
use JSON::XS;
use YAML::Syck;
use DBIx::Class::ResultClass::HashRefInflator;

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Conv::Common::Util;
use OpenBib::Catalog::Factory;

my $config    = new OpenBib::Config;
my $enrichmnt = new OpenBib::Enrichment;

my ($init,$inputfile,$jsonfile,$database,$import,$logfile,$loglevel);

&GetOptions(
    "init"              => \$init,
    "database=s"        => \$database,
    "import"            => \$import,
    "inputfile=s"       => \$inputfile,
    "json-file=s"       => \$jsonfile,
    "logfile=s"         => \$logfile,
    "loglevel=s"        => \$loglevel,
    );

if (!$inputfile && !$jsonfile){
    print << "HELP";
zeitpunktnrw2enrich.pl - Aufrufsyntax

    zeitpunktnrw2enrich.pl -init -import --json-importfile=zeitpunktnrw.json --inputfile=zeitpunktnrw.csv

      -init                        : Loeschen des bisherigen Inhalts
      -import                      : Direkt importieren
      --inputfile=                 : Name der Ursprungs-Eingabedatei
      --json-file=                 : Name der JSON-Datei

      --logfile=                   : Name der Logdatei
      --loglevel=                  : Loglevel
HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/zeitpunktnrw2enrich.log';
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

my $enrichment = new OpenBib::Enrichment;

my $origin = 31; # ZeitpunktNRW

$logger->debug("Origin: $origin");

my $csv_options = {
    'eol' => "\n",
	'sep_char' => "\t",
	'quote_char' => '"',
  'escape_char' => '"',
	'binary' => 1,
};

if ($init){
    $logger->info("Loesche URLs");
    $enrichment->init_enriched_content({ field => '4120', origin => $origin });
}

$database = $database || 'uni';

my $csv = Text::CSV_XS->new($csv_options);

my $count=1;

my $tuple_count = 1;

my $enrich_data_by_title_ref = [];

if ($import && $jsonfile){
    if (! -e $jsonfile){
        $logger->error("JSON-Einladedatei $jsonfile existiert nicht");
        exit;
    }
    open(JSON,$jsonfile);
    
    $logger->info("Einlesen und -laden der neuen Daten");

    while (<JSON>){
        my $item_ref = decode_json($_);

        push @{$enrich_data_by_title_ref}, $item_ref if (defined $item_ref->{titleid});
	
        $tuple_count++;
        
        if ($count % 10000 == 0){
	    $logger->info("$count records done");
            $enrichment->add_enriched_content({ matchkey => 'title',   content => $enrich_data_by_title_ref }) if (@$enrich_data_by_title_ref);
            $enrich_data_by_title_ref   = [];
        }
        $count++;
    }

    $enrichment->add_enriched_content({ matchkey => 'title',   content => $enrich_data_by_title_ref }) if (@$enrich_data_by_title_ref);
    
    $logger->info("$tuple_count Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }
    
}
else {
    if (! -e $inputfile){
	$logger->error("Eingabedatei $inputfile existiert nicht");
	exit;
    }

    $logger->info("Einlesen der neuen Daten");
    
    open my $in,   "<:encoding(utf8)",$inputfile;

    if ($jsonfile){
        open(JSON,">$jsonfile");
    }
    
    my @cols = @{$csv->getline ($in)};
    my $row = {};
    $csv->bind_columns (\@{$row}{@cols});
    
    while ($csv->getline ($in)){
        my $url = $row->{'url'};
	my $titleid = $row->{'titleid'};

	my $fulltexturl_ref = {
	    titleid  => $titleid,
	    origin   => $origin,
	    dbname   => $database,
	    field    => '4120',
	    subfield => 'g',
	    content  => $url,
	};
		
	print JSON encode_json($fulltexturl_ref),"\n" if ($jsonfile);

	if ($import && $count % 1000 == 0){
	    $enrichment->add_enriched_content({ matchkey => 'title',   content => $enrich_data_by_title_ref }) if (@$enrich_data_by_title_ref);
	    $enrich_data_by_title_ref   = [];
	}
        $count++;
    }
    
    $logger->info("$count done");
    
    $logger->info("$tuple_count Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }
}

