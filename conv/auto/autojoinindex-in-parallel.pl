#!/usr/bin/perl

#####################################################################
#
#  autojoinindex-in-parallel.pl
#
#  Paralleles Verschmelzen von Suchindizes in verschiedenen Suchmaschinen
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@openbib.org>
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

my ($help,@sb,$logfile,$loglevel);

&GetOptions(
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
	    "search-backend=s@" => \@sb,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile  = ($logfile)?$logfile:"/var/log/openbib/autojoinindex-in-parallel.log";
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

# Zu nutzende lokale Suchmaschinen-Backends bestimmen
{
    if (@sb){
	foreach my $backend (@sb){
	    $use_searchengine_ref->{$backend} = 1;
	}
    }

}

my $num_parts = keys %$use_searchengine_ref;

if ($num_parts < 1){
    $logger->error("No searchengines defined");
    exit;
}

my $pm = Parallel::ForkManager->new( $num_parts );

INDEX_PART:
    
    foreach my $searchengine (keys %$use_searchengine_ref){
	$pm->start and next INDEX_PART; # do the fork
	
	# Xapian	    
	if ($searchengine eq "xapian"){		
	    $logger->info("### Joining indexes in Xapian searchengine");
	    
	    my $cmd = "$rootdir/bin/autojoinindex_xapian.pl";
	    
	    $logger->info("Executing: $cmd");
	    
	    system($cmd);
	}
	
	# Elasticsearch
	if ($searchengine eq "elasticsearch"){
	    $logger->info("### Joining indexes in ElasticSearch searchengine");
	    
	    my $cmd = "$rootdir/bin/autojoinindex_elasticsearch.pl";
	    
	    $logger->info("Executing: $cmd");
	    
	    system($cmd);
	}
	
	# SOLR
	if ($searchengine eq "solr"){
	    $logger->info("### Joining indexes in Solr searchengine");
	    $logger->info("### Solr currently not supported");
	    
#	    my $cmd = "$rootdir/bin/autojoinindex_solr.pl";
	    
#	    $logger->info("Executing: $cmd");
	    
#	    system($cmd);
	}
	$pm->finish; # do the exit in the child process		
}

$pm->wait_all_children;

sub print_help {
    print << "ENDHELP";
autojoinindex-in-parallel.pl - Paralleles Mergen von Indizes in mehreren Suchmaschinen-Backends

   Optionen:
   -help                 : Diese Informationsseite
       
   --loglevel=[DEBUG|..] : Loglevel aendern
   --logfile=...         : Logdateinamen aendern
   --search-backend=...  : Angabe mehrerer Suchmaschinen, in denen Indexiert werden soll

ENDHELP
    exit;
}
