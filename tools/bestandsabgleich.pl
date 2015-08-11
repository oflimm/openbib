#!/usr/bin/perl

#####################################################################
#
#  bestandsabgleich.pl
#
#  Abgleich des Bestandes auf Mehrfachbesitz mehrerer Kataloge
#  anhand des Selektors und Ausgabe in eine csv-Datei
#
#  Dieses File ist (C) 2009-2015 Oliver Flimm <flimm@openbib.org>
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

my (@databases,$help,$logfile,$selector,$filename);

&GetOptions("database=s@"     => \@databases,
            "logfile=s"       => \$logfile,
            "selector=s"      => \$selector,
            "filename=s"      => \$filename,
	    "help"            => \$help
	    );

if ($help || !@databases || !$selector || !$filename){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/bestandsabgleich.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=ERROR, LOGFILE, Screen
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

my $common_holdings_ref = $enrichmnt->get_common_holdings({ selector => $selector, databases => \@databases});

my $csv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});


#my $csv = new Text::CSV_XS;

my %database_lookup = ();
map { $database_lookup{$_} = 1 } @databases;

my @categories = sort keys %{$common_holdings_ref->[0]};

my $fh;

open $fh, ">:encoding(utf8)", $filename;

my $out_ref = [
    'selector',
    'persons',
    'title',
    'title_supplement',
    'year',    
];

foreach my $database (sort @databases){
    push @$out_ref, $database;
}

$csv->print($fh,$out_ref);

foreach my $item_ref (@{$common_holdings_ref}){
    my $out_ref = [
        $item_ref->{$selector},
        $item_ref->{persons},
        $item_ref->{title},
        $item_ref->{title_supplement},
        $item_ref->{year}
    ];

    foreach my $database (sort @databases){
        if ($item_ref->{$database}->{loc_mark}){
            push @$out_ref, $item_ref->{$database}->{loc_mark};
        }
        else {
            push @$out_ref, '-';
        }
    }

    $csv->print($fh,$out_ref);
}

close $fh;

sub print_help {
    print << "HELP";
bestandsabgleich.pl - Abgleich des Bestandes auf Mehrfachbesitz mehrerer Kataloge anhand des Selektors
                      Ausgabe in eine csv-Datei

    bestandsabgleich.pl --selector=[ISBN13|ISSN|BibKey] --database=db1 --database=db2 --filename=data.csv
HELP
exit;
}
