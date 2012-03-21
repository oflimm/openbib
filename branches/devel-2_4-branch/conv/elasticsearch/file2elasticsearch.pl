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
$loglevel=($loglevel)?$loglevel:"DEBUG";

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
open(SEARCHENGINE,    "<:utf8","searchengine.csv"  ) || die "SEARCHENGINE konnte nicht geoeffnet werden";

my $atime = new Benchmark;

{    
    $logger->info("Aufbau eines neuen temporaeren Index fuer Datenbank $database");

    my $es = ElasticSearch->new(
        servers      => $config->{elasticsearch}->{servers},       # default '127.0.0.1:9200'
        transport    => $config->{elasticsearch}->{transport},     # default 'httplite'
        max_requests => $config->{elasticsearch}->{max_requests},  # default 10_000
        trace_calls  => $config->{elasticsearch}->{trace_calls},
        no_refresh   => $config->{elasticsearch}->{no_refesh},
    );

    my $result = $es->index_exists(
            index => $database,
    );

    if ($result->{ok}){
        $result = $es->delete_index( index => $database );
    }
    
    $result = $es->create_index(
        index => $database,
        mappings => {
            title => {
                properties => {
                    listitem => {
                        type => 'object',
                        enabled => 'false',
                    },

                    id => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    personid => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    corporatebodyid => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    classificationid => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    subjectid => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    subid => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    freesearch => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    title => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    person => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    corporatebody => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    classification => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    subject => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },

                    database => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },

                    facet_database => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_person => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_corporatebody => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_classification => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_subject => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_year => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_tag => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_litlist => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_language => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    facet_mediatype => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },

                    personstring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    corporatebodystring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    classificationstring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    subjectstring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    yearstring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    tagstring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    litliststring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    languagestring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    mediatypestring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    markstring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    dbstring => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    
                    mark => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    tag => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    listlist => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    source => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    language => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    content => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    mediatype => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    t4100 => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    t4100 => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    t4100 => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    t4100 => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    sort_person => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    sort_title => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    sort_order => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    sort_year => {
                        type => 'integer',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    sort_publisher => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    sort_mark => {
                        type => 'string',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    sort_popularity => {
                        type => 'integer',
                        index => 'not_analyzed', # analyzed | not_analyzed | no
                        #analyze => 'default',
                    },
                    
                },
            },
        },
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

            my $title_listitem_ref = decode_json $listitem;

            $searchcontent_ref->{listitem} = $title_listitem_ref;
            
            my $sorting_ref = [
                {
                    # Verfasser/Koepeschaft
                    id         => $config->{elasticsearch_sorttype_value}{'person'},
                    category   => 'PC0001',
                    type       => 'stringcategory',
                },
                {
                    # Titel
                    id         => $config->{elasticsearch_sorttype_value}{'title'},
                    category   => 'T0331',
                    type       => 'stringcategory',
                },
                {
                    # Zaehlung
                    id         => $config->{elasticsearch_sorttype_value}{'order'},
                    category   => 'T5100',
                    type       => 'integercategory',
                },
                {
                    # Jahr
                    id         => $config->{elasticsearch_sorttype_value}{'year'},
                    category   => 'T0425',
                    type       => 'integercategory',
                },
                {
                    # Verlag
                    id         => $config->{elasticsearch_sorttype_value}{'publisher'},
                    category   => 'T0412',
                    type       => 'stringcategory',
                    },
                {
                    # Signatur
                    id         => $config->{elasticsearch_sorttype_value}{'mark'},
                        category   => 'X0014',
                    type       => 'stringcategory',
                },
                {
                    # Popularitaet
                    id         => $config->{elasticsearch_sorttype_value}{'popularity'},
                    category   => 'popularity',
                    type       => 'integervalue',
                },
                
            ];

            foreach my $this_sorting_ref (@{$sorting_ref}){
                
                if ($this_sorting_ref->{type} eq "stringcategory"){
                    my $content = (exists $title_listitem_ref->{$this_sorting_ref->{category}}[0]{content})?$title_listitem_ref->{$this_sorting_ref->{category}}[0]{content}:"";
                    next unless ($content);
                    
                    $content = OpenBib::Common::Util::grundform({
                        content   => $content,
                    });
                    
                    if ($content){
                        $logger->debug("Adding $content as sortvalue");                        
                        $searchcontent_ref->{$this_sorting_ref->{id}} = $content;
                    }
                }
                elsif ($this_sorting_ref->{type} eq "integercategory"){
                    my $content = 0;
                    if (exists $title_listitem_ref->{$this_sorting_ref->{category}}[0]{content}){
                        ($content) = $title_listitem_ref->{$this_sorting_ref->{category}}[0]{content}=~m/^(\d+)/;
                    }
                    if ($content){
                        $content = sprintf "%08d", $content;
                        $logger->debug("Adding $content as sortvalue");
                        $searchcontent_ref->{$this_sorting_ref->{id}} = $content;
                    }
                }
                elsif ($this_sorting_ref->{type} eq "integervalue"){
                    my $content = 0 ;
                    if (exists $title_listitem_ref->{$this_sorting_ref->{category}}){
                        ($content) = $title_listitem_ref->{$this_sorting_ref->{category}}=~m/^(\d+)/;
                    }
                    if ($content){                    
                        $content = sprintf "%08d",$content;
                        $logger->debug("Adding $content as sortvalue");
                        $searchcontent_ref->{$this_sorting_ref->{id}} = $content;
                    }
                }
            }
            
            $logger->debug(YAML::Dump($searchcontent_ref));

            # ID setzen:

            push @$doc_buffer_ref, {
                id   => $s_id,
                data => $searchcontent_ref,
            };
            
            if ($count % 1000 == 0) {
                # Bulk-Indexieren

                my $result = $es->bulk_index(
                    index       => $database,                   # optional
                    type        => 'title',                     # optional
                    docs        => $doc_buffer_ref,
                    #                    consistency => 'quorum' |  'one' | 'all'    # optional
                    refresh     => 1,
                    #                        refresh     => 0 | 1,                       # optional
                    #                    replication => 'sync' | 'async',            # optional
                );

                print Dump($result);
                
                $result = $es->flush_index( index => $database );
                
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

        # Bulk-Indexieren
        
        my $result = $es->bulk_index(
            index       => $database,                   # optional
            type        => 'title',                     # optional
            docs        => $doc_buffer_ref,
            #                    consistency => 'quorum' |  'one' | 'all'    # optional
            refresh     => 1,
            #                        refresh     => 0 | 1,                       # optional
            #                    replication => 'sync' | 'async',            # optional
        );
        
        print Dump($result);
        
        $result = $es->flush_index( index => $database );
        
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
