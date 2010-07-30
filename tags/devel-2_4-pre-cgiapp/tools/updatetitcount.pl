#!/usr/bin/perl

#####################################################################
#
#  updatetitcount.pl
#
#  Aktualisierung der Information ueber die Titelanzahl in den
#  Katalogen
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

use DBI;
use Getopt::Long;

use OpenBib::Config;

# Definition der Programm-Optionen
my ($database);

&GetOptions("database=s" => \$database
	    );

my $config = OpenBib::Config->instance;

my @databases=();

# Wenn ein Katalog angegeben wurde, werden nur in ihm die Titel gezaehlt
# und der Counter aktualisiert

if ($database ne ""){
    @databases=("$database");
}
# Ansonsten werden alle als Aktiv markierten Kataloge aktualisiert
else {
    @databases = $config->get_active_databases();
}

my $maxidns=0;
my $maxidns_journals=0;
my $maxidns_articles=0;
my $allidns=0;
my $allidns_journals=0;
my $allidns_articles=0;

# Verbindung zur SQL-Datenbank herstellen
my $configdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
    or $logger->error_die($DBI::errstr);

foreach $database (@databases){
  my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or die "could not connect";

  # Titel bestimmen;
  $idnresult=$dbh->prepare("select count(*) as rowcount from titlistitem") or die "Error -- $DBI::errstr";
  $idnresult->execute();

  my $result=$idnresult->fetchrow_hashref;
  
  $maxidns=$result->{rowcount};

  # Serien/Zeitschriften bestimmen
  $idnresult=$dbh->prepare("select count(distinct id) as rowcount from tit where category=800 and content = 'Zeitschrift/Serie'") or die "Error -- $DBI::errstr";
  $idnresult->execute();

  my $result=$idnresult->fetchrow_hashref;
  
  $maxidns_journals=$result->{rowcount};

  # Aufsaetze bestimmen
  $idnresult=$dbh->prepare("select count(distinct id) as rowcount from tit where category=800 and content = 'Aufsatz'") or die "Error -- $DBI::errstr";
  $idnresult->execute();

  my $result=$idnresult->fetchrow_hashref;
  
  $maxidns_articles=$result->{rowcount};

  
  $idnresult->finish();

  $allidns          = $allidns+$maxidns;
  $allidns_journals = $allidns_journals+$maxidns_journals;
  $allidns_articles = $allidns_articles+$maxidns_articles;

  $idnresult=$configdbh->prepare("delete from titcount where dbname=?") or die "Error -- $DBI::errstr";

  $idnresult->execute($database);
  
  $idnresult=$configdbh->prepare("insert into titcount values (?,?,?)") or die "Error -- $DBI::errstr";
  $idnresult->execute($database,$maxidns,1);
  $idnresult->execute($database,$maxidns_journals,2);
  $idnresult->execute($database,$maxidns_articles,3);
  
  print "$database -> $maxidns / $maxidns_journals / $maxidns_articles\n";
  $idnresult->finish();
  $dbh->disconnect();
  
}

if ($database eq ""){
  my $notexist=0;
  
  $idnresult=$configdbh->prepare("delete from titcount where dbname='alldbs'") or die "Error -- $DBI::errstr";
  $idnresult->execute();
  
  $idnresult=$configdbh->prepare("insert into titcount values ('alldbs',?,?)") or die "Error -- $DBI::errstr";
  $idnresult->execute($allidns,1);
  $idnresult->execute($allidns_journals,2);
  $idnresult->execute($allidns_articles,3);
}

$configdbh->disconnect();

