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
#  Dieses File ist (C) 1997-2012 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Catalog;

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
my $pgsqlexe      = "/usr/bin/psql -U $config->{'dbuser'} ";

if (!$database){
  $logger->fatal("Kein Katalog mit --database= ausgewaehlt");
  exit;
}

my $databasetmp=$database."tmp";

if (!$config->db_exists($database)){
  $logger->fatal("Pool $database existiert nicht");
  exit;
}

my $dbinfo = $config->get_databaseinfo->search_rs({ dbname => $database })->single;

$logger->info("### POOL $database");

my $atime = new Benchmark;

# Aktuelle Pool-Version von entfernter Quelle uebertragen

my $postgresdbh = DBI->connect("DBI:Pg:dbname=postgres;host=localhost;port=5432", $config->{dbuser}, $config->{dbpasswd}) or die "could not connect to local postgres database";

{
    if (! -d "$pooldir/$database"){
        system("mkdir $pooldir/$database");
    }

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

            system("ls -l $pooldir/$database/");
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
        system("cd $pooldir/$database/ ; zcat meta.title.gz | $meta2mexexe");
    }
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_move.pl"){
        $logger->info("### $database: Verwende Plugin pre_move.pl");
        system("$config->{autoconv_dir}/filter/$database/pre_move.pl $database");
    }
    
    system("rm $rootdir/data/$database/*");
    system("/bin/gzip -dc $pooldir/$database/meta.title.gz > $rootdir/data/$database/meta.title");
    system("/bin/gzip -dc $pooldir/$database/meta.person.gz > $rootdir/data/$database/meta.person");
    system("/bin/gzip -dc $pooldir/$database/meta.subject.gz > $rootdir/data/$database/meta.subject");
    system("/bin/gzip -dc $pooldir/$database/meta.classification.gz > $rootdir/data/$database/meta.classification");
    system("/bin/gzip -dc $pooldir/$database/meta.corporatebody.gz > $rootdir/data/$database/meta.corporatebody");
    system("/bin/gzip -dc $pooldir/$database/meta.holding.gz > $rootdir/data/$database/meta.holding");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");

    if (! -e "$rootdir/data/$database/meta.title" || ! -s "$rootdir/data/$database/meta.title"){
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

    # Temporaer Zugriffspassword setzen
    system("echo \"*:*:*:$config->{'dbuser'}:$config->{'dbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
    
    system("/usr/bin/dropdb -U $config->{'dbuser'} $databasetmp");
    system("/usr/bin/createdb -U $config->{'dbuser'} -E UTF-8 -O $config->{'dbuser'} $databasetmp");
    
    $logger->info("### $database: Datendefinition einlesen");
    
    system("$pgsqlexe -f '$config->{'dbdesc_dir'}/postgresql/pool.sql' $databasetmp");

    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_index_off.pl"){
        $logger->info("### $database: Verwende Plugin post_index_off.pl");
        system("$config->{autoconv_dir}/filter/$database/post_index_off.pl $databasetmp");
    }
    

    # Einladen der Daten
    $logger->info("### $database: Einladen der Daten in temporaere Datenbank");
    system("$pgsqlexe -f '$rootdir/data/$database/control.sql' $databasetmp");
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_dbload.pl"){
        $logger->info("### $database: Verwende Plugin post_dbload.pl");
        system("$config->{autoconv_dir}/filter/$database/post_dbload.pl $databasetmp");
    }

    # Index setzen
    $logger->info("### $database: Index in temporaerer Datenbank aufbauen");
    system("$pgsqlexe -f '$config->{'dbdesc_dir'}/postgresql/pool_create_index.sql' $databasetmp");
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_index_on.pl"){
        $logger->info("### $database: Verwende Plugin post_index_on.pl");
        system("$config->{autoconv_dir}/filter/$database/post_index_on.pl $databasetmp");
    }
    
    # Tabellen Packen
    if (-e "$config->{autoconv_dir}/filter/common/pack_data.pl"){
        system("$config->{autoconv_dir}/filter/common/pack_data.pl $databasetmp");
    }
    
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Suchmaschinen-Index aufbauen

{
    my $atime = new Benchmark;

    my $indexpathtmp = $config->{xapian_index_base_path}."/$databasetmp";
    $logger->info("### $database: Importing data into searchengine");   
    system("cd $rootdir/data/$database/ ; $config->{'base_dir'}/conv/file2xapian.pl -with-sorting -with-positions --database=$databasetmp --indexpath=$indexpathtmp");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Suchmaschinen-Index aufbauen - Elasticsearch

{
    my $atime = new Benchmark;

#    $logger->info("### $database: Importing data into elasticsearch");   
#    system("cd $rootdir/data/$database/ ; $config->{'base_dir'}/conv/file2elasticsearch.pl --database=$database > /dev/null 2>&1");

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

#    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Potentiell Blockierende Prozesse entfernen

# {
#     $logger->info("### $database: Marodierende Processe auf der Datenbank toeten");

#     my $request=$dbh->prepare("show processlist");
#     $request->execute();
    
#     while (my $result=$request->fetchrow_hashref){
#         my $id    = $result->{Id}    || 'n/a';
#         my $db    = $result->{db}    || 'n/a';
#         my $time  = $result->{Time}  || 'n/a';
#         my $state = $result->{State} || 'n/a';
#         my $info  = $result->{Info}  || 'n/a';
        
#         next unless ($db eq $database);

#         my $request2=$dbh->prepare("kill ?");
#         $request2->execute($id);
#         $logger->error("Killed process Id: $id - Db: $db - Time: $time - State: $state - Info: $info");
#     }
# }

my $loading_error = 0;

# Konsistenzcheck zwischen Einlade-Daten und eingeladenen Daten in der temporaeren Datenbank
{

    my $table_map_ref = {
        'Title'               => 'title',
        'TitleField'          => 'title_fields',
        'Person'              => 'person',
        'PersonField'         => 'person_fields',
        'Corporatebody'       => 'corporatebody',
        'CorporatebodyField'  => 'corporatebody_fields',
        'Subject'             => 'subject',
        'SubjectField'        => 'subject_fields',
        'Classification'      => 'classification',
        'ClassificationField' => 'classification_fields',
        'Holding'             => 'holding',
        'HoldingField'        => 'holding_fields',
        'TitlePerson'         => 'title_person',
        'TitleCorporatebody'  => 'title_corporatebody',
        'TitleClassification' => 'title_classification',
        'TitleSubject'        => 'title_subject',
        'TitleHolding'        => 'title_holding',
    };
    
    my $catalog = new OpenBib::Catalog($databasetmp);

    foreach my $resultset (keys %$table_map_ref){
        my $dumpfilename = "$config->{autoconv_dir}/data/$database/$table_map_ref->{$resultset}.dump";
        
        my $count_in_db = $catalog->{schema}->resultset($resultset)->count;
        my ($count_in_file) = `wc -l $dumpfilename` =~m/(\d+)\s+/;

        $loading_error = 1 unless ($count_in_db == $count_in_file);
    }

    
}

if ($loading_error){
    $logger->fatal("### $database: Problem beim Einladen. Exit.");
    $logger->fatal("### $database: Loesche temporaere Datenbank/Index.");

    $postgresdbh->do("drop database $databasetmp");

    system("rm $config->{xapian_index_base_path}/${databasetmp}/* ; rmdir $config->{xapian_index_base_path}/${databasetmp}");

    goto CLEANUP;
}
else {
    $logger->info("### $database: Daten fehlerfrei eingeladen.")
}

# Tabellen aus temporaerer Datenbank in finale Datenbank verschieben
{
    my $atime = new Benchmark;

    $logger->info("### $database: Tabellen aus temporaerer Datenbank in finale Datenbank verschieben");

    my $request = $postgresdbh->prepare("SELECT count(datname) AS dbcount FROM pg_database WHERE datname=?");
    $request->execute($database);
    
    my $result = $request->fetchrow_hashref;
    
    my $old_database_exists = $result->{dbcount};

    $postgresdbh->do("SELECT pg_terminate_backend(pg_stat_activity.procpid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$database'");

    if ($old_database_exists){
	$postgresdbh->do("ALTER database $database RENAME TO ${database}tmp2");
    }

    $postgresdbh->do("ALTER database $databasetmp RENAME TO $database");

    $logger->info("### $database: Temporaeren Suchindex aktivieren");

    if (-d "$config->{xapian_index_base_path}/$database"){
        system("mv $config->{xapian_index_base_path}/$database $config->{xapian_index_base_path}/${database}tmp2");
    }

    system("mv $config->{xapian_index_base_path}/$databasetmp $config->{xapian_index_base_path}/$database");

    if (-d "$config->{xapian_index_base_path}/${database}tmp2"){
        system("rm $config->{xapian_index_base_path}/${database}tmp2/* ; rmdir $config->{xapian_index_base_path}/${database}tmp2");
    }

    if ($old_database_exists){
	$postgresdbh->do("drop database ${database}tmp2");
    }

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

# ISBNs etc. zentral merken

{
    $logger->info("### $database: Updating All-ISBN table");    
    system("$config->{'base_dir'}/bin/update_all_isbn_table.pl --database=$database");
}

CLEANUP:

$logger->info("### $database: Cleanup");

# Temporaer Zugriffspassword setzen
system("rm ~/.pgpass ");

system("rm $rootdir/data/$database/*") unless ($database eq "openbib");

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

