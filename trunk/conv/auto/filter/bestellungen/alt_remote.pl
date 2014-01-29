#!/usr/bin/perl

#####################################################################
#
#  alt_wget.pl
#
#  Holen per wget und Konvertieren der zbmed-Daten
#
#  Dieses File ist (C) 2005-2011 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie k"onnen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es w"unschen) jeder sp"ateren Version.
#
#  Die Ver"offentlichung dieses Programms erfolgt in der
#  Hoffnung, da"s es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEW"AHRLEISTUNG - sogar ohne die implizite Gew"ahrleistung
#  der MARKTREIFE oder der EIGNUNG F"UR EINEN BESTIMMTEN ZWECK.
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

my $pool          = $ARGV[0];

my $config        = new OpenBib::Config;

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $baseurl       = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath;

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};

my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $bcp2metaexe   = "$konvdir/bcp2meta.pl";


print "### $pool: Hole Exportdateien mit wget von $baseurl\n";

system("cd $pooldir/$pool ; rm meta.* pool-*");
system("$wgetexe -P $pooldir/$pool/ 'http://www.vub.de/search/stockdl/usb?user=externsearch\@ub.uni-koeln.de&password=lit_proc' -O pool-vub.csv");

system("cd $pooldir/$pool/ ; echo \"ID,Date,A,B,Price,Currency,ISBN,Verlag,Autor,Titel,Jahr,C,Source\" > pool.dat ; cat pool-*.csv >> pool.dat");

system("cd $pooldir/$pool ; /opt/openbib/conv/simplecsv2meta.pl --inputfile=pool.dat --configfile=/opt/openbib/conf/bestellungen.yml ; gzip meta.*");
#system("cd $pooldir/$pool ; zcat meta.title.gz| $rootdir/filter/$pool/filter-rswk.pl | gzip > meta.title.gz.tmp ; mv -f meta.title.gz.tmp meta.title.gz");
