#####################################################################
#
#  OpenBib::Login::Util
#
#  Dieses File ist (C) 2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Login::Util;

use strict;
use warnings;

use DBI;

use Socket;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub authenticate_self_user {
  my ($username,$pin,$userdbh,$sessionID)=@_;

  my $userresult=$userdbh->prepare("select userid from user where loginname='$username' and pin='$pin'") or die "Error -- $DBI::errstr";
  
  $userresult->execute();

  my $res=$userresult->fetchrow_hashref();

  my $userid=$res->{'userid'};
  
  return $userid;
}

sub authenticate_slnp_user {
  my ($username,$pin,$slnptargetname,$slnptargetport,$slnptargetuser,$slnptargetdatabase)=@_;

  my %userinfo=();

  #####################################################################
  # Verbindung zur SLNP-Datenbank herstellen

  my $debug=0;
  my $response="";
  my $out=0;
  
  socket(SERVER, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2])||die "keine Verbindung";
  my $sin=sockaddr_in($slnptargetport,inet_aton($slnptargetname)) || die "Fehler";
  connect(SERVER,$sin) || die "connect failed";
  
  # SERVER wird default filehandle
  
  my $slnpquery="";
  
  select(SERVER);
  
  # flushen
  
  $|=1;
  
  # Initsequenz definieren

  my $initseq = << "INITSEQ";
SLNPServerInit
Kennung:$slnptargetuser
Datenbank:$slnptargetdatabase
SLNPEndCommand
INITSEQ

  # Sequenz definieren, um den Server zu beenden

  my $closeserver=<< "CLOSESERVER";
SLNPServerExit
SLNPEndCommand
CLOSESERVER
  
# Sequenz definieren, um die Verbindung abzubrechen

  my $closeconnection=<< "CLOSECONN";
SLNPQuit
SLNPEndCommand
CLOSECONN

  # Erste Auesserung ignorieren
  get_response("^220 SLNP",0);

  print SERVER $initseq;

  # Ergebnis einlesen

  get_response("^240 OK",0);

  # Ueberpruefen und in SQL-DB vermerken

  print SERVER << "BENKONTOPRUEF";
SLNPOpacBenutzerPruefung
BenutzerNummer:$username
Kennwort:$pin
BenutzerAktion:AKTIONKontoAnzeige
SLNPEndCommand
BENKONTOPRUEF

  while ($response=<SERVER>){
    
    if ($response=~/^601 Ergebnis:J$/){
      $userinfo{'erfolgreich'}=1;
    }

    if ($response=~/^510 OpsBenutzerPinFalsch/){
      $userinfo{'falsche Pin'}=1;
    }
    
    # Einlesen bis zum Ende
    
    if (($response=~/^250 SLNPEndOfData/)||($response=~/^510/)){
      print STDOUT "-- " if ($debug == 1);
      print STDOUT $response if (($out == 1)||($debug == 1));
      last;
    }
    else {
      
      print STDOUT "-- " if ($debug == 1);
      print STDOUT $response if (($out == 1)||($debug == 1));
    }
  }

  print SERVER << "BENKONTO";
SLNPBenutzerKurzKonto
BenutzerNummer:$username
SLNPEndCommand
BENKONTO

  while ($response=<SERVER>){
    
    print STDOUT "-- $response" if ($debug);
    if ($response=~/^601 Vorname:(.*)$/){
      $userinfo{'Vorname'}=$1;
    }
    
    if ($response=~/^601 Nachname:(.*)$/){
      $userinfo{'Nachname'}=$1;
    }
    
    if ($response=~/^601 Gut:(.*)$/){
      $userinfo{'Guthaben'}=$1;
    }

    if ($response=~/^601 Soll:(.*)$/){
      $userinfo{'Soll'}=$1;
    }

    if ($response=~/^601 AvAnz:(.*)$/){
      $userinfo{'AVanz'}=$1;
    }

    if ($response=~/^601 VmAnz:(.*)$/){
      $userinfo{'Vmanz'}=$1;
    }

    if ($response=~/^601 GeburtsDatum:(.*)$/){
      $userinfo{'Geburtsdatum'}=$1;
    }

    if ($response=~/^601 Alter:(.*)$/){
      $userinfo{'Alter'}=$1;
    }

    # Einlesen bis zum Ende
    
    if (($response=~/^250 SLNPEndOfData/)||($response=~/^510/)){
      print STDOUT "-- " if ($debug == 1);
      print STDOUT $response if (($out == 1)||($debug == 1));
      last;
    }
    else {
      
      print STDOUT "-- " if ($debug == 1);
      print STDOUT $response if (($out == 1)||($debug == 1));
    }
  }
  
  # Server beenden

  print STDOUT $closeserver if ($debug);
  print SERVER $closeserver;
  
  # Ergebnis einlesen
  
  get_response("^240 OK",0);
  
  # Verbindung beenden
  
  print STDOUT $closeconnection if ($debug);
  print SERVER $closeconnection;
  
  # Ergebnis einlesen
  
  
  get_response("^240 OK",0);
  
  # Filehandle schliessen
  
  close(SERVER);

  select(STDOUT);
  return \%userinfo;
}

sub get_response {

  my ($responsecode,$out)=@_;

  my $debug=0;

  # Einlesen der Antwort des Servers
  
  my $thisresponse="";
  my $response="";
  while ($response=<SERVER>){

    # und Abbruch, bei regul"arem Ende oder einem Fehler

    if (($response=~/$responsecode/)||($response=~/^5.0/)){
      print STDOUT "-- " if ($debug == 1);
      print STDOUT $response if (($out == 1)||($debug == 1));
      last;
    }
    else {
      print STDOUT "-- " if ($debug == 1);
      print STDOUT $response if (($out == 1)||($debug == 1));
    }
    $thisresponse.=$response;
  }
  return $thisresponse;
}
