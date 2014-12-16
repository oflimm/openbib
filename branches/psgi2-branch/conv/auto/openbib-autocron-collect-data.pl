#!/usr/bin/perl

#####################################################################
#
#  openbib-autocron-collect-data.pl
#
#  CRON-Job zum automatischen Einsammeln von Daten
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

use 5.008001;
use utf8;
use strict;
use warnings;
use threads;
use threads::shared;

use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use OpenBib::Config;

our ($logfile,$loglevel,$host);

&GetOptions(
    "host=s"        => \$host,
    "logfile=s"     => \$logfile,
    "loglevel=s"    => \$loglevel,
    );

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/openbib-autocron-collect.log";
$loglevel=($loglevel)?$loglevel:"INFO";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
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

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";

my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";

$logger->info("###### Starting automatic collection");

foreach my $dbinfo ($config->get_databaseinfo->search({ host => $host},{order_by => 'dbname ASC'})->all){
    my $database = $dbinfo->dbname;
    
    my $base_url =  $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/";
    
    $logger->info("### $database: Hole Exportdateien mit wget von $base_url");
    
    my $httpauthstring="";
    if ($dbinfo->protocol eq "http" && $dbinfo->remoteuser ne "" && $dbinfo->remotepassword ne ""){
        $httpauthstring=" --http-user=".$dbinfo->remoteuser." --http-passwd=".$dbinfo->remotepassword;
    }
    
    
    
    system("cd $pooldir/$database ; rm meta.*");
    system("$wgetexe $httpauthstring -P $pooldir/$database/ $base_url".$dbinfo->titlefile." > /dev/null 2>&1 ");
    system("$wgetexe $httpauthstring -P $pooldir/$database/ $base_url".$dbinfo->personfile." > /dev/null 2>&1 ");
    system("$wgetexe $httpauthstring -P $pooldir/$database/ $base_url".$dbinfo->corporatebodyfile." > /dev/null 2>&1 ");
    system("$wgetexe $httpauthstring -P $pooldir/$database/ $base_url".$dbinfo->subjectfile." > /dev/null 2>&1 ");
    system("$wgetexe $httpauthstring -P $pooldir/$database/ $base_url".$dbinfo->classificationfile." > /dev/null 2>&1 ");
    system("$wgetexe $httpauthstring -P $pooldir/$database/ $base_url".$dbinfo->holdingfile." > /dev/null 2>&1 ");
}

