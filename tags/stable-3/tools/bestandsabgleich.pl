#!/usr/bin/perl

#####################################################################
#
#  bestandsabgleich.pl
#
#  Abgleich des Bestandes auf Mehrfachbesitz mehrerer Kataloge
#  anhand des Selektors und Ausgabe in eine csv-Datei
#
#  Dieses File ist (C) 2009 Oliver Flimm <flimm@openbib.org>
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
use YAML::Syck;

my $config      = OpenBib::Config->instance;

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

my $dbh = DBI->connect("DBI:CSV:f_dir=.;csv_sep_char=,;csv_eol=\n");

my %database_lookup = ();
map { $database_lookup{$_} = 1 } @databases;


my @categories = sort keys %{$common_holdings_ref->[0]};

my $sql_create_table = "create table $filename (".join(",",map {"$_ CHAR(64)"} @categories).")";

$dbh->do("drop table $filename");

$logger->debug($sql_create_table);

my $request = $dbh->prepare($sql_create_table);
$request->execute(@categories);

foreach my $item_ref (@{$common_holdings_ref}){
    $logger->debug(YAML::Dump($item_ref));
    my $sql_insert = "insert into $filename (".join(',',@categories).") values (".join(',',map {'?'} @categories).")";

    $logger->debug($sql_insert);
    
    my @sql_args = ();
    
    foreach my $row (@categories){
        if ($database_lookup{$row}){
            push @sql_args, $item_ref->{$row}->{loc_mark};
        }
        else {
            push @sql_args, $item_ref->{$row};
        }       
    }
    $logger->debug("Args: ".join(',',@sql_args));
    $request = $dbh->prepare($sql_insert);
    $request->execute(@sql_args);
}

$request->finish;
$dbh->disconnect;

sub print_help {
    print << "HELP";
bestandsabgleich.pl - Abgleich des Bestandes auf Mehrfachbesitz mehrerer Kataloge anhand des Selektors
                      Ausgabe in eine csv-Datei

    bestandsabgleich.pl --selector=[ISBN13|ISSN|BibKey] --database=db1 --database=db2 --filename=data.csv
HELP
exit;
}
