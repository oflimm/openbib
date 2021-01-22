#!/usr/bin/perl

#####################################################################
#
#  bestandsabgleich-nach-exemplar.pl
#
#  Abgleich des Bestandes *eines* Katalogs auf Mehrfachbesitz
#  anhand vorgegebener Standorte in den Exemplaren und
#  Ausgabe in eine csv-Datei
#
#  Fork von bestandsabgleich.pl
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@openbib.org>
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

my ($database,$location1,$location2,$help,$logfile,$loglevel,$selector,$filename);

&GetOptions(
    "database=s"      => \$database,
    "location1=s"     => \$location1,
    "location2=s"     => \$location2,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "filename=s"      => \$filename,
    "help"            => \$help
);

if ($help || !$location1 || !$location2 || !$filename){
    print_help();
}

$logfile =($logfile)?$logfile:'/var/log/openbib/bestandsabgleich-exemplare.log';
$loglevel=($loglevel)?$loglevel:'INFO';

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

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});

my $common_holdings_ref = $catalog->get_common_holdings({ location1 => $location1, location2 => $location2, config => $config});

my $csv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});


#my $csv = new Text::CSV_XS;

my $fh;

open $fh, ">:encoding(utf8)", $filename;

my $out_ref = [
    'katkey',
    'persons',
    'title',
    'title_supplement',
    'year',
    'loc_marks',
];

$csv->print($fh,$out_ref);

foreach my $item_ref (@{$common_holdings_ref}){
    my $out_ref = [
        $item_ref->{katkey},
        $item_ref->{persons},
        $item_ref->{title},
        $item_ref->{title_supplement},
        $item_ref->{year},
	$item_ref->{loc_marks},
    ];

    $csv->print($fh,$out_ref);
}

close $fh;

sub print_help {
    print << "HELP";
bestandsabgleich-nach-xemplar.pl - Abgleich des Bestandes *eines* Katalogs auf Mehrfachbesitz mehrerer Kataloge anhand einer Auswertung der Exemplare und
                      Ausgabe in eine csv-Datei

    bestandsabgleich-nach-exemplar.pl --database=Katalogname --location=StandortRegExp1 --location=StandortRexExp2 --filename=data.csv

Beispiel:

    ./bestandsabgleich-nach-exemplar.pl --database=inst001 --location1="^HWA" --location2="^Hauptabteilung"

Hinweid: Es koennen nur zwei Standorte verglichen werden
HELP
exit;
}
