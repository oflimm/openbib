#!/usr/bin/perl

#####################################################################
#
#  session-cleanup.pl
#
#  Loeschung alter Sessions
#
#  Dieses File ist (C) 2003-2016 Oliver Flimm <flimm@openbib.org>
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
use Date::Manip;
use DBI;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Session;
use OpenBib::User;

our ($help,$logfile,$loglevel,$limit,$from,$to);

&GetOptions(
    "help"         => \$help,
    "loglevel=s"   => \$loglevel,
    "logfile=s"    => \$logfile,
    "limit=s"      => \$limit,
    "from=s"       => \$from,
    "to=s"         => \$to,
    );



if ($help){
    print_help();
}

$loglevel=($loglevel)?$loglevel:"INFO";
$logfile=($logfile)?$logfile:"/var/log/openbib/session-cleanup.log";

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

my $config  = OpenBib::Config->new;
my $session = OpenBib::Session->new;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $current_time   = Date::Manip::ParseDate("now");

$current_time = Date::Manip::UnixDate($current_time,"%Y-%m-%d %H:%M:%S");

# Default: Abgelaufene Session
my $where_ref =  { 
    expiretime => { '<' => $current_time },
};

my $options_ref = {
    group_by => ['id','expiretime'],
    order_by => ['expiretime asc'],
};

# Alternativ: Zeitspanne der Session-Erzeugung
if ($from && $to){
    $options_ref = {
	group_by => ['id','createtime'],
	order_by => ['createtime asc'],
    };
    
    $where_ref = {
	-and => [
	     createtime => { '<' => $to },
	     createtime => { '>' => $from },
	    ],
    };
}

if ($limit){
    $options_ref->{rows} = $limit;
}

my $open_sessions = $session->get_schema->resultset('Sessioninfo')->search(
    $where_ref,
    $options_ref,
);

my $count = 1;
foreach my $sessioninfo ($open_sessions->all){
  my $sessionID  = $sessioninfo->sessionid;
  my $createtime = $sessioninfo->createtime;
  my $viewname   = $sessioninfo->viewname;

#  last if ($count == 10);
  $logger->info("Purging SessionID $sessionID from $createtime");

  my $session = new OpenBib::Session({sessionID => $sessionID, view => $viewname });
  $session->clear_data();

  # Zwischengespeicherte Benutzerinformationen loeschen
  my $user   = new OpenBib::User();
  my $userid = $user->get_userid_of_session($sessionID);

  if ($userid){
      $user->clear_cached_userdata($userid);
  }

  if ($count % 10000 == 0){
      $logger->error("Purged $count sessions");
  }
  
  $count++;
}

sub print_help {
    print << "ENDHELP";
session-cleanup.pl - Schliessen abgelaufener Sessions und Uebertragung in Statistik-DB

Optionen:
  -help                    : Diese Informationsseite
  --loglevel=DEBUG         : Loglevel [DEBUG|INFO|ERROR]
  --logfile=...            : Log-Datei
  --limit=...              : Maximale Zahl an zu schliessenden Sessions
  --from=...               : Von Erzeugungs-Datum (Format: yyyy-mm-dd hh:mm:ss), nur zusammen mit --to
  --to=...                 : Bis Erzeugungs-Datum (Format: yyyy-mm-dd hh:mm:ss), nur zusammen mit --from

Wichtig: from/to beziehen sich gezielt auf das Erzeugungs-Datum der Session.

Das Standardverhalten ist das Schliessen von Sessions bei ueberschrittenem Ablaufdatum.
ENDHELP


    exit;
}

