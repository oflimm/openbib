#!/usr/bin/perl

#####################################################################
#
#  inject_json.pl
#
#  Einladen von Anreicherungsdaten im JSON-Format
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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
use utf8;

use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use MARC::Batch;
use MARC::Charset 'marc8_to_utf8';
use MARC::File::XML;
use JSON::XS;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;

my ($help,$key,$initorigin,$initfield,$jsonfile,$logfile,$loglevel);

&GetOptions("help"          => \$help,
            "init-origin=s" => \$initorigin,
            "init-field=s"  => \$initfield,
            "jsonfile=s"    => \$jsonfile,
            "key=s"         => \$key,
            "logfile=s"    => \$logfile,
            "loglevel=s"   => \$loglevel,
	    );

if ($help || !$key || !$jsonfile){
   print_help();
}

my $config = OpenBib::Config->instance;

$logfile=($logfile)?$logfile:"/var/log/openbib/inject_enrichment.log";
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

my $resultset = "EnrichedContentByIsbn";

my $enrichment = new OpenBib::Enrichment;

if ($key eq "isbn"){
    $resultset="EnrichedContentByIsbn";
}
elsif ($key eq "issn"){
    $resultset="EnrichedContentByIssn";
}
if ($key eq "bibkey"){
    $resultset="EnrichedContentByBibkey";
}

if ($initorigin || $initfield){
    $logger->info("Loeschen der bisherigen Daten");

    my $where_ref = {};

    if ($initorigin){
        $where_ref->{origin} = $initorigin;
    }

    if ($initfield){
        $where_ref->{field} = $initfield;
    }

    $enrichment->{schema}->resultset($resultset)->search_rs($where_ref)->delete;
}

if (! -e $jsonfile){
    $logger->error("JSON-Datei $jsonfile existiert nicht");
    exit;
}
open(JSON,$jsonfile);

my $count=1;

my $data_tuple_count = 1;

my $enrich_data_ref = [];

$logger->info("Einlesen und -laden der neuen Daten");

while (<JSON>){
    my $thisdata_ref = decode_json($_);

    my $content = $thisdata_ref->{content};
    
    foreach my $chunk (unpack( "(a2000)*", $content )) {
#        print length($chunk)." Chunk: $chunk\n";
        $thisdata_ref->{content} = $chunk;
        push @{$enrich_data_ref}, $thisdata_ref;
    }
    
    $data_tuple_count++;

    if ($count % 1000 == 0){
        $logger->info("$count Tupel eingeladen");
        $enrichment->{schema}->resultset($resultset)->populate($enrich_data_ref);
        $enrich_data_ref = [];
    }
    $count++;
}

if (@$enrich_data_ref){
    $enrichment->{schema}->resultset($resultset)->populate($enrich_data_ref);
}

$logger->info("$data_tuple_count Tupel eingefuegt");

close(JSON);

sub print_help {
    print << "ENDHELP";
inject_json.pl - Anreicherung mit Informationen

   Optionen:
   -help                 : Diese Informationsseite

   -init-origin=         : Zuerst Eintraege fuer dieses Origin aus Anreicherungsdatenbank loeschen
   -init-field=          : Zuerst Eintraege fuer dieses Feld aus Anreicherungsdatenbank loeschen
   -key=...              : Schluessel [isbn,issn,bibkey]

   --jsonfile=...        : Name der JSON-Einlade-Datei

   --logfile=...         : Name der Log-Datei
   --loglevel=...        : Loglevel (default: INFO)

ENDHELP
    exit;
}
