#!/usr/bin/perl

#####################################################################
#
#  alt_remote.pl
#
#  Konvertieren in das Meta-Format
#
#  Dieses File ist (C) 2003-2006 Oliver Flimm <flimm@openbib.org>
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

my $config = new OpenBib::Config();

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};
my $confdir       = $config->{'base_dir'}."/conf";
my $wgetexe       = "/usr/bin/curl";
my $marcjson2marcmetaexe   = "$konvdir/marcjson2marcmeta.pl";

my $pool          = $ARGV[0];

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $filename      = $dbinfo->titlefile;

my $url =  $dbinfo->protocol."://".$dbinfo->host."/".$filename;

my $marcfile = "oapen.marc.xml";

print "### $database: Hole Exportdateien mit $wgetexe von $url\n";

system("cd $pooldir/$pool ; rm $marcfile ");
system("$wgetexe -o $pooldir/$pool/$marcfile \"$url\" > /dev/null 2>&1 ");

print "### $pool: Konvertierung von $filename\n";
system("cd $pooldir/$pool ; rm meta.* ");

print "### $pool: Umwandlung von $filename in MARC-in-JSON via yaz-marcdump\n";
system("cd $pooldir/$pool; yaz-marcdump -i marcxml -o json $marcfile | jq -S -c .  > pool.json");

print "### $pool: IDs fixen\n";
system("cd $pooldir/$pool; cat pool.json | $rootdir/filter/$pool/fix-id.pl > pool.json.tmp ; mv -f pool.json.tmp pool.json");

print "### $pool: Konvertierung von pool.json\n";
system("cd $pooldir/$pool; $marcjson2marcmetaexe --database=$pool -reduce-mem --inputfile=pool.json --configfile=/opt/openbib/conf/uni.yml; gzip meta.*");

system("cd $pooldir/$pool ; rm pool.json");
