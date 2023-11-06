#!/usr/bin/perl
#####################################################################
#
#  gen_locations_by_view.pl
#
#  Bestimmung der verfuegbaren Standorte pro View
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';
use utf8;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use Unicode::Collate;
use YAML;

use OpenBib::Config;
use OpenBib::Catalog;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::System;
use OpenBib::Statistics;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::User;

my ($view,$help,$logfile);

&GetOptions(
            "view=s"          => \$view,
            "logfile=s"       => \$logfile,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/locations_by_view.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

my $config     = OpenBib::Config->new;
my $statistics = OpenBib::Statistics->instance;

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh = DBI->connect("DBI:Pg:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd},{'pg_enable_utf8'    => 1})
    or $logger->error($DBI::errstr);


# Typ 15 => Standorte pro View
my @views = ();

if ($view){
    push @views, $view;
}
else {
    @views=$config->get_active_views();
}

my $db_cache_ref = {};

foreach my $view (@views){
    $logger->info("Generating Type 15 locations for view $view");
    
    my @databases = $config->get_dbs_of_view($view);

    my $locations_ref = {};
    
    foreach my $database (@databases){

	# Ggf. schon bestimmte Standorte der Datenbanken aus dem Cache holen
	if (defined $db_cache_ref->{$database}){
	    $logger->info("Getting locations for db $database from cache");
	    foreach my $loc (keys %{$db_cache_ref->{$database}}){
		$locations_ref->{$loc} = 1;
	    }
	    next;
	}
	
	# Verbindung zur SQL-Datenbank herstellen
	eval {
	    $logger->info("Getting locations for db $database from database");
	my $catalogdbh
	    = DBI->connect("DBI:Pg:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
	    or $logger->error_die($DBI::errstr);
	
    
	my $sqlstring="select distinct(content) from title_fields where field = 4230;";
	
	$logger->debug("$sqlstring");
	my $request=$catalogdbh->prepare($sqlstring) or $logger->error($DBI::errstr);
	$request->execute();
	
	while (my $result=$request->fetchrow_hashref){
	    my $location      = $result->{content};
	    $locations_ref->{$location} = 1;
	}

	# Cachen
	$db_cache_ref->{$database} = $locations_ref;
	
	};

	if ($@){
	    $logger->error("Problem mit Datenbank $database: ".$@);
	}
    }
    
    my @locations = keys %$locations_ref;

    if ($logger->is_debug){
	$logger->debug(YAML::Dump(\@locations));
    }
    
    $config->set_datacache({
	type => 15,
	id   => $view,
	data => \@locations,
			    });
}


sub print_help {
    print << "ENDHELP";
gen_locations_by_view.pl - Bestimmung der vorhandenen Standorte pro View

   Optionen:
   -help                 : Diese Informationsseite
   --view=...            : Name eines Views (sonst automatisch alle Views)
   --logfile=...         : Alternatives Logfile

   Typ:

  15 => Vorhandene Standorte pro View       
ENDHELP
    exit;
}

