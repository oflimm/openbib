#!/usr/bin/perl

#####################################################################
#
#  bvb_extract_phil.pl
#
#  Extrahierung der Philosophien Titel aus den BVB Open Data Dumps
#  anhand der Klassifikationen
#
#  Dieses File ist (C) 2013-2019 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;
use utf8;

use YAML;


use Business::ISBN;
use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use MARC::Batch;
use MARC::Charset 'marc8_to_utf8';
use MARC::File::XML;
use JSON::XS;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;

my ($help,$format,$use_xml,$inputencoding,$inputfile,$outputfile,$logfile,$loglevel);

&GetOptions("help"         => \$help,
            "inputfile=s"  => \$inputfile,
            "input-encoding=s"  => \$inputencoding,
            "outputfile=s"  => \$outputfile,
            "use-xml"      => \$use_xml,
            "format=s"     => \$format,
            "logfile=s"    => \$logfile,
            "loglevel=s"   => \$loglevel,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->new;

$outputfile=($outputfile)?$outputfile:"$inputfile.out";

$logfile=($logfile)?$logfile:"/var/log/openbib/bvb_extract_phil.log";
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

$format=($format)?$format:'MARC21';

$logger->debug("Using format $format");

my $batch;

if ($use_xml){
    $logger->debug("Using MARC-XML");
    
    MARC::File::XML->default_record_format($format);
    
    $batch = MARC::Batch->new('XML', $inputfile);    
}
else {
    $logger->debug("Using native MARC");
    $batch = MARC::Batch->new($format, $inputfile);
}

# Recover from errors
$batch->strict_off();
$batch->warnings_off();

# Fallback to UTF8
MARC::Charset->assume_unicode(1);

# Ignore Encoding Errors
MARC::Charset->ignore_errors(1);

$logger->info("Reding records from file $inputfile and writing to $outputfile");

my $output = MARC::File::XML->out( $outputfile );

my $idx=1;

while (my $record = safe_next($batch)){
    if ($logger->is_debug){
	$logger->debug($record->field("001")->data);
    }


    my $encoding = ($inputencoding)?$inputencoding:$record->encoding();
    
    $logger->debug("Encoding:$encoding:");
    
    my $is_phil = 0;
    
    {        
	
	
	# RVKs
	foreach my $fieldno ('084'){
	    foreach my $field ($record->field($fieldno)){
		my $content_a ;
		my $content_2 ;

		eval {
		    $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
		    $content_2 = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('2')):decode_utf8($field->as_string('2'));
		};

		if ($@){
		    $logger->error("Decoding error: ".$@);
		    next;
		}
		
		next unless ($content_2=~/rvk/);
		
		if ($content_a =~/^C[A-K]/){
		    $is_phil = 1;
		}
	    }
	}
    }
    
    if ($is_phil){
	eval {
	    $output->write($record);
	};

	if ($@){
	    $logger->error("Error writing record: ".$@);
	}
    }

    if ($idx % 1000 == 0){
	$logger->info("Read $idx records");
    }

    $idx++;
}

$output->close;

$logger->info("Done");

sub print_help {
    print << "ENDHELP";
bvb_extract_phil.pl - Extraktion der philosophischen Titel aus den offenen Daten des BVB

   Optionen:
   -help                 : Diese Informationsseite

   -use-xml              : MARCXML-Format verwenden
   -format=...           : Format z.B. UNIMARC (default: USMARC)

   --inputfile=...       : Name der Einladedatei im MARC-Format
   --outputfile=...      : Name der Ausgabedatei im MARC-Format

   --logfile=...         : Name der Log-Datei
   --loglevel=...        : Loglevel (default: INFO)

ENDHELP
    exit;
}

sub safe_next {
    my $batch = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $record;
    
    eval {
	$record = $batch->next();
    };

    if ($@){
	$logger->error("Error reading next record: ".$@);
	$record=safe_next($batch);
    }

    return $record;
}

sub konv {
    my $content = shift;

    $content=~s/\s*[.,:]\s*$//g;
    $content=~s/&/&amp;/g;
    $content=~s/</&lt;/g;
    $content=~s/>/&gt;/g;
    # Buchstabenersetzungen Grundbuchstabe plus Diaeresis
    $content=~s/u\x{0308}/ü/g;
    $content=~s/a\x{0308}/ä/g;
    $content=~s/o\x{0308}/ö/g;
    $content=~s/U\x{0308}/Ü/g;
    $content=~s/A\x{0308}/Ä/g;
    $content=~s/O\x{0308}/Ö/g;

    return $content;
}
