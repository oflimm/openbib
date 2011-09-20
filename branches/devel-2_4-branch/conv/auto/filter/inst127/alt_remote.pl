#!/usr/bin/perl

#####################################################################
#
#  sample_prepost.pl
#
#  Beispielfilter
#
#  Dieses File ist (C) 2005-2011 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;

my $config = OpenBib::Config->instance;

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};
my $helperexe     = "$config->{'conv_dir'}/ald2simple.pl";
my $simpleexe     = "$config->{'conv_dir'}/simple2meta.pl";

my $pool          = $ARGV[0];

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $titlefile     = $dbinfo->titlefile;

print "### $pool: Alternative Umwandlung\n";

system("zcat $rootdir/pools/$pool/$titlefile | $helperexe > $rootdir/pools/$pool/pool.tmp.dat");
system("cd $rootdir/pools/$pool ; $simpleexe --inputfile=pool.tmp.dat --configfile=/opt/openbib/conf/inst127.yml");
system("cd $rootdir/pools/$pool ; rm unload.*.gz ; gzip unload.*");

