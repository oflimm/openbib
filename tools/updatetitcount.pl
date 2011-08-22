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

use strict;
use warnings;

use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

# Definition der Programm-Optionen
my ($database,$logfile);

&GetOptions(
    "database=s" => \$database,
    "logfile=s"  => \$logfile,    
);

$logfile=($logfile)?$logfile:'/var/log/openbib/gen-subset.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

my ($allcount,$journalcount,$articlecount,$digitalcount)=(0,0,0,0);

# Verbindung zur SQL-Datenbank herstellen
my $configdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
    or $logger->error_die($DBI::errstr);

foreach $database (@databases){
  my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or die "could not connect";

  # Titel bestimmen;
  my $idnresult=$dbh->prepare("select count(*) as rowcount from title_listitem") or die "Error -- $DBI::errstr";
  $idnresult->execute();

  my $result=$idnresult->fetchrow_hashref;
  
  $allcount=$result->{rowcount};

  # Serien/Zeitschriften bestimmen
  $idnresult=$dbh->prepare("select count(distinct id) as rowcount from title where category=800 and content = 'Zeitschrift/Serie'") or die "Error -- $DBI::errstr";
  $idnresult->execute();

  $result=$idnresult->fetchrow_hashref;
  
  $journalcount=$result->{rowcount};

  # Aufsaetze bestimmen
  $idnresult=$dbh->prepare("select count(distinct id) as rowcount from title where category=800 and content = 'Aufsatz'") or die "Error -- $DBI::errstr";
  $idnresult->execute();

  $result=$idnresult->fetchrow_hashref;
  
  $articlecount=$result->{rowcount};

  # E-Median bestimmen
  $idnresult=$dbh->prepare("select count(distinct id) as rowcount from title where category=800 and content = 'Digital'") or die "Error -- $DBI::errstr";
  $idnresult->execute();

  $result=$idnresult->fetchrow_hashref;
  
  $digitalcount=$result->{rowcount};
  
  $idnresult->finish();

  $idnresult=$configdbh->prepare("update databaseinfo set allcount = ?, journalcount = ?, articlecount = ?, digitalcount = ? where dbname=?") or die "Error -- $DBI::errstr";
  $idnresult->execute($allcount,$journalcount,$articlecount,$digitalcount,$database);
  
  print "$database -> $allcount / $journalcount / $articlecount / $digitalcount\n";

  $idnresult->finish();
  $dbh->disconnect();
  
}

# if ($database eq ""){
#   my $notexist=0;
  
#   $idnresult=$configdbh->prepare("delete from titcount where dbname='alldbs'") or die "Error -- $DBI::errstr";
#   $idnresult->execute();
  
#   $idnresult=$configdbh->prepare("insert into titcount values ('alldbs',?,?,?,?)") or die "Error -- $DBI::errstr";
#   $idnresult->execute($allidns,$allidns_journals,$allidns_articles,$allidns_online);
# }

$configdbh->disconnect();

