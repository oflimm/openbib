#!/usr/bin/perl

#####################################################################
#
#  file2elasticsearch.pl
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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
    $ENV{XAPIAN_FLUSH_THRESHOLD} = '200000';
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
use ElasticSearch;
use String::Tokenizer;
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$loglevel);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/file2elasticsearch.log';
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

$logger->info("### POOL $database");

open(TITLE_LISTITEM,  "<:utf8","title_listitem.mysql" ) || die "TITLE_LISTITEM konnte nicht geoeffnet werden";
open(SEARCHENGINE, "<:utf8","searchengine.csv"  ) || die "SEARCHENGINE konnte nicht geoeffnet werden";

my $atime = new Benchmark;

{    
    $logger->info("Aufbau eines neuen temporaeren Index fuer Datenbank $database");

    my $es = ElasticSearch->new(
        servers      => '127.0.0.1:9200',       # default '127.0.0.1:9200'
        transport    => 'http',                 # default 'http'
        max_requests => 10_000,                 # default 10_000
        trace_calls  => 'log_file',
        no_refresh   => 0 | 1,
    );
    
    
    $logger->info("Migration der Titelsaetze");
    
    my $count = 1;

    my $doc_buffer_ref = [];
    
    {
        my $atime = new Benchmark;
        while (my $title_listitem=<TITLE_LISTITEM>, my $searchengine=<SEARCHENGINE>) {
            my ($s_id,$searchcontent)=split ("",$searchengine);
            my ($t_id,$listitem)=split ("",$title_listitem);
            
            if ($s_id ne $t_id) {
                $logger->fatal("Id's stimmen nicht ueberein ($s_id != $t_id)!");
                next;
            }
            
            my $searchcontent_ref = decode_json $searchcontent;

            # ID setzen:

            $searchcontent_ref->{id} = $s_id;
            
            push @$doc_buffer_ref, $searchcontent_ref;
            
            if ($count % 1000 == 0) {
                # Bulk-Indexieren

                my $result = $es->bulk(
                    actions     => [ 'index' ],                 # required
                        
                    index       => $database,                   # optional
                    type        => 'title',                     # optional
                    data        => $doc_buffer_ref,
                    #                    consistency => 'quorum' |  'one' | 'all'    # optional
                    #                        refresh     => 0 | 1,                       # optional
                    #                    replication => 'sync' | 'async',            # optional
                );

                $doc_buffer_ref = [];
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

close(TITLE_LISTITEM);
close(SEARCHENGINE);

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

sub print_help {
    print << "ENDHELP";
file2elasticsearch.pl - Datenbank-Konnektor zum Aufbau eines ElasticSearch-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
