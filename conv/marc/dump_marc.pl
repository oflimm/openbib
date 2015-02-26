#!/usr/bin/perl

#####################################################################
#
#  dump_marc.pl
#
#  Ausabe von MARC-Daten
#
#  Dieses File ist (C) 2009-2013 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;

use Encode 'decode_utf8';
use Getopt::Long;
use DBI;
use MARC::Batch;
use MARC::Charset 'marc8_to_utf8';
use MARC::File::XML;
use YAML::Syck;
use JSON::XS qw(encode_json);
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $logfile = '/var/log/openbib/marc2meta.log';

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

my $config = OpenBib::Config->instance;

my ($inputfile,$format,$use_xml);

&GetOptions(
	    "inputfile=s"     => \$inputfile,
            "format=s"        => \$format,
            "use-xml"         => \$use_xml,
	    );

if (!$inputfile){
    print << "HELP";
dump_marc.pl - Aufrufsyntax

    dump_marc.pl --inputfile=xxx
HELP
exit;
}

# Einlesen und Reorganisieren

open(DAT,"$inputfile");

binmode(STDOUT, 'utf8');

$format=($format)?$format:'USMARC';

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

while (my $record = $batch->next()){
    
    my $encoding = $record->encoding();

    print "Encoding:$encoding:\n";

    my $idfield = $record->field('001');

    print "ID: ",$idfield->as_string(),"\n";

    foreach my $field ($record->fields()){
        my $tag        = $field->tag();
        my $indicator1 = defined $field->indicator(1)?$field->indicator(1):"";
        my $indicator2 = defined $field->indicator(2)?$field->indicator(2):"";
        
        foreach my $subfield_ref ($field->subfields()){
            my $subfield = $subfield_ref->[0];
            
            my $kateg   = $tag.$indicator1.$indicator2.$subfield;
            my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string($subfield)):decode_utf8($field->as_string($subfield));
            
            print ":$kateg:",$content,"\n";
        }

    }

    print "-----------------------------------------------------\n";
}
