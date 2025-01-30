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

use OpenBib::Config;
use OpenBib::ILS::Factory;

use Date::Manip;
use Log::Log4perl qw(get_logger :levels);
use YAML;

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=ERROR, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=/tmp/alt_remote_uni.log
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config();

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $filterdir     = $rootdir."/filter";
my $konvdir       = $config->{'conv_dir'};
my $confdir       = $config->{'base_dir'}."/conf";
my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $marcjson2marcmetaexe   = "$konvdir/marcjson2marcmeta.pl";

my $pool          = $ARGV[0];
    
my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $filename      = $dbinfo->titlefile;
my $url           = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/".$dbinfo->titlefile;

system("cd $pooldir/$pool ; rm meta.* *.xml");

print "### $pool: Datenabzug von $url\n";

system("$wgetexe -P $pooldir/$pool/ $url   > /dev/null 2>&1 ");

print "### $pool: Umwandlung von $filename in MARC-in-JSON via yaz-marcdump\n";
system("cd $pooldir/$pool; yaz-marcdump -i marcxml -o json $filename |sed -e 's/<\!-- .* -->//g' | jq -S -c . > ${filename}.processed");

print "### $pool: Konvertierung von $filename\n";
system("cd $pooldir/$pool; $marcjson2marcmetaexe --database=$pool -reduce-mem --inputfile=${filename}.processed ; gzip meta.*");

system("cd $pooldir/$pool ; rm pool.mrc.processed");
