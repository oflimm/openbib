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
use DBI;

use Business::ISBN;
use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util;
use OpenBib::Config;

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

my $config = OpenBib::Config->instance;

$logfile=($logfile)?$logfile:"/var/log/openbib/swt-enrichmnt.log";

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

my $sigel = $config->get_dbinfo($database)->{sigel};

if (! $sigel =~/^\d+$/){
    $logger->fatal("Datenbank muss numerisches Sigel besitzen");
    exit;
}

my $origin = 5000+$sigel;

$logger->debug("Origin: $origin");

# 20 = USB
my $deleterequest = $enrichdbh->prepare("delete from normdata where category=4300 and origin=?");
my $enrichrequest = $enrichdbh->prepare("insert into normdata values(?,?,4300,?,?)");

my $isbn_ref = {};

if ($importyml){
    $logger->info("Einladen der Daten aus YAML-Datei $filename");
    $isbn_ref = YAML::LoadFile($filename);
}
else {
    # Kein Spooling von DB-Handles!
    my $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
        or $logger->error_die($DBI::errstr);
    
    $logger->info("Bestimmung der Schlagworte");
    
    my $request=$dbh->prepare("select tit.content as isbn,swt.content as schlagwort from swt,tit,conn where swt.category=1 and conn.targettype=4 and conn.targetid=swt.id and conn.sourcetype=1 and tit.id=conn.sourceid and tit.category in (540,553)");
    $request->execute();
    
    while (my $res=$request->fetchrow_hashref){
        my $isbn        = decode_utf8($res->{isbn});
        my $schlagwort  = decode_utf8($res->{schlagwort});
        
        my $isbnXX = Business::ISBN->new($isbn);
        
        if (defined $isbnXX && $isbnXX->is_valid){
            $isbn = $isbnXX->as_isbn13->as_string;
        }
        else {
            next;
        }
        
        $isbn = OpenBib::Common::Util::grundform({
            category => '0540',
            content  => $isbn,
        });
        
        push @{$isbn_ref->{"$isbn"}}, $schlagwort;
    }

    YAML::DumpFile("swt-isbn-$database.yml",$isbn_ref);
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

