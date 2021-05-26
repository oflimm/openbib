#!/usr/bin/perl

#####################################################################
#
#  bvb_tocurls2enrich.pl
#
#  Extrahierung der URLS zu Inhaltsverzeichnissen aus den BVB Open Data Dumps
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2013-2016 Oliver Flimm <flimm@openbib.org>
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

$logfile=($logfile)?$logfile:"/var/log/openbib/bvb_tocurls-enrichmnt.log";
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
    
    $enrichment->init_enriched_content({ field => '4110', origin => $origin });
}

$logger->info("Bestimmung der TOC-URLs");

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
    
    my $subject_tuple_count = 1;
    
    my $enrich_data_by_isbn_ref   = [];
    my $enrich_data_by_bibkey_ref = [];
    
    $logger->info("Einlesen und -laden der neuen Daten");

    while (<JSON>){
        my $item_ref = decode_json($_);

        push @{$enrich_data_by_isbn_ref},   $item_ref if (defined $item_ref->{isbn});
        push @{$enrich_data_by_bibkey_ref}, $item_ref if (defined $item_ref->{bibkey});

        $subject_tuple_count++;
        
        if ($count % 1000 == 0){
            $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
            $enrichment->add_enriched_content({ matchkey => 'bibkey', content => $enrich_data_by_bibkey_ref })  if (@$enrich_data_by_bibkey_ref);
            $enrich_data_by_isbn_ref   = [];
            $enrich_data_by_bibkey_ref = [];
        }
        $count++;
    }

    $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
    $enrichment->add_enriched_content({ matchkey => 'bibkey', content => $enrich_data_by_bibkey_ref }) if (@$enrich_data_by_bibkey_ref);
    
    $logger->info("$subject_tuple_count RVK-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }
    
}
else {
    if ($jsonfile){
        open(JSON,">$jsonfile");
    }
    
    my $count=1;

    my $tocurl_tuple_count = 1;

    # Logik: Bibkeys werden nur verwendet, wenn es keine ISBNs gibt. Also nicht entweder ISBN oder Bibkey, sondern sowohl ISBN wie auch Bibkey!
    
    my $enrich_data_by_isbn_ref = [];
    my $enrich_data_by_bibkey_ref = [];
    
    $logger->info("Einlesen und -laden der neuen Daten");
    
    while (my $record = $batch->next()){
        
        my $encoding = $record->encoding();
        
        $logger->debug("Encoding:$encoding:");

        my $bibkey = OpenBib::Common::Util::gen_bibkey_from_marc($record,$encoding);

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
        
        my @tocurls = ();
        {        
            # TOCURLs
            foreach my $fieldno ('856'){
                foreach my $field ($record->field($fieldno)){
                    my $content_u = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('u')):decode_utf8($field->as_string('u'));
                    my $content_3 = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('3')):decode_utf8($field->as_string('3'));

                    next unless ($content_3=~/Inhaltsverzeichnis/);

		    $logger->debug("TocURL: $content_u - Desc: $content_3");
		    
                    push @tocurls, {
                        content  => $content_u,
                        subfield => 'u'
                    } if ($content_u);
                }
            }
        }

        if (@isbns){
            # Dublette TOCURL's entfernen
            my %seen_terms  = ();
            my @unique_isbns    = grep { ! $seen_terms{$_} ++ } @isbns;
            
            foreach my $isbn (@unique_isbns){
                foreach my $tocurl (@tocurls){
                    $logger->debug("Found $isbn -> $tocurl");
                    my $tocurl_ref = {
                        isbn     => $isbn,
                        origin   => $origin,
                        field    => '4110',
                        subfield => $tocurl->{subfield},
                        content  => $tocurl->{content},
                    };
                    
                    print JSON encode_json($tocurl_ref),"\n" if ($jsonfile);
                    
                    push @{$enrich_data_by_isbn_ref}, $tocurl_ref;
                    $tocurl_tuple_count++;
                }
            }
        }
        elsif ($bibkey){
            foreach my $tocurl (@tocurls){
                $logger->debug("Found Bibkey $bibkey -> $tocurl");
                my $tocurl_ref = {
                    bibkey   => $bibkey,
                    origin   => $origin,
                    field    => '4101',
                    subfield => $tocurl->{subfield},
                    content  => $tocurl->{content},
                };
                
                print JSON encode_json($tocurl_ref),"\n" if ($jsonfile);
                
                push @{$enrich_data_by_bibkey_ref}, $tocurl_ref;
                $tocurl_tuple_count++;
            }            
        }
        
        if ($import && $count % 1000 == 0){
            $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
            $enrichment->add_enriched_content({ matchkey => 'bibkey', content => $enrich_data_by_bibkey_ref })  if (@$enrich_data_by_bibkey_ref);
            $enrich_data_by_isbn_ref   = [];
            $enrich_data_by_bibkey_ref = [];
        }

	if ($count % 10000 == 0){
	    $logger->info("$count Datensaetze bearbeitet");
	}
	
        $count++;
        
    }
    
    if ($import && (@$enrich_data_by_isbn_ref || @$enrich_data_by_bibkey_ref) ){
        $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
        $enrichment->add_enriched_content({ matchkey => 'bibkey', content => $enrich_data_by_bibkey_ref })  if (@$enrich_data_by_bibkey_ref);
    }
    
    $logger->info("$tocurl_tuple_count TOCURL-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }

}

sub print_help {
    print << "ENDHELP";
bvb_tocurls2enrich.pl - Anreicherung mit TOCURL-Informationen aus den offenen Daten des BVB

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
