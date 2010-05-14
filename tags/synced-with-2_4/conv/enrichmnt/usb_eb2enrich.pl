#!/usr/bin/perl

#####################################################################
#
#  usb_eb2enrich.pl
#
#  Extrahierung der Ebook-URL aus den USB-Ebook-Daten fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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
use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util;
use OpenBib::Config;

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

my $config = OpenBib::Config->instance;

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

# Verbindung zur SQL-Datenbank herstellen
my $enrichdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
    or $logger->error_die($DBI::errstr);

# 20 = USB
my $deleterequest = $enrichdbh->prepare("delete from normdata where category=4120 and origin=20");
my $enrichrequest = $enrichdbh->prepare("insert into normdata values(?,20,4120,?,?)");

my $isbn_ref = {};

if ($importyml){
    $logger->info("Einladen der Daten aus YAML-Datei $filename");
    $isbn_ref = YAML::LoadFile($filename);
}
else {
    # Kein Spooling von DB-Handles!
    $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=ebooks;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
        or $logger->error_die($DBI::errstr);
    
    $logger->info("Bestimmung der ebook-URL");

    my $request=$dbh->prepare("select t1.content as isbn, t2.content as eburl from tit as t1 left join tit as t2 on t1.id=t2.id where t2.category=662 and (t1.category=540 or t1.category=553)");
    $request->execute();
    
    while (my $res=$request->fetchrow_hashref){
        my $isbn  = decode_utf8($res->{isbn});
        my $eburl = decode_utf8($res->{eburl});
        
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
        
        push @{$isbn_ref->{"$isbn"}}, $eburl;
    }
}

$logger->info("Loeschen der bisherigen Daten");
$deleterequest->execute();

$logger->info("Einladen der neuen Daten");

foreach my $thisisbn (keys %{$isbn_ref}){

    my $indicator = 1;

    # Dublette BK's entfernen
    my %seen_terms = ();
    my @unique_bk = grep { ! $seen_terms{$_} ++ } @{$isbn_ref->{$thisisbn}}; 

    foreach my $thisbk (@unique_bk){
        $enrichrequest->execute($thisisbn,$indicator,$thisbk);
        
        $indicator++;
    }
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

