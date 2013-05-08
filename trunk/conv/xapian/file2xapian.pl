#!/usr/bin/perl

#####################################################################
#
#  file2xapian.pl
#
#  Dieses File ist (C) 2007-2012 Oliver Flimm <flimm@openbib.org>
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

BEGIN {
#    $ENV{XAPIAN_PREFER_CHERT}    = '1';
    $ENV{XAPIAN_FLUSH_THRESHOLD} = $ENV{XAPIAN_FLUSH_THRESHOLD} || '200000';
}

use Benchmark ':hireswallclock';
use DB_File;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use MLDBM qw(DB_File Storable);
use Storable ();
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Index::Factory;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$withsorting,$withpositions,$loglevel,$indexpath);

&GetOptions(
    "indexpath=s"     => \$indexpath,
    "database=s"      => \$database,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "with-sorting"    => \$withsorting,
    "with-positions"  => \$withpositions,
    "help"            => \$help
);

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/file2xapian.log';
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

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config();

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

$indexpath=($indexpath)?$indexpath:$config->{xapian_index_base_path}."/".$database;

my $FLINT_BTREE_MAX_KEY_LEN = $config->{xapian_option}{max_key_length};

$logger->info("### POOL $database");

open(SEARCHENGINE, "<:utf8","searchengine.json"  ) || die "SEARCHENGINE konnte nicht geoeffnet werden";

$logger->info("Loeschung des alten Index fuer Datenbank $database");

system("rm $indexpath/*");

my $atime = new Benchmark;

{
    $logger->info("Aufbau eines neuen temporaeren Index fuer Datenbank $database");
    
    
    $logger->info("Migration der Titelsaetze");
    
    my $count = 1;

    {
        my $indexer = OpenBib::Index::Factory->create_indexer({ database => $database, create_index => 1, index_type => 'readwrite', index_path => $indexpath });

        $indexer->set_stopper;
        $indexer->set_termgenerator;
        
        my $atime = new Benchmark;
        while (my $searchengine=<SEARCHENGINE>) {            
            my $document = OpenBib::Index::Document->new()->from_json($searchengine);

            my $doc = $indexer->create_document({ document => $document, with_sorting => $withsorting, with_positions => $withpositions });
            $indexer->create_record($doc);
            
            if ($count % 1000 == 0) {
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                $atime         = new Benchmark;
                $logger->info("$count Saetze indexiert in $resulttime Sekunden");
            }
            
            $count++;
        }
    }
    
}

close(SEARCHENGINE);


my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

sub print_help {
    print << "ENDHELP";
file2xapian.pl - Datenbank-Konnektor zum Aufbau eines Xapian-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Integration von einzelnen Suchfeldern (nicht default)
   -with-sorting         : Integration von Sortierungsinformationen (nicht default)
   -with-positions       : Integration von Positionsinformationen(nicht default)
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
