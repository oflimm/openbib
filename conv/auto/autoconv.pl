#!/usr/bin/perl

#####################################################################
#
#  autoconv.pl
#
#  Automatische Konvertierung
#
#  Default: JSON-basiertes Metadaten-Format (intern MAB2 oder MARC21)
#
#  Andere : Ueber Plugins/Filter realisierbar
#
#  Dieses File ist (C) 1997-2025 Oliver Flimm <flimm@openbib.org>
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
use Date::Manip qw/DateCalc ParseDate Delta_Format UnixDate/;
use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Catalog;
use OpenBib::Catalog::Factory;
use OpenBib::Index::Factory;

my ($database,$sync,$scheme,$help,$keepfiles,$purgefirst,$sb,$logfile,$loglevel,$updatemaster,$incremental,$reducemem,$noauthorities,$noenrichment,$searchengineonly,$nosearchengine);

&GetOptions("database=s"        => \$database,
            "logfile=s"         => \$logfile,
            "loglevel=s"        => \$loglevel,
	    "sync"              => \$sync,
            "keep-files"        => \$keepfiles,
            "purge-first"       => \$purgefirst,
            "update-master"     => \$updatemaster,
            "incremental"       => \$incremental,
            "reduce-mem"        => \$reducemem,
            "scheme=s"          => \$scheme,
	    'no-enrichment'     => \$noenrichment,
	    'no-authorities'    => \$noauthorities,
            "no-searchengine"   => \$nosearchengine,	    
            "searchengine-only" => \$searchengineonly,
	    "search-backend=s"  => \$sb,
	    "help"              => \$help
	    );

if ($help){
    print_help();
}

$logfile  = ($logfile)?$logfile:"/var/log/openbib/autoconv/${database}.log";
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

if (!-d "/var/log/openbib/autoconv/"){
    mkdir "/var/log/openbib/autoconv/";
}

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config();

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $tooldir       = $config->{'tool_dir'};

my $wgetexe       = "/usr/bin/wget --auth-no-challenge -nH --cut-dirs=3";
my $meta2sqlexe   = "$config->{'conv_dir'}/meta2sql.pl";
my $enrichmetaexe = "$config->{'conv_dir'}/enrich_meta.pl";
my $meta2mexexe   = "$config->{'conv_dir'}/meta2mex.pl";
my $pgsqlexe      = "/usr/bin/psql -U $config->{'dbuser'} ";

my $duration_stage_collect = 0;
my $duration_stage_unpack = 0;
my $duration_stage_convert = 0;
my $duration_stage_load_db = 0;
my $duration_stage_load_index = 0;
my $duration_stage_load_authorities = 0;
my $duration_stage_switch = 0;
my $duration_stage_analyze = 0;
my $duration_stage_update_enrichment = 0;

if (!$database){
  $logger->fatal("Kein Katalog mit --database= ausgewaehlt");
  exit;
}

my $databasetmp  = ($incremental)?$database:$database."tmp" ;

my $authority    = $database."_authority";
my $authoritytmp = $authority."tmp";


if (!$config->db_exists($database)){
  $logger->fatal("Pool $database existiert nicht");
  exit;
}

my $pg_pid_column = ($config->get('postgresql_version') >= 90200)?'pid':'procpid';

my $dbinfo     = $config->get_databaseinfo->search_rs({ dbname => $database })->single;
my $serverinfo = $config->get_serverinfo->search_rs({ hostip => $config->{local_ip} })->single;

my $tstamp_start = ParseDate("now");

$logger->info("### POOL $database on ".UnixDate($tstamp_start,"%Y-%m-%d %T"));

my $atime = new Benchmark;

# Aktuelle Pool-Version von entfernter Quelle uebertragen

my $postgresdbh = DBI->connect("DBI:Pg:dbname=$config->{pgdbname};host=$config->{pgdbhost};port=$config->{pgdbport}", $config->{pgdbuser}, $config->{pgdbpasswd}) or die "could not connect to local postgres database";

{
    if (! -d "$pooldir/$database"){
        system("mkdir $pooldir/$database");
    }

    if ($sync){
        my $atime = new Benchmark;
	my $duration_stage_collect_start = ParseDate("now");
        
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

	my $duration_stage_collect_end = ParseDate("now");
	
	$duration_stage_collect = DateCalc($duration_stage_collect_start,$duration_stage_collect_end);
	$duration_stage_collect = Delta_Format($duration_stage_collect, 0,"%st seconds");

    }
}

# Entpacken der Pool-Daten in separates Arbeits-Verzeichnis unter 'data'

{    
    my $atime = new Benchmark;
    my $duration_stage_unpack_start = ParseDate("now");

    if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_unpack.pl"){
        $logger->info("### $database: Verwende Plugin pre_unpack.pl");
        system("$config->{autoconv_dir}/filter/$database/pre_unpack.pl $database");
    }

    $logger->info("### $database: Entpacken der Pool-Daten");

    if (! -d "$rootdir/data/$database"){
        system("mkdir $rootdir/data/$database");
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

    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_unpack.pl"){
        $logger->info("### $database: Verwende Plugin post_unpack.pl");
        system("$config->{autoconv_dir}/filter/$database/post_unpack.pl $database");
    }

    my $duration_stage_unpack_end = ParseDate("now");
    
    $duration_stage_unpack = DateCalc($duration_stage_unpack_start,$duration_stage_unpack_end);
    $duration_stage_unpack = Delta_Format($duration_stage_unpack, 0,"%st seconds");

    if (! -e "$rootdir/data/$database/meta.title" || ! -s "$rootdir/data/$database/meta.title"){
        $logger->error("### $database: Keine Daten vorhanden");

        goto CLEANUP;
    }
    
}

# Anreichern mit Daten aus der Anreicherungs-Datenbank

{
    my $atime = new Benchmark;
    my $duration_stage_enrich_start = ParseDate("now");

    # Anreicherung pre-Skript
    if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_enrich.pl"){
        $logger->info("### $database: Verwende Plugin pre_enrich.pl");
        system("$config->{autoconv_dir}/filter/$database/pre_enrich.pl $database");
    }

    # Alternative Anreicherung
    if ($database && -e "$config->{autoconv_dir}/filter/$database/alt_enrich.pl"){
        $logger->info("### $database: Verwende Plugin alt_enrich.pl");
        system("$config->{autoconv_dir}/filter/$database/alt_enrich.pl $database");
    }
    elsif (!$noenrichment) {

        my $cmd = "$enrichmetaexe --loglevel=$loglevel --database=$database --filename=meta.title";

        if ($keepfiles){
            $cmd.=" -keep-files";
        }
	
        if ($scheme){
            $cmd.=" --scheme=$scheme";
        }
	else {
	    my $dbschema = $config->get_databaseinfo->single({ dbname => $database })->schema ;
	    if ($dbschema eq "marc21"){
		$cmd.=" --scheme=marc";
	    }
	}
	
        $logger->info("Executing in $rootdir/data/$database : $cmd");
        
        system("cd $rootdir/data/$database ; $cmd");
    }    
    
    # Anreicherung post-Skript
    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_enrich.pl"){
        $logger->info("### $database: Verwende Plugin post_enrich.pl");
        system("$config->{autoconv_dir}/filter/$database/post_enrich.pl $database");
    }
}

# Konvertierung aus dem Meta- in das SQL-Einladeformat

{
    my $atime = new Benchmark;
    my $duration_stage_convert_start = ParseDate("now");

    # Konvertierung Exportdateien -> SQL
    if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_conv.pl"){
        $logger->info("### $database: Verwende Plugin pre_conv.pl");
        system("$config->{autoconv_dir}/filter/$database/pre_conv.pl $database");
    }

    # Kanonische und deterministische JSON-Serialisierung erzwingen
    system("$tooldir/canonify-json.pl < $rootdir/data/$database/meta.title > $rootdir/data/$database/meta.title.tmp ; mv -f $rootdir/data/$database/meta.title.tmp $rootdir/data/$database/meta.title");
    system("$tooldir/canonify-json.pl < $rootdir/data/$database/meta.person > $rootdir/data/$database/meta.person.tmp ; mv -f $rootdir/data/$database/meta.person.tmp $rootdir/data/$database/meta.person");
    system("$tooldir/canonify-json.pl < $rootdir/data/$database/meta.subject > $rootdir/data/$database/meta.subject.tmp ; mv -f $rootdir/data/$database/meta.subject.tmp $rootdir/data/$database/meta.subject");
    system("$tooldir/canonify-json.pl < $rootdir/data/$database/meta.classification > $rootdir/data/$database/meta.classification.tmp ; mv -f $rootdir/data/$database/meta.classification.tmp $rootdir/data/$database/meta.classification");
    system("$tooldir/canonify-json.pl < $rootdir/data/$database/meta.corporatebody > $rootdir/data/$database/meta.corporatebody.tmp ; mv -f $rootdir/data/$database/meta.corporatebody.tmp $rootdir/data/$database/meta.corporatebody");
    system("$tooldir/canonify-json.pl < $rootdir/data/$database/meta.holding > $rootdir/data/$database/meta.holding.tmp ; mv -f $rootdir/data/$database/meta.holding.tmp $rootdir/data/$database/meta.holding");

    system("cd $rootdir/data/$database ; gzip meta.*");
	    
    $logger->info("### $database: Konvertierung Exportdateien -> SQL");

    if ($database && -e "$config->{autoconv_dir}/filter/$database/alt_conv.pl"){
        $logger->info("### $database: Verwende Plugin alt_conv.pl");
        system("$config->{autoconv_dir}/filter/$database/alt_conv.pl $database");
    }
    else {

        my $cmd = "$meta2sqlexe --loglevel=$loglevel -add-superpers -add-mediatype --add-language --database=$database";

        if ($incremental){
            $cmd.=" -incremental";
        }

        if ($reducemem){
            $cmd.=" -reduce-mem";
        }

        if ($keepfiles){
            $cmd.=" -keep-files";
        }

        if ($scheme){
            $cmd.=" --scheme=$scheme";
        }
	else {
	    my $dbschema = $config->get_databaseinfo->single({ dbname => $database })->schema ;
	    if ($dbschema eq "marc21"){
		$cmd.=" --scheme=marc";
	    }
	}
	
        $logger->info("Executing in $rootdir/data/$database : $cmd");
        
        system("cd $rootdir/data/$database ; $cmd");
    }
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_conv.pl"){
        $logger->info("### $database: Verwende Plugin post_conv.pl");
        system("$config->{autoconv_dir}/filter/$database/post_conv.pl $database");
    }

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    my $duration_stage_convert_end = ParseDate("now");
    
    $duration_stage_convert = DateCalc($duration_stage_convert_start,$duration_stage_convert_end);
    $duration_stage_convert = Delta_Format($duration_stage_convert, 0,"%st seconds");

    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Einladen in temporaere SQL-Datenbank

unless ($searchengineonly){
    my $atime = new Benchmark;
    my $duration_stage_load_db_start = ParseDate("now");

    # Temporaer Zugriffspassword setzen
    system("echo \"*:*:*:$config->{'dbuser'}:$config->{'dbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");

    if ($purgefirst){
	$logger->info("### $database: Bestehende Datenbank $database loeschen");
	
	$postgresdbh->do("SELECT pg_terminate_backend(pg_stat_activity.$pg_pid_column) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$database'");
	
	system("/usr/bin/dropdb -U $config->{'dbuser'} $database");
    }

    $logger->info("### $database: Temporaere Datenbank erzeugen");
    
#     if ($incremental){
#         $postgresdbh->do("SELECT pg_terminate_backend(pg_stat_activity.$pg_pid_column) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$database'"); 
#         $postgresdbh->do("CREATE DATABASE $databasetmp with template $database owner ".$config->{'dbuser'}); 
#     }
#     else {
    if (!$incremental){
        $postgresdbh->do("SELECT pg_terminate_backend(pg_stat_activity.$pg_pid_column) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$databasetmp'");             

        system("/usr/bin/dropdb -U $config->{'dbuser'} $databasetmp");
        system("/usr/bin/createdb -U $config->{'dbuser'} -E UTF-8 -O $config->{'dbuser'} $databasetmp");
    
        $logger->info("### $database: Datendefinition einlesen");
        
        system("$pgsqlexe -f '$config->{'dbdesc_dir'}/postgresql/pool.sql' $databasetmp");
    }
    
    if (!$incremental && $database && -e "$config->{autoconv_dir}/filter/$database/post_index_off.pl"){
        $logger->info("### $database: Verwende Plugin post_index_off.pl");
        system("$config->{autoconv_dir}/filter/$database/post_index_off.pl $databasetmp");
    }

    # Einladen der Daten
    $logger->info("### $database: Einladen der Daten in temporaere Datenbank");
    system("$pgsqlexe -f '$rootdir/data/$database/control.sql' $databasetmp");
    
    if (!$incremental && $database && -e "$config->{autoconv_dir}/filter/$database/post_dbload.pl"){
        $logger->info("### $database: Verwende Plugin post_dbload.pl");
        system("$config->{autoconv_dir}/filter/$database/post_dbload.pl $databasetmp");
    }

    # Index setzen
    if (!$incremental){
        $logger->info("### $database: Index in temporaerer Datenbank aufbauen");
        system("$pgsqlexe -f '$config->{'dbdesc_dir'}/postgresql/pool_create_index.sql' $databasetmp");
    }
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_index_on.pl"){
        $logger->info("### $database: Verwende Plugin post_index_on.pl");
        system("$config->{autoconv_dir}/filter/$database/post_index_on.pl $databasetmp");
    }

    # Index setzen
    $logger->info("### $database: Sequenzen aktualisieren");    
    system("$pgsqlexe -f '$config->{'dbdesc_dir'}/postgresql/pool_update_sequences.sql' $databasetmp");

    # Tabellen Packen
    if (-e "$config->{autoconv_dir}/filter/common/pack_data.pl"){
        system("$config->{autoconv_dir}/filter/common/pack_data.pl $databasetmp");
    }
    
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    my $duration_stage_load_db_end = ParseDate("now");
    
    $duration_stage_load_db = DateCalc($duration_stage_load_db_start,$duration_stage_load_db_end);
    $duration_stage_load_db = Delta_Format($duration_stage_load_db, 0,"%st seconds");
    
    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

my $use_searchengine_ref = {};

# Zu nutzende lokale Suchmaschinen-Backends bestimmen
unless ($nosearchengine){
    if ($sb){
	$use_searchengine_ref->{$sb} = 1;
    }
    else {
	foreach my $searchengine (@{$config->get_searchengines_of_db($database)}){
	    $use_searchengine_ref->{$searchengine} = 1;
	}
    }

}

if ($logger->is_debug){
    $logger->debug(YAML::Dump($use_searchengine_ref));
}

# Suchmaschinen-Index fuer Titel aufbauen

my $es_indexer;
my $es_indexname;
my $es_new_indexname;
my $es_authority_indexname;
my $es_new_authority_indexname;

if ($use_searchengine_ref->{"elasticsearch"}){
    $es_indexer = OpenBib::Index::Factory->create_indexer({ sb => 'elasticsearch', database => $database, index_type => 'readwrite' });

    $es_indexname = $es_indexer->get_aliased_index($database);
    $es_authority_indexname = $es_indexer->get_aliased_index("${database}_authority");
		
    $es_new_indexname = ($es_indexname eq "${database}_a")?"${database}_b":"${database}_a";
    $es_new_authority_indexname = ($es_authority_indexname eq "${database}_authority_a")?"${database}_authority_b":"${database}_authority_a";
}

{
    my $atime = new Benchmark;
    my $duration_stage_load_index_start = ParseDate("now");
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/pre_searchengine.pl"){
	$logger->info("### $database: Verwende Plugin pre_searchengine.pl");
	system("$config->{autoconv_dir}/filter/$database/pre_searchengine.pl $database");
    }
    
    if ($database && -e "$config->{autoconv_dir}/filter/$database/alt_searchengine.pl"){
	$logger->info("### $database: Verwende Plugin alt_searchengine.pl");
	system("$config->{autoconv_dir}/filter/$database/alt_searchengine.pl $database");
    }
    else {

	my $num_searchengines = keys %$use_searchengine_ref;

	if ($purgefirst && $use_searchengine_ref->{"xapian"}){
	    $logger->info("### $database: Purging Xapian index");
	    system("rm $config->{xapian_index_base_path}/${database}/* ; rmdir $config->{xapian_index_base_path}/${database}");
	    
	}

	if ($purgefirst && $use_searchengine_ref->{"elasticsearch"}){
	    $logger->info("### $database: Purging ElasticSearch index");
		$es_indexer->drop_alias($database,$es_indexname);
		$es_indexer->drop_index($es_indexname);
	}	
	
	if ($num_searchengines == 1){
	    # Xapian
	    if ($use_searchengine_ref->{"xapian"}){
		
		my $indexpath    = $config->{xapian_index_base_path}."/$database";
		my $indexpathtmp = $config->{xapian_index_base_path}."/$databasetmp";
		
		$logger->info("### $database: Importing data into Xapian searchengine");
		
		my $cmd = "cd $rootdir/data/$database/ ; $config->{'base_dir'}/conv/file2xapian.pl --loglevel=$loglevel -with-sorting -with-positions --database=$databasetmp --indexpath=$indexpathtmp";
		
		if ($incremental){
		    $cmd.=" -incremental --deletefile=$rootdir/data/$database/title.delete";
		}
		
		$logger->info("Executing: $cmd");
		
		system($cmd);
	    }
	    
	    # Elasticsearch
	    if ($use_searchengine_ref->{"elasticsearch"}){		
		$logger->info("### $database: Importing data into ElasticSearch searchengine");
		
		my $cmd = "cd $rootdir/data/$database/ ; $config->{'base_dir'}/conv/file2elasticsearch.pl --database=$database";

		if ($incremental){
		    $cmd.=" --indexname=$es_indexname -incremental --deletefile=$rootdir/data/$database/title.delete";
		}
		else {
		    $cmd.=" --indexname=$es_new_indexname";
		}

		$logger->info("Executing: $cmd");
		
		system($cmd);
	    }
	    
	    # SOLR
	    if ($use_searchengine_ref->{"solr"}){
		$logger->info("### $database: Importing data into Solr searchengine");
		
		my $cmd = "cd $rootdir/data/$database/ ; $config->{'base_dir'}/conv/file2solr.pl --loglevel=$loglevel --database=$database";
		
		$logger->info("Executing: $cmd");
		
		system($cmd);
	    }
	}
	elsif ($num_searchengines > 1){
	    my $cmd = "$rootdir/bin/index-in-parallel.pl --loglevel=$loglevel --database=$database";
	    
	    $cmd.= " ".join(' ', map { $_ = "--search-backend=$_" } keys %$use_searchengine_ref);

	    if ($incremental){
		$cmd.= " -incremental";
		if ($use_searchengine_ref->{'xapian'}){
		    $cmd.= " --xapian-indexname=$database";
		}
		if ($use_searchengine_ref->{'elasticsearch'}){
		    $cmd.= " --es-indexname=$es_indexname";
		}
	    }
	    else {
		if ($use_searchengine_ref->{'xapian'}){
		    $cmd.= " --xapian-indexname=$databasetmp";
		}
		if ($use_searchengine_ref->{'elasticsearch'}){
		    $cmd.= " --es-indexname=$es_new_indexname";
		}
	    }
	    
	    $logger->info("Executing: $cmd");
	    
	    system($cmd);
	}
    }

    if ($database && -e "$config->{autoconv_dir}/filter/$database/post_searchengine.pl"){
	$logger->info("### $database: Verwende Plugin post_searchengine.pl");
	system("$config->{autoconv_dir}/filter/$database/post_searchengine.pl $database");
    }

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    my $duration_stage_load_index_end = ParseDate("now");
    
    $duration_stage_load_index = DateCalc($duration_stage_load_index_start,$duration_stage_load_index_end);
    $duration_stage_load_index = Delta_Format($duration_stage_load_index, 0,"%st seconds");
    
    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Suchmaschinen-Index fuer Normdaten aufbauen

unless ($noauthorities) {    
    my $atime = new Benchmark;
    my $duration_stage_load_authorities_start = ParseDate("now");

    if ($database && -e "$config->{autoconv_dir}/filter/$database/alt_searchengine_authority.pl"){
	$logger->info("### $database: Verwende Plugin alt_searchengine_authority.pl");
	system("$config->{autoconv_dir}/filter/$database/alt_searchengine_authority.pl $database");
    }
    else {
	my $num_searchengines = keys %$use_searchengine_ref;

	if ($purgefirst && $use_searchengine_ref->{"xapian"}){
	    $logger->info("### $database: Purging Xapian authority index");
	    system("rm $config->{xapian_index_base_path}/${authority}/* ; rmdir $config->{xapian_index_base_path}/${authority}");
	}

	if ($purgefirst && $use_searchengine_ref->{"elasticsearch"}){
	    $logger->info("### $database: Purging ElasticSearch authority index");
	    $es_indexer->drop_alias("${database}_authority",$es_authority_indexname);
	    $es_indexer->drop_index($es_authority_indexname);
	}	
	
	if ($num_searchengines == 1){
	
	    if ($use_searchengine_ref->{"xapian"}){
		my $authority_indexpathtmp = $config->{xapian_index_base_path}."/$authoritytmp";
		
		# Inkrementelle Aktualisierung der Normdatenindizes wird zunaechst nicht realisiert. Es werden immer anhand der aktuellen Daten alle Normdatenindizes neu erzeugt!!!
		# Zukuenftig kann die inkrementelle Aktualisierung jedoch implementiert werden
		
		$logger->info("### $database: Importing authority data into Xapian searchengine");
		
		my $cmd = "$config->{'base_dir'}/conv/authority2xapian.pl --loglevel=$loglevel -with-sorting -with-positions --database=$database --indexpath=$authority_indexpathtmp";
		
		$logger->info("Executing: $cmd");
		
		system($cmd);
	    }
	    
	    # Elasticsearch
	    if ($use_searchengine_ref->{"elasticsearch"}){
		$logger->info("### $database: Importing authority data into ElasticSearch searchengine");
		
		my $cmd = "$config->{'base_dir'}/conv/authority2elasticsearch.pl --loglevel=$loglevel -with-sorting --database=$database";
		
		$cmd.=" --indexname=$es_new_authority_indexname";
		
		$logger->info("Executing: $cmd");
		
		system($cmd);
		
	    }
	    
	    # SOLR
	    if ($use_searchengine_ref->{"solr"}){
		$logger->info("### $database: Importing authority data into SOLR searchengine currently not supported");
		$logger->info("### $database: Authority Data import to SOLR currently not supported");   
		#	    my $cmd = "$config->{'base_dir'}/conv/authority2solr.pl --loglevel=$loglevel -with-sorting --database=$database";
		#	    $logger->info("Executing: $cmd");
		
		#	    system($cmd);
	    }
	}
	elsif ($num_searchengines > 1){
	    my $cmd = "$rootdir/bin/index-in-parallel.pl --loglevel=$loglevel --database=$database -authority";
	    
	    $cmd.= " ".join(' ', map { $_ = "--search-backend=$_" } keys %$use_searchengine_ref);

	    # Keine Inkrementellen Updates
	    if ($use_searchengine_ref->{'xapian'}){
		$cmd.= " --xapian-indexname=$authoritytmp";
	    }
	    if ($use_searchengine_ref->{'elasticsearch'}){
		$cmd.= " --es-indexname=$es_new_authority_indexname";
	    }
	    
	    $logger->info("Executing: $cmd");
	    
	    system($cmd);
	}
    }

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    my $duration_stage_load_authorities_end = ParseDate("now");
    
    $duration_stage_load_authorities = DateCalc($duration_stage_load_authorities_start,$duration_stage_load_authorities_end);
    $duration_stage_load_authorities = Delta_Format($duration_stage_load_authorities, 0,"%st seconds");
    
    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
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
# Bei inkrementellen Updates wird auf der aktiven Datenbank aktualisiert. Daher ist kein Konsistenzcheck notwendig/moeglich

unless ($incremental || $searchengineonly){

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
    
    my $catalog = new OpenBib::Catalog({ database => $databasetmp });

    foreach my $resultset (keys %$table_map_ref){
        my $dumpfilename = "$config->{autoconv_dir}/data/$database/$table_map_ref->{$resultset}.dump.gz";
        
        my $count_in_db = $catalog->get_schema->resultset($resultset)->count;
        my ($count_in_file) = `zcat $dumpfilename | wc -l` =~m/(\d+)\s+/;

        if ($count_in_db != $count_in_file){
            $logger->fatal("Inkonsistenz Datenbank! Problem mit $resultset: $count_in_file in Datei / $count_in_db in Datenbank");
            $loading_error = 1;
        }
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
unless ($incremental || $searchengineonly){
    my $atime = new Benchmark;
    my $duration_stage_switch_start = ParseDate("now");

    $logger->info("### $database: Tabellen aus temporaerer Datenbank in finale Datenbank verschieben");

    my $request = $postgresdbh->prepare("SELECT count(datname) AS dbcount FROM pg_database WHERE datname=?");
    $request->execute($database);
    
    my $result = $request->fetchrow_hashref;
    
    my $old_database_exists = $result->{dbcount};

    $postgresdbh->do("SELECT pg_terminate_backend(pg_stat_activity.$pg_pid_column) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$database'");
    $postgresdbh->do("SELECT pg_terminate_backend(pg_stat_activity.$pg_pid_column) FROM pg_stat_activity WHERE pg_stat_activity.datname = '${database}tmp2'");

    if ($old_database_exists){
        $postgresdbh->do("DROP database ${database}tmp2");
	$postgresdbh->do("ALTER database $database RENAME TO ${database}tmp2");
    }

    $postgresdbh->do("SELECT pg_terminate_backend(pg_stat_activity.$pg_pid_column) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$databasetmp'");

    $postgresdbh->do("ALTER database $databasetmp RENAME TO $database");

    unless ($nosearchengine){
	$logger->info("### $database: Temporaeren Suchindex aktivieren");
	
	if ($database && -e "$config->{autoconv_dir}/filter/$database/alt_move_searchengine.pl"){
	    $logger->info("### $database: Verwende Plugin alt_move_searchengine.pl");
	    system("$config->{autoconv_dir}/filter/$database/alt_move_searchengine.pl $database");
	}
	else {
	    if ($use_searchengine_ref->{"xapian"}){
		if (-d "$config->{xapian_index_base_path}/${database}tmp2"){
		    system("rm $config->{xapian_index_base_path}/${database}tmp2/* ; rmdir $config->{xapian_index_base_path}/${database}tmp2");
		}
		
		if (-d "$config->{xapian_index_base_path}/$database"){
		    system("mv $config->{xapian_index_base_path}/$database $config->{xapian_index_base_path}/${database}tmp2");
		}
		
		system("mv $config->{xapian_index_base_path}/$databasetmp $config->{xapian_index_base_path}/$database");
		
		if (-d "$config->{xapian_index_base_path}/${database}tmp2"){
		    system("rm $config->{xapian_index_base_path}/${database}tmp2/* ; rmdir $config->{xapian_index_base_path}/${database}tmp2");
		}
	    }
	    
	    if ($use_searchengine_ref->{"elasticsearch"}){
		
		$es_indexer->drop_alias($database,$es_indexname) unless ($purgefirst);
		$es_indexer->create_alias($database,$es_new_indexname);		
		$es_indexer->drop_index($es_indexname) unless ($purgefirst);
	    }
	    
	}
	$logger->info("### $database: Temporaeren Normdaten-Suchindex aktivieren");
	
	if ($use_searchengine_ref->{"xapian"}){
	    if (-d "$config->{xapian_index_base_path}/${authority}tmp2"){
		system("rm $config->{xapian_index_base_path}/${authority}tmp2/* ; rmdir $config->{xapian_index_base_path}/${authority}tmp2");
	    }
	    
	    if (-d "$config->{xapian_index_base_path}/$authority"){
		system("mv $config->{xapian_index_base_path}/$authority $config->{xapian_index_base_path}/${authority}tmp2");
	    }
	    
	    system("mv $config->{xapian_index_base_path}/$authoritytmp $config->{xapian_index_base_path}/$authority");
	    
	    if (-d "$config->{xapian_index_base_path}/${authority}tmp2"){
		system("rm $config->{xapian_index_base_path}/${authority}tmp2/* ; rmdir $config->{xapian_index_base_path}/${authority}tmp2");
	    }
	}
	
	if ($use_searchengine_ref->{"elasticsearch"}){	    
	    $es_indexer->drop_alias("${database}_authority",$es_authority_indexname) unless ($purgefirst);
	    $es_indexer->create_alias("${database}_authority",$es_new_authority_indexname);
	    $es_indexer->drop_index($es_authority_indexname) unless ($purgefirst);
	}

    }
    
    if ($old_database_exists){
	$postgresdbh->do("drop database ${database}tmp2");
    }

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    my $duration_stage_switch_end = ParseDate("now");
    
    $duration_stage_switch = DateCalc($duration_stage_switch_start,$duration_stage_switch_end);
    $duration_stage_switch = Delta_Format($duration_stage_switch, 0,"%st seconds");
    
    $logger->info("### $database: Benoetigte Zeit -> $resulttime");     
}

# Titelanzahl in Datenbank festhalten

if ($updatemaster && !$searchengineonly){
    my $duration_stage_analyze_start = ParseDate("now");

    $logger->info("### $database: Updating Titcount");    
    system("$config->{'base_dir'}/bin/updatetitcount.pl --database=$database");

    $logger->info("### $database: Updating clouds");

    foreach my $thistype (qw/1 3 4 5 6 7 9/){
        system("$config->{'base_dir'}/bin/gen_metrics.pl --type=$thistype --database=$database");
    }

    my $duration_stage_analyze_end = ParseDate("now");
    
    $duration_stage_analyze = DateCalc($duration_stage_analyze_start,$duration_stage_analyze_end);
    $duration_stage_analyze = Delta_Format($duration_stage_analyze, 0,"%st seconds");
    
}

# ISBNs etc. zentral merken bei zentraler Anreicherungs-Datenbank

#if ($updatemaster){
#    $logger->info("### $database: Updating All-Titles table");    
#    system("$config->{'base_dir'}/bin/update_all_titles_table.pl --database=$database");
#}

unless ($searchengineonly){
    my $duration_stage_update_enrichment_start = ParseDate("now");

    # Ansonsten bei jedem Node
    my $cmd = "$config->{'base_dir'}/bin/update_all_titles_table.pl --database=$database -reduce-mem";

    if ($scheme){
	$cmd.=" --scheme=$scheme";
    }
    else {
	my $dbschema = $config->get_databaseinfo->single({ dbname => $database })->schema ;
	if ($dbschema eq "marc21"){
	    $cmd.=" --scheme=marc";
	}
    }
    
    $logger->info("### $database: Updating All-Titles table");
    system($cmd);
    
    my $duration_stage_update_enrichment_end = ParseDate("now");
    
    $duration_stage_update_enrichment = DateCalc($duration_stage_update_enrichment_start,$duration_stage_update_enrichment_end);
    $duration_stage_update_enrichment = Delta_Format($duration_stage_update_enrichment, 0,"%st seconds");

}

CLEANUP:

$logger->info("### $database: Cleanup");

# Temporaer Zugriffspassword setzen
# system("rm ~/.pgpass ");

system("rm $rootdir/data/$database/*") unless ($keepfiles);

if ($database && -e "$config->{autoconv_dir}/filter/$database/post_cleanup.pl"){
    $logger->info("### $database: Verwende Plugin post_cleanup.pl");
    system("$config->{autoconv_dir}/filter/$database/post_cleanup.pl $database");
}

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("### $database: Gesamte Zeit -> $resulttime");

my $tstamp_end = ParseDate("now");

my $duration = DateCalc($tstamp_start,$tstamp_end);

$duration=Delta_Format($duration, 0,"%st seconds");

if ($serverinfo && !$searchengineonly){
    $logger->info("### $database: Writing updatelog");
    
    my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database});
    
    my $counter = $catalog->get_bibliographic_counters;
    
    $counter->{dbid} = $dbinfo->id;
    $counter->{tstamp_start} = UnixDate($tstamp_start,"%Y-%m-%d %T");
    $counter->{duration} = $duration;
    $counter->{is_incremental} = (defined $incremental && $incremental)?1:0;
    $counter->{duration_stage_collect} = $duration_stage_collect;
    $counter->{duration_stage_unpack} = $duration_stage_unpack;
    $counter->{duration_stage_convert} = $duration_stage_convert;
    $counter->{duration_stage_load_db} = $duration_stage_load_db;
    $counter->{duration_stage_load_index} = $duration_stage_load_index;
    $counter->{duration_stage_load_authorities} = $duration_stage_load_authorities;
    $counter->{duration_stage_switch} = $duration_stage_switch;
    $counter->{duration_stage_analyze} = $duration_stage_analyze;
    $counter->{duration_stage_update_enrichment} = $duration_stage_update_enrichment;

    if ($use_searchengine_ref->{"xapian"}){
	my $index = OpenBib::Index::Factory->create_indexer({ sb => 'xapian', database => $database});
	$counter->{title_count_xapian} = $index->get_doccount;
    }
    else {
	$counter->{title_count_xapian} = undef;
    }
    
    if ($use_searchengine_ref->{"elasticsearch"}){
	my $index = OpenBib::Index::Factory->create_indexer({ sb => 'elasticsearch', database => $database});
	$counter->{title_count_es} = $index->get_doccount;
    }
    else {
	$counter->{title_count_es} = undef;
    }

    $logger->info("### $database: doc counts PSQL (".$counter->{title_count}.") / Xapian (".$counter->{title_count_xapian}.") / ES (".$counter->{title_count_es}.")");
    if ($logger->is_debug){
	$logger->debug(YAML::Dump($counter));
    }
    
    $serverinfo->updatelogs->create($counter);
}

sub print_help {
    print << "ENDHELP";
autoconv.pl - Automatisches Update eines Katalogs/Suchindex aus dem Metaformat

   Optionen:
   -help                 : Diese Informationsseite
       
   -sync                 : Hole Pool automatisch ueber das Netz
   --database=...        : Angegebenen Katalog verwenden
   --loglevel=[DEBUG|..] : Loglevel aendern
   --logfile=...         : Logdateinamen aendern
   -update-master        : Aktualisierung Titelzahl/ISBN-Vergabe in zentraler Datenbank
   -keep-files           : Temporaere Dateien in data-Verzeichnis nicht loeschen
   -purge-first          : Bestehende Datenbank und Suchindizes zu Beginn loeschen
   -reduce-mem           : Reduzierung des Speicherverbrauchs bei der Umwandlung
   -incremental          : Inkrementelles Update in der aktiven Datenbank/Suchindex

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

