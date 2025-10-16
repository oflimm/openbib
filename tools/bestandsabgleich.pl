#!/usr/bin/perl

#####################################################################
#
#  bestandsabgleich.pl
#
#  Abgleich des Bestandes auf Mehrfachbesitz mehrerer Kataloge
#  anhand des Selektors und Ausgabe in eine csv-Datei
#
#  Dieses File ist (C) 2009-2022 Oliver Flimm <flimm@openbib.org>
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

my (@locations,@databases,$help,$logfile,$loglevel,$selector,$filename);

&GetOptions(
    "location=s@"     => \@locations,
    "databases=s@"    => \@databases,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "selector=s"      => \$selector,
    "filename=s"      => \$filename,
    "help"            => \$help
);

if ($help || !@locations || !$selector || !$filename){
    print_help();
}

$logfile =($logfile)?$logfile:'/var/log/openbib/bestandsabgleich.log';
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

my $common_holdings_ref = $enrichmnt->get_common_holdings({ selector => $selector, locations => \@locations, databases => \@databases, config => $config});

my $csv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});


#my $csv = new Text::CSV_XS;

my %location_lookup = ();
map { $location_lookup{$_} = 1 } @locations;

my @categories = sort keys %{$common_holdings_ref->[0]};

my $fh;

open $fh, ">:encoding(utf8)", $filename;

my $out_ref = [
    'selector',
    'persons',
    'title',
    'title_supplement',
    'year',    
    'edition',    
];

foreach my $location (sort @locations){
    push @$out_ref, $location;
}

$csv->print($fh,$out_ref);

foreach my $item_ref (@{$common_holdings_ref}){
    my $out_ref = [
        $item_ref->{$selector},
        $item_ref->{persons},
        $item_ref->{title},
        $item_ref->{title_supplement},
        $item_ref->{year},
        $item_ref->{edition}
    ];

    foreach my $location (sort @locations){
	push @$out_ref, $item_ref->{$location}{loc_mark};
    }

    $csv->print($fh,$out_ref);
}

close $fh;

sub print_help {
    print << "HELP";
bestandsabgleich.pl - Abgleich des Bestandes auf Mehrfachbesitz mehrerer Kataloge anhand des Selektors
                      Ausgabe in eine csv-Datei

    bestandsabgleich.pl --selector=[ISBN13|ISSN|BibKey] --location=db1 --location=db2 --filename=data.csv
HELP
exit;
}
