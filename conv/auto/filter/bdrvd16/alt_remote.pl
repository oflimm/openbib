#!/usr/bin/perl

#####################################################################
#
#  alt_remote.pl
#
#  Holen via oai und konvertieren in das Meta-Format
#
#  Dieses File ist (C) 2003-2020 Oliver Flimm <flimm@openbib.org>
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

my $harvestoaiexe     = "$config->{'conv_dir'}/harvestOAI.pl";
my $simplexml2metaexe = "$config->{'conv_dir'}/simplexml2meta.pl";
my $marc2metaexe      = "$config->{'conv_dir'}/marc2meta.pl";

my $pool          = $ARGV[0];

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $oaiurl        = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/".$dbinfo->titlefile;

print "### $pool: Datenabzug via OAI von $oaiurl\n";
system("cd $pooldir/$pool ; rm meta.* ; rm pool*");
system("cd $pooldir/$pool ; $harvestoaiexe -all --set=$pool --format=MarcXchange --url=\"$oaiurl\" ");

system("cd $pooldir/$pool ; echo '<recordlist>' > $pooldir/$pool/pool.dat ; cat pool-*.xml >> $pooldir/$pool/pool.dat ; echo '</recordlist>' >> $pooldir/$pool/pool.dat");

system("cd $pooldir/$pool; yaz-marcdump -i marcxchange -o marc pool.dat > pool.mrc");
#system("cd $pooldir/$pool; $simplexml2metaexe --inputfile=pool.dat --configfile=/opt/openbib/conf/${pool}.yml; gzip meta.*");
system("cd $pooldir/$pool; $marc2metaexe --database=$pool --encoding='UTF-8' --inputfile=pool.mrc; gzip meta.*");

system("rm $pooldir/$pool/pool.dat $pooldir/$pool/pool-*.xml");
