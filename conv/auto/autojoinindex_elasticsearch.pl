#!/usr/bin/perl

#####################################################################
#
#  autojoinindex_xapian.pl
#
#  Automatische Verschmelzung von Indizes durch einem neuen Index
#
#  Dieses File ist (C) 2012-2021 Oliver Flimm <flimm@openbib.org>
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

use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Search::Elasticsearch;
use YAML;

use OpenBib::Config;

my ($searchprofileid,$help,$logfile,$loglevel,$onlyauthorities,$onlytitles);

&GetOptions("searchprofileid=s" => \$searchprofileid,
            "only-authorities"  => \$onlyauthorities,
            "only-titles"       => \$onlytitles,
            "logfile=s"         => \$logfile,
            "loglevel=s"        => \$loglevel,
	    "help"              => \$help
	    );

if ($help){
    print_help();
}

$logfile  = ($logfile)?$logfile:'/var/log/openbib/autojoinindex_elasticsearch.log';
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

my $fullatime = new Benchmark;

my $dboverview = $config->get_dbinfo_overview;

my $db_is_not_local_ref = {
};

foreach my $thisdb (@$dboverview){
    if ($thisdb->{system} =~m/Backend/){
	$db_is_not_local_ref->{$thisdb->{dbname}} = 1;
    }
}

my @searchprofiles = ();
if ($searchprofileid && $config->searchprofile_exists($searchprofileid)){
    push @searchprofiles, $searchprofileid;
}
else {
    push @searchprofiles, $config->get_searchprofiles_with_own_index;
}

my $es = Search::Elasticsearch->new(
	    userinfo   => $config->{elasticsearch}{userinfo},
#	    cxn_pool   => $config->{elasticsearch}{cxn_pool},    # default 'Sniff'
	    nodes      => $config->{elasticsearch}{nodes},       # default '127.0.0.1:9200'
    );

# Bestehende Profile entfernen
{
    $logger->info("Entfernung bestehender Profile");
    
    my $all_indices_ref = $es->indices->stats({index => '_all'});

    foreach my $indexname (keys %{$all_indices_ref->{indices}}){
	if ($indexname =~m/^searchprofile_\d+_authority$/){
	    my ($thisprofileid) = $indexname =~m/searchprofile_(\d+)_authority$/;
	    if ($searchprofileid && $thisprofileid ne $searchprofileid ){
		next;
	    }

	    if (!$onlytitles){
		$logger->info("Authority Profil $indexname entfernt");

		$es->indices->delete( 'index' => $indexname );
	    }		    
	}
	elsif ($indexname =~m/^searchprofile_\d+$/){
	    my ($thisprofileid) = $indexname =~m/searchprofile_(\d+)$/;
	    if ($searchprofileid && $thisprofileid ne $searchprofileid ){
		next;
	    }

	    if (!$onlyauthorities){
		$logger->info("Profil $indexname entfernt");

		$es->indices->delete( 'index' => $indexname );
	    }
	}
	    
    }
}

foreach my $searchprofile (@searchprofiles){
    $logger->fatal("Bearbeite Suchprofil $searchprofile");

    my $atime = new Benchmark;

    my @databases = $config->get_databases_of_searchprofile($searchprofile);

    # Herausfiltern der externen Datenbanken

    @databases = grep { !$db_is_not_local_ref->{$_} } @databases;
    
    # Check, welche Indizes irregulaer sind

    my @existing_databases = ();
    
    my $sane_index = 1;
    my $sane_authority_index = 1;
    foreach my $indexname (@databases){

	if (!$es->indices->exists( index => $indexname )){
	    if ($indexname =~m/authority/){
		$sane_authority_index = 0;
	    }
	    else {
		$sane_index = 0;
	    }
	}
	else {
	    push @existing_databases, $indexname;
	}
    }

    # Todo: Implementation von authority_indizes mit Elasticsearch, daher
    $sane_authority_index = 1;
    
    if (!$sane_index || !$sane_authority_index){
        $logger->info("Mindestens ein Index korrupt");
	$logger->info("Verwende existierende Indizes");
    }
    
    my @authoritydatabases    = @existing_databases;
    @authoritydatabases       = map { $_.="_authority" } @authoritydatabases;

    # Todo: Erst temporaeren Index erzeugen und dann umbenennen
    
    my $joinedindex             = "searchprofile_$searchprofile";
    my $joinedauthorityindex    = "searchprofile_${searchprofile}_authority";

    if (!$onlyauthorities){
        $logger->info("### Merging indices to index $joinedindex");

	my $result_ref = $es->reindex(
	    wait_for_completion => 0,
	    
	    body => {
		source  => {
		    index       => \@existing_databases,
		},
		
		dest => {
		    index       => $joinedindex
		}
	    }
	    );

	if ($result_ref->{'task'}){

	  RUNNINGTASK: while (my $response = $es->tasks->get( task_id => $result_ref->{'task'} )){

	      last RUNNINGTASK if ($response->{completed});
	      
	      sleep 20;

	      $logger->info($response->{task}{status}{created}." Titel bearbeitet") if ($response->{task}{status}{created});
		
	    }
		  
	    $logger->info(YAML::Dump($es->tasks->get( task_id => $result_ref->{'task'} )));
	    
	}	
    }
    
    
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info("### Suchprofil $searchprofile: Gesamte Zeit -> $resulttime");

}


my $fullbtime      = new Benchmark;
my $fulltimeall    = timediff($fullbtime,$fullatime);
my $fullresulttime = timestr($fulltimeall,"nop");
$fullresulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("### Gesamtezeit alle Indize-> $fullresulttime");

sub print_help {
    print << "ENDHELP";
autojoinindex_elasticsearch.pl - Automatische Verschmelzung von Elasticsearch-Indizes fuer Suchprofile

   Optionen:
   -help                 : Diese Informationsseite
       
   --searchprofileid=... : Angegebne Suchprofil-ID verwenden (ansonsten fuer alle Kataloge die own_index=true in Admin haben)
   -only-title           : Nur Titel-Indizes verschmelzen
   -only-authority       : Nur Authority-Indizes verschmelzen
ENDHELP
    exit;
}

