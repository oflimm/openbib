#!/usr/bin/perl

#####################################################################
#
#  sync_locationinfo.pl
#
#  Aktualisierung der Standortinformationen via http von einem MediaWiki-Dump
#
#  Uebernahme der Web-Scraper-Routinen aus zmslibinfo2configdb.pl
#
#  Dieses File ist (C) 2017 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use OpenBib::Config;
use LWP::UserAgent ();
use Web::Scraper;
use Encode qw/decode_utf8 encode_utf8/;

our ($logfile,$loglevel,$isil,$baseurl);

&GetOptions(
    "isil=s"        => \$isil,
    "baseurl=s"     => \$baseurl,
    "logfile=s"     => \$logfile,
    "loglevel=s"    => \$loglevel,
    );

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/sync_bibinfo.log";
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

my $ua = LWP::UserAgent->new;

my $url = "$baseurl$isil.txt";

my $response = $ua->get($url);

unless ($response->is_success){
    $logger->error_die("Keine Daten unter $url abrufbar");
}

my $locinfo = $response->content;

my $s = scraper {
  process 'table.ZMSTable tr td ' => 'zeilen[]'   => 'HTML';
};

my $field_map_ref = {
    "Institution" => '10',
    'Adresse' => '20',
    'Gebäude' => '30',
    'Interaktiver Lageplan der Universität' => '40',
    'Gemeinsame Bibliothek' => '50',
    'Telefon' => '60',
    'Fax' => '70',
    'E-Mail' => '80',
    'Internet' => '90',
    'Auskunft / Bibliothekar(in)' => '100',
    'Öffnungszeiten' => '110',
    'Bestand Monografien'  => '120',
    'Bestand Zeitschriften'  => '130',        
    'Bestand Lfd. Zeitschriften' => '140',
    #'CDs / Digitale Medien' => '150',
    'Sonstige Bestandsangaben' => '160',
    'Besondere Sammelgebiete' => '170',
    'Art der Bibliothek' => '180',
    'Neuerwerbungslisten' => '190',
    #'Kopierer / Technische Ausstattung' => '200',
    #'Art der Vernetzung' => '260',
    #'DV-Ausstattung' => '210',
    #'Art des Systems' => '220',
    'Online-Katalogisierung' => '230',
    #'Online-Katalogisierung seit Erwerbungsjahr' => '235',
    #'Mitarbeit am KUG' => '240',
    'Sigel in ZDB' => '250',
    #'Bemerkung' => '270',
    'Geo-Koordinaten' => '280',
    'Weitere Kataloge' => '290',
};

my $r;
eval {
    $r = $s->scrape($locinfo);
};

my $location = $config->get_locationinfo_by_id($isil);

if ($location){
    
    my @inhalt = @{$r->{zeilen}};
    
    for (my $i=0;$i< $#inhalt;$i=$i+2){
        my ($field,$content);
	
        eval {
            $content  = decode_utf8($inhalt[$i+1]);
        };
        if ($@){
            $content = $inhalt[$i+1];
        }
	
        $field   = decode_utf8($inhalt[$i]);
        $content = decode_utf8($inhalt[$i+1]);

	#$field=~s/^\s*(.*?)\s*\n\s*$/$1/;
	
        my $num_field = $field_map_ref->{$field};

        if ($num_field){
	    my $old_field = $location->locationinfo_fields->search({ field => $num_field })->single;

	    my $old_content = $old_field->content;

	    if ($old_content ne $content){

		$logger->info("$isil: Updating field '$field' / '$num_field' with content '$content'");

		$location->locationinfo_fields->search({ field => $num_field })->delete;
		
		if ($num_field == 10){ # Institutsname
		    $logger->info("$isil: Updating description");
		    $location->update({description => $content});
		}
		
		$logger->info("$isil Deleting former content");
		
		my $fields_ref = [];
		push @$fields_ref, 
		{
		    field   => $num_field,
		    mult    => 1,
		    content => $content,
		};
		
		$logger->info("$isil: Writing new content for field $num_field: $content");
		
		$location->locationinfo_fields->populate($fields_ref);
	    }
	    else {
		$logger->info("$isil: Nothing to do for field 'field'");
	    }
        }
	else {
	    $logger->error("$isil: No numeric field number for '$field'");
	}

    }
    
}
