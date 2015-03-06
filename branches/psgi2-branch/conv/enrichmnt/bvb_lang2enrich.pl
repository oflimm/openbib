#!/usr/bin/perl

#####################################################################
#
#  bvb_lang2enrich.pl
#
#  Extrahierung der Sprachinformationen aus den BVB Open Data Dumps
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

my ($help,$format,$use_xml,$importjson,$import,$init,$jsonfile,$inputfile,$logfile,$loglevel);

&GetOptions("help"         => \$help,
            "init"         => \$init,
            "import"       => \$import,
            "inputfile=s"  => \$inputfile,
            "jsonfile=s"   => \$jsonfile,
            "use-xml"      => \$use_xml,
            "format=s"     => \$format,
            "import-json"  => \$importjson,
            "logfile=s"    => \$logfile,
            "loglevel=s"   => \$loglevel,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->new;

$jsonfile=($jsonfile)?$jsonfile:"$inputfile.json";

$logfile=($logfile)?$logfile:"/var/log/openbib/bvb_lang-enrichmnt.log";
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

my $enrichment = new OpenBib::Enrichment;

my $origin = 24;

$logger->debug("Origin: $origin");

if ($init){
    $logger->info("Loeschen der bisherigen Daten");
    
    $enrichment->{schema}->resultset('EnrichedContentByIsbn')->search_rs({ field => '4301', origin => $origin })->delete;
}

$logger->info("Bestimmung der Sprachcodes");

$format=($format)?$format:'USMARC';

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

if ($importjson){
    if (! -e $jsonfile){
        $logger->error("JSON-Datei $jsonfile existiert nicht");
        exit;
    }
    open(JSON,$jsonfile);

    my $count=1;
    
    my $lang_tuple_count = 1;
    
    my $enrich_data_ref = [];
    
    $logger->info("Einlesen und -laden der neuen Daten");

    while (<JSON>){
        my $lang_ref = decode_json($_);

        push @{$enrich_data_ref}, $lang_ref;
        $lang_tuple_count++;
        
        if ($count % 1000 == 0){
            $enrichment->{schema}->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref);        
            $enrich_data_ref = [];
        }
        $count++;
    }

    if (@$enrich_data_ref){
        $enrichment->{schema}->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref);        
    }
    
    $logger->info("$lang_tuple_count ISBN-Sprach-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }
    
}
else {
    if ($jsonfile){
        open(JSON,">$jsonfile");
    }
    
    my $count=1;

    my $lang_tuple_count = 1;
    
    my $enrich_data_ref = [];
    
    $logger->info("Einlesen und -laden der neuen Daten");
    
    while (my $record = $batch->next()){
        
        my $encoding = $record->encoding();
        
        $logger->debug("Encoding:$encoding:");
        
        my @isbns = ();
        {
            # ISBN
            foreach my $field ($record->field('020')){
                my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
                my $content_z = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('z')):decode_utf8($field->as_string('z'));
                
                $content_a=~s/\s+\(.+?\)\s*$//;
                $content_z=~s/\s+\(.+?\)\s*$//;
                
                if ($content_a){
                    my $isbn = $content_a;
                    my $isbnXX = Business::ISBN->new($content_a);
                    
                    if (defined $isbnXX && $isbnXX->is_valid){
                        $isbn = $isbnXX->as_isbn13->as_string;
                    }
                    else {
                        next;
                    }
                    
                    $isbn = OpenBib::Common::Util::normalize({
                        field    => 'T0540',
                        content  => $isbn,
                    });
                    
                    push @isbns, $isbn;
                }
            }
        }
        
        my @langs = ();
        {        
            # Sprache
            foreach my $fieldno ('041'){
                foreach my $field ($record->field($fieldno)){
                    my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
                    my $content_b = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('b')):decode_utf8($field->as_string('b'));
                    my $content_g = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('g')):decode_utf8($field->as_string('g'));

                    if ($content_a){
                        foreach my $lang (split /\s+/, $content_a){                    
                            push @langs, {
                                content  => $lang,
                                subfield => 'a'
                            };
                        }
                    }
                    if ($content_b){
                        foreach my $lang (split /\s+/, $content_b){                    
                            push @langs, {
                                content  => $lang,
                                subfield => 'b'
                            };
                        }
                    }
                    if ($content_g){
                        foreach my $lang (split /\s+/, $content_g){                    
                            push @langs, {
                                content  => $lang,
                                subfield => 'g'
                            };
                        }
                    }
                }
            }
        }
        
        # Dublette Schlagworte's entfernen
        my %seen_terms  = ();
        my @unique_langs = grep { ! $seen_terms{$_->{content}} ++ } @langs; 
        my @unique_isbns    = grep { ! $seen_terms{$_} ++ } @isbns;
        
        foreach my $isbn (@unique_isbns){
            foreach my $lang (@unique_langs){
                $logger->debug("Found $isbn -> $lang");
                my $lang_ref = {
                    isbn     => $isbn,
                    origin   => $origin,
                    field    => '4301',
                    subfield => $lang->{subfield},
                    content  => $lang->{content},
                };

                print JSON encode_json($lang_ref),"\n" if ($jsonfile);
                
                push @{$enrich_data_ref}, $lang_ref;
                $lang_tuple_count++;
            }
        }
        
        if ($count % 1000 == 0){
            $enrichment->{schema}->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref) if ($import);
            $enrich_data_ref = [];
        }
        $count++;
        
    }
    
    if (@$enrich_data_ref && $import){
        $enrichment->{schema}->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref);        
    }
    
    $logger->info("$lang_tuple_count ISBN-Sprach-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }

}

sub print_help {
    print << "ENDHELP";
bvb_lang2enrich.pl - Anreicherung mit Sprach-Informationen aus den offenen Daten des BVB

   Optionen:
   -help                 : Diese Informationsseite

   -init                 : Zuerst Eintraege fuer dieses Feld und Origin aus Anreicherungsdatenbank loeschen
   -import               : Einladen der verarbeiteten Daten
   -use-xml              : MARCXML-Format verwenden
   -format=...           : Format z.B. UNIMARC (default: USMARC)

   --inputfile=...       : Name der Einladedatei im MARC-Format
   --jsonfile=...        : Name der JSON-Einlade-/ausgabe-Datei

     -import-json        : Einladen der Daten aus der JSON-Einlade-Datei

   --logfile=...         : Name der Log-Datei
   --loglevel=...        : Loglevel (default: INFO)

ENDHELP
    exit;
}
