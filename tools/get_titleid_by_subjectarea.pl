#!/usr/bin/perl
#####################################################################
#
#  get_titleid_by_subjectarea.pl
#
#  Erzeugen von Listen aus Titel-IDs zu verschiedenen Themengebieten
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';
use utf8;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use DBIx::Class::ResultClass::HashRefInflator;
use Getopt::Long;
use Unicode::Collate;
use YAML;

use OpenBib::Catalog::Subset;

my ($type,$database,$outputfile,$area,$excludelabel,$help,$num,$logfile,$loglevel);

&GetOptions("type=s"          => \$type,
	    "area=s"          => \$area,
            "database=s"      => \$database,
            "outputfile=s"    => \$outputfile,
            "loglevel=s"      => \$loglevel,
	    "excludelabel=s"  => \$excludelabel,
            "logfile=s"       => \$logfile,	    
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$database=($database)?$database:'uni';
$outputfile=($outputfile)?$outputfile:"${area}.txt";
    
$logfile  = ($logfile)?$logfile:'/var/log/openbib/get_mmsid_by_subjectarea.log';
$loglevel = ($loglevel)?$loglevel:'INFO';

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

if (!$area){
  $logger->fatal("Kein Themengebiet mit --area= ausgewaehlt");
  exit;
}

our $subset = new OpenBib::Catalog::Subset($database,$outputfile);

my $process = "process_$area";

open(OUT,">:utf8", $outputfile);

if (exists &{$process}) {
    my $sub = \&{$process};

    $logger->info("Bestimmung der Titel-IDs zum Themengebiet $area");
    $sub->();

    # Ausgabe
    $logger->info("Ausgabe der Titel-IDs in Datei $outputfile");    
    foreach my $titleid (keys %{$subset->{titleid}}){
	next if (defined $subset->{exclude_titleid}{$titleid});
	print OUT "$titleid\n";
    }
}
else {
    $logger->error("Keine Bestimmung zu Themengebiet $area möglich");
    exit;
}

close(OUT);

sub process_sowi {
    # RVK
    $subset->identify_by_field_content('title',([ { field => '4101', content => '^M[NOPQRS] ' } ]));
    # DDC
    $subset->identify_by_field_content('title',([ { field => '0082', subfield => 'a', content => '^(300|360)' } ]));

    # ggf Ausschluss von Titeln mit bestimmter Markierung
    if ($excludelabel){
	$logger->info("Ausschluss von Titel-IDs mit Markierung $excludelabel");

	$subset->exclude_by_field_content('title',([ { field => '0980', subfield => 'a', content => '^'.$excludelabel.'$' } ]));
    }
}

sub process_wiwi {
    # RVK
    $subset->identify_by_field_content('title',([ { field => '4101', content => '^Q[ABEHKLPQRSTVX] ' } ]));
    # DDC
    $subset->identify_by_field_content('title',([ { field => '0082', subfield => 'a', content => '^(330|380|650)' } ]));

    # ggf Ausschluss von Titeln mit bestimmter Markierung
    if ($excludelabel){
	$logger->info("Ausschluss von Titel-IDs mit Markierung $excludelabel");

	$subset->exclude_by_field_content('title',([ { field => '0980', subfield => 'a', content => '^'.$excludelabel.'$' } ]));
    }
}

sub print_help {
    print << "ENDHELP";
get_titleid_by_subjectarea.pl - Erzeugen von Listen von Titel-IDs zu einem Themengebiet

   Optionen:
   -help                 : Diese Informationsseite
   --database=...        : Einzelner Katalog (nur mit MARC-Internformat)
   --outputfile=...      : Ausgabedatei
   --area=...            : Themengebiet
   --logfile=...         : Alternatives Logfile
   --type=...            : Metrik-Typ

   Themengebiete:

   sowi => Sozialwissenschaften
   wiwi => Wirtschaftswissenschaften

   Beispiel:

   ./get_titleid_by_subjectarea.pl --area=sowi --excludelabel=so

ENDHELP
    exit;
}

