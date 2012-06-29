#!/usr/bin/perl

#####################################################################
#
#  autojoinindex_xapian.pl
#
#  Automatische Verschmelzung von Indizes durch einem neuen Index
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;

use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

my ($searchprofileid,$help,$logfile,$loglevel);

&GetOptions("searchprofileid=s" => \$searchprofileid,
            "logfile=s"         => \$logfile,
            "loglevel=s"        => \$loglevel,
	    "help"              => \$help
	    );

if ($help){
    print_help();
}

$logfile  = ($logfile)?$logfile:'/var/log/openbib/autojoinindex_xapian.log';
$loglevel = ($loglevel)?$loglevel:"INFO";

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

my $config = new OpenBib::Config();

my $xapian_cmd  = "/usr/bin/xapian-compact";
my @xapian_args = ();
my $xapian_base = $config->{xapian_index_base_path};

my @searchprofiles = ();
if ($searchprofileid && $config->searchprofile_exists($searchprofileid)){
    push @searchprofiles, $searchprofileid;
}
else {
    push @searchprofiles, $config->get_searchprofiles_with_own_index;
}

if (! -d "$xapian_base/profile"){
    $logger->info("Profil-Verzeichnis wurde angelegt");
    
    mkdir "$xapian_base/profile";
}

foreach my $searchprofile (@searchprofiles){
    $logger->fatal("Bearbeite Suchprofil $searchprofile");

    my $atime = new Benchmark;

    my @databases = $config->get_databases_of_searchprofile($searchprofile);
    
    if (@databases > 3){
        push @xapian_args, "--multipass";
    }

    my $thisindex         = "profile/$searchprofile";
    my $thistmpindex      = $thisindex.".tmp";

    my $thisindex_path    = "$xapian_base/$thisindex";
    my $thistmpindex_path = $thisindex_path.".tmp";

    
    push @databases, $thistmpindex;

    my $database_string = join " ", map { $_="$xapian_base/$_" } @databases;
    my $args = join " ",@xapian_args;
    my $cmd = "$xapian_cmd $args $database_string";

    $logger->info("### Compacting with $cmd to temp index");

    system("$cmd");

    $logger->info("### Replacing index");

    system("rm -f $thisindex_path/* ; rmdir $thisindex_path ; mv $thistmpindex_path $thisindex_path");
    
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info("### Suchprofil $searchprofile: Gesamte Zeit -> $resulttime");

}



sub print_help {
    print << "ENDHELP";
autoconv-sikis.pl - Automatische Konvertierung von SIKIS-Daten

   Optionen:
   -help                 : Diese Informationsseite
       
   -sync                 : Hole Pool automatisch ueber das Netz
   --database=...        : Angegebenen Katalog verwenden

   Datenbankabhaengige Filter:

   pre_remote.pl
   alt_remote.pl
   post_remote.pl
   pre_move.pl
   pre_conv.pl
   post_conv.pl
   post_dbload.pl
   post_index_off.pl
   post_index_on.pl

ENDHELP
    exit;
}

