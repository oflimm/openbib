#!/usr/bin/perl

#####################################################################
#
#  alt_remote.pl
#
#  Holen via oai und konvertieren in das Meta-Format
#
#  Dieses File ist (C) 2003-2011 Oliver Flimm <flimm@openbib.org>
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

my $harvestoaiexe        = "$config->{'conv_dir'}/harvestOAI.pl";
my $marcjson2marcmetaexe = "$config->{'conv_dir'}/marcjson2marcmeta.pl";

my $pool          = $ARGV[0];

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $oaiurl        = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/".$dbinfo->titlefile;

print "### $pool: Datenabzug via OAI von $oaiurl\n";
system("cd $pooldir/$pool ; rm meta.* pool.* ");
system("cd $pooldir/$pool ; catmandu convert OAI --url $oaiurl --metadataPrefix marcxml --set fidn:all --handler marcxml to MARC --type ISO > pool.mrc");

system("cd $pooldir/$pool; yaz-marcdump -i marc -o json pool.mrc | jq -S -c . > pool.json");

system("cd $pooldir/$pool; $marcjson2marcmetaexe --database=$pool -reduce-mem --inputfile=pool.json --configfile=/opt/openbib/conf/uni.yml; gzip meta.*");
