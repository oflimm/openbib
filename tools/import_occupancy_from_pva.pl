#!/usr/bin/perl

#####################################################################
#
#  import_occupancy_from_pva.pl
#
#  Import der Belegungsdaten anhand der Informationen aus der PVA
#  (PersonenVereinzelungsAnlage) der USB Koeln
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use Getopt::Long;
use OpenBib::Config;

use Date::Manip;
use Encode qw/decode_utf8 encode decode/;
use File::Find;
use File::Slurp;
use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS;
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$location,$basedir,$year,$month,$day,$logfile,$loglevel,$renderer);

&GetOptions(
    "help"       => \$help,
    "location=s" => \$location,
    "basedir=s"  => \$basedir,
    "year=s"     => \$year,
    "month=s"    => \$month,    
    "day=s"      => \$day,    
    "logfile=s"  => \$logfile,            
    "loglevel=s" => \$loglevel,            
    );

if ($help || !$basedir || !$year || !$month || !$day){
    print_help();
}

$location = ($location)?$location:"DE-38";
$loglevel  =($loglevel)?$loglevel:'INFO';

$logfile  =($logfile)?$logfile:'/var/log/openbib/import_occupancy_from_pva.log';

my $inputdir = "$basedir/$year/${year}_${month}_${day}";

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

our $peoplecount_ref = {};

$logger->debug("Processing directory $inputdir");

find(\&process_file, $inputdir);

my $config = new OpenBib::Config;

my $locationinfo = $config->get_locationinfo_by_id($location);

my @tstamps = sort keys %$peoplecount_ref;

if ($logger->is_debug){
    $logger->debug(YAML::Dump($peoplecount_ref));
    
    $logger->debug(YAML::Dump(\@tstamps));
}

my $min_tstamp = shift @tstamps;
my $max_tstamp = pop @tstamps;

$logger->debug("Min timestamp: $min_tstamp - Max timestamp: $max_tstamp");

if ($locationinfo){

    # Bisherige Timestamps zum Tag holen

    my $tstamps_done_ref = {};
    
    my $existing_timestamps = $locationinfo->locationinfo_occupancies->search(
	{
	    -and => [
		 tstamp => { '>=' => $min_tstamp },
		 tstamp => { '<=' => $max_tstamp },
		],
	},
	);

    while (my $this_timestamp = $existing_timestamps->next()){
	$tstamp_done_ref->{$this_timestamp->get_column('tstamp')} = 1;
    }
    
    foreach my $newtimestamp (keys %$peoplecount_ref){
	next if ($tstamp_done_ref->{$newtimestamp});

	my $new_ref = {
	    tstamp        => $newtimestamp,
	    num_entries   => $peoplecount_ref->{$newtimestamp}{'entries'},
	    num_exits     => $peoplecount_ref->{$newtimestamp}{'exits'},
	    num_occupancy => $peoplecount_ref->{$newtimestamp}{'occupancy'},
	};

	if ($logger->is_debug){
	    $logger->debug("Inserting ".YAML::Dump($new_ref));
	}
	
	$locationinfo->locationinfo_occupancies->create($new_ref);
    }
}

sub process_file {
    my $logger = get_logger();
    
    return unless ($File::Find::name=~/.csv$/);

    my $filename = $File::Find::name;

    $logger->debug("Processing $filename");

    my $csv = Text::CSV_XS->new({  'eol' => "\n",
				       'sep_char' => ';',
							   'binary' => 1,
				});
    
    open my $in,   "<",$filename;

    my @cols = ('type','utc_timestamp','count','other');
    my $row = {};
    $csv->bind_columns (\@{$row}{@cols});
    
    while ($csv->getline ($in)){
	my $type          = $row->{'type'};
	my $utc_timestamp = $row->{'utc_timestamp'};
	my ($count)       = $row->{'count'} =~m/^([-0-9]+?),00/;

	my $date = ParseDate($utc_timestamp); # Convert to localtime

	my $datelocal =  Date_ConvTZ($date,"UTC","Europe/Berlin");

	my $timestamp =  UnixDate($datelocal,"%Y-%m-%d %H:%M:%S");
	
	if ($type =~m/FW$/){
	    $peoplecount_ref->{$timestamp}{entries}=$count;
	}
	elsif ($type =~m/BW$/){
	    $peoplecount_ref->{$timestamp}{exits}=$count;
	}
	elsif ($type =~m/OC$/){
	    $peoplecount_ref->{$timestamp}{occupancy}=$count;
	}
    }

    close $in;
}

sub print_help {
    print << "ENDHELP";
import_occupancy_from_pva.pl - Import der Belegungsdaten anhand der Informationen aus der PVA

   Optionen:
   -help                 : Diese Informationsseite
       
   --location=           : Standort-Identifier fue den Daten existieren (default: DE-38)
   --basedir=            : Vollqualifizierter absoluter Basis-Pfad der PVA Export-CSV-Dateien
   --year=...            : Jahr
   --month=...           : Monat
   --day=...             : Tag

ENDHELP
    exit;
}

