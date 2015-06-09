#!/usr/bin/perl

#####################################################################
#
#  session-cleanup.pl
#
#  Loeschung alter Sessions
#
#  Dieses File ist (C) 2003-2012 Oliver Flimm <flimm@openbib.org>
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

use Date::Manip;
use DBI;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Session;
use OpenBib::User;

my $logfile='/var/log/openbib/session-cleanup.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=ERROR, LOGFILE, Screen
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

my $thistimedate   = Date::Manip::ParseDate("now");
my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-24hours");

$expiretimedate = Date::Manip::UnixDate($expiretimedate,"%Y-%m-%d %H:%M:%S");

my $open_sessions = $session->get_schema->resultset('Sessioninfo')->search(
    {
        createtime => { '<' => $expiretimedate },
    },
    {
        group_by => ['id','createtime'],
        order_by => ['createtime asc'],
    }
);

my $count = 1;
foreach my $sessioninfo ($open_sessions->all){
  my $sessionID  = $sessioninfo->sessionid;
  my $createtime = $sessioninfo->createtime;

#  last if ($count == 10);
  $logger->info("Purging SessionID $sessionID from $createtime");

  my $session = new OpenBib::Session({sessionID => $sessionID});
  $session->clear_data();

  # Zwischengespeicherte Benutzerinformationen loeschen
  my $user   = new OpenBib::User();
  my $userid = $user->get_userid_of_session($sessionID);

  if ($userid){
      $user->clear_cached_userdata($userid);
  }

  $count++;
}
