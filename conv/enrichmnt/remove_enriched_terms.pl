#!/usr/bin/perl

#####################################################################
#
#  remove_enriched_terms.pl
#
#  Entfernen von Begriffen aus der Anreicherungsdatenbank
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;

my ($help,$field,$filename,$withregex,$logfile);

&GetOptions("help"       => \$help,
            "field=s"    => \$field,
            "with-regex" => \$withregex,
            "filename=s" => \$filename,
            "logfile=s"  => \$logfile,
	    );

if ($help){
   print_help();
}

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/remove_enriched_terms.log";

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

open(BLACKLIST, $filename);

$logger->info("Entfernen der Terme");

while (my $term=<BLACKLIST>){
    chomp($term);
    $logger->info("Term: $term");

    my $where_ref = {
    };

    if ($field){
	$where_ref->{field} = $field;
    }

    if ($withregex){
	$where_ref->{content} = { '~' => $term	};
    }
    else {
	$where_ref->{content} = $term;
    }

    $logger->info(YAML::Dump($where_ref));
#    $enrichment->get_schema->resultset('EnrichedContentByIsbn')->search_rs({ field => '4100', origin => $origin })->delete;

}

sub print_help {
    print << "ENDHELP";
remove_enriched_terms.pl - Entfernung angereicherter Terme

   Optionen:
   -help                 : Diese Informationsseite

   -with-regex           : Terme als regulaere Ausdruecke interpretieren
   --field=...           : Begrenzung der Term-Entfernung auf ein Feld
   --filename=...        : Dateiname mit den Termen
   --logfile=...         : Name der Log-Datei

ENDHELP
    exit;
}

