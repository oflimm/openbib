#!/usr/bin/perl

#####################################################################
#
#  picafiles2enrich.pl
#
#  Extrahierung relevanter Kategorieinhalte im Pica-Formates und
#  Einladen in die Anreicherungsdatenbank
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

use 5.008001;

use utf8;
use warnings;
use strict;

use Encode 'decode';
use File::Find;
use File::Slurp;
use Getopt::Long;
use YAML::Syck;
use Encode qw /decode_utf8/;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util;
use OpenBib::Config;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

use PICA::Record;
use PICA::Parser;

use DBI;

our ($help,$importyml,$inputdir,$logfile);

&GetOptions("help"       => \$help,
            "import-yml" => \$importyml,
            "inputdir=s" => \$inputdir,
            "logfile=s"  => \$logfile,
	    );

if ($help || !$inputdir){
   print_help();
}

my $config = OpenBib::Config->instance;

$logfile=($logfile)?$logfile:"/var/log/openbib/picafiles-enrichmnt.log";

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
our $enrichdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
    or $logger->error_die($DBI::errstr);

# 22 = GBV
our $deleterequest = $enrichdbh->prepare("delete from normdata where category=4100 and origin=22");
our $enrichrequest = $enrichdbh->prepare("insert into normdata values(?,22,4100,?,?)");

sub process_file {
    return unless ($File::Find::name=~/.pica$/);

    $logger->debug("Processing ".$File::Find::name);

    my %bk = ();

    my $slurped_file = decode_utf8(read_file($File::Find::name));

    next if (!$slurped_file);

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my ($record) =  PICA::Parser->parsedata( $slurped_file, Limit => 1)->records();

    my @isbns = ();
    my @issns = ();

    if ($record->field('004A')){
        my %seen_terms = ();
        @isbns = grep { ! $seen_terms{$_} ++ } $record->field('004A')->subfield('0');
    }

    if ($record->field('005A')){
        my %seen_terms = ();
        @issns = grep { ! $seen_terms{$_} ++ } $record->field('005A')->subfield('0');
    }
    
    my @bks = ();

    push @bks, map { ($_)=$_=~m/(\d\d\.\d\d)/ } $record->subfield('045Q/..$8');
    push @bks, map { ($_)=$_=~m/(\d\d\.\d\d)/ } $record->subfield('045Q/..$a');

    $logger->debug("ISBN ".YAML::Dump(\@isbns));
    $logger->debug("ISSN ".YAML::Dump(\@issns));
    $logger->debug("BK ".YAML::Dump(\@bks));

    my $isbn_ref = {};
    my $issn_ref = {};
    
    if (@isbns){
        foreach my $isbn (@isbns){
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

            # BK's
            {
                my $indicator = 1;
                
                # Dublette BK's entfernen
                my %seen_terms = ();
                my @unique_bks = grep { ! $seen_terms{$_} ++ } @bks; 
                
                foreach my $thisbk (@unique_bks){
                    $logger->debug("Add: $isbn,$indicator,$thisbk");
                    $enrichrequest->execute($isbn,$indicator,$thisbk);                
                    $indicator++;
                }
            }
        }
    }
    elsif (@issns){
        foreach my $issn (@issns){
            $issn = OpenBib::Common::Util::grundform({
                category => '0543',
                content  => $issn,
            });
            
            # BK's
            {
                my $indicator = 1;
                
                # Dublette BK's entfernen
                my %seen_terms = ();
                my @unique_bks = grep { ! $seen_terms{$_} ++ } @bks; 
                
                foreach my $thisbk (@unique_bks){
                    $logger->debug("Add: $issn,$indicator,$thisbk");
                    $enrichrequest->execute($issn,$indicator,$thisbk);                
                    $indicator++;
                }
            }
        }
    }
    
$logger->debug("Processing done");
}

find(\&process_file, $inputdir);

sub print_help {
    print << "ENDHELP";
pica2enrich.pl - Anreicherung mit Informationen aus den PICA-Daten
    
   Optionen:
   -help                 : Diese Informationsseite

   -import-yml           : Import der YAML-Datei
   --filename=...        : Name der YAML-Datei
   --inputdir=...        : Dateiname der Dateibaums mit PICA-Dateien
   --logfile=...         : Name der Log-Datei

z.B. pica2enrich.pl --inputdir=xxx
       
ENDHELP
    exit;
}

