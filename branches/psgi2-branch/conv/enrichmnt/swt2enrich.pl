#!/usr/bin/perl

#####################################################################
#
#  swt2enrich.pl
#
#  Extrahierung der Schlagworte aus den Daten eines Katalogs
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2009 Oliver Flimm <flimm@openbib.org>
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

use YAML;

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

my ($help,$importyml,$filename,$logfile,$database);

&GetOptions("help"       => \$help,
            "database=s" => \$database,
            "import-yml" => \$importyml,
            "filename=s" => \$filename,
            "logfile=s"  => \$logfile,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/swt-enrichmnt.log";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

my $sigel = $config->get_dbinfo({ dbname => $database})->single->sigel;

if (!$sigel || ! $sigel =~/^\d+$/){
    $logger->fatal("Datenbank muss numerisches Sigel besitzen: $sigel");
    exit;
}

my $enrichment = new OpenBib::Enrichment;

my $origin = 5000+$sigel;

$logger->debug("Origin: $origin");

my $isbn_ref = {};

if ($importyml){
    $logger->info("Einladen der Daten aus YAML-Datei $filename");
    $isbn_ref = YAML::LoadFile($filename);
}
else {
    my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});

    $logger->info("Bestimmung der Schlagworte");
    
    my $isbn_swts = $catalog->{schema}->resultset('TitleSubject')->search(
        {
            'subject_fields.field' => '0800',
            -or => [
                'title_fields.field' => '0540',
                'title_fields.field' => '0553',
            ],
        },
        {
            select => ['subject_fields.content','title_fields.content'],
            as     => ['schlagwort','isbn'],
            join   => ['titleid', { 'titleid' => 'title_fields'},'subjectid', {'subjectid' => 'subject_fields'}],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }   
    );

    while (my $isbn_swt = $isbn_swts->next()){
        my $isbn        = $isbn_swt->{isbn};
        my $schlagwort  = $isbn_swt->{schlagwort};
        
        my $isbnXX = Business::ISBN->new($isbn);
        
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
        
        push @{$isbn_ref->{"$isbn"}}, $schlagwort;
    }

    YAML::DumpFile("swt-isbn-$database.yml",$isbn_ref);
}

$logger->info("Loeschen der bisherigen Daten");

$enrichment->{schema}->resultset('EnrichedContentByIsbn')->search_rs({ field => '4300', origin => $origin })->delete;

$logger->info("Einladen der neuen Daten");

my $isbncount = 0;

my $count = 1;
my $enrich_data_ref = [];

foreach my $thisisbn (keys %{$isbn_ref}){

    my $indicator = 1;

    # Dublette Schlagworte's entfernen
    my %seen_terms  = ();
    my @unique_swts = grep { ! $seen_terms{$_} ++ } @{$isbn_ref->{$thisisbn}}; 

    foreach my $thisswt (@unique_swts){
        push @{$enrich_data_ref},
            {
                isbn     => $thisisbn,
                origin   => $origin,
                field    => '4300',
                subfield => $indicator,
                content  => $thisswt,
            };
        
        $indicator++;
    }

    if ($count % 1000 == 0){
        $enrichment->{schema}->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref);        
        $enrich_data_ref = [];
    }
    $count++;

    $isbncount++;
}

if (@$enrich_data_ref){
    $enrichment->{schema}->resultset('EnrichedContentByIsbn')->populate($enrich_data_ref);        
}

$logger->info("Fuer $isbncount ISBNs wurden Schlagworte angereichert");

sub print_help {
    print << "ENDHELP";
swt2enrich.pl - Anreicherung mit Schlagwort-Informationen aus Daten eines Katalogs

   Optionen:
   -help                 : Diese Informationsseite

   --database=...        : Datenbankname aus dem die Inhalte extrahiert werden
   -import-yml           : Import der YAML-Datei
   --filename=...        : Dateiname der YAML-Datei
   --logfile=...         : Name der Log-Datei

ENDHELP
    exit;
}

