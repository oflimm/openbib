#!/usr/bin/perl

#####################################################################
#
#  tictocs2enrich.pl
#
#  Anreicherung mit RSS-Feed-Informationen fuer die letzen Artikel
#  einer Zeitschrift.
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

$url=($url)?$url:"http://www.tictocs.ac.uk/text.php";

$logfile=($logfile)?$logfile:"/var/log/openbib/tictocs-enrichmnt.log";

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

my $origin = "23";

$logger->debug("Origin: $origin");

# 23 = TicTocs
my $deleterequest = $enrichdbh->prepare("delete from normdata where category=4115 and origin=?");
my $enrichrequest = $enrichdbh->prepare("insert into normdata values(?,?,4115,?,?)");

my $isbn_ref = {};

if ($importyml){
    $logger->info("Einladen der Daten aus YAML-Datei $filename");
    $isbn_ref = YAML::LoadFile($filename);
}
else {
    # Einladen der aktuellen Feed-Liste

    my $feed_list_string = get($url);

    $logger->info("Hole TicTocs");
    
    foreach my $feedinfo (split("\n",$feed_list_string)){
        my ($id,$title,$rssurl,$paperissn,$eissn) = split("\t",$feedinfo);

        $logger->info("ID: $id - Title: $title - RSS: $rssurl - PISSN: $paperissn - EISSN: $eissn");
        
        for my $issn ($paperissn,$eissn){
            next unless ($issn);
            
            $issn = OpenBib::Common::Util::grundform({
                category => '0543',
                content  => $issn,
            });

            push @{$isbn_ref->{"$issn"}}, $rssurl;

            $logger->debug("Adding $rssurl to ISSN $issn");
        }
    }

    YAML::DumpFile("tictocs-issn.yml",$isbn_ref);
}

$logger->info("Loeschen der bisherigen Daten");
$deleterequest->execute($origin);

$logger->info("Einladen der neuen Daten");

my $isbncount = 0;
foreach my $thisisbn (keys %{$isbn_ref}){

    my $indicator = 1;

    # Dublette Schlagworte's entfernen
    my %seen_terms  = ();
    my @unique_swts = grep { ! $seen_terms{$_} ++ } @{$isbn_ref->{$thisisbn}}; 

    foreach my $thisswt (@unique_swts){
        $enrichrequest->execute($thisisbn,$origin,$indicator,$thisswt);
        
        $indicator++;
    }

    $isbncount++;
}

$logger->info("Fuer $isbncount ISBNs wurden Schlagworte angereichtert");

sub print_help {
    print << "ENDHELP";
tictocs2enrich.pl - Anreicherung mit RSS-Feeds der Artikel zu Zeitschriften via ISSN

   Optionen:
   -help                 : Diese Informationsseite

   --url=...             : URL mit FeedListe (bisher http://www.tictocs.ac.uk/text.php)
   -import-yml           : Import der YAML-Datei
   --filename=...        : Dateiname der YAML-Datei
   --logfile=...         : Name der Log-Datei

ENDHELP
    exit;
}

