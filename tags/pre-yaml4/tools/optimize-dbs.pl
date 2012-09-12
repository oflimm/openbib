#!/usr/bin/perl

#####################################################################
#
#  optimize-dbs.pl
#
#  DBMS-Optimierung der Katalog-Datenbanken
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

use OpenBib::Config;

my $config = OpenBib::Config->instance;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $sessiondbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd}) or die "could not connect";

#####################################################################
# Optimierung der Session-Datenbank

open(SESSIONTABS,"$config->{'dbdesc_dir'}/mysql/session.mysql");

my @sessiontabs=();

while (<SESSIONTABS>){
  if (/create\s+table\s+(\S+)\s+\(/i){
    push @sessiontabs, $1;
  }
}

close(SESSIONTABS);

# flushen

$|=1;

print "Optimizing DB session";

# Schleife ueber alle Tabellen

foreach $tab (@sessiontabs){

  $idnresult=$sessiondbh->prepare("optimize table $tab");
  $idnresult->execute();
  
  print ".";
}
print "done\n";

# Einlesen aller Datenbanknamen

my @optimizedbs=$config->get_active_databases();

$idnresult->finish;
$sessiondbh->disconnect;

#####################################################################
# Optimierung der Katalog-Datenbanken

# Einlesen aller Tabellennamen

open(TABS,"$config->{'dbdesc_dir'}/mysql/pool.mysql");

my @dbtabs=();

while (<TABS>){
  if (/create\s+table\s+(\S+)\s+\(/i){
    push @dbtabs, $1;
  }
}

close(TABS);

foreach $dbname (@optimizedbs){

  my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$dbname;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or die "could not connect";

  print "Optimizing DB $dbname";

  # Schleife ueber alle Tabellen

  foreach $tab (@dbtabs){

    $idnresult=$dbh->prepare("optimize table $tab");
    $idnresult->execute();
    
    print ".";
  }
  print "done\n";

  $idnresult->finish;
  $dbh->disconnect;
}

