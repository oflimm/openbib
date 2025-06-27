#!/usr/bin/perl
#####################################################################
#
#  admin_ctl.pl
#
#  Helper for OpenBib Admin
#
#  Dieses File ist (C) 2023 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use JSON::XS qw/encode_json decode_json/;
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Config;
use OpenBib::User;

our ($do,$scope,$view,$id,$db,$loc,$help,$loglevel,$logfile);

&GetOptions("do=s"            => \$do,

	    "scope=s"         => \$scope,
	    "view=s"          => \$view,
	    "db=s"            => \$db,
	    "id=s"            => \$id,	    
	    "loc=s"           => \$loc,	    
	    
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
	    "help"            => \$help
	    );

if ($help || !$do || !$scope){
    print_help();
}

$logfile=($logfile)?$logfile:'./admin_ctl.log';
$loglevel=($loglevel)?$loglevel:'ERROR';


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

$do = $scope."_".$do;

if (defined &{$do}){
    no strict 'refs';
    &{$do};
}
else {
    $logger->error("Action $do not supported");
    exit;
}

sub view_add_db {

    my $config = new OpenBib::Config;

    if (!$view || !$db){
	$logger->error("Missing args db or view");
	exit;
    }

    $logger->info("Adding DB $db to view $view");       

    unless ($config->view_exists($view)){
	$logger->error("View $view doesn't exist");
	exit;
    }

    unless ($config->db_exists($db)){
	$logger->error("DB $db doesn't exist");
	exit;
    }

    my $profile = $config->get_profilename_of_view($view);

    my @profiledbs = $config->get_profiledbs($profile);

    unless (grep($db,@profiledbs)){
	$logger->error("DB $db doesn't exist in correpsonding profile $profile");
	exit;
    }
    
    # 1) DB bereits in View enthalten? Dann exit mit Meldung

    my @viewdbs = $config->get_viewdbs($view);

    if (grep(/$db/,@viewdbs)){
	$logger->error("DB $db already in view $view");
	exit;
    }
    
    # 2) Hinzufuegen der DB

    eval {
	my $viewid = $config->get_viewinfo->single({ viewname => $view })->id;
	
	$config->get_schema->resultset('ViewDb')->search_rs({ viewid => $viewid})->delete;
	
	push @viewdbs, $db;
	
	my $this_db_ref = [];
	foreach my $dbname (@viewdbs){
	    my $dbid = $config->get_databaseinfo->single({ dbname => $dbname })->id;
	    
	    push @$this_db_ref, {
		viewid => $viewid,
		dbid   => $dbid,
	    };
	}
	
	# Dann die zugehoerigen Datenbanken eintragen
	$config->get_schema->resultset('ViewDb')->populate($this_db_ref);
    };

    # Flushen und aktualisieren in Memcached
    if (defined $config->{memc}){
        $config->memc_cleanup_viewinfo($view);
    }    
}

sub view_delete_db {

    my $config = new OpenBib::Config;

    if (!$view || !$db){
	$logger->error("Missing args db or view");
	exit;
    }

    $logger->info("Removing DB $db from view $view");       

    unless ($config->view_exists($view)){
	$logger->error("View $view doesn't exist");
	exit;
    }
    
    # 1) DB nicht in View enthalten? Dann exit mit Meldung

    my @viewdbs = $config->get_viewdbs($view);

    unless (grep($db,@viewdbs)){
	$logger->error("DB $db not in view $view");
	exit;
    }
    
    # 2) Entfernen der DB

    eval {
	my $viewid = $config->get_viewinfo->single({ viewname => $view })->id;
	
	$config->get_schema->resultset('ViewDb')->search_rs({ viewid => $viewid})->delete;
	
	@viewdbs = grep (!/$db/,@viewdbs);
	
	my $this_db_ref = [];
	foreach my $dbname (@viewdbs){
	    my $dbid = $config->get_databaseinfo->single({ dbname => $dbname })->id;
	    
	    push @$this_db_ref, {
		viewid => $viewid,
		dbid   => $dbid,
	    };
	}
	
	# Dann die zugehoerigen Datenbanken eintragen
	$config->get_schema->resultset('ViewDb')->populate($this_db_ref);
    };

    # Flushen und aktualisieren in Memcached
    if (defined $config->{memc}){
        $config->memc_cleanup_viewinfo($view);
    }
    
}

sub view_list_db {

    my $config = new OpenBib::Config;
    
    if (!$view){
	$logger->error("Missing arg view");
	exit;
    }

    unless ($config->view_exists($view)){
	$logger->error("View $view doesn't exist");
	exit;
    }
    
    my @viewdbs = $config->get_viewdbs($view);

    foreach my $dbname (@viewdbs){
	print $dbname,"\n";
    }
}

sub view_add_loc {

    my $config = new OpenBib::Config;

    if (!$view || !$loc){
	$logger->error("Missing args db or loc");
	exit;
    }

    $logger->info("Adding location $loc to view $view");       

    unless ($config->view_exists($view)){
	$logger->error("View $view doesn't exist");
	exit;
    }

    unless ($config->location_exists($loc)){
	$logger->error("Location $loc doesn't exist");
	exit;
    }

    my @viewlocations = $config->get_viewlocations($view);

    if (grep(/$loc/,@viewlocations)){
	$logger->error("Location $loc already in view $view");
	exit;
    }
    
    eval {
	my $viewid = $config->get_viewinfo->single({ viewname => $view })->id;

	$config->get_schema->resultset('ViewLocation')->search_rs({ viewid => $viewid})->delete;
	
	push @viewlocations, $loc;

        my $this_location_ref = [];
        foreach my $location (@viewlocations){
            my $locationid = $config->get_locationinfo->single({ identifier => $location })->id;
                
            push @$this_location_ref, {
                viewid     => $viewid,
                locationid => $locationid,
            };
        }

	$logger->debug(YAML::Dump($this_location_ref));
        
        # Dann die zugehoerigen Datenbanken eintragen
        $config->get_schema->resultset('ViewLocation')->populate($this_location_ref);
    };

    # Flushen und aktualisieren in Memcached
    if (defined $config->{memc}){
        $config->memc_cleanup_viewinfo($view);
    }
}

sub view_delete_loc {

    my $config = new OpenBib::Config;

    if (!$view || !$loc){
	$logger->error("Missing args loc or view");
	exit;
    }

    $logger->info("Removing location $loc from view $view");       

    unless ($config->view_exists($view)){
	$logger->error("View $view doesn't exist");
	exit;
    }

    my @viewlocations = $config->get_viewlocations($view);

    unless (grep(/$loc/,@viewlocations)){
	$logger->error("Location $loc not in view $view");
	exit;
    }

    eval {
	my $viewid = $config->get_viewinfo->single({ viewname => $view })->id;

	$config->get_schema->resultset('ViewLocation')->search_rs({ viewid => $viewid})->delete;

	@viewlocations = grep (!/$loc/,@viewlocations);

        my $this_location_ref = [];
        foreach my $location (@viewlocations){
            my $locationid = $config->get_locationinfo->single({ identifier => $location })->id;
                
            push @$this_location_ref, {
                viewid     => $viewid,
                locationid => $locationid,
            };
        }

	$logger->debug(YAML::Dump($this_location_ref));
        
        # Dann die zugehoerigen Datenbanken eintragen
        $config->get_schema->resultset('ViewLocation')->populate($this_location_ref);
    };

    # Flushen und aktualisieren in Memcached
    if (defined $config->{memc}){
        $config->memc_cleanup_viewinfo($view);
    }
    
}

sub view_list_loc {

    my $config = new OpenBib::Config;
    
    if (!$view){
	$logger->error("Missing arg view");
	exit;
    }

    unless ($config->view_exists($view)){
	$logger->error("View $view doesn't exist");
	exit;
    }
    
    my @viewlocations = $config->get_viewlocations($view);

    foreach my $location (@viewlocations){
	print $location,"\n";
    }
}


sub view_list {

    my $config = new OpenBib::Config;

    my $viewinfo_overview_ref = $config->get_viewinfo_overview;

    foreach my $info_ref (@$viewinfo_overview_ref){
	print $info_ref->{viewname},"\n";
    }
}

sub view_listinfo {

    my $config = new OpenBib::Config;

    my $viewinfo_overview_ref = $config->get_viewinfo_overview;

    print YAML::Dump($viewinfo_overview_ref),"\n";

}

sub database_delete {

    my $config = new OpenBib::Config;

    if (!$db){
	$logger->error("Missing arg db");
	exit;
    }

    my $result = $config->del_databaseinfo($db);

}

sub cluster_check_consistency {

    if (!$id){
	$logger->error("Missing arg (cluster)id");
	exit;
    }

    $logger->info("Checking consistency of CLUSTER $id");       

    my $config = new OpenBib::Config;

    my $servers_ref = {};

    my $serverids_ref = $config->get_serverids_of_cluster($id);

    foreach my $serverid (@$serverids_ref){
	$servers_ref->{$serverid} = $config->get_serverinfo_description($serverid);
    }

    my $differences_ref = $config->check_cluster_consistency($id);

    foreach my $db_ref (@$differences_ref){
	my @output = ();
	foreach my $serverid (sort keys %{$db_ref->{server}}){
	    push @output, $servers_ref->{$serverid}." (".$db_ref->{server}{$serverid}.")";
	}

	print $db_ref->{dbname}.": ", join(' - ',@output),"\n" if (@output);

    }
    

}

sub user_delete_account {

    if (!$id){
	$logger->error("Missing arg numeric (user)id");
	exit;
    }

    $logger->info("Deleting account for userid $id");       

    my $user   = new OpenBib::User;

    $user->wipe_account($id);
}


sub print_help {
    print << "ENDHELP";
admin_ctl.pl - Helper for OpenBib Admin

Generel Options:
   -help                 : This info
   --logfile=...         : logfile (default: ./es_ctl.log)
   --loglevel=...        : loglevel (default: INFO)

List views
   --scope=view
   --do=list

List information on all views (YAML)
   --scope=view
   --do=listinfo

List databases of view
   --scope=view
   --do=list_db
   --viewe=...           : View name

Add database to view
   --scope=view
   --do=add_db
   --db=...              : Database name
   --viewe=...           : View name

Delete database in view
   --scope=view
   --do=delete_db
   --db=...              : Database name
   --viewe=...           : View name

List locations of view
   --scope=view
   --do=list_loc
   --view=...           : View name

Add location to view
   --scope=view
   --do=add_loc
   --loc=...            : Location
   --view=...           : View name

Delete location in view
   --scope=view
   --do=delete_loc
   --loc=...            : Location
   --view=...           : View name

Delete database
   --scope=database
   --do=delete
   --db=...             : Database name

Check consistency of DBs-counts in Cluster
   --scope=cluster
   --do=check_consistency
   --id=...              : Cluster id

Delete Useraccount by id
   --scope=user
   --do=delete_account
   --id=...              : Cluster id

e.g:

./admin_ctl.pl --scope=view --do=list --view=unikatalog

./admin_ctl.pl --scope=view --do=listinfo --view=unikatalog

./admin_ctl.pl --scope=view --do=list_db --view=unikatalog

./admin_ctl.pl --scope=view --do=add_db --view=unikatalog --db=inst123

./admin_ctl.pl --scope=view --do=delete_db --view=unikatalog --db=inst123

./admin_ctl.pl --scope=view --do=list_loc --view=unikatalog

./admin_ctl.pl --scope=view --do=add_loc --view=unikatalog --loc=DE-38-123

./admin_ctl.pl --scope=view --do=delete_loc --view=unikatalog --loc=DE-38-123

./admin_ctl.pl --scope=cluster --do=check_consistency --id=1

./admin_ctl.pl --scope=user --do=delete_account --id=1

ENDHELP
    exit;
}

