#!/usr/bin/perl

#####################################################################
#
#  examine_xapianindex.pl
#
#  Dieses File ist (C) 2007-2015 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
use utf8;

BEGIN {
    $ENV{XAPIAN_PREFER_FLINT}    = '1';
}

use DB_File;
use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Config;
use OpenBib::Search::Factory;

my ($database,$help,$titleid,$statistics);

&GetOptions("database=s"      => \$database,
            "titleid=s"       => \$titleid,
            "statistics"      => \$statistics,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, Screen
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = OpenBib::Config->new;

if ($database && $statistics){
    $logger->info("Allgemeine Informationen zum Suchindex von $database");
    
    my $searcher = OpenBib::Search::Factory->create_searcher({database => $database, config => $config });

    my $doc_count = $searcher->get_number_of_documents;

    $logger->info("### POOL $database");

    $logger->info("### Anzahl indexierter Dokumente: $doc_count");    
}
elsif ($database && $titleid){
    $logger->info("Index for id $titleid in database $database");
    
    my $searcher = OpenBib::Search::Factory->create_searcher({database => $database, config => $config });
    
    $logger->info("### POOL $database");
    
    my $terms_ref = $searcher->get_indexterms({ database => $database, id => $titleid });
    
    $logger->info("### Termlist");
    
    $logger->info(join(' ',@$terms_ref));
    
    my $values_ref = $searcher->get_values({ database => $database, id => $titleid });
    
    $logger->info("### Values");
    $logger->info(YAML::Dump($values_ref));
}
else {
  $logger->fatal("Keine korrekten Aufrufparameter");
}       

sub print_help {
    print << "ENDHELP";
examine_xapianindex.pl - Ausgabe des Term-Index von Xapian zu einem 
                         Katalogschluessel

   Optionen:
   -help                 : Diese Informationsseite

   -statistics           : Allgemeine Statistikinformationen

   ODER

   --titleid=            : Titelid
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
