#!/usr/bin/perl
#####################################################################
#
#  metastat2sqldb.pl
#
#  Dieses File ist (C) 2006-2008 Oliver Flimm <flimm@openbib.org>
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

use DBI;
use YAML;
use OpenBib::Config;

my $config = OpenBib::Config->instance;

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd});

my $request1=$statisticsdbh->prepare("delete from relevance where tstamp=? and id=? and dbname=? and katkey=? and origin=?");
my $request2=$statisticsdbh->prepare("insert into relevance values (?,?,?,?,?,?)");

while (<>){
    my ($tstamp,$id,$isbn,$database,$katkey,$origin)=split("\\|",$_);
    chomp($origin);
    $request1->execute($tstamp,$id,$database,$katkey,$origin);
    $request2->execute($tstamp,$id,$isbn,$database,$katkey,$origin);
}

$request1->finish();
$request2->finish();

$statisticsdbh->disconnect;
