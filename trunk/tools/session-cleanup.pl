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

use DBI;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";

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

foreach $sessionID (@delsessionids){

  print "Purging SessionID $sessionID from ".$createtime{$sessionID};

  # Tabelle session

  $idnresult=$sessiondbh->prepare("delete from session where sessionid='$sessionID'");
  $idnresult->execute();

  print ".";

  # Tabelle treffer

  $idnresult=$sessiondbh->prepare("delete from treffer where sessionid='$sessionID'");
  $idnresult->execute();

  print ".";

  # Tabelle sessionlog

  $idnresult=$sessiondbh->prepare("delete from sessionlog where sessionid='$sessionID'");
  $idnresult->execute();

  print ".";

  # Tabelle queries

  $idnresult=$sessiondbh->prepare("delete from queries where sessionid='$sessionID'");
  $idnresult->execute();

  print ".";

  # Tabelle dbchoice

  $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid='$sessionID'");
  $idnresult->execute();

  print ".";

  # Tabelle searchresults

  $idnresult=$sessiondbh->prepare("delete from searchresults where sessionid='$sessionID'");
  $idnresult->execute();

    print ". done\n";
}

$idnresult->finish;
$sessiondbh->disconnect;
