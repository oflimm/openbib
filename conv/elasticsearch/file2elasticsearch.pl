#!/usr/bin/perl

#####################################################################
#
#  file2elasticsearch.pl
#
#  Dieses File ist (C) 2013-2022 Oliver Flimm <flimm@openbib.org>
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
use DB_File;
use Encode qw(decode_utf8 encode_utf8);
use MLDBM qw(DB_File Storable);
use Storable ();
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Elasticsearch;
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Index::Factory;
use OpenBib::Normalizer;

#use Devel::Leak::Object qw{ GLOBAL_bless };
#$Devel::Leak::Object::TRACKSOURCELINES = 1;

my ($database,$indexname,$help,$logfile,$withsorting,$withpositions,$loglevel,$indexpath,$incremental,$withalias,$deletefile);

&GetOptions(
    "database=s"      => \$database,
    "indexname=s"     => \$indexname,
    "with-alias"      => \$withalias,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "with-sorting"    => \$withsorting,
    "with-positions"  => \$withpositions,
    "incremental"     => \$incremental,
    "deletefile=s"    => \$deletefile,    
    "help"            => \$help
);

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:"/var/log/openbib/file2elasticsearch/${database}.log";
$loglevel=($loglevel)?$loglevel:"INFO";

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

if (!-d "/var/log/openbib/file2elasticsearch/"){
    mkdir "/var/log/openbib/file2elasticsearch/";
}

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config();

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

$logger->info("### POOL $database");

my $old_indexname;

if ($withalias){
    my $es_indexer = OpenBib::Index::Factory->create_indexer({ sb => 'elasticsearch', database => $database, index_type => 'readwrite' });
    
    $old_indexname = $es_indexer->get_aliased_index($database);
    
    $indexname = ($old_indexname eq "${database}_a")?"${database}_b":"${database}_a";

    $logger->info("Indexing with alias");
    $logger->info("Old index for $database: $old_indexname");
    $logger->info("New index for $database: $indexname");    
}

open(SEARCHENGINE, "zcat searchengine.json.gz|"  ) || die "SEARCHENGINE konnte nicht geoeffnet werden";

binmode(SEARCHENGINE,":raw");

my $atime = new Benchmark;

{
    
    $logger->info("Migration der Titelsaetze");
    
    my $count = 1;

    {
        my $create_index = 1;

        if ($incremental){
            $create_index = 0;
        }

	my $normalizer = OpenBib::Normalizer->new;
               
        my $indexer = OpenBib::Index::Factory->create_indexer({ sb => 'elasticsearch', database => $database, indexname => $indexname, create_index => $create_index, index_type => 'readwrite', normalizer => $normalizer });

	if ($logger->is_debug){
	    $logger->debug("Indexer: ".YAML::Dump($indexer));
	}
	
        if ($incremental){
            $logger->info("Loeschen der obsoleten Titelsaetze");
            open (DELETE_IDS,$deletefile);
            while (my $id = <DELETE_IDS>){
                chomp($id);
                $logger->debug("Deleting Record $id");
                
                $indexer->delete_record($id);
            }
        }

        
        $indexer->set_stopper;
        $indexer->set_termgenerator;
	
        my $atime = new Benchmark;
        while (my $searchengine=<SEARCHENGINE>) {
	    my $document = OpenBib::Index::Document->new()->from_json($searchengine);
	    
	    my $doc = $indexer->create_document({ document => $document, with_sorting => $withsorting });
	    
            $indexer->create_record($doc);
            
            if ($count % 1000 == 0) {
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                $atime         = new Benchmark;
                $logger->info("$database (ES): 1000 ($count) Saetze indexiert in $resulttime Sekunden");
            }

            $count++;
        }

	$indexer->get_index->flush;
	
	$logger->debug(($count - 1)." records processed");
	
	if ($withalias){
	    # Aliases umswitchen
	    $logger->info("Switching alias and dropping old index $old_indexname");
	    $indexer->drop_alias($database,$old_indexname);
	    $indexer->create_alias($database,$indexname);
	    $indexer->drop_index($old_indexname);
	}
    }
    
}

close(SEARCHENGINE);

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit (ES): $resulttime Sekunden");

sub print_help {
    print << "ENDHELP";
file2elasticsearch.pl - Datenbank-Konnektor zum Aufbau eines Elasticsearch-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Integration von einzelnen Suchfeldern (nicht default)
   -with-sorting         : Integration von Sortierungsinformationen (nicht default)
   -with-positions       : Integration von Positionsinformationen(nicht default)
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}

