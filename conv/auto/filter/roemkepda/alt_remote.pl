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
use HTML::Entities qw/decode_entities/;

my $config = new OpenBib::Config();

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};
my $confdir       = $config->{'base_dir'}."/conf";
my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $simplecsv2metaexe   = "$konvdir/simplecsv2meta.pl";

my $pool          = $ARGV[0];

my $dbinfo = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $url    = $dbinfo->protocol."://".$dbinfo->host."/".decode_entities($dbinfo->remotepath)."/".decode_entities($dbinfo->titlefile);

print "### $pool: Datenabzug via http von $url\n";
system("cd $pooldir/$pool ; rm data.json");
system("cd $pooldir/$pool ; $wgetexe --no-check-certificate -O data.json '$url' # > /dev/null 2>&1 ");

print "### $pool: Konvertierung von data.csv\n";
system("cd $pooldir/$pool ; rm meta.*");
system("cd $pooldir/$pool; $rootdir/filter/$pool/roemkejson2csv.pl data.json data.csv");
system("cd $pooldir/$pool; $simplecsv2metaexe --inputfile=data.csv --configfile=$confdir/$pool.yml; gzip meta.*");
