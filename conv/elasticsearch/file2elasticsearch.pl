#!/usr/bin/perl

#####################################################################
#
#  file2elasticsearch.pl
#
#  Dieses File ist (C) 2012-2017 Oliver Flimm <flimm@openbib.org>
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
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use MLDBM qw(DB_File Storable);
use Storable ();
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Elasticsearch;
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

open(SEARCHENGINE,    "searchengine.json"  ) || die "SEARCHENGINE konnte nicht geoeffnet werden";

my $atime = new Benchmark;

{    
    $logger->info("Aufbau eines neuen temporaeren Index fuer Datenbank $database");

    my $es = Search::Elasticsearch->new(
	cxn_pool   => $config->{elasticsearch}{cxn_pool},    # default 'Sniff'
        nodes      => $config->{elasticsearch}{nodes},       # default '127.0.0.1:9200'
    );

    my $result;

    if ($es->indices->exists( index => $database )){
        $result = $es->indices->delete( index => $database );
    }
    
    $result = $es->indices->create(
        index    => $database,
#	type     => 'title',
    );

    $result = $es->indices->put_mapping(
	index => $database,
	type  => 'title',
	body => {
	    title => {
		properties => $config->{elasticsearch_index_mappings}{title}{properties},
	    }
	}	
	);
    
    $logger->info("Migration der Titelsaetze");
    
    my $count = 1;

    my $doc_buffer_ref = [];
    
    {
	my $bulk = $es->bulk_helper(
	    index => $database,
	    type => 'title',
	    );
	
        my $atime = new Benchmark;
        while (my $searchengine=<SEARCHENGINE>) {
	    my $searchengine_ref = decode_json $searchengine;

	    my $id                 = $searchengine_ref->{id};
	    my $title_listitem_ref = $searchengine_ref->{record};
	    my $searchcontent_ref  = $searchengine_ref->{index};

	    my $elasticsearch_ref = {};
	    
            $elasticsearch_ref->{listitem} = $title_listitem_ref;
	    
            foreach my $sorttype (keys %{$config->{elasticsearch_sorttype_value}}){
                
                if ($config->{elasticsearch_sorttype_value}{$sorttype}{type} eq "stringcategory"){
                    my $content = (exists $title_listitem_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{category}}[0]{content})?$title_listitem_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{category}}[0]{content}:"";
                    next unless ($content);
                    
                    $content = OpenBib::Common::Util::normalize({
                        content   => $content,
                    });
                    
                    if ($content){
                        $logger->debug("Adding $content as sortvalue");

			$elasticsearch_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{field}} = $content;
                    }
                }
                elsif ($config->{elasticsearch_sorttype_value}{$sorttype}{type} eq "integercategory"){
                    my $content = 0;
                    if (exists $title_listitem_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{category}}[0]{content}){
                        ($content) = $title_listitem_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{category}}[0]{content}=~m/^(\d+)/;
                    }
                    if ($content){
                        $content = sprintf "%08d", $content;
                        $logger->debug("Adding $content as sortvalue");
                        $elasticsearch_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{field}} = $content;
                    }
                }
                elsif ($config->{elasticsearch_sorttype_value}{$sorttype}{type} eq "integervalue"){
                    my $content = 0 ;
                    if (exists $title_listitem_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{category}}){
                        ($content) = $title_listitem_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{category}}=~m/^(\d+)/;
                    }
                    if ($content){                    
                        $content = sprintf "%08d",$content;
                        $logger->debug("Adding $content as sortvalue");
                        $elasticsearch_ref->{$config->{elasticsearch_sorttype_value}{$sorttype}{field}} = $content;
                    }
                }
            }
            
            if ($logger->is_debug){
                $logger->debug(YAML::Dump($searchcontent_ref));
            }
            
            # Gewichtungen aus Suchfeldern entfernen

            foreach my $searchfield (keys %{$config->{searchfield}}){
                if (defined $searchcontent_ref->{$searchfield}){
                    my $newcontent_ref = [];
                    foreach my $weight (keys %{$searchcontent_ref->{$searchfield}}){
			foreach my $newstring_ref (@{$searchcontent_ref->{$searchfield}{$weight}}){
			    push @$newcontent_ref, $newstring_ref->[1];
			}
                    }
                    $elasticsearch_ref->{$searchfield} = $newcontent_ref;
                }
            }

	    if ($logger->is_debug){
		$logger->debug(YAML::Dump($elasticsearch_ref));
	    }
	    
	    $bulk->index(
		{
		    _id    => $id,
		    source => $elasticsearch_ref,
		}
		);

	    if ($count % 1000){
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                $atime         = new Benchmark;
                $logger->info("$count Saetze indexiert in $resulttime Sekunden");            }
            
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
file2elasticsearch.pl - Datenbank-Konnektor zum Aufbau eines ElasticSearch-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
