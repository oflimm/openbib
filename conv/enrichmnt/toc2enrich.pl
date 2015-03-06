#!/usr/bin/perl

#####################################################################
#
#  toc2json.pl
#
#  Extrahierung der Links zu Anreicherungsinformationen des hbz
#  Digitalisierungsservers fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2010-2013 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use warnings;
use strict;

use YAML::Syck;

use Business::ISBN;
use Encode qw(decode_utf8 decode);
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Encode::MAB2;
use MAB2::Record::Base;
use Tie::MAB2::Recno;
use File::Find;
use File::Slurp;
use DB_File;
use Storable ();
use JSON::XS qw(encode_json);

use OpenBib::Enrichment;
use OpenBib::Common::Util;
use OpenBib::Config;

# Autoflush
$|=1;

my ($help,$filename,$logfile,$tocdir,$initdb,$hbzidmappingfile);

&GetOptions("help"        => \$help,
            "initdb"      => \$initdb,
            "hbzidmappingfile=s" => \$hbzidmappingfile,
            "filename=s" => \$filename,
            "tocdir=s"    => \$tocdir,
            "logfile=s"   => \$logfile,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/toc2json.log";
$filename=($filename)?$filename:"./isbndata.db";

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

my $enrichment = new OpenBib::Enrichment;

my $origin = 24;

open(OUT,">:raw",$filename);

$logger->debug("Origin: $origin");

our %hbzid2isbn = ();

tie %hbzid2isbn,         'DB_File', "./hbzid2isbn.db"
    or die "Could not tie ISBN data.\n";


if ($initdb){
    $logger->info("Mapping hbzid -> isbn13 aus mapping-Datei generieren");

    %hbzid2isbn = ();
    my $i = 1;

    open (MAPPING,"$hbzidmappingfile");
    while (<MAPPING>) {
        my ($hbzid,$isbn)=split /:/;
    
        my $isbnXX = Business::ISBN->new($isbn);
        
        if (defined $isbnXX && $isbnXX->is_valid) {
            $isbn = $isbnXX->as_isbn13->as_string;
        } else {
            next;
        }
    
        $isbn = OpenBib::Common::Util::normalize({
            field   => 'T0540',
            content => $isbn,
        });
    
        $hbzid2isbn{$hbzid} = $isbn;
    
        if ($i % 10000 == 0) {            
            $logger->info("$i hbz IDs analysiert");
        }
        $i++;
    }
    close(MAPPING);
}

$logger->info("TOC-Dateien einlesen, normieren und JSON ausgeben");

find(\&process_file, $tocdir);

close(OUT);

sub print_help {
    print << "ENDHELP";
toc2json.pl - Erzeugung von Anreicherunginformationen mit Inhaltsverzeichnissen

   Optionen:
   -help                 : Diese Informationsseite


   --filename=...        : Dateiname der JSON-Ausgabe-Datei
   --hbzidmappingfile=...: Dateiname der hbz Mapping-Datei hbzid->isbn13
   --tocdir=...          : Dateiname des Verzeichnisses mit TOCs
   --logfile=...         : Name der Log-Datei

ENDHELP
    exit;
}

sub process_ocr {
    my ($ocr)=@_;

    # Preambel entfernen
    $ocr=~s/ocr-text://;

    # Nur noch eine Zeile
    $ocr=~s/\n/ /g;

    # Mindestens drei Zeichen
    $ocr=~s/\s+.{0,3}\s+/ /g;

    # Roemische Zahen weg
    $ocr=~s/\s+M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})\s+/ /gi;

    $ocr=~s/(Inhaltsverzeichnis|Seite|Page|Table\s+Of\s+Contents|Chapter|Vorwort|Geleitwort|Abbildungsverzeichnis|Abkürzungsverzeichnis|Einleitung|Preface|Contents|Introduction|http:\/\/.*?\s|Appendix|Index|References)/ /gi;
    
    $ocr=OpenBib::Common::Util::normalize({ content => $ocr });

    $ocr=~s/[^\p{Alphabetic}]/ /g;

    $ocr=~s/\s\d+(\.\d)+\s/ /g;
    $ocr=~s/-/ /g;
    $ocr=~s/,/ /g;
    $ocr=~s/,/ /g;
    $ocr=~s/\d+\.?/ /g;

    # Dublette Inhalte entfernen
    my %seen_terms = ();
    $ocr = join(" ",grep { ! $seen_terms{lc($_)} ++ } split ("\\s+",$ocr)); 
        
    return $ocr;
}    

sub process_file {
    return unless (-f $File::Find::name);

#    my $slurped_file = decode("iso-8859-1",read_file($File::Find::name));
    my $slurped_file = decode_utf8(read_file($File::Find::name));

    $slurped_file = process_ocr($slurped_file);
    
    my ($hbzid) = $File::Find::name =~m/\/([a-z0-9]*?)\.txt$/;

    my $isbn = $hbzid2isbn{$hbzid};

    return unless ($isbn && $slurped_file);

#    print "$hbzid - $isbn - $slurped_file\n";
    
    my $this_toc = {
        content  => $slurped_file,
        origin   => $origin,
        subfield => '',
        isbn     => $isbn,
        field    => 4111,
    };

    print OUT encode_json($this_toc), "\n";

}
