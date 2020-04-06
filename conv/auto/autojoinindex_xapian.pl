#!/usr/bin/perl

#####################################################################
#
#  autojoinindex_xapian.pl
#
#  Automatische Verschmelzung von Indizes durch einem neuen Index
#
#  Dieses File ist (C) 2012-2013 Oliver Flimm <flimm@openbib.org>
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
use Search::Xapian;

use OpenBib::Config;

my ($usedirectories,$searchprofileid,$help,$logfile,$loglevel,$onlyauthorities,$onlytitles);

&GetOptions("searchprofileid=s" => \$searchprofileid,
            "only-authorities"  => \$onlyauthorities,
	    "use-directories"   => \$usedirectories,
            "only-titles"       => \$onlytitles,
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

my $fullatime = new Benchmark;

my $dboverview = $config->get_dbinfo_overview;

my $db_is_not_local_ref = {
};

foreach my $thisdb (@$dboverview){
    if ($thisdb->{system} =~m/Backend/){
	$db_is_not_local_ref->{$thisdb->{dbname}} = 1;
    }
}

my $xapian_cmd  = "/usr/bin/xapian-compact";
my @xapian_args = ();

unless ($usedirectories){
    # Glass-Backend mit Verzeichnissen braucht doppelt soviel Zeit bei
    # xapian-compact wie die Verwendung von einer Datei pro Index
    push @xapian_args, '-s';
}

my $xapian_base = $config->{xapian_index_base_path};

my @searchprofiles = ();
if ($searchprofileid && $config->searchprofile_exists($searchprofileid)){
    push @searchprofiles, $searchprofileid;
}
else {
    push @searchprofiles, $config->get_searchprofiles_with_own_index;
}

my $searchprofiledir = "$xapian_base/_searchprofile";

if (! -d $searchprofiledir){
    $logger->info("Profil-Verzeichnis $searchprofiledir wurde angelegt");
    
    mkdir $searchprofiledir;
}

# Bestehende Profile entfernen

opendir(DIR, $searchprofiledir);

$logger->info("Profil-Verzeichnis von alten Profilen reinigen");

while (my $file = readdir(DIR)) {
    next if ($file=~/^\./);

    if ($searchprofileid && !$file eq $searchprofileid && !$file eq $searchprofileid."_authority" ){
        next;
    }
    
    my $is_authority = 0;

    if ($file=~/_authority/){
	$is_authority = 1;
    }
    
    if (!$onlyauthorities && !$is_authority){
	$logger->info("Profil $file entfernt");

	if ($usedirectories){
	    system("rm $searchprofiledir/$file/*");
	    system("rmdir $searchprofiledir/$file");
	}
	else {
	    system("rm $searchprofiledir/$file");
	}
    }
    elsif (!$onlytitles && $is_authority){
	$logger->info("Authority Profil $file entfernt");
	
	if ($usedirectories){
	    system("rm $searchprofiledir/$file/*");
	    system("rmdir $searchprofiledir/$file");
	}
	else {
	    system("rm $searchprofiledir/$file");
	}
    }	
}

closedir(DIR);

foreach my $searchprofile (@searchprofiles){
    $logger->fatal("Bearbeite Suchprofil $searchprofile");

    my $atime = new Benchmark;

    my @databases = $config->get_databases_of_searchprofile($searchprofile);

    # Herausfiltern der externen Datenbanken

    @databases = grep { !$db_is_not_local_ref->{$_} } @databases;
    
    # Check, welche Indizes irregulaer sind

    my $sane_index = 1;
    my $sane_authority_index = 1;
    foreach my $database (@databases){
        my $dbh;
        eval {
            $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
        };
        
        if ($@) {
            $logger->error("Database Index: $database - :".$@);
            $sane_index = 0;
        }

        eval {
            $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database."_authority") || $logger->fatal("Couldn't open/create Xapian DB $!\n");
        };
        
        if ($@) {
            $logger->error("Authority Index: ${database}_authority - :".$@);
            $sane_authority_index = 0;
        }

    }

    if (!$sane_index || !$sane_authority_index){
        $logger->info("Mindestens ein Index korrupt");
        exit;
    }
    
    if (@databases > 3){
        push @xapian_args, "--multipass";
    }

    my @authoritydatabases    = @databases;
    @authoritydatabases       = map { $_.="_authority" } @authoritydatabases;
    
    my $thisindex             = "_searchprofile/$searchprofile";
    my $thisauthorityindex    = "_searchprofile/$searchprofile"."_authority";
    my $thistmpindex          = $thisindex.".tmp";
    my $thisauthoritytmpindex = $thisauthorityindex.".tmp";

    my $thisindex_path              = "$xapian_base/$thisindex";
    my $thisauthorityindex_path     = "$xapian_base/$thisauthorityindex";
    my $thistmpindex_path           = $thisindex_path.".tmp";
    my $thisauthoritytmpindex_path  = $thisauthorityindex_path.".tmp";
    my $thistmp2index_path          = $thisindex_path.".tmp2";
    my $thisauthoritytmp2index_path = $thisauthorityindex_path.".tmp2";

    push @databases, $thistmpindex;
    push @authoritydatabases, $thisauthoritytmpindex;

    my $database_string = join " ", map { $_="$xapian_base/$_" } @databases;
    my $args = join " ",@xapian_args;
    my $cmd = "$xapian_cmd $args $database_string";

    if (!$onlyauthorities){
        $logger->info("### Compacting with $cmd to temp index");        
        system("$cmd");
    }
    
    my $authority_string = join " ", map { $_="$xapian_base/$_" } @authoritydatabases;
    $cmd = "$xapian_cmd $args $authority_string";
    
    if (!$onlytitles){
        $logger->info("### Compacting authorities with $cmd to temp index");
        system("$cmd");
    }

    if (!$onlyauthorities){
        $logger->info("### Replacing index");

        if ($usedirectories){
	    system("rm -f $thistmp2index_path/* ; rmdir $thistmp2index_path ; mv $thisindex_path $thistmp2index_path ; mv $thistmpindex_path $thisindex_path ; rm -f $thistmp2index_path/* ; rmdir $thistmp2index_path ");
	}
	else {
	    system("rm $thistmp2index_path ; mv $thisindex_path $thistmp2index_path ; mv $thistmpindex_path $thisindex_path ; rm $thistmp2index_path ");
	}
    }

    if (!$onlytitles){
        $logger->info("### Replacing authority index");
        
        if ($usedirectories){
	    system("rm -f $thisauthoritytmp2index_path/* ; rmdir $thisauthoritytmp2index_path ; mv $thisauthorityindex_path $thisauthoritytmp2index_path ; mv $thisauthoritytmpindex_path $thisauthorityindex_path ; rm -f $thisauthoritytmp2index_path/* ; rmdir $thisauthoritytmp2index_path ");
	}
	else {
	    system("rm $thisauthoritytmp2index_path ; mv $thisauthorityindex_path $thisauthoritytmp2index_path ; mv $thisauthoritytmpindex_path $thisauthorityindex_path ; rm $thisauthoritytmp2index_path ");
	}
    }
    
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info("### Suchprofil $searchprofile: Gesamte Zeit -> $resulttime");

}


my $fullbtime      = new Benchmark;
my $fulltimeall    = timediff($fullbtime,$fullatime);
my $fullresulttime = timestr($fulltimeall,"nop");
$fullresulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("### Gesamtezeit alle Indize-> $fullresulttime");

sub print_help {
    print << "ENDHELP";
autojoinindex_xapian.pl - Automatische Verschmelzung von Xapian-Indizes fuer Suchprofile

   Optionen:
   -help                 : Diese Informationsseite
       
   --searchprofileid=... : Angegebne Suchprofil-ID verwenden (ansonsten fuer alle Kataloge die own_index=true in Admin haben)
   -use-directories      : Verwendung von Verzeichnissen fuer die Xapian-Indizes anstelle Dateien
ENDHELP
    exit;
}

