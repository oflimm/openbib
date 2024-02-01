#!/usr/bin/perl
#####################################################################
#
#  update_classifications.pl
#
#  Aktualisierung einer Klassifikation (z.B. RVK) in der System-Datenbank
#  aus einer YAML-Datei
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

use warnings;
use strict;

use utf8;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use Getopt::Long;
use Unicode::Collate;
use YAML::Syck;

use OpenBib::Config;

my ($type,$inputfile,$help,$logfile,$loglevel);

&GetOptions("type=s"          => \$type,
            "inputfile=s"     => \$inputfile,
            "loglevel=s"      => \$loglevel,
            "logfile=s"       => \$logfile,	    
	    "help"            => \$help
	    );

if ($help || !$type){
    print_help();
}

$logfile  = ($logfile)?$logfile:'/var/log/openbib/update_classifications.log';
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

$YAML::Syck::ImplicitTyping  = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $config = OpenBib::Config->new;

my $yaml_ref = YAML::Syck::LoadFile($inputfile);

$logger->info("Purging data for classification $type");

$config->get_schema->resultset('Classification')->search({ type => $type })->delete;
$config->get_schema->resultset('Classificationshierarchy')->search({ type => $type })->delete;

$logger->info("Importing new data for classification $type");

$logger->info("Importing descriptions");

my $idx = 1;
my $descriptions_ref = [];
foreach my $classification (keys %{$yaml_ref->{description}}){
    push @$descriptions_ref, {
	type => $type,
	name => $classification,
	description => $yaml_ref->{description}{$classification}
    };

    if ($idx % 10000 == 0){
	$config->get_schema->resultset('Classification')->populate($descriptions_ref);
	$logger->info("Processed $idx descriptions");
	$descriptions_ref = [];
    }
    
    $idx ++;
}
$logger->info("Processed $idx descriptions");
$config->get_schema->resultset('Classification')->populate($descriptions_ref);

$logger->info("Importing hierarchy");

$idx = 1;
my $hierarchies_ref = [];
foreach my $classification (keys %{$yaml_ref->{hierarchy}}){
    my $number = 1;    
    foreach my $subname (@{$yaml_ref->{hierarchy}{$classification}}){
	push @$hierarchies_ref, {
	    type => $type,
	    name => $classification,
	    subname => $subname,
	    number => $number
	};
	$number++;
    }

    if ($idx % 10000 == 0){
	$config->get_schema->resultset('Classificationshierarchy')->populate($hierarchies_ref);
	$logger->info("Processed hierarchies for $idx classifications");
	$hierarchies_ref = [];
    }

    $idx++;
}
$logger->info("Processed hierarchies for $idx classifications");
$config->get_schema->resultset('Classificationshierarchy')->populate($hierarchies_ref);


sub print_help {
    print << "ENDHELP";
update_classifications.pl - Import einer Klassifikation in die System-DB aus einer YAML-Datei

   Optionen:
   -help                 : Diese Informationsseite
   --inputfile=...       : YAML-Datei
   --type=...            : Typ der Klassifikation (rvk,bk,...)
   --logfile=...         : Logfile
   --loglevel=...        : Loglevel

ENDHELP
    exit;
}

