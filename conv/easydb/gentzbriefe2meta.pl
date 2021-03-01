#!/usr/bin/perl

#####################################################################
#
#  gentzbriefe2meta.pl
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@ub.uni-koeln.de>
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

use strict;
use warnings;
use utf8;

use File::Slurp;
use Encode 'decode';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use JSON::XS;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;
use OpenBib::Catalog::Factory;

my ($logfile,$loglevel,$inputfile);

&GetOptions(
	    "inputfile=s"             => \$inputfile,
            "logfile=s"               => \$logfile,
            "loglevel=s"              => \$loglevel,
	    );

if (!$inputfile){
    print << "HELP";
gentzbriefe2meta.pl - Aufrufsyntax

    gentzbriefe2meta.pl --inputfile=xxx

      --inputfile=                 : Name der Eingabedatei

HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/gentzbriefe2meta.log';
$loglevel=($loglevel)?$loglevel:'INFO';

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

our $have_titleid_ref = {};

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

open(IN ,           "<:raw", $inputfile );

my $multcount_ref = {};

while (my $jsonline = <IN>){
    my $item_ref = decode_json($jsonline); 

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($item_ref));
    }
    
    my $letter_ref = $item_ref->{gentz_letter};
    
    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    if ($letter_ref->{contentdm_id}){
	$title_ref->{id} = $letter_ref->{contentdm_id};
    }
    else {
	$title_ref->{id} = $letter_ref->{_id};
    }

    my @senders = ();
    
    # Person
    if ($letter_ref->{sender}{_standard}{1}{text}{'de-DE'}){
	my $name = $letter_ref->{sender}{_standard}{1}{text}{'de-DE'};

	push @senders, $name;
	
	my ($person_id,$new)=OpenBib::Conv::Common::Util::get_person_id($name);
	
	my $mult = 1;
	
	if ($new){
	    
	    my $normitem_ref = {
		'fields' => {},
	    };
	    $normitem_ref->{id} = $person_id;
	    push @{$normitem_ref->{fields}{'0800'}}, {
		mult     => 1,
		subfield => '',
		content  => $name,
	    };
	    
	    print PERSON encode_json $normitem_ref, "\n";
	}
	
	my $new_category = "0100";
	
	push @{$title_ref->{fields}{$new_category}}, {
	    content    => $name,
	    mult       => $mult,
	    subfield   => '',
	    id         => $person_id,
	    supplement => '',
	};
	
	$mult++;
    }        

    my @recipients = ();
    
    # Koerperschaft
    foreach my $recipient_ref (@{$letter_ref->{'_nested:gentz_letter__recipients'}}){	
	my $name = $recipient_ref->{recipient}{_standard}{1}{text}{'de-DE'};

	push  @recipients, $name;
	
	my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($name);
	
	my $mult = 1;
	
	if ($new){
	    
	    my $normitem_ref = {
		'fields' => {},
	    };
	    
	    $normitem_ref->{id} = $corporatebody_id;
	    push @{$normitem_ref->{fields}{'0800'}}, {
		mult     => 1,
		subfield => '',
		content  => $name,
	    };
	    
	    print CORPORATEBODY encode_json $normitem_ref, "\n";
	}
	
	my $new_category = "0200";
	
	push @{$title_ref->{fields}{$new_category}}, {
	    content    => $name,
	    mult       => $mult,
	    subfield   => '',
	    id         => $corporatebody_id,
	    supplement => '',
	};
	
	$mult++;
    }        

    # EasyDB-Exportsatz in Feld Bemerkung (0600)

    push @{$title_ref->{fields}{'0600'}}, {
      content => $jsonline,
    };
        
    # Titel
    
    if ($letter_ref->{title}){
	push @{$title_ref->{fields}{'0331'}}, {
	    content => $letter_ref->{title},
	}
    }

    if ($letter_ref->{reference_publication_incipit}){
	push @{$title_ref->{fields}{'0335'}}, {
	    content => $letter_ref->{reference_publication_incipit},
	}
    }

    if ($letter_ref->{reference_publication}{_standard}{3}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0591'}}, {
	    content => $letter_ref->{reference_publication}{_standard}{3}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{reference_publication}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0590'}}, {
	    content => $letter_ref->{reference_publication}{_standard}{1}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{reference_publication_date}){
	push @{$title_ref->{fields}{'0595'}}, {
	    content => $letter_ref->{reference_publication_date},
	}
    }
    
    if ($letter_ref->{reference_publication_page}){
	push @{$title_ref->{fields}{'0433'}}, {
	    content => $letter_ref->{reference_publication_page},
	}
    }

    my $year = "";
    
    if ($letter_ref->{sent_date_original}){
	($year) = $letter_ref->{sent_date_original} =~m/(\d\d\d\d)/;
	
	push @{$title_ref->{fields}{'0424'}}, {
	    content => $letter_ref->{sent_date_original},
	}
    }

    if ($year || $letter_ref->{sent_date_year}){
	$year = ($letter_ref->{sent_date_year})?$letter_ref->{sent_date_year}:$year;
	
	push @{$title_ref->{fields}{'0425'}}, {
	    content => $year,
	}
    }

    if ($letter_ref->{sent_location_normalized}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0410'}}, {
	    content => $letter_ref->{sent_location_normalized}{_standard}{1}{text}{'de-DE'},
	}
    }
    
    if ($letter_ref->{format_size}){
	push @{$title_ref->{fields}{'0433'}}, {
	    content => $letter_ref->{format_size},
	}
    }

    if ($letter_ref->{language}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0015'}}, {
	    content => $letter_ref->{language}{_standard}{1}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{archive}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0412'}}, {
	    content => $letter_ref->{archive}{_standard}{1}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{provenance}){
	push @{$title_ref->{fields}{'1664'}}, {
	    content => $letter_ref->{provenance},
	}
    }

    # Auswertung Kategorie 'Mit Inhaltsrepraesentation'
    {
	
	my $is_inhalt_volltext = 0;
	my $is_inhalt_analog = 0;
	
	# Kategorie Mit Inhaltsrepraesentation: Volltext
	if (@{$letter_ref->{'_nested:gentz_letter__transcriptions'}}){
	    $is_inhalt_volltext = 1;
	}
	
	# Kategorie Mit Inhaltsrepraesentation: analog transkribiert
	if ($letter_ref->{'transcription_type'}){
	    eval {
		if ($letter_ref->{transcription_type}{_standard}{1}{text}{text}{'de-DE'} eq "Handschrift" || $letter_ref->{transcription_type}{_standard}{1}{text}{text}{'de-DE'} eq "Schreibmaschine" ){
		    $is_inhalt_analog = 1;
		}
	    };
	}

	# 0517: Angaben zum Inhalt
	if ($is_inhalt_volltext){
	    push @{$title_ref->{fields}{'0517'}}, {
		content => 'Volltext',
	    }
	}
	if ($is_inhalt_analog){
	    push @{$title_ref->{fields}{'0517'}}, {
		content => 'Analog transkribiert',
	    }
	}
    }
    
    # Auswergung Kategorie 'Kopie Original'
    {

	my $is_papierkopie_usb = 0;
	my $is_mikrofilm_digitalisiert = 0;
	my $is_digitalisat = 0;
	
	# Todo: Im Export noch keine Inhalte zum Auswerten von is_digitalisat vorhanden!
	
	eval {
	    if ($letter_ref->{'hardcopy_herterich'}{_standard}{1}{text}{'de-DE'} eq "Papier"){
		$is_papierkopie_usb = 1;
	    }
	    elsif ($letter_ref->{'hardcopy_herterich'}{_standard}{1}{text}{'de-DE'} eq "Mikrofilm (digitalisiert)"){
		$is_mikrofilm_digitalisiert = 1;
	    }
	};
	foreach my $herterich_record_ref (@{$letter_ref->{'_nested:gentz_letter__records_collection_herterich'}}){
	    
	    eval {
		if ($herterich_record_ref->{collection_herterich_type}{_standard}{1}{text}{'de-DE'} eq "Aktenordner"){
		    $is_papierkopie_usb = 1;
		}
		elsif ($herterich_record_ref->{collection_herterich_type}{_standard}{1}{text}{'de-DE'} eq "Mikrofilm"){
		    $is_mikrofilm_digitalisiert = 1;
		}
	    }
	}

	# 0334: Material
	if ($is_papierkopie_usb){
	    push @{$title_ref->{fields}{'0334'}}, {
		content => 'Papierkopie (USB)',
	    }
	}
	if ($is_mikrofilm_digitalisiert){
	    push @{$title_ref->{fields}{'0334'}}, {
		content => 'Mikrofilm (digitalisiert)',
	    }
	}
	
    }


    # Auswertung Kategorie 'Sammlung Herterich'
    {

	my $is_herterich_ungedruckt = 0;
	my $is_herterich_gedruckt = 0;
	my $is_herterich_archiv = 0;
	
	eval {
	    if ($letter_ref->{archive}{_standard}{1}{text}{'de-DE'}){
		$is_herterich_archiv = 1;
	    }

	    if (! defined $letter_ref->{reference_publication}{_standard}{1}{text}{'de-DE'} && ! @${$letter_ref->{'_nested:gentz_letter__doublets'}}){
		$is_herterich_ungedruckt = 1;
	    }
	    if ($letter_ref->{reference_publication}{_standard}{1}{text}{'de-DE'} || @${$letter_ref->{'_nested:gentz_letter__doublets'}}){
		$is_herterich_gedruckt = 1;
	    }	    
	    
	};

	# 4700: Sammlungsschwerpunkt
	if ($is_herterich_ungedruckt){
	    push @{$title_ref->{fields}{'4700'}}, {
		content => 'Ungedruckt',
	    }
	}
	if ($is_herterich_gedruckt){
	    push @{$title_ref->{fields}{'4700'}}, {
		content => 'Gedruckt',
	    }
	}
	if ($is_herterich_archiv){
	    push @{$title_ref->{fields}{'4700'}}, {
		content => 'Archiv',
	    }
	}
	
    }

    # Auswertung Kategorie 'Druckpublikationen'
    {

	my $is_druck_mehrfach = 0;
	my $is_druck_archiv = 0;
	
	eval {
	    if ($letter_ref->{archive}{_standard}{1}{text}{'de-DE'}){
		$is_druck_archiv = 1;
	    }

	    if (@${$letter_ref->{'_nested:gentz_letter__doublets'}}){
		$is_druck_mehrfach = 1;
	    }	    
	    
	};

	# 0434: Sonstige Angaben
	if ($is_druck_mehrfach){
	    push @{$title_ref->{fields}{'0434'}}, {
		content => 'Mehrfach gedruckt',
	    }
	}
	if ($is_druck_archiv){
	    push @{$title_ref->{fields}{'0434'}}, {
		content => 'Archiv',
	    }
	}
	
    }
    
    my $is_digital = 0;
    
    # URLs

    foreach my $transcription_ref (@{$letter_ref->{'_nested:gentz_letter__transcriptions'}}){

	if ($transcription_ref->{transcription_fulltext}){
	    push @{$title_ref->{fields}{'6053'}}, {
		mult    => 1,
		content => $transcription_ref->{'transcription_fulltext'},
	    }
	}
	

	# URLs
	foreach my $file_ref (@{$transcription_ref->{transcription_file}}){

	    # Volles Bild zum Download
	    if ($file_ref->{versions}{original}{url}){
		push @{$title_ref->{fields}{'0662'}}, {
		    content => $file_ref->{versions}{original}{download_url},
		};
		$is_digital = 1;
	    }

	    # Thumbnail
	    if ($file_ref->{versions}{small}{url}){
		push @{$title_ref->{fields}{'2662'}}, {
		    content => $file_ref->{versions}{small}{url},
		};
		$is_digital = 1;
	    }	    
	}
    }

    if ($is_digital){
	push @{$title_ref->{fields}{'4400'}}, {
	    content  => 'online',
	    mult     => 1,
	    subfield => '',
	}
    }


    my $mediatype = "";

    foreach my $sender (@senders){
	if ($sender eq "Friedrich Gentz"){
	    $mediatype = "Briefe von Gentz";
	}
    }

    foreach my $recipient (@recipients){
	if ($recipient eq "Friedrich Gentz"){
	    $mediatype = "Briefe an Gentz";
	}
    }

    if (!$mediatype){
	$mediatype = "Briefe Dritter";
    }

    if ($mediatype){
	$title_ref->{fields}{'0800'} = [
	    {
		mult     => 1,
		subfield => '',
		content  => $mediatype,
	    }
	    ];
    }
    
    if ($mediatype eq "Briefe von Gentz"){
	if ($year){
	    $title_ref->{fields}{'0426'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $year,
		},
                ];
	}
	else {
	    $title_ref->{fields}{'0425'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	    $title_ref->{fields}{'0426'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	}
    }
    elsif ($mediatype eq "Briefe an Gentz"){
	if ($year){
	    $title_ref->{fields}{'0427'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $year,
		},
                ];
	}
	else {
	    $title_ref->{fields}{'0425'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	    $title_ref->{fields}{'0427'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	}
    }
    elsif ($mediatype eq "Briefe Dritter"){
	if ($year){
	    $title_ref->{fields}{'0428'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $year,
		},
                ];
	}
	else {
	    $title_ref->{fields}{'0425'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	    $title_ref->{fields}{'0428'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	}
    }

    
    print TITLE encode_json($title_ref),"\n";
	

    
}

close (TITLE);
close (PERSON);
close (CORPORATEBODY);
close (CLASSIFICATION);
close (SUBJECT);
close (HOLDING);

close(IN);
