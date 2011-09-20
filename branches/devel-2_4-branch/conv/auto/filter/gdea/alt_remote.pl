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

my $harvestoaiexe = "$config->{'conv_dir'}/harvestOAI.pl";
my $oai2metaexe   = "$config->{'conv_dir'}/oai2meta.pl";

my $pool          = $ARGV[0];

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $oaiurl        = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/".$dbinfo->titlefile;

print "### $pool: Datenabzug via OAI von $oaiurl\n";
system("cd $pooldir/$pool ; rm *");
system("$harvestoaiexe --oaiurl=\"$oaiurl\" | /bin/gzip -c > $pooldir/$pool/pool.dat.gz");

system("/bin/gzip -dc $pooldir/$pool/pool.dat.gz > $pooldir/$pool/pool.dat");
system("cd $pooldir/$pool; $oai2metaexe --inputfile=pool.dat --idmappingfile=${pool}.yml ; gzip unload.*");
system("rm $pooldir/$pool/pool.dat");
