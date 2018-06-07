#!/usr/bin/perl

#####################################################################
#
#  bvb_subject2enrich.pl
#
#  Extrahierung der Schlagworte aus den BVB Open Data Dumps
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
use XML::Twig::XPath;
use XML::Simple;
use Storable ();
use Data::Dumper;
use JSON::XS;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;


my ($help,$importjson,$import,$init,$jsonfile,$inputfile,$logfile,$loglevel);

&GetOptions("help"         => \$help,
            "init"         => \$init,
            "import"       => \$import,
            "inputfile=s"  => \$inputfile,
            "jsonfile=s"   => \$jsonfile,
            "import-json"  => \$importjson,
            "logfile=s"    => \$logfile,
            "loglevel=s"   => \$loglevel,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->new;

$jsonfile=($jsonfile)?$jsonfile:"$inputfile.json";

$logfile=($logfile)?$logfile:"/var/log/openbib/bvb_subject-enrichmnt.log";
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

my $twig= XML::Twig::XPath->new(
   TwigHandlers => {
     "marc:collection/marc:record" => \&parse_record
#     "/collection/record" => \&parse_record
   }
 );

#$twig->set_namespace('marc',
#       'http://www.loc.gov/MARC21/slim');

if ($init){
    $logger->info("Loeschen der bisherigen Daten");
    
    $enrichment->init_enriched_content({ field => '4300', origin => $origin });
}

#$logger->info("Bestimmung der Schlagworte");

our $count=1;

our $subject_tuple_count = 1;

our $enrich_data_by_isbn_ref = [];

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
        $subject_tuple_count++;
        
        if ($count % 1000 == 0){
            $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
            $enrich_data_by_isbn_ref   = [];
        }
        $count++;
    }

    $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
    
    $logger->info("$subject_tuple_count Schlagwort-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }
    
}
else {
    if ($jsonfile){
        open(JSON,">$jsonfile");
    }
    
    
    $logger->info("Einlesen und -laden der neuen Daten");

    $twig->safe_parsefile($inputfile);
    
    $logger->info("$count done");
    
    $logger->info("$subject_tuple_count ISBN-Schlagwort-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }

}

sub parse_record {
    my($t, $titset)= @_;

    my $logger = get_logger();

#    $logger->info("Bestimmung der ISBNs");

    my @isbns = ();
    
    {
	my @elements = $titset->findnodes('//marc:datafield[@tag="020"]/marc:subfield[@code="a"]');
#	my @elements = $titset->findnodes('//datafield[@tag="020"]/subfield[@code="a"]');

#	$logger->info(Data::Dumper::Dumper(\@elements));
	foreach my $element (@elements){
	    
	    my $isbn = $element->text();

#	    $logger->info("ISBN: $isbn");
	    $isbn=~s/\s+\(.+?\)\s*$//;


	    
	    if ($isbn){
		my $isbn = $isbn;
		my $isbnXX = Business::ISBN->new($isbn);
		
		if (defined $isbnXX && $isbnXX->is_valid){
		    $isbn = $isbnXX->as_isbn13->as_string;
		}
		else {
		    $logger->error("$isbn NOT valid!");
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

#    $logger->info("Found ISBN: ".join(';',@isbns)) if (@isbns);

#    $logger->info("Bestimmung der Schlagworte");    

    my @subjects = ();
    {        
	# Schlagwort
	my @elements = $titset->findnodes('//marc:datafield[@tag="650" or @tag="651"]/marc:subfield[@code="a" or @code="x" or @code="y" or @code="z"]');
	
	foreach my $element (@elements){
	    
	    my $subject = $element->text();
	    my $code    = $element->att("code");

	    $logger->debug("SW: $subject - Code: $code");
	    push @subjects, {
		content  => konv($subject),
		subfield => $code
	    } if ($subject);
	}
    }
    
    # Dublette Schlagworte's entfernen
    my %seen_terms  = ();
    my @unique_subjects = grep { ! $seen_terms{$_->{content}} ++ } @subjects; 
    
    if (@isbns){
	my @unique_isbns    = grep { ! $seen_terms{$_} ++ } @isbns;
	
	foreach my $isbn (@unique_isbns){
	    foreach my $subject (@unique_subjects){
		$logger->debug("Found $isbn -> $subject");
		my $item_ref = {
		    isbn     => $isbn,
		    origin   => $origin,
		    field    => '4300',
		    subfield => $subject->{subfield},
		    content  => $subject->{content},
		};
		
		print JSON encode_json($item_ref),"\n" if ($jsonfile);
		
		push @{$enrich_data_by_isbn_ref}, $item_ref;
		$subject_tuple_count++;
	    }
	}
    }
    
    if ($count % 1000 == 0){
	$logger->info("$count done");
	if ($import){
	    $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
	    $enrich_data_by_isbn_ref   = [];
	}
    }
    $count++;
    
    # Release memory of processed tree
    # up to here
    $t->purge();

}

sub print_help {
    print << "ENDHELP";
bvb_subjects2enrich.pl - Anreicherung mit Schlagwort-Informationen aus den offenen Daten des BVB

   Optionen:
   -help                 : Diese Informationsseite

   -init                 : Zuerst Eintraege fuer dieses Feld und Origin aus Anreicherungsdatenbank loeschen
   -import               : Einladen der verarbeiteten Daten

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
