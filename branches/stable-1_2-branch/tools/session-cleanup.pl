#!/usr/bin/perl

#####################################################################
#
#  session-cleanup.pl
#
#  Loeschung alter Sessions
#
#  Dieses File ist (C) 2003-2004 Oliver Flimm <flimm@openbib.org>
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

use DBI;

use OpenBib::Config;

use OpenBib::Common::Util;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";

my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or die "$DBI::errstr";

my $validtimespan=84000; # in Sek. = 24 Std.

# Schleife ueber alle SessionID's

my $idnresult=$sessiondbh->prepare("select distinct sessionid,createtime from session where (UNIX_TIMESTAMP()-UNIX_TIMESTAMP(createtime)) > $validtimespan order by createtime asc");
$idnresult->execute();

my @delsessionids=();
my %createtime=();

while (my $result=$idnresult->fetchrow_hashref()){
  my $sessionID=$result->{'sessionid'};
  push @delsessionids,$sessionID;
  $createtime{$sessionID}=$result->{'createtime'};
}

foreach my $sessionID (@delsessionids){

  print "Purging SessionID $sessionID from ".$createtime{$sessionID};

  # Tabelle session

  $idnresult=$sessiondbh->prepare("delete from session where sessionid = ?");
  $idnresult->execute($sessionID);

  print ".";

  # Tabelle treffer

  $idnresult=$sessiondbh->prepare("delete from treffer where sessionid = ?");
  $idnresult->execute($sessionID);

  print ".";

  # Tabelle sessionlog

  $idnresult=$sessiondbh->prepare("delete from sessionlog where sessionid = ?");
  $idnresult->execute($sessionID);

  print ".";

  # Tabelle queries

  $idnresult=$sessiondbh->prepare("delete from queries where sessionid = ?");
  $idnresult->execute($sessionID);

  print ".";

  # Tabelle dbchoice

  $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid = ?");
  $idnresult->execute($sessionID);

  print ".";

  # Tabelle searchresults

  $idnresult=$sessiondbh->prepare("delete from searchresults where sessionid = ?");
  $idnresult->execute($sessionID);

  print ".";

  # Tabelle sessionmask

  $idnresult=$sessiondbh->prepare("delete from sessionmask where sessionid = ?") or die "$DBI::errstr";
  $idnresult->execute($sessionID) or die "$DBI::errstr";

  print ".";

  # Tabelle sessionprofile

  $idnresult=$sessiondbh->prepare("delete from sessionprofile where sessionid = ?") or die "$DBI::errstr";
  $idnresult->execute($sessionID) or die "$DBI::errstr";

  print ".";

  # Zwischengespeicherte Benutzerinformationen

  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  my $userresult=$userdbh->prepare("update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?") or die "$DBI::errstr";
  $userresult->execute($userid) or die "$DBI::errstr";
  
  $userresult->finish();

  print ". done\n";
}

$idnresult->finish;
$sessiondbh->disconnect;
