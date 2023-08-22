#!/usr/bin/perl
#####################################################################
#
#  refresh_titlecache.pl
#
#  Aktualisierung des Title-Caches bei Merklisten- und Literaturlisten-
#  eintraegen
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
no warnings 'redefine';
use utf8;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use DBIx::Class::ResultClass::HashRefInflator;
use Getopt::Long;
use Unicode::Collate;
use YAML;

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::User;

my ($type,$username,$from,$to,$listusers,$selectobsolete,$authenticatorid,$viewname,$dryrun,$help,$logfile,$loglevel);

&GetOptions(
    "type=s"          => \$type,
    "select-obsolete" => \$selectobsolete,
    "username=s"      => \$username,
    "from=s"          => \$from,
    "to=s"            => \$to,
    "authenticatorid=s" => \$authenticatorid,
    "viewname=s"      => \$viewname,
    "dry-run"         => \$dryrun,
    "list-users"      => \$listusers,
    "loglevel=s"      => \$loglevel,
    "logfile=s"       => \$logfile,	    
    "help"            => \$help
    );

if ($help){
    print_help();
}

$from            = ($from)?$from:"1970-01-01 00:00:00";
$to              = ($to)?$to:"2100-01-01 00:00:00";
$authenticatorid = ($authenticatorid)?$authenticatorid:1; # Default 1 = USB Ausweis
$logfile         = ($logfile)?$logfile:'/var/log/openbib/usercartitems2fullrecord.log';
$loglevel        = ($loglevel)?$loglevel:'INFO';
$viewname        = ($viewname)?$viewname:'';
$type            = ($type)?$type:'';

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

my $config     = OpenBib::Config->new;
my $user       = new OpenBib::User;
my $dbinfo     = new OpenBib::Config::DatabaseInfoTable;



if (!$type){
    $logger->error("Type ist nicht gesetzt. Bitte geben Sie als --type= entweder cart oder litlist ein.");
    exit;
}

my $userid = 0;

if ($username){
    if (!$user->user_exists($username)){
	$logger->error("NO_USER: $username");
	exit;
    }
    
    $userid = $user->get_userid_for_username($username,$viewname);

    $logger->info("userid is $userid for username $username");
}


if ($type eq "litlist"){
    # Persistente Cartitems von Nutzern bestimmen

    my $where_ref = {
	-and => [
	     'litlistitems.tstamp' => { '>=' => $from },
	     'litlistitems.tstamp' => { '<=' => $to },
	    ],
	    
	    'userid.authenticatorid' => $authenticatorid,
    };

    if ($userid){
	$where_ref->{'userid.username'} = $username;
    }

    # Obsolete Titlecaches im Kurzformat besitzen das Feld PC0001
    if ($selectobsolete){
	$where_ref->{'litlistitems.titlecache'} = {'~' => 'PC0001'};
    }
    
    if ($viewname){

	if (!$config->view_exists($viewname)){
	    $logger->error("View $viewname existiert nicht");
	    exit;
	}
	
	my $viewid;

	eval {
	    $viewid = $config->get_viewinfo->single({ viewname => $viewname })->id;
	};

	if ($@){
	    $logger->error($@);
	    exit;
	}
	
	$where_ref->{'userid.viewid'} = $viewid;
    }

    $logger->debug("Where: ".YAML::Dump($where_ref));

    if ($listusers){
	my $litlistitems = $user->get_schema->resultset('Litlist')->search_rs(
	    $where_ref,
	    {
		select  => ['userid.username'],
		as       => ['thisusername'],
		group_by => ['userid.username'],
		order_by => ['userid.username ASC'],	
		join     => ['userid','litlistitems'],
		result_class => 'DBIx::Class::ResultClass::HashRefInflator',
	    }
	    );

	while (my $thisuser = $litlistitems->next()){
	    print $thisuser->{thisusername},"\n";
	}
	exit;
    }

    my $userlitlistitems = $user->get_schema->resultset('Litlist')->search_rs(
	$where_ref,
	{
	    columns  => ['litlistitems.id'],
	    group_by => ['litlistitems.id'],	
	    join     => ['userid','litlistitems'],
	}
	);

    my $litlistitems = $user->get_schema->resultset('Litlistitem')->search_rs(
	{
	    id => { -in => $userlitlistitems->as_query },
	}
	);

    my $litlistitems_count = $litlistitems->count;

    $logger->info("$litlistitems_count litlistitems found");

    while (my $thislitlistitem = $litlistitems->next()){
	my $id      = $thislitlistitem->get_column('id');    
	my $titleid = $thislitlistitem->get_column('titleid');
	my $dbname  = $thislitlistitem->get_column('dbname');

	if ($dbname=~m/^(eds|dbis|ezb)$/){
	    $logger->info("ID $titleid in DB $dbname ignored");
	    next;
	}

	if (!$config->db_exists($dbname)){
	    $logger->error("NO_DB: $dbname");
	    next;
	}
	
	my $record = new OpenBib::Record::Title({ database => $dbname , id => $titleid, config => $config })->load_full_record;

	if ($record->record_exists){
	    
	    my $record_json = $record->to_json;

	    if ($dryrun){
		$logger->info("Would try to update id $id ($dbname/$titleid) with content $record_json");
	    }
	    else {
		$thislitlistitem->update({
		    titlecache => $record_json	    
				      });
	    }
	}
	else {
	    $logger->error("Litlistitemid $id: DB: $dbname - TITLEID: $titleid existiert nicht!");
	}
    }
}
elsif ($type eq "cart"){
    # Persistente Cartitems von Nutzern bestimmen

    my $where_ref = {
	-and => [
	     'cartitemid.tstamp' => { '>=' => $from },
	     'cartitemid.tstamp' => { '<=' => $to },
	    ],
	    
	    'userid.authenticatorid' => $authenticatorid,
    };

    if ($userid){
	$where_ref->{'userid.username'} = $username;
    }

    # Obsolete Titlecaches im Kurzformat besitzen das Feld PC0001
    if ($selectobsolete){
	$where_ref->{'cartitems.titlecache'} = {'~' => 'PC0001'};
    }
    
    if ($viewname){

	if (!$config->view_exists($viewname)){
	    $logger->error("View $viewname existiert nicht");
	    exit;
	}
	
	my $viewid;

	eval {
	    $viewid = $config->get_viewinfo->single({ viewname => $viewname })->id;
	};

	if ($@){
	    $logger->error($@);
	    exit;
	}
	
	$where_ref->{'userid.viewid'} = $viewid;
    }

    $logger->debug("Where: ".YAML::Dump($where_ref));

    if ($listusers){
	my $usercartitems = $user->get_schema->resultset('UserCartitem')->search_rs(
	    $where_ref,
	    {
		select  => ['userid.username'],
		as       => ['thisusername'],
		group_by => ['userid.username'],
		order_by => ['userid.username ASC'],	
		join     => ['userid','cartitemid'],
		result_class => 'DBIx::Class::ResultClass::HashRefInflator',
	    }
	    );

	while (my $thisuser = $usercartitems->next()){
	    print $thisuser->{thisusername},"\n";
	}
	exit;
    }

    my $usercartitems = $user->get_schema->resultset('UserCartitem')->search_rs(
	$where_ref,
	{
	    columns  => ['cartitemid.id'],
	    group_by => ['cartitemid.id'],	
	    join     => ['userid','cartitemid'],
	}
	);

    my $cartitems = $user->get_schema->resultset('Cartitem')->search_rs(
	{
	    id => { -in => $usercartitems->as_query },
	}
	);

    my $cartitems_count = $cartitems->count;

    $logger->info("$cartitems_count cartitems found");

    while (my $thiscartitem = $cartitems->next()){
	my $id      = $thiscartitem->get_column('id');    
	my $titleid = $thiscartitem->get_column('titleid');
	my $dbname  = $thiscartitem->get_column('dbname');

	if ($dbname=~m/^(eds|dbis|ezb)$/){
	    $logger->info("ID $titleid in DB $dbname ignored");
	    next;
	}

	if (!$config->db_exists($dbname)){
	    $logger->error("NO_DB: $dbname");
	    next;
	}
	
	my $record = new OpenBib::Record::Title({ database => $dbname , id => $titleid, config => $config })->load_full_record;

	if ($record->record_exists){
	    
	    my $record_json = $record->to_json;

	    if ($dryrun){
		$logger->info("Would try to update id $id ($dbname/$titleid) with content $record_json");
	    }
	    else {
		$thiscartitem->update({
		    titlecache => $record_json	    
				      });
	    }
	}
	else {
	    $logger->error("Cartitemid $id: DB: $dbname - TITLEID: $titleid existiert nicht!");
	}
    }
}
else {
    $logger->error("Der Typ $type wird nicht unterstuetzt");
}

sub print_help {
    print << "ENDHELP";
refresh_titlecache.pl - Refresh des Titelcaches von Merk- und Literaturlisten mit aktuellen (Komplett)Daten

   Optionen:
   -help                 : Diese Informationsseite
   --type=...            : Welchen Titelcache? (cart|litlist)
   -dry-run              : Testlauf ohne Aenderungen
   -list-users           : Anzeige der Nutzeraccounts mit Merklisten
   -select-obsolete      : Eingrenzung auf obsolete Kurztitel mit PC0001
   --from=...            : Von Erstellungsdatum (z.B. 2013-01-01 00:00:00)
   --to=...              : Bis Erstellungsdatum (z.B. 2013-01-02 00:00:00)
   --username=...        : Einzelner Nutzer
   --logfile=...         : Alternatives Logfile
   --loglevel=...        : Alternatives Loglevel

ENDHELP
    exit;
}

