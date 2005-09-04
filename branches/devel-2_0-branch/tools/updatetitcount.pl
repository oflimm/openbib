#!/usr/bin/perl

#####################################################################
#
#  updatetitcount.pl
#
#  Aktualisierung der Information ueber die Titelanzahl in den
#  Katalogen
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
use Getopt::Long;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

# Definition der Programm-Optionen

&GetOptions("single-pool=s" => \$singlepool
	    );


my @databases=();

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";

# Wenn ein Katalog angegeben wurde, werden nur in ihm die Titel gezaehlt
# und der Counter aktualisiert

if ($singlepool ne ""){
  @databases=("$singlepool");
}

# Ansonsten werden alle als Aktiv markierten Kataloge aktualisiert

else {

  my $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1");
  $idnresult->execute();
  
  while (my $dbname=$idnresult->fetchrow){
    push @databases, $dbname;
  }
}

my $maxidns=0;
my $allidns=0;

foreach $database (@databases){
  my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or die "could not connect";
    
  $idnresult=$dbh->prepare("select idn from tit") or die "Error -- $DBI::errstr";
  $idnresult->execute();
  
  $maxidns=$idnresult->rows;

  $idnresult->finish();

  $allidns=$allidns+$maxidns;

  $idnresult=$sessiondbh->prepare("delete from titcount where dbname='$database'") or die "Error -- $DBI::errstr";

  $idnresult->execute();
  
  $idnresult=$sessiondbh->prepare("insert into titcount values ('$database',$maxidns)") or die "Error -- $DBI::errstr";
  $idnresult->execute();
  
  print "$database -> $maxidns\n";
  $idnresult->finish();
  $dbh->disconnect();
  
}

if ($singlepool eq ""){
  my $notexist=0;
  
  $idnresult=$sessiondbh->prepare("delete from titcount where dbname='alldbs'") or die "Error -- $DBI::errstr";
  $idnresult->execute();
  
  $idnresult=$sessiondbh->prepare("insert into titcount values ('alldbs',$allidns)") or die "Error -- $DBI::errstr";
  $idnresult->execute();
}

$sessiondbh->disconnect();

