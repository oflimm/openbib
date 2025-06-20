#!/usr/bin/perl

#####################################################################
#
#  authority2elasticsearch.pl
#
#  Basis: authority2xapian.pl
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
use DBI;
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

my ($database,$help,$logfile,$withsorting,$withpositions,$loglevel,$indexname,$withalias,$authtype);

&GetOptions(
    "database=s"       => \$database,
    "indexname=s"      => \$indexname,
    "with-alias"       => \$withalias,
    "authority-type=s" => \$authtype,
    "logfile=s"        => \$logfile,
    "loglevel=s"       => \$loglevel,
    "with-sorting"     => \$withsorting,
    "with-positions"   => \$withpositions,
    "help"             => \$help
);

if ($help){
    print_help();
}

if (!-d "/var/log/openbib/authority2elasticsearch/"){
    mkdir "/var/log/openbib/authority2elasticsearch/";
}

$logfile=($logfile)?$logfile:"/var/log/openbib/authority2elasticsearch/${database}.log";
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

my $config  = new OpenBib::Config();
my $rootdir = $config->{'autoconv_dir'};

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

$indexname=($indexname)?$indexname:"${database}_authority";

my @authority_files = (
    {
        type     => "person",
        filename => "$rootdir/pools/$database/meta.person.gz",
    },
    {
        type     => "corporatebody",
        filename => "$rootdir/pools/$database/meta.corporatebody.gz",
    },
    {
        type     => "subject",
        filename => "$rootdir/pools/$database/meta.subject.gz",
    },
    {
        type     => "title",
        filename => "$rootdir/pools/$database/meta.title.gz",
    },
    # {
    #     type     => "holding",
    #     filename => "$rootdir/pools/$database/meta.holding.gz",
    # }
);

my $conv_config = new OpenBib::Conv::Config({dbname => $database});

$logger->info("### POOL $database: Creating index $indexname");

my $old_indexname;

if ($withalias){
    my $es_indexer = OpenBib::Index::Factory->create_indexer({ sb => 'elasticsearch', database => $database, index_type => 'readwrite' });
    
    $old_indexname = $es_indexer->get_aliased_index("${database}_authority");
    
    $indexname = ($old_indexname eq "${database}_authority_a")?"${database}_authority_b":"${database}_authority_a";

    $logger->info("Indexing with alias");
    $logger->info("Old index for ${database}_authority: $old_indexname");
    $logger->info("New index for ${database}_authority: $indexname");    
}


my $atime = new Benchmark;

my $normalizer = OpenBib::Normalizer->new;

my $indexer = OpenBib::Index::Factory->create_indexer({ database => $database, create_index => 1, index_type => 'readwrite', sb => 'elasticsearch', indexname => $indexname, normalizer => $normalizer });

#$indexer->set_stopper;
#$indexer->set_termgenerator;


if (! -d "$rootdir/data/$database"){
    system("mkdir $rootdir/data/$database");
}

foreach my $authority_file_ref (@authority_files){
    
    my $type            = $authority_file_ref->{type};
    my $source_filename = $authority_file_ref->{filename};
    my $dest_filename   = "authority_meta.$type";

    next if ($authtype && $authtype ne $type);
    
    if (-f $source_filename){
        my $atime = new Benchmark;

        # Entpacken der Pool-Daten in separates Arbeits-Verzeichnis unter 'data'

        $logger->info("### $database: Entpacken der Authority-Daten fuer Typ $type");
                
        #system("rm $rootdir/data/$database/authority_*");
        system("/bin/gzip -dc $source_filename > $rootdir/data/$database/$dest_filename");
        
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $logger->info("### $database: Benoetigte Zeit -> $resulttime");
        
        if ($database && -e "$config->{autoconv_dir}/filter/$database/authority_pre_conv_$type.pl"){
            $logger->info("### $database: Verwende Plugin authority_pre_conv_$type.pl");
            system("$config->{autoconv_dir}/filter/$database/authority_pre_conv_$type.pl $database");
        }
        
        $logger->info("### POOL $database - ".$type);
        
        my $fieldprefix = ($authority_file_ref->{type} eq "person")?"P":
            ($authority_file_ref->{type} eq "subject")?"S":
	    ($authority_file_ref->{type} eq "corporatebody")?"C":
	    ($authority_file_ref->{type} eq "title")?"T":
	    ($authority_file_ref->{type} eq "holding")?"X":"";
        next unless ($fieldprefix);
        
        open(SEARCHENGINE,"cat $rootdir/data/$database/$dest_filename |" ) || die "$rootdir/data/$database/$dest_filename konnte nicht geoeffnet werden";
        
        {
            $logger->info("Aufbau eines neuen temporaeren Index fuer Datenbank $database");
            
            
            $logger->info("Migration der Normdaten");
            
            my $count = 1;
            
            {
                
                my $atime = new Benchmark;
                
                while (my $searchengine=<SEARCHENGINE>) {

                    my $auth_ref = decode_json($searchengine);

                    my $fields_ref = $auth_ref->{fields};
                    
                    # Initialisieren und Basisinformationen setzen
                    my $document = OpenBib::Index::Document->new({ database => $database, id => $auth_ref->{id} });

                    $document->set_data("type",$authority_file_ref->{type});
                    
                    foreach my $field (keys %{$fields_ref}){
                        $document->set_data("$fieldprefix$field",$fields_ref->{$field});

			foreach my $item_ref (@{$fields_ref->{$field}}){
			    # Subfield aus Datensatz, ggf Default '' setzen
			    my $subfield = (defined $item_ref->{subfield})?$item_ref->{subfield}:'';
			    
			    foreach my $searchfield (keys %{$conv_config->{"inverted_authority_".$authority_file_ref->{type}}{$field}{$subfield}->{index}}) {
				my $weight = $conv_config->{"inverted_authority_".$authority_file_ref->{type}}{$field}{$subfield}->{index}{$searchfield};
                            
                                next unless $item_ref->{content};
                                
                                $document->add_index($searchfield,$weight, ["$fieldprefix$field",$item_ref->{content}]);
                            }
                        }
                    }
                    
                    my $doc = $indexer->create_document({ document => $document, with_sorting => $withsorting, with_positions => $withpositions });

                    $indexer->create_record($doc);
                    
                    if ($count % 1000 == 0) {
                        my $btime      = new Benchmark;
                        my $timeall    = timediff($btime,$atime);
                        my $resulttime = timestr($timeall,"nop");
                        $resulttime    =~s/(\d+\.\d+) .*/$1/;
                        $atime         = new Benchmark;
                        $logger->info("$database (ES): $count Saetze indexiert in $resulttime Sekunden");
                    }
                    
                    $count++;
                }
            }
        }

        
        close(SEARCHENGINE);
    }

    
}

if ($withalias){
    # Aliases umswitchen
    $logger->info("Switching alias and dropping old index $old_indexname");
    $indexer->drop_alias($database,$old_indexname);
    $indexer->create_alias($database,$indexname);
    $indexer->drop_index($old_indexname);
}

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

sub print_help {
    print << "ENDHELP";
authority2elasticsearch.pl - Aufbau eines Elasticsearch-Index für die Normdaten

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Integration von einzelnen Suchfeldern (nicht default)
   -with-sorting         : Integration von Sortierungsinformationen (nicht default)
   --database=...        : Angegebenen Datenpool verwenden
   --authority-type=...  : Angegebenen Normdatentyp (person, corporatebody, ...) verwenden

ENDHELP
    exit;
}
