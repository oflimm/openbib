#!/usr/bin/perl

#####################################################################
#
#  alt_remote.pl
#
#  Konvertieren in das Meta-Format
#
#  Dieses File ist (C) 2003-2023 Oliver Flimm <flimm@openbib.org>
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
my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $simplecsv2metaexe   = "$konvdir/simplecsv2meta.pl";

my $pool          = $ARGV[0];

# my $dbinfo = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

# my $url    = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/".$dbinfo->titlefile;

# my $ftpauthstring="";
# if ($dbinfo->protocol eq "ftp" && $dbinfo->remoteuser ne "" && $dbinfo->remotepassword ne ""){
#     $ftpauthstring=" --ftp-user=".$dbinfo->remoteuser." --ftp-password=\"".$dbinfo->remotepassword."\"";
# }

# print "### $pool: Datenabzug via http von $url\n";
# system("cd $pooldir/$pool ; rm data.csv");
# system("cd $pooldir/$pool ; $wgetexe $ftpauthstring -O data.csv '$url' # > /dev/null 2>&1 ");

print "### $pool: Konvertierung von pool.csv\n";
system("cd $pooldir/$pool ; rm meta.* fixed_pool.csv");
system("cd $pooldir/$pool ; cat pool.csv | sed -e 's/;-;/;;/' | sed -e 's/;-;/;;/' | sed -e 's/;-;/;;/' > fixed_pool.csv");
system("cd $pooldir/$pool; $simplecsv2metaexe --inputfile=fixed_pool.csv --configfile=$confdir/$pool.yml; gzip meta.*");
