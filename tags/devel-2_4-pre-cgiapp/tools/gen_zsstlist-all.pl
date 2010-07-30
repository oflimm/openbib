#!/usr/bin/perl

#####################################################################
#
#  gen_zsstlist-all.pl
#
#  Extrahieren der Zeitschriftenliste eines Instituts anhand aller
#  im Katalog instzs gefundenen lokalen Sigeln
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

#####################################################################
# Einladen der benoetigten Perl-Module 
#####################################################################

use utf8;

use Getopt::Long;
use OpenBib::Config;

use DBI;
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$sigel,$showall,$mode);

&GetOptions(
	    "help"    => \$help,
	    "sigel=s" => \$sigel,
	    "mode=s"  => \$mode,
	    "showall" => \$showall,
	    );

if ($help){
    print_help();
}

if (!$mode){
  $mode="tex";
}


if ($mode ne "tex" && $mode ne "pdf"){
  print "Mode muss enweder tex oder pdf sein.\n";
  exit;
}

my $config      = OpenBib::Config->instance;
my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

my $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=instzs;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

my $request=$dbh->prepare("select distinct content from mex where category = 3330 order by content") or $logger->error($DBI::errstr);

$request->execute() or $logger->error($DBI::errstr);;

while (my $result=$request->fetchrow_hashref()){
    my $sigel=$result->{content};
    system($config->{tool_dir}."/gen_zsstlist.pl --sigel=$sigel --mode=pdf");
    system($config->{tool_dir}."/gen_zsstlist.pl --sigel=$sigel -showall --mode=pdf");
}

sub print_help {
    print "gen-zsstlist-all.pl - Erzeugen von Zeitschiftenlisten fuer alle Sigel\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n";

    exit;
}
