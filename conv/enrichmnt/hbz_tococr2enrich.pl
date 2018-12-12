#!/usr/bin/perl

#####################################################################
#
#  hbz_tococr2enrich.pl
#
#  Verarbeitung von OCR-Inhaltsverzeichnissen
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2013-2018 Oliver Flimm <flimm@openbib.org>
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
use JSON::XS;
use Encode::MAB2;
use MAB2::Record::Base;
use Tie::MAB2::Recno;
use File::Slurp;
use DB_File;
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Common::Util;
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;

my ($help,$importjson,$import,$init,$jsonfile,$inputfile,$ocrdir,$logfile,$loglevel);

&GetOptions("help"         => \$help,
            "init"         => \$init,
            "import"       => \$import,
            "inputfile=s"  => \$inputfile,
            "jsonfile=s"   => \$jsonfile,
            "ocrdir=s"     => \$ocrdir,
            "import-json"  => \$importjson,
            "logfile=s"    => \$logfile,
            "loglevel=s"   => \$loglevel,
	    );

if ($help){
   print_help();
}

$jsonfile=($jsonfile)?$jsonfile:"$inputfile.json";

$logfile=($logfile)?$logfile:"/var/log/openbib/hbz_tocurls-enrichmnt.log";
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

my $origin = 26; # hbz

$logger->debug("Origin: $origin");

if ($init){
    $logger->info("Loeschen der bisherigen Daten");
    
    $enrichment->init_enriched_content({ field => '4111', origin => $origin });
}

$logger->info("Bestimmung der TOCs");

our $count=0;

our $toc_tuple_count = 0;

our $enrich_data_by_isbn_ref   = [];

if ($importjson){
    if (! -e $jsonfile){
        $logger->error("JSON-Datei $jsonfile existiert nicht");
        exit;
    }
    open(JSON,$jsonfile);

    
    $logger->info("Einlesen und -laden der neuen Daten");

    while (<JSON>){
        my $item_ref = decode_json($_);

        push @{$enrich_data_by_isbn_ref},   $item_ref if (defined $item_ref->{isbn});

        $toc_tuple_count++;
        
        if ($count % 1000 == 0){
            $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
            $enrich_data_by_isbn_ref   = [];
        }
        $count++;
    }

    $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
    
    $logger->info("$toc_tuple_count TOCOCR-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }
    
}
else {
    if ($jsonfile){
        open(JSON,">$jsonfile");
    }
    
    $logger->info("Einlesen und -laden der neuen Daten");

    my $enrich_data_by_isbn_ref   = [];
    
    my @mab2titdata = ();

    tie @mab2titdata, 'Tie::MAB2::Recno', file => $inputfile;

    $count=1;
    foreach my $rawrec (@mab2titdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #print $rec->readable."\n----------------------\n";    
	
        my @isbns = ();
	
        my $id;
	
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = $category_ref->[2];
	    
#	    $logger->debug("$category - $indicator - $content");
	    
            # Titel-ID sowie Ueberordnungs-ID
            if ($category =~ /^001$/){
                $id=$content;
            }
	    
            if ($category =~ /^540$/ || $category =~ /^634$/){
		if    ($content =~m/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/){
		    $content = "$1$2$3$4$5$6$7$8$9$10$11$12$13";
		    push @isbns, $content;
		}
		elsif ($content =~m/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/){
		    $content = "$1$2$3$4$5$6$7$8$9$10";
		    push @isbns, $content;
		}

            }
	    
	}

	my $ocr_content;
	
	if ($id){
	    $ocrdir=~s/\/$//;

	    my $ocrfile = "$ocrdir/$id.txt";
	    
	    $logger->debug("OCR-File: $ocrfile");

	    if ($ocrdir && -e $ocrfile){
		my $slurped_file = decode_utf8(read_file($ocrfile));
		if ($slurped_file){
		    $ocr_content = process_ocr($slurped_file);
		    $logger->debug("TOC-OCR: $ocr_content");
		}
	    }
	    else {
		$logger->error("Keine Datei $ocrfile vorhanden.");
	    }
	    
	}
	
	next if (!$ocr_content);
	next if (!@isbns);
	
	my @unique_isbns = ();
	my %have_isbn = ();
	
	foreach my $isbn (@isbns){
	    my $isbnXX = Business::ISBN->new($isbn);
	    
	    if (defined $isbnXX && $isbnXX->is_valid){
		$isbn = $isbnXX->as_isbn13->as_string;
	    }
	    else {
		$logger->error("ISBN $isbn NOT valid");
		next;
	    }
	    
	    $isbn = OpenBib::Common::Util::normalize({
		field   => 'T0540',
		content => $isbn,
						     });
	    
	    push @unique_isbns, $isbn if (!defined $have_isbn{$isbn});
	    $have_isbn{$isbn} = 1;
	}
	
	foreach my $isbn (@unique_isbns){

	    my $tococr_ref = {
		isbn     => $isbn,
		origin   => $origin,
		field    => '4111',
		subfield => 'c',
		content  => $ocr_content,
	    };
	    
	    print JSON encode_json($tococr_ref),"\n" if ($jsonfile);
	    
	    push @{$enrich_data_by_isbn_ref}, $tococr_ref;
	}

        if ($count % 1000 == 0){            
           $logger->info("$count Titel analysiert");
	   if ($import){
	       $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
	       $enrich_data_by_isbn_ref   = [];
	   }
        }
        $count++;
    }    
    
    $logger->info("$count done");
    
    if ($jsonfile){
        close(JSON);
    }

}

sub print_help {
    print << "ENDHELP";
hbz_tococr2enrich.pl - Anreicherung mit TOC-OCR aus Lieferungen des hbz

   Optionen:
   -help                 : Diese Informationsseite

   -init                 : Zuerst Eintraege fuer dieses Feld und Origin aus Anreicherungsdatenbank loeschen
   -import               : Einladen der verarbeiteten Daten

   --inputfile=...       : Name der Einladedatei im MARC-Format
   --jsonfile=...        : Name der JSON-Einlade-/ausgabe-Datei

     -import-json        : Einladen der Daten aus der JSON-Einlade-Datei

   --ocrdir=...          : Name des Verzeichnisses mit OCR-Daten
   --logfile=...         : Name der Log-Datei
   --loglevel=...        : Loglevel (default: INFO)

Beispiele:

 hbz_tococr2enrich.pl -ocrdir=./storage --inputfile=tocs.mab --jsonfile=hbz_tocs_20181130_ocr.json
 hbz_tococr2enrich.pl -import-json -init --jsonfile=hbz_tocs_20181130_ocr.json


ENDHELP
    exit;
}

sub process_ocr {
    my ($ocr)=@_;

    # Preambel entfernen
    $ocr=~s/ocr-text://;
    
    # Nur noch eine Zeile
    $ocr=~s/\n/ /g;

    $ocr=OpenBib::Common::Util::normalize({ content => $ocr });

    $ocr=~s/[^\p{Alphabetic}] / /g;

    $ocr=~s/\s\d+(\.\d)+\s/ /g;
    $ocr=~s/-/ /g;
    $ocr=~s/,/ /g;
    $ocr=~s/,/ /g;
    $ocr=~s/\d+\.?/ /g;

    # Dublette Inhalte entfernen
    my %seen_terms = ();
    $ocr = join(" ",grep { ! $seen_terms{$_} ++ } split ("\\s+",$ocr)); 
        
    return $ocr;
}    
