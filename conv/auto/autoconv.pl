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
#  Dieses File ist (C) 1997-2010 Oliver Flimm <flimm@openbib.org>
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

my ($database,$sync,$genmex,$help,$logfile,$loglevel);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
	    "sync"            => \$sync,
            "gen-mex"         => \$genmex,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile  = ($logfile)?$logfile:'/var/log/openbib/autoconv.log';
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

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";

my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $meta2sqlexe   = "$config->{'conv_dir'}/meta2sql.pl";
my $meta2mexexe   = "$config->{'conv_dir'}/meta2mex.pl";
my $meta2waisexe  = "$config->{'conv_dir'}/meta2wais.pl";
my $wais2sqlexe   = "$config->{'conv_dir'}/wais2searchSQL.pl";
my $mysqlexe      = "/usr/bin/mysql -u $config->{'dbuser'} --password=$config->{'dbpasswd'} -f";
my $mysqladminexe = "/usr/bin/mysqladmin -u $config->{'dbuser'} --password=$config->{'dbpasswd'} -f";

if (!$database){
  $logger->fatal("Kein Katalog mit --database= ausgewaehlt");
  exit;
}

my $databasetmp=$database."tmp";

if (!$config->db_exists($database)){
  $logger->fatal("Pool $database existiert nicht");
  exit;
}

my $dboptions_ref = $config->get_dboptions($database);

my $dbh           = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
    or $logger->error_die($DBI::errstr);


$logger->info("### POOL $database");

my $atime = new Benchmark;

# Aktuelle Pool-Version von entfernter Quelle uebertragen

{
    if ($sync){
        my $atime = new Benchmark;
        
        if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_remote.pl"){
            $logger->info("### $database: Verwende Plugin pre_remote.pl");
            system("$config->{autoconv_dir}/filter/$database/pre_remote.pl $database");
        }
    
        if ($database && -e "$config->{autoconv_dir}/filter/$database/alt_remote.pl"){
            $logger->info("### $database: Verwende Plugin alt_remote.pl");
            system("$config->{autoconv_dir}/filter/$database/alt_remote.pl $database");
        }
        else {
            $logger->info("### $database: Hole Exportdateien mit wget von $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/");
                        
            my $httpauthstring="";
            if ($dboptions_ref->{protocol} eq "http" && $dboptions_ref->{remoteuser} ne "" && $dboptions_ref->{remotepasswd} ne ""){
                $httpauthstring=" --http-user=$dboptions_ref->{remoteuser} --http-passwd=$dboptions_ref->{remotepasswd}";
            }
            
            system("cd $pooldir/$database ; rm unload.*");
            system("$wgetexe $httpauthstring -P $pooldir/$database/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{titfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$database/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{autfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$database/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{korfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$database/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{swtfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$database/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{notfilename} > /dev/null 2>&1 ");
            system("$wgetexe $httpauthstring -P $pooldir/$database/ $dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{mexfilename} > /dev/null 2>&1 ");
        }

    
        if ($database && -e "$config->{autoconv_dir}/filter/$database/post_remote.pl"){
            $logger->info("### $database: Verwende Plugin post_remote.pl");
            system("$config->{autoconv_dir}/filter/$database/post_remote.pl $database");
        }
        
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $logger->info("### $database: Benoetigte Zeit -> $resulttime");
    }
}

# Entpacken der Pool-Daten in separates Arbeits-Verzeichnis unter 'data'

{    
    my $atime = new Benchmark;

    $logger->info("### $database: Entpacken der Pool-Daten");

    if (! -d "$rootdir/data/$database"){
        system("mkdir $rootdir/data/$database");
    }
    
    if ($genmex){
        $logger->info("### $database: Erzeuge Exemplardaten aus Titeldaten");
        system("cd $pooldir/$database/ ; zcat $dboptions_ref->{titfilename} | $meta2mexexe");
    }
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_move.pl"){
        $logger->info("### $database: Verwende Plugin pre_move.pl");
        system("$config->{autoconv_dir}/filter/$database/pre_move.pl $database");
    }
    
    system("rm $rootdir/data/$database/*");
    system("/bin/gzip -dc $pooldir/$database/$dboptions_ref->{titfilename} > $rootdir/data/$database/tit.exp");
    system("/bin/gzip -dc $pooldir/$database/$dboptions_ref->{autfilename} > $rootdir/data/$database/aut.exp");
    system("/bin/gzip -dc $pooldir/$database/$dboptions_ref->{swtfilename} > $rootdir/data/$database/swt.exp");
    system("/bin/gzip -dc $pooldir/$database/$dboptions_ref->{notfilename} > $rootdir/data/$database/not.exp");
    system("/bin/gzip -dc $pooldir/$database/$dboptions_ref->{korfilename} > $rootdir/data/$database/kor.exp");
    system("/bin/gzip -dc $pooldir/$database/$dboptions_ref->{mexfilename} > $rootdir/data/$database/mex.exp");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");

    if (! -e "$rootdir/data/$database/tit.exp" || ! -s "$rootdir/data/$database/tit.exp"){
        $logger->error("### $database: Keine Daten vorhanden");

        goto CLEANUP;
    }
}
    
# Konvertierung aus dem Meta- in das SQL-Einladeformat

{
    my $atime = new Benchmark;

    # Konvertierung Exportdateien -> SQL
    if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_conv.pl"){
        $logger->info("### $database: Verwende Plugin pre_conv.pl");
        system("$config->{autoconv_dir}/filter/$database/pre_conv.pl $database");
    }

    $logger->info("### $database: Konvertierung Exportdateien -> SQL");

    if ($database && -e "$config->{autoconv_dir}/filter/$database/alt_conv.pl"){
        $logger->info("### $database: Verwende Plugin alt_conv.pl");
        system("$config->{autoconv_dir}/filter/$database/alt_conv.pl $database");
    }
    else {
        system("cd $rootdir/data/$database ; $meta2sqlexe --loglevel=$loglevel -add-superpers -add-mediatype --database=$database");
    }
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_conv.pl"){
        $logger->info("### $database: Verwende Plugin post_conv.pl");
        system("$config->{autoconv_dir}/filter/$database/post_conv.pl $database");
    }

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Einladen in temporaere SQL-Datenbank

{
    my $atime = new Benchmark;
        
    $logger->info("### $database: Temporaere Datenbank erzeugen");

    # Fuer das Einladen externer SQL-Daten mit 'load' wird das File_priv
    # fuer den Benutzer dbuser benoetigt

    system("$mysqladminexe drop   $databasetmp");
    system("$mysqladminexe create $databasetmp");
    
    $logger->info("### $database: Datendefinition einlesen");
    
    system("$mysqlexe $databasetmp < $config->{'dbdesc_dir'}/mysql/pool.mysql");
    
    # Index entfernen
    $logger->info("### $database: Index in temporaerer Datenbank entfernen");
    system("$mysqlexe $databasetmp < $rootdir/data/$database/control_index_off.mysql");
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_index_off.pl"){
        $logger->info("### $database: Verwende Plugin post_index_off.pl");
        system("$config->{autoconv_dir}/filter/$database/post_index_off.pl $databasetmp");
    }
    
    # Einladen der Daten
    $logger->info("### $database: Einladen der Daten in temporaere Datenbank");
    system("$mysqlexe $databasetmp < $rootdir/data/$database/control.mysql");

    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_dbload.pl"){
        $logger->info("### $database: Verwende Plugin post_dbload.pl");
        system("$config->{autoconv_dir}/filter/$database/post_dbload.pl $databasetmp");
    }

    # Index setzen
    $logger->info("### $database: Index in temporaerer Datenbank aufbauen");
    system("$mysqlexe $databasetmp < $rootdir/data/$database/control_index_on.mysql");

    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_index_on.pl"){
        $logger->info("### $database: Verwende Plugin post_index_on.pl");
        system("$config->{autoconv_dir}/filter/$database/post_index_on.pl $databasetmp");
    }

    # Tabellen Packen
    system("$config->{autoconv_dir}/filter/common/pack_data.pl $databasetmp");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Potentiell Blockierende Prozesse entfernen

{
    $logger->info("### $database: Marodierende Processe auf der Datenbank toeten");

    my $request=$dbh->prepare("show processlist");
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $id    = $result->{Id}    || 'n/a';
        my $db    = $result->{db}    || 'n/a';
        my $time  = $result->{Time}  || 'n/a';
        my $state = $result->{State} || 'n/a';
        my $info  = $result->{Info}  || 'n/a';
        
        next unless ($db eq $database);

        my $request2=$dbh->prepare("kill ?");
        $request2->execute($id);
        $logger->error("Killed process Id: $id - Db: $db - Time: $time - State: $state - Info: $info");
    }
}

# Tabellen aus temporaerer Datenbank in finale Datenbank verschieben

{
    my $atime = new Benchmark;

    $logger->info("### $database: Tabellen aus temporaerer Datenbank in finale Datenbank verschieben");

    system("$mysqladminexe drop $database ");
    system("$mysqladminexe create $database ");
    #system("mv /var/lib/mysql/$databasetmp /var/lib/mysql/$database");


    open(COPYIN, "echo \"show tables;\" | $mysqlexe -s $databasetmp |");
    open(COPYOUT,"| $mysqlexe -s $databasetmp |");

    while (<COPYIN>){
        chomp();
    print COPYOUT <<"ENDE";
rename table $databasetmp.$_ to $database.$_ ;
ENDE
    }

    close(COPYIN);
    close(COPYOUT);

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Titelanzahl in Datenbank festhalten

{
    $logger->info("### $database: Updating Titcount");    
    system("$config->{'base_dir'}/bin/updatetitcount.pl --database=$database");
}

# Daten aus SQL-Datenbank durch Suchmachinenkonnektor extrahieren und
# Suchmaschinen-Index aufbauen

{
    my $atime = new Benchmark;

    $logger->info("### $database: Importing data into searchengine");   
    system("cd $rootdir/data/$database/ ; $config->{'base_dir'}/conv/file2xapian.pl -with-fields -with-sorting -with-positions --database=$database");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

CLEANUP:

$logger->info("### $database: Cleanup");

system("$mysqladminexe drop   $databasetmp");
#system("rm $rootdir/data/$database/*");

if ($database && -e "$config->{autoconv_dir}/filter/$database/post_cleanup.pl"){
    $logger->info("### $database: Verwende Plugin post_cleanup.pl");
    system("$config->{autoconv_dir}/filter/$database/post_cleanup.pl $database");
}

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("### $database: Gesamte Zeit -> $resulttime");

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

