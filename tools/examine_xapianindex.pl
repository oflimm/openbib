#!/usr/bin/perl

#####################################################################
#
#  examine_xapianindex.pl
#
#  Dieses File ist (C) 2007-2008 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;

my ($database,$help,$titid);

&GetOptions("database=s"      => \$database,
            "titid=s"         => \$titid,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, Screen
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = OpenBib::Config->instance;

if (!$database || !$titid){
  $logger->fatal("Kein Katalog mit --database= oder kein Titel mit --titid= ausgewaehlt");
  exit;
}

$logger->info("### POOL $database");

my %xapian_idmapping;

# Die DB xapian_idmapping.db wird bei dem Neu-Aufbau eines Katalogs erzeugt
# und liefert zu einem Katalogschluessel die entsprechende Xapian DocID

tie %xapian_idmapping, 'DB_File', $config->{'autoconv_dir'}."/pools/$database/xapian_idmapping.db";

my $docid=$xapian_idmapping{$titid};

unless ($docid){
    $logger->error_die("Keine Doc-ID zu diesem Titel gefunden");
}

system("delve -r $docid ".$config->{xapian_index_base_path}."/$database");

untie(%xapian_idmapping);

sub print_help {
    print << "ENDHELP";
examine_xapianindex.pl - Ausgabe des Term-Index von Xapian zu einem 
                         Katalogschluessel

   Optionen:
   -help                 : Diese Informationsseite
       
   --titid=              : Titelid
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
