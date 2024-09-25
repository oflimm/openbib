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
my $do_publish    = 0; # Soll dieses Skript auch das Publishing anstossen
    
my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $filename      = $dbinfo->titlefile;

my $use_api       = 0; # Use Alma API to get published data

my $use_join      = 1; # Combine several MARC21 files to pool.mrc

if ($use_api){
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $pool });
    
    my $api_key = $config->get('alma')->{'api_key'};
    
    my $jobid;
    
    # Job-ID fuer das Publishing bestimmen
    {
	my $url     = $config->get('alma')->{'api_baseurl'}."/conf/jobs?limit=100&offset=0&category=PUBLISHING&apikey=$api_key";
	
	my $api_result_ref = $ils->send_alma_api_call({ method => 'GET', url => $url });
	
	
	foreach my $job_ref (@{$api_result_ref->{'data'}{'job'}}){
	    if ($logger->is_debug){
		$logger->debug(YAML::Dump($job_ref));
	    }
	    
	    if ($job_ref->{'name'} =~m/^Publishing Platform Job UBK Export Full$/){
		$jobid = $job_ref->{'id'};
		last;
	    }
	}
	
	exit unless ($jobid);
    }
    
    # Job submitten (wegen Clusterbetrieb deaktiviert)
    my $instance_jobid;
    
    if ($do_publish){
	my $url     = $config->get('alma')->{'api_baseurl'}."/conf/jobs/$jobid?op=run&apikey=$api_key";
	
	my $data_ref = {
	};
	
	my $api_result_ref = $ils->send_alma_api_call({ method => 'POST', url => $url, post_data => $data_ref });
	
	if ($logger->is_debug){
	    $logger->debug(YAML::Dump($api_result_ref));
	}
	
	my $instance_job_url = $api_result_ref->{'data'}{'additional_info'}{'link'};
	
	($instance_jobid) = $instance_job_url =~m/instance\/.+?$/;
	
    }
    
    # Jobs des Publishing Profiles ueberwachen und warten bis sie fertig sind
    {
	
	# Startdatum
	my $start_date   = Date::Manip::ParseDate("now");
	
	# Maximal 12 Stunden warten
	my $cancel_date = Date::Manip::DateCalc($start_date,"+60hours");
	
	my $job_completed = 0;
	
	while (!$job_completed){		
	    # Fuer jeden Lauf Daten aktualisieren, sonst Probleme
	    # beim Datumswechsel waehrend eines Laufs
	    my $to_date   = Date::Manip::ParseDate("now");
	    my $from_date = Date::Manip::DateCalc($to_date,"-70hours");
	    
	    my $cancel = Date_Cmp($cancel_date,$to_date);
	    
	    # Notfall-Abbruch, falls zu lange gewartet ($cancel_date < $to_date)
	    if ($cancel < 0){
		if ($logger->is_error){
		    $logger->error("Abbruch. Warten auf vollendetes Publishing hat zu lange gedauert!");
		}
		
		exit 1; # Return mit Error-Code
	    }
	    
	    $from_date = Date::Manip::UnixDate($from_date,"%Y-%m-%d");
	    $to_date = Date::Manip::UnixDate($to_date,"%Y-%m-%d");
	    
	    my $url     = $config->get('alma')->{'api_baseurl'}."/conf/jobs/$jobid/instances?submit_date_from=$from_date&submit_date_to=$to_date&limit=100&status=COMPLETED_SUCCESS&apikey=$api_key";
	    
	    my $api_result_ref = $ils->send_alma_api_call({ method => 'GET', url => $url });
	    
	    if ($logger->is_debug){
		$logger->debug(YAML::Dump($api_result_ref));
	    }
	    
	    if ($api_result_ref->{'data'}{'total_record_count'} > 0){
		$job_completed = 1;
	    }
	    else {
		sleep 300;
	    }
	}
    }
    
    # Gepublishte Datei aus /alma/export kopieren
    {

	opendir(DIR, "/alma/export/");
	@FILES= readdir(DIR);
	
	my $lastdate    = 0;
	my $newest_file = "";
	
	foreach my $file(@FILES){
	    if ($file=~m/^ubkfull_(\d\d\d\d\d\d\d\d).*?_*.mrc/){
		my $thisdate = $1;
		if ($thisdate > $lastdate){
		    $lastdate    = $thisdate;
		    $newest_file = $file;
		}
	    }
	}
	
	print "### $pool: Kopieren von $newest_file to  $filename\n";    
	
	system("cp /alma/export/$newest_file $pooldir/$pool/$filename");    
    }
}

if ($use_join) {
    system("cd $filterdir/$pool/_common/alma ; ./join_ubk.sh");
}

system("cd $pooldir/$pool ; rm meta.* ");

print "### $pool: Umwandlung von $filename in MARC-in-JSON via yaz-marcdump\n";
system("cd $pooldir/$pool; yaz-marcdump -o json $filename  | jq -S -c . > ${filename}.processed");

print "### $pool: Konvertierung von $filename\n";
system("cd $pooldir/$pool; $marcjson2marcmetaexe --database=$pool -reduce-mem --inputfile=${filename}.processed --configfile=/opt/openbib/conf/uni.yml; gzip meta.*");

system("cd $pooldir/$pool ; rm pool.mrc.processed");
