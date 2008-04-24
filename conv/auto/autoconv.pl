#!/usr/bin/perl

#####################################################################
#
#  autoconv.pl
#
#  Automatische Konvertierung
#
#  Default: Sikis-Daten
#
#  Andere : Ueber Plugins/Filter realisierbar
#
#  Dieses File ist (C) 1997-2007 Oliver Flimm <flimm@openbib.org>
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

my ($singlepool,$sync,$help,$logfile);

&GetOptions("single-pool=s"   => \$singlepool,
            "logfile=s"       => \$logfile,
	    "sync"            => \$sync,            
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/autoconv.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
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

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";

my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $meta2sqlexe   = "$config->{'conv_dir'}/meta2sql.pl";
my $meta2mexexe   = "$config->{'conv_dir'}/meta2mex.pl";
my $meta2waisexe  = "$config->{'conv_dir'}/meta2wais.pl";
my $wais2sqlexe   = "$config->{'conv_dir'}/wais2searchSQL.pl";
my $mysqlexe      = "/usr/bin/mysql -u $config->{'dbuser'} --password=$config->{'dbpasswd'} -f";
my $mysqladminexe = "/usr/bin/mysqladmin -u $config->{'dbuser'} --password=$config->{'dbpasswd'} -f";

if (!$singlepool){
  $logger->fatal("Kein Pool mit --single-pool= ausgewaehlt");
  exit;
}

my $singlepooltmp=$singlepool."tmp";

if (!$config->db_exists($singlepool)){
  $logger->fatal("Pool $singlepool existiert nicht");
  exit;
}

my $dboptions_ref = $config->get_dboptions($singlepool);

$logger->info("### POOL $singlepool");

my $atime = new Benchmark;

# Aktuelle Pool-Version von entfernter Quelle uebertragen

{
    if ($sync){
        my $atime = new Benchmark;
        
        if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/pre_remote.pl"){
            $logger->info("### $singlepool: Verwende Plugin pre_remote.pl");
            system("$config->{autoconv_dir}/filter/$singlepool/pre_remote.pl $singlepool");
        }
    
        if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/alt_remote.pl"){
            $logger->info("### $singlepool: Verwende Plugin alt_remote.pl");
            system("$config->{autoconv_dir}/filter/$singlepool/alt_remote.pl $singlepool");
        }
        else {
            $logger->info("### $singlepool: Hole Exportdateien mit wget von $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/");
                        
            my $httpauthstring="";
            if ($dboptions_ref->{protocol} eq "http" && $dboptions_ref->{remoteuser} ne "" && $dboptions_ref->{remotepasswd} ne ""){
                $httpauthstring=" --http-user=$dboptions_ref->{remoteuser} --http-passwd=$dboptions_ref->{remotepasswd}";
            }
            
            system("cd $pooldir/$singlepool ; rm unload.*");
            system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{titfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{autfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{korfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{swtfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{notfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{mexfilename} > /dev/null 2>&1 ");
        }

    
        if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/post_remote.pl"){
            $logger->info("### $singlepool: Verwende Plugin post_remote.pl");
            system("$config->{autoconv_dir}/filter/$singlepool/post_remote.pl $singlepool");
        }
        
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $logger->info("### $singlepool: Benoetigte Zeit -> $resulttime");
    }
}

# Entpacken der Pool-Daten in separates Arbeits-Verzeichnis unter 'data'

{    
    my $atime = new Benchmark;

    $logger->info("### $singlepool: Entpacken der Pool-Daten");

    if (! -d "$rootdir/data/$singlepool"){
        system("mkdir $rootdir/data/$singlepool");
    }
    
    system("cd $pooldir/$singlepool/ ; zcat $dboptions_ref->{titfilename} | $meta2mexexe");
    
    if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/pre_move.pl"){
        $logger->info("### $singlepool: Verwende Plugin pre_move.pl");
        system("$config->{autoconv_dir}/filter/$singlepool/pre_move.pl $singlepool");
    }
    
    system("rm $rootdir/data/$singlepool/*");
    system("/bin/gzip -dc $pooldir/$singlepool/$dboptions_ref->{titfilename} > $rootdir/data/$singlepool/tit.exp");
    system("/bin/gzip -dc $pooldir/$singlepool/$dboptions_ref->{autfilename} > $rootdir/data/$singlepool/aut.exp");
    system("/bin/gzip -dc $pooldir/$singlepool/$dboptions_ref->{swtfilename} > $rootdir/data/$singlepool/swt.exp");
    system("/bin/gzip -dc $pooldir/$singlepool/$dboptions_ref->{notfilename} > $rootdir/data/$singlepool/not.exp");
    system("/bin/gzip -dc $pooldir/$singlepool/$dboptions_ref->{korfilename} > $rootdir/data/$singlepool/kor.exp");
    system("/bin/gzip -dc $pooldir/$singlepool/$dboptions_ref->{mexfilename} > $rootdir/data/$singlepool/mex.exp");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $singlepool: Benoetigte Zeit -> $resulttime");

    if (! -e "$rootdir/data/$singlepool/tit.exp" || ! -s "$rootdir/data/$singlepool/tit.exp"){
        $logger->error("### $singlepool: Keine Daten vorhanden");

        goto CLEANUP;
    }
}
    
# Konvertierung aus dem Meta- in das SQL-Einladeformat

{
    my $atime = new Benchmark;

    # Konvertierung Exportdateien -> SQL
    if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/pre_conv.pl"){
        $logger->info("### $singlepool: Verwende Plugin pre_conv.pl");
        system("$config->{autoconv_dir}/filter/$singlepool/pre_conv.pl $singlepool");
    }

    $logger->info("### $singlepool: Konvertierung Exportdateien -> SQL");

    if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/alt_conv.pl"){
        $logger->info("### $singlepool: Verwende Plugin alt_conv.pl");
        system("$config->{autoconv_dir}/filter/$singlepool/alt_conv.pl $singlepool");
    }
    else {
        system("cd $rootdir/data/$singlepool ; $meta2sqlexe -add-superpers --single-pool=$singlepool");
    }
    
    if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/post_conv.pl"){
        $logger->info("### $singlepool: Verwende Plugin post_conv.pl");
        system("$config->{autoconv_dir}/filter/$singlepool/post_conv.pl $singlepool");
    }

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $singlepool: Benoetigte Zeit -> $resulttime");     
}

# Einladen in temporaere SQL-Datenbank

{
    my $atime = new Benchmark;
        
    $logger->info("### $singlepool: Temporaere Datenbank erzeugen");

    # Fuer das Einladen externer SQL-Daten mit 'load' wird das File_priv
    # fuer den Benutzer dbuser benoetigt

    system("$mysqladminexe drop   $singlepooltmp");
    system("$mysqladminexe create $singlepooltmp");
    
    $logger->info("### $singlepool: Datendefinition einlesen");
    
    system("$mysqlexe $singlepooltmp < $config->{'dbdesc_dir'}/mysql/pool.mysql");
    
    # Index entfernen
    $logger->info("### $singlepool: Index in temporaerer Datenbank entfernen");
    system("$mysqlexe $singlepooltmp < $rootdir/data/$singlepool/control_index_off.mysql");
    
    if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/post_index_off.pl"){
        $logger->info("### $singlepool: Verwende Plugin post_index_off.pl");
        system("$config->{autoconv_dir}/filter/$singlepool/post_index_off.pl $singlepooltmp");
    }
    
    # Einladen der Daten
    $logger->info("### $singlepool: Einladen der Daten in temporaere Datenbank");
    system("$mysqlexe $singlepooltmp < $rootdir/data/$singlepool/control.mysql");

    if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/post_dbload.pl"){
        $logger->info("### $singlepool: Verwende Plugin post_dbload.pl");
        system("$config->{autoconv_dir}/filter/$singlepool/post_dbload.pl $singlepooltmp");
    }

    # Index setzen
    $logger->info("### $singlepool: Index in temporaerer Datenbank aufbauen");
    system("$mysqlexe $singlepooltmp < $rootdir/data/$singlepool/control_index_on.mysql");

    if ($singlepool && -e "$config->{autoconv_dir}/filter/$singlepool/post_index_on.pl"){
        $logger->info("### $singlepool: Verwende Plugin post_index_on.pl");
        system("$config->{autoconv_dir}/filter/$singlepool/post_index_on.pl $singlepooltmp");
    }

    # Tabellen Packen
    system("$config->{autoconv_dir}/filter/common/pack_data.pl $singlepooltmp");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $singlepool: Benoetigte Zeit -> $resulttime");     
}
 
# Tabellen aus temporaerer Datenbank in finale Datenbank verschieben

{
    my $atime = new Benchmark;

    $logger->info("### $singlepool: Tabellen aus temporaerer Datenbank in finale Datenbank verschieben");

    system("$mysqladminexe drop $singlepool ");
    system("$mysqladminexe create $singlepool ");
    #system("mv /var/lib/mysql/$singlepooltmp /var/lib/mysql/$singlepool");


    open(COPYIN, "echo \"show tables;\" | $mysqlexe -s $singlepooltmp |");
    open(COPYOUT,"| $mysqlexe -s $singlepooltmp |");

    while (<COPYIN>){
        chomp();
    print COPYOUT <<"ENDE";
rename table $singlepooltmp.$_ to $singlepool.$_ ;
ENDE
    }

    close(COPYIN);
    close(COPYOUT);

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $singlepool: Benoetigte Zeit -> $resulttime");     
}

# Titelanzahl in Datenbank festhalten

{
    $logger->info("### $singlepool: Updating Titcount");    
    system("$config->{'base_dir'}/bin/updatetitcount.pl --single-pool=$singlepool");
}

# Daten aus SQL-Datenbank durch Suchmachinenkonnektor extrahieren und
# Suchmaschinen-Index aufbauen

{
    my $atime = new Benchmark;

    $logger->info("### $singlepool: Importing data into searchengine");   
    system("cd $rootdir/data/$singlepool/ ; $config->{'base_dir'}/conv/file2xapian.pl --with-fields --single-pool=$singlepool");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $singlepool: Benoetigte Zeit -> $resulttime");     
}

CLEANUP:

$logger->info("### $singlepool: Cleanup");

system("$mysqladminexe drop   $singlepooltmp");
system("rm $rootdir/data/$singlepool/*");

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("### $singlepool: Gesamte Zeit -> $resulttime");

sub print_help {
    print << "ENDHELP";
autoconv-sikis.pl - Automatische Konvertierung von SIKIS-Daten

   Optionen:
   -help                 : Diese Informationsseite
       
   -sync                 : Hole Pool automatisch ueber das Netz
   --single-pool=...     : Angegebenen Datenpool verwenden

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

