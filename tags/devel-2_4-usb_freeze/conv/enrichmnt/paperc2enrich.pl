#!/usr/bin/perl

#####################################################################
#
#  paperc2enrich.pl
#
#  Anreicherung mit den URL's fuer Buecher bei PaperC, die dort
#  kostenfrei gelesen werden koennen
#
#  Dieses File ist (C) 2010 Oliver Flimm <flimm@openbib.org>
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
use DBI;
use LWP::Simple;

use Business::ISBN;
use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util;
use OpenBib::Config;

# Autoflush
$|=1;

my ($help,$importyml,$filename,$logfile,$url);

&GetOptions("help"       => \$help,
            "url=s"      => \$url,
            "import-yml" => \$importyml,
            "filename=s" => \$filename,
            "logfile=s"  => \$logfile,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->instance;

$url=($url)?$url:"http://paperc.de/documents/export.csv";

$logfile=($logfile)?$logfile:"/var/log/openbib/paperc-enrichmnt.log";

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

# Verbindung zur SQL-Datenbank herstellen
my $enrichdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
    or $logger->error_die($DBI::errstr);

my $origin = "25";

$logger->debug("Origin: $origin");

# 25 = PaperC
my $deleterequest = $enrichdbh->prepare("delete from normdata where category=4122 and origin=?");
my $enrichrequest = $enrichdbh->prepare("insert into normdata values(?,?,4122,?,?)");

my $isbn_ref = {};

if ($importyml){
    $logger->info("Einladen der Daten aus YAML-Datei $filename");
    $isbn_ref = YAML::LoadFile($filename);
}
else {
    # Einladen der aktuellen Feed-Liste

    my $feed_list_string = get($url);

    $logger->info("Hole PaperC E-Book-Daten");
    
    foreach my $feedinfo (split("\n",$feed_list_string)){
        my ($ebookisbn,$printisbn,$title,$paperc_url) = split("\";\"",$feedinfo);

        $ebookisbn=~s/^\"//;
        $paperc_url=~s/\";$//;
        
        $logger->debug("EbookISBN: $ebookisbn - PrintISBN: $printisbn - Title: $title - PaperC-URL: $paperc_url");
        
        for my $isbn ($ebookisbn,$printisbn){
            next unless ($isbn);
            
            $isbn = OpenBib::Common::Util::grundform({
                category => '0540',
                content  => $isbn,
            });

            push @{$isbn_ref->{"$isbn"}}, $paperc_url;

            $logger->debug("Adding $paperc_url to ISBN $isbn");
        }
    }

    YAML::DumpFile("paperc-isbn.yml",$isbn_ref);
}


$logger->info("Loeschen der bisherigen Daten");
$deleterequest->execute($origin);

$logger->info("Einladen der neuen Daten");

my $isbncount = 0;
foreach my $thisisbn (keys %{$isbn_ref}){

    my $indicator = 1;

    # Dublette Schlagworte's entfernen
    my %seen_terms  = ();
    my @unique_urls = grep { ! $seen_terms{$_} ++ } @{$isbn_ref->{$thisisbn}}; 

    foreach my $thisurl (@unique_urls){
        $enrichrequest->execute($thisisbn,$origin,$indicator,$thisurl);
        
        $indicator++;
    }

    $isbncount++;
}

$logger->info("Fuer $isbncount ISBNs wurden PaperC-URLs angereichtert");

sub print_help {
    print << "ENDHELP";
paperc2enrich.pl - Anreicherung mit PaperC-URLs via ISBN

   Optionen:
   -help                 : Diese Informationsseite

   --url=...             : URL mit PaperC-Feed (bisher http://paperc.de/documents/export.csv)
   -import-yml           : Import der YAML-Datei
   --filename=...        : Dateiname der YAML-Datei
   --logfile=...         : Name der Log-Datei

ENDHELP
    exit;
}

