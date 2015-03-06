#!/usr/bin/perl

#####################################################################
#
#  create_missing_pools.pl
#
#  Anzeige fehlernder PostgreSQL-Katalog-Datenbanken auf Grundlage
#  der in OpenBib definierten
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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
use YAML;

my $config = OpenBib::Config->new;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $systemdbh=DBI->connect("DBI:$config->{systemdbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd}) or die "could not connect";

my $localdbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{pgdbname};host=$config->{pgdbhost};port=$config->{pgdbport}", $config->{pgdbuser}, $config->{pgdbpasswd}) or die "could not connect";

my $request=$localdbh->prepare("select datname from pg_database");
$request->execute();

my %created_dbs = ();
while (my $res=$request->fetchrow_hashref){
    $created_dbs{$res->{datname}}=1;
}

$request=$systemdbh->prepare("select dbname from databaseinfo where active is true");
$request->execute();

while (my $res=$request->fetchrow_hashref){
    my $dbname = $res->{dbname};
    
    if (!$created_dbs{$dbname}){
        print "$dbname\n";
    }
}
