#!/usr/bin/perl

#####################################################################
#
#  wikipedia_related_article2enrich.pl
#
#  Extrahierung relevanter Artikel und der darin genannten Literatur
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2008-2022 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;

use utf8;
use Encode;

use Business::ISBN;
use Encode qw/decode_utf8/;
use Getopt::Long;
use IO::File;
use IO::Uncompress::Gunzip;
use IO::Uncompress::Bunzip2;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use URI::Escape;
use XML::Twig;
use YAML;

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Schema::Enrichment;
use OpenBib::Common::Util;

# Autoflush
$|=1;

my ($help,$init,$jsonfile,$lang,$logfile,$loglevel);

my $lang2origin_ref = {
    'de' => '1',
    'en' => '2',
    'fr' => '3',
};

&GetOptions("help"        => \$help,
            "init"        => \$init,
	    "lang=s",     => \$lang,
	    "jsonfile=s"  => \$jsonfile,
            "loglevel=s"   => \$loglevel,
            "logfile=s"   => \$logfile,
	    );


if (!$jsonfile || !exists  $lang2origin_ref->{$lang}){
   print_help();
}

my $config = new OpenBib::Config;

$logfile=($logfile)?$logfile:"/var/log/openbib/wikipedia-related-article-enrichmnt-$lang.log";
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

# Verbindung zur SQL-Datenbank herstellen
my $enrichment = new OpenBib::Enrichment;

$logger->debug("Origin: ".$lang2origin_ref->{$lang});

if ($init){
    $logger->info("Loeschen der bisherigen Daten");
    
    $enrichment->get_schema->resultset('WikiarticleByIsbn')->search_rs({ origin => $lang2origin_ref->{$lang} })->delete;   
}

my $count=1;


if (! -e $jsonfile){
    $logger->error("JSON-Datei $jsonfile existiert nicht");
    exit;
}

open(JSON,"<",$jsonfile);

$logger->info("Einlesen und -laden der neuen Daten");

my $populate_related_isbn_ref = [];

while (<JSON>){
    my $item_ref = decode_json($_);

    push @$populate_related_isbn_ref, {
	article => $item_ref->{content},
	isbn => $item_ref->{isbn},
	origin => $lang2origin_ref->{$lang},
    };
    
    if ($count % 1000 == 0){
	$logger->info("Processed $count articles");
	$enrichment->get_schema->resultset('WikiarticleByIsbn')->populate($populate_related_isbn_ref);
	$populate_related_isbn_ref = [];
	
    }
    $count++;
}

$enrichment->get_schema->resultset('WikiarticleByIsbn')->populate($populate_related_isbn_ref);

$logger->info("Processed all $count articles");

close(JSON);
    
$logger->info("Ende und aus");

sub print_help {
    print << "ENDHELP";
wikipedia_related_article2enrich.pl - Bestimmen von Beziehungen zwischen Wikipedia-Artikeln fuer Anreicherungs-DB

   Optionen:
   -help                 : Diese Informationsseite
       
   --jsonfile=...        : Dateiname der Artikel-ISBN-JSON-Datei
   --lang=\[de\|en\|fr\]     : Sprache des Wikipedia-Dumps und der Artikel-Namen
   --logfile=...         : Name der Log-Datei

Bsp:
     wikipedia_related_article2enrich.pl -init --filename=frwiki-20080305-pages-articles.json --lang=fr

ENDHELP
    exit;
}
