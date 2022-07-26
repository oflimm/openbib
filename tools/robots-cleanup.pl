#!/usr/bin/perl

#####################################################################
#
#  robots-cleanup.pl
#
#  Loeschung archivierter Sessions von robots in Statistik-DB
#
#  basierend auf session-cleanup.pl fuer Statistik-DBs mit Daten vor
#  dem 27.7.2022, in denen noch Sessions von robots archiviert wurden.
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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
use DBIx::Class::ResultClass::HashRefInflator;
use HTTP::BrowserDetect;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Statistics;

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
$logfile=($logfile)?$logfile:"/var/log/openbib/robots-cleanup.log";

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
my $statistics = OpenBib::Statistics->new;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $thistimedate   = Date::Manip::ParseDate("now");
my $expiretimedate = Date::Manip::DateCalc($thistimedate,"-24hours");

$expiretimedate = Date::Manip::UnixDate($expiretimedate,"%Y-%m-%d %H:%M:%S");

my $where_ref = {
};

my $options_ref = {
    select   => ['sid.id','me.content','sid.createtime'],
    as       => ['thisid','thisua','thiscreatetime'],
#    group_by => ['sid.id','me.content','sid.createtime'],
#    order_by => ['createtime asc'],
    join     => ['sid'],
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
};
    
if ($limit){
    $options_ref->{rows} = $limit;
}

if ($from && $to){
    $where_ref = {
	-and => [
	     'sid.createtime' => { '<' => $to },
	     'sid.createtime' => { '>' => $from },
	    ],
        'me.type' => 101,	    
    };
}
else {
    $where_ref = { 
	'sid.createtime' => { '<' => $expiretimedate },
        'me.type' => 101,
    };
}

my $sessions = $statistics->get_schema->resultset('Eventlog')->search(
    $where_ref,
    $options_ref,
);

my $count = 1;
while (my $session = $sessions->next()){
  my $sessionID  = $session->{'thisid'};
  my $createtime = $session->{'thiscreatetime'};
  my $ua         = $session->{'thisua'};

  $logger->info("$sessionID - $createtime - $ua");

  my $browser = HTTP::BrowserDetect->new($ua);

  if ($browser->robot()){
      # Rudimentaere Session-Informationen uebertragen
      my $robotsession = $statistics->get_schema->resultset('Sessioninfo')->search_rs(
	  {
	      id => $sessionID,
	  }
	  )->single;

      if ($robotsession){
	  $logger->debug("Trying to clear data for robot sessionID $sessionID");
	    
	  eval {
	      $robotsession->eventlogs->delete;
	      $robotsession->eventlogjsons->delete;
	      $robotsession->searchfields->delete;
	      $robotsession->searchterms->delete;
	      $robotsession->titleusages->delete;
	      $robotsession->delete;
	  };
	  
	  if ($@){
	      $logger->fatal("Problem clearing robot session $sessionID: $@");
	  }
	  else {
	      $logger->debug("Done");
	      $count++;
	  }
      }      
  }

  if ($count % 10000 == 0){
      $logger->error("Purged $count robot sessions");
  }
}

sub print_help {
    print "robots-cleanup.pl - Entfernen archivierter Sessions von Robots in Statistik-DB\n\n";
    print "Optionen: \n";
    print "  -help                    : Diese Informationsseite\n";
    print "  --loglevel=DEBUG         : Loglevel [DEBUG|INFO|ERROR]\n";
    print "  --logfile=...            : Log-Datei\n";
    print "  --limit=...              : Maximale Zahl an zu schliessenden Sessions\n";
    print "  --from=...               : Von Datum (Format: yyyy-mm-dd hh:mm:ss), nur zusammen mit --to\n";
    print "  --to=...                 : Bis Datum (Format: yyyy-mm-dd hh:mm:ss), nur zusammen mit --from\n";    
    exit;
}

