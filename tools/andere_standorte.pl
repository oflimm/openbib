#!/usr/bin/perl

#####################################################################
#
#  andere_standorte.pl
#
#  Abgleich des Bestandes eines Standortes auf Besitz an anderen 
#  Standorten anhand des Selektors und Ausgabe in eine csv-Datei
#
#  Dieses File ist (C) 2009-2016 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

use Business::ISBN;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use Text::CSV_XS;
use YAML::Syck;

my $config      = OpenBib::Config->new;

my (@other_locations,$location,$help,$logfile,$loglevel,$selector,$filename);

&GetOptions(
    "other_location=s@"  => \@other_locations,
    "location=s"      => \$location,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "selector=s"      => \$selector,
    "filename=s"      => \$filename,
    "help"            => \$help
);

if ($help || !$location || !$selector || !$filename){
    print_help();
}

$logfile =($logfile)?$logfile:'/var/log/openbib/andere_standorte.log';
$loglevel=($loglevel)?$loglevel:'ERROR';

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

my $enrichmnt = new OpenBib::Enrichment;

my $other_locations_ref = $enrichmnt->get_other_locations({ selector => $selector, location => $location, other_locations => \@other_locations});

my $csv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});

my $fh;

open $fh, ">:encoding(utf8)", $filename;

my $out_ref = [
    'selector',
    'persons',
    'title',
    'title_supplement',
    'year',
    'other_locations'
];

$csv->print($fh,$out_ref);

foreach my $item_ref (@{$other_locations_ref}){
    my $out_ref = [
        $item_ref->{selector},
        $item_ref->{persons},
        $item_ref->{title},
        $item_ref->{title_supplement},
        $item_ref->{year},
	$item_ref->{other_locations}
    ];

    $csv->print($fh,$out_ref);
}

close $fh;

sub print_help {
    print << "HELP";
andere_standorte.pl - Abgleich des Bestandes auf Besitz an anderen Standorten anhand des Selektors
                      Ausgabe in eine csv-Datei

    andere_standorte.pl --selector=[ISBN13|ISSN|BibKey] --location=primary_location --other_location=loc1 --other_location=loc2 --filename=data.csv
HELP
exit;
}
