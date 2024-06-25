#!/usr/bin/perl

#####################################################################
#
#  post_cleanup.pl
#
#  Dieses File ist (C) 2003-2009 Oliver Flimm <flimm@openbib.org>
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

my $config = new OpenBib::Config();

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};
my $confdir       = $config->{'base_dir'}."/conf";
my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $simplecsv2metaexe  = "$konvdir/simplecsv2meta.pl";

my $pool          = $ARGV[0];
my $dbinfo = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;
my $filename = $dbinfo->titlefile;

print "### $pool: Metriken erstellen und cachen\n";
system("/opt/openbib/bin/gen_metrics.pl --database=mies --type=14 --field=4101");
system("/opt/openbib/bin/gen_metrics.pl --database=mies --type=14 --field=689:a");
