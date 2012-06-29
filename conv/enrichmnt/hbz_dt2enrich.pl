#!/usr/bin/perl

#####################################################################
#
#  hbz_dt2enrich.pl
#
#  Extrahierung der Links zu Anreicherungsinformationen des hbz
#  Digitalisierungsservers fuer eine Anreicherung per ISBN
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

use utf8;

use YAML::Syck;
use DBI;

use Business::ISBN;
use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Encode::MAB2;
use MAB2::Record::Base;
use Tie::MAB2::Recno;
use File::Slurp;
use DB_File;
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Common::Util;
use OpenBib::Config;

# Autoflush
$|=1;

my ($help,$usedbfile,$filename,$logfile,$ocrdir,$mabfile);

&GetOptions("help"        => \$help,
            "use-dbfile"  => \$usedbfile,
            "mabfile=s"   => \$mabfile,
            "filename=s"  => \$filename,
            "ocrdir=s"    => \$ocrdir,
            "logfile=s"   => \$logfile,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->instance;

$logfile=($logfile)?$logfile:"/var/log/openbib/hbz_dt-enrichmnt.log";
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

# Verbindung zur SQL-Datenbank herstellen
my $enrichdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
    or $logger->error_die($DBI::errstr);

# 24 = HBZ
my $origin = 24;

my $deleterequest     = $enrichdbh->prepare("delete from normdata where category=4110 and origin=$origin");
my $ocr_deleterequest = $enrichdbh->prepare("delete from normdata where category=4111 and origin=$origin");
my $publ_deleterequest = $enrichdbh->prepare("delete from normdata where category=4125 and origin=$origin");
my $enrichrequest     = $enrichdbh->prepare("insert into normdata values(?,$origin,4110,?,?)");
my $ocr_enrichrequest = $enrichdbh->prepare("insert into normdata values(?,$origin,4111,?,?)");
my $publ_enrichrequest = $enrichdbh->prepare("insert into normdata values(?,$origin,4125,?,?)");

unless ($usedbfile){
    unlink $filename;
}

my %isbndata = ();

tie %isbndata,         'MLDBM', "$filename"
    or die "Could not tie ISBN data.\n";


if ($usedbfile){
    $logger->info("Verwendung der Daten aus DB-Datei $filename");
}
else {
    $logger->info("Neue DB-Datei $filename verwenden");

    %isbndata = ();
    
    tie @mab2titdata, 'Tie::MAB2::Recno', file => $mabfile;

    $i=1;
    foreach my $rawrec (@mab2titdata){
        my $rec = MAB2::Record::Base->new($rawrec);
        #print $rec->readable."\n----------------------\n";    
        my $title_ref = {};
        my $thisisbn_ref = [];
        
        foreach my $category_ref (@{$rec->_struct->[1]}){
            my $category  = $category_ref->[0];
            my $indicator = $category_ref->[1];
            my $content   = $category_ref->[2];

            # Titel-ID sowie Ueberordnungs-ID
            if ($category =~ /^001$/){
                $content=lc($content);
                $title_ref->{id}=$content ;
            }
        
        
            if ($category =~ /^002$/){
                $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
            }

            if ($category =~ /^540$/){
                $content=~s/^ISBN //;
                $content=~s/^(\S+)(\s.+?)/\1/;
                push @{$thisisbn_ref}, $content;
            }

            if ($category =~ /^655$/){
#                print "---- $indikator - $content\n";
                @subfields = split("",$content);
                my $thisenrich_ref = {};
                foreach my $subfield (@subfields){
                    my ($subindikator,$subcontent)=$subfield=~m/^([a-z])(.+?)$/;
#                    print "## $subindikator - $subcontent\n";
                    if ($subindikator eq "x"){
                       $thisenrich_ref->{type} = $subcontent;
                    }
                    if ($subindikator eq "u"){
                       $thisenrich_ref->{url} = $subcontent;
                    }
                }
                push @{$title_ref->{enrich}}, $thisenrich_ref;                
            }
         }

        foreach my $isbn (@{$thisisbn_ref}){
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

            my @thisdata = exists ($isbndata{$isbn})?@{$isbndata{$isbn}}:();
            push @thisdata, $title_ref;

            $isbndata{$isbn} = \@thisdata;
        }

        if ($i % 10000 == 0){            
           $logger->info("$i Titel analysiert");
        }
        $i++;
    }    
}

$logger->info("Loeschen der bisherigen Daten");
$deleterequest->execute();
$ocr_deleterequest->execute();

$logger->info("Einladen der neuen Daten in die Datenbank");

foreach my $thisisbn (keys %isbndata){
    next if (!$thisisbn);

    $logger->debug("ISBN: $thisisbn");

    $logger->debug("YAML: ".YAML::Dump($isbndata{$thisisbn}));

    # Dublette Inhalte entfernen
    my $toc_indicator=1;

    foreach my $item (@{$isbndata{$thisisbn}}){
        my $id     = $item->{id};
        my @enrich = @{$item->{enrich}};
        foreach my $thisitem_ref (@enrich){
            $logger->debug("ITEM: ".YAML::Dump($thisitem_ref));
            if ($thisitem_ref->{type} eq "Inhaltsverzeichnis"){        
               $enrichrequest->execute($thisisbn,$toc_indicator,$thisitem_ref->{url});
               $logger->debug("TOC-URL: $thisitem_ref->{url}");

               my $ocrfile = $ocrdir."/".$id.".txt";

               $logger->debug("OCR-File: $ocrfile");
               if ($ocrdir && -e $ocrfile){
                   my $slurped_file = decode_utf8(read_file($ocrfile));
                   if ($slurped_file){
                       my $ocr = process_ocr($slurped_file);
                       $ocr_enrichrequest->execute($thisisbn,$toc_indicator,$ocr);
                       $logger->debug("TOC-OCR: $ocr");
                   }
               }
               $toc_indicator++;
            }
            elsif ($thisitem_ref->{type} =~/^Verlagsdaten/){        
               $publ_enrichrequest->execute($thisisbn,1,$thisitem_ref->{url});
            }
#        else {
#            $logger->info("Typ: $thisitem_ref->{type}");
#        }
        }
        }
    }
sub print_help {
    print << "ENDHELP";
hbz_dt2enrich.pl - Anreicherung mit Informationen aus den hbz-Daten

   Optionen:
   -help                 : Diese Informationsseite

   -use-dbfile           : Verwendung der DB-Datei
   --filename=...        : Dateiname der DB-Datei (default: ./isbndata.db)
   --mabfile=...         : Dateiname der hbz MAB2-Datei
   --ocrdir=...          : Dateiname des Verzeichnisses mit OCR-Texten
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

    $ocr=OpenBib::Common::Util::grundform({ content => $ocr });

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
