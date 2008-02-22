#!/usr/bin/perl

#####################################################################
#
#  session-cleanup.pl
#
#  Loeschung alter Sessions
#
#  Dieses File ist (C) 2003-2008 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Session;
use OpenBib::User;

my $config = OpenBib::Config->instance;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $sessiondbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd}) or die "could not connect";

my $validtimespan=84000; # in Sek. = 24 Std.

# Schleife ueber alle SessionID's

my $idnresult=$sessiondbh->prepare("select distinct sessionid,createtime from session where (UNIX_TIMESTAMP()-UNIX_TIMESTAMP(createtime)) > $validtimespan order by createtime asc");
$idnresult->execute();

my @delsessions = ();

while (my $result=$idnresult->fetchrow_hashref()){
  my $sessionID  = $result->{'sessionid'};
  my $createtime = $result->{'createtime'};
  push @delsessions, {
      id         => $sessionID,
      createtime => $createtime,
  };
}

$idnresult->finish;
$sessiondbh->disconnect;

foreach my $session_ref (@delsessions){
  print "Purging SessionID ".$session_ref->{id}." from ".$session_ref->{createtime};

  my $session = new OpenBib::Session({sessionID => $session_ref->{id}});
  $session->clear_data();

  print " .";

  # Zwischengespeicherte Benutzerinformationen loeschen
  my $user   = new OpenBib::User();
  my $userid = $user->get_userid_of_session($session_ref->{id});

  $user->clear_cached_userdata($userid);

  print ". done\n";
}
