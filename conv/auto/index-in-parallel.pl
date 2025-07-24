#!/usr/bin/perl

#####################################################################
#
#  index-in-parallel.pl
#
#  Parallele Indexierung in verschiedenen Suchmaschinen
#
#  Dieses File ist (C) 2021-2023 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Parallel::ForkManager;

use OpenBib::Config;

my ($database,$indexname,$xapianindexname,$elasticsearchindexname,$help,@sb,$logfile,$loglevel,$incremental,$authority);

&GetOptions("database=s"      => \$database,
	    "indexname=s"     => \$indexname,
	    "xapian-indexname=s"     => \$xapianindexname,
	    "es-indexname=s"         => \$elasticsearchindexname,
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
            "incremental"     => \$incremental,
            "authority"       => \$authority,
	    "search-backend=s@" => \@sb,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

if (!-d "/var/log/openbib/index-in-parallel"){
    mkdir "/var/log/openbib/index-in-parallel";
}

if ($indexname && !$xapianindexname && !$elasticsearchindexname){
    $xapianindexname        = $indexname;
    $elasticsearchindexname = $indexname;
}

$logfile  = ($logfile)?$logfile:"/var/log/openbib/index-in-parallel/${database}.log";
$loglevel = ($loglevel)?$loglevel:"INFO";

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

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $tooldir       = $config->{'tool_dir'};

my $use_searchengine_ref = {};

my $xapian_cmd = "$config->{'base_dir'}/conv/file2xapian.pl";
my $es_cmd     = "$config->{'base_dir'}/conv/file2elasticsearch.pl";

if ($authority){
    $logger->info("### $database: Building authority index");
    $xapian_cmd = "$config->{'base_dir'}/conv/authority2xapian.pl";
    $es_cmd     = "$config->{'base_dir'}/conv/authority2elasticsearch.pl";

    $logger->info("### $database: Unpacking authority files");    
    my $cmd = "cd $rootdir/data/$database/ ; $xapian_cmd --loglevel=$loglevel -unpack-only --database=$database";

    $logger->info("Executing: $cmd");
    
    system($cmd);        
}
else {
    $logger->info("### $database: Building catalog index");
}

# Zu nutzende lokale Suchmaschinen-Backends bestimmen
{
    if (@sb){
	foreach my $backend (@sb){
	    $use_searchengine_ref->{$backend} = 1;
	}
    }
    else {
	foreach my $searchengine (@{$config->get_searchengines_of_db($database)}){
	    $use_searchengine_ref->{$searchengine} = 1;
	}
    }

}

my $num_parts = keys %$use_searchengine_ref;

my $pm = Parallel::ForkManager->new( $num_parts );

INDEX_PART:
    
    foreach my $searchengine (keys %$use_searchengine_ref){
	$pm->start and next INDEX_PART; # do the fork
	
	# Xapian	    
	if ($searchengine eq "xapian"){		
#	    my $indexpath    = $config->{xapian_index_base_path}."/$database";
	    my $indexpathtmp = $config->{xapian_index_base_path}."/$xapianindexname";
	    $logger->info("### $database: Importing data into Xapian searchengine");
	    
	    my $cmd = "cd $rootdir/data/$database/ ; $xapian_cmd --loglevel=$loglevel -with-sorting -with-positions --database=$xapianindexname --indexpath=$indexpathtmp";
	    if ($authority){
		$cmd = "cd $rootdir/data/$database/ ; $xapian_cmd --loglevel=$loglevel -with-sorting -with-positions -without-unpack --database=$database --indexpath=$indexpathtmp";
	    }
	    
	    if ($incremental){
		$cmd.=" -incremental --deletefile=$rootdir/data/$database/title.delete";
	    }
	    
	    $logger->info("Executing: $cmd");
	    
	    system($cmd);
	}
	
	# Elasticsearch
	if ($searchengine eq "elasticsearch"){
	    $logger->info("### $database: Importing data into ElasticSearch searchengine");
	    
	    my $cmd = "cd $rootdir/data/$database/ ; $es_cmd --database=$database";

	    if ($authority){
		$cmd = "cd $rootdir/data/$database/ ; $es_cmd --loglevel=$loglevel --database=$database -without-unpack";
	    }
	    
	    if ($incremental){
		$cmd.=" --indexname=$elasticsearchindexname -incremental --deletefile=$rootdir/data/$database/title.delete";
	    }
	    else {
		$cmd.=" --indexname=$elasticsearchindexname";
	    }
	    	    
	    $logger->info("Executing: $cmd");
	    
	    system($cmd);
	}
	
	# SOLR
	if ($searchengine eq "solr"){
	    $logger->info("### $database: Importing data into Solr searchengine");
	    
	    my $cmd = "cd $rootdir/data/$database/ ; $config->{'base_dir'}/conv/file2solr.pl --loglevel=$loglevel --database=$database -without-unpack";
	    
	    $logger->info("Executing: $cmd");
	    
	    system($cmd);
	}
	$pm->finish; # do the exit in the child process		
}

$pm->wait_all_children;

sub print_help {
    print << "ENDHELP";
index-in-parallel.pl - Parallele Indexierung in mehreren Suchmaschinen-Backends

   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Angegebenen Katalog verwenden
   --indexname=...       : Standard Name des Index fuer Xapian und Elasticsearch
   --xapian-indexname=...: Name des Xapian Index
   --es-indexname=...    : Name des Elasticsearch Index
   --loglevel=[DEBUG|..] : Loglevel aendern
   --logfile=...         : Logdateinamen aendern
   --search-backend=...  : Angabe mehrerer Suchmaschinen, in denen Indexiert werden soll

   -authority            : Normdatenindizes erzeugen

ENDHELP
    exit;
}
