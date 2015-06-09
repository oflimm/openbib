#!/usr/bin/perl

#####################################################################
#
#  usb_eb2enrich.pl
#
#  Extrahierung der Ebook-URL aus den USB-Ebook-Daten fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2008-2013 Oliver Flimm <flimm@openbib.org>
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

use YAML;
use DBI;

use Business::ISBN;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;

my ($help,$importyml,$filename,$logfile);

&GetOptions("help"       => \$help,
            "import-yml" => \$importyml,
            "filename=s" => \$filename,
            "logfile=s"  => \$logfile,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/usb_eb-enrichmnt.log";

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

my $enrichment = new OpenBib::Enrichment;

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => 'ebooks'});

# 20 = USB
my $origin = 20;

my $isbn_ref = {};

if ($importyml){
    $logger->info("Einladen der Daten aus YAML-Datei $filename");
    $isbn_ref = YAML::LoadFile($filename);
}
else {
    $logger->info("Bestimmung der ebook-URL");

    my $isbn_urls = $catalog->get_schema->resultset('Title')->search(
        {
            'title_fields.field' => '0662',
            -or => [
                'title_fields_2.field' => '0540',
                'title_fields_2.field' => '0553',
            ],
        },
        {
            select => ['title_fields.content','title_fields_2.content'],
            as     => ['eburl','isbn'],
            join   => ['title_fields','title_fields'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }   
    );
    
    while (my $isbn_url = $isbn_urls->next()){
        my $isbn  = decode_utf8($isbn_url->{isbn});
        my $eburl = decode_utf8($isbn_url->{eburl});
        
        my $isbnXX = Business::ISBN->new($isbn);
        
        if (defined $isbnXX && $isbnXX->is_valid){
            $isbn = $isbnXX->as_isbn13->as_string;
        }
        else {
            next;
        }
        
        $isbn = OpenBib::Common::Util::normalize({
            field => 'T0540',
            content  => $isbn,
        });
        
        push @{$isbn_ref->{"$isbn"}}, $eburl;
    }
}

$logger->info("Loeschen der bisherigen Daten");

$enrichment->get_schema->resultset('EnrichedContentByIsbn')->search_rs({ field => '4120', origin => $origin })->delete;

$logger->info("Einladen der neuen Daten");

my $count = 1;
my $enrich_data_ref = [];

foreach my $thisisbn (keys %{$isbn_ref}){
    my $indicator = 1;

    # Dublette URL's entfernen
    my %seen_terms = ();
    my @unique_urls = grep { ! $seen_terms{$_} ++ } @{$isbn_ref->{$thisisbn}}; 

    foreach my $thisurl (@unique_urls){
        push @{$enrich_data_ref},
            {
                isbn => $thisisbn,
                origin => $origin,
                field => '4120',
                subfield => $indicator,
                content => $thisurl,
            };
        
        $indicator++;        
    }

    if ($count % 1000 == 0){
        $enrichment->get_schema->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref);        
        $enrich_data_ref = [];
    }
    $count++;
}

if (@$enrich_data_ref){
    $enrichment->get_schema->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref);        
}

sub print_help {
    print << "ENDHELP";
usb_eb2enrich.pl - Anreicherung mit eBook-URL-Informationen aus den USB/eBook-Daten

   Optionen:
   -help                 : Diese Informationsseite

   -import-yml           : Import der YAML-Datei
   --filename=...        : Dateiname der YAML-Datei
   --logfile=...         : Name der Log-Datei

ENDHELP
    exit;
}

