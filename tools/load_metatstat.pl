#!/usr/bin/perl
#####################################################################
#
#  load_metastat.pl
#
#  Einladen von Metastat-Ausleihdaten
#
#  Dieses File ist (C) 2016-2022 Oliver Flimm <flimm@openbib.org>
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

use Business::ISBN;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use Getopt::Long;
use YAML;
use Digest::MD5;
use DBIx::Class::ResultClass::HashRefInflator;

use OpenBib::Enrichment;
use OpenBib::Statistics;
use OpenBib::Normalizer;

my ($filename,$date,$help,$logfile);

&GetOptions("filename=s"      => \$filename,
            "date=s"          => \$date,
	    "help"            => \$help
    );

$logfile=($logfile)?$logfile:'/var/log/openbib/load_metastat.log';

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

my $enrichmnt  = OpenBib::Enrichment->new;
my $normalizer = OpenBib::Normalizer->new;

unless (-e $filename){
    $logger->error("Datei $filename existiert nicht");
}

if ($filename=~/(\d\d\d\d\d\d\d\d)/){
    $date=$1;
}

unless ($date){
    $logger->error("Kein Datum vorhanden - weder im Dateinamen noch als Parameter");
    exit;
}

my ($year,$month,$day)=$date=~/(\d\d\d\d)(\d\d)(\d\d)/;

unless ($year && $month && $day){
    $logger->error("Kein valides Datum vorhanden");
    exit;
}

my $statistics = OpenBib::Statistics->new;

my $rows_ref = [];

if ($filename=~/\.gz$/){
    open(IN,"zcat $filename|");
}
else {
    open(IN,$filename);
}

my $idx=0;

my $loans = $statistics->get_schema->resultset('Loan');
    
while (<IN>){
    my ($borrow_date,$groupid,$anon_userid,$isbn,$dbname,$titleid,$dummy) = split("\\|",$_);

    # Normierung auf ISBN13
    if ($isbn){
	my $isbn13 = Business::ISBN->new($isbn);
	
	if (defined $isbn13 && $isbn13->is_valid){
            $isbn = $isbn13->as_isbn13->as_string;
        }

	# Normierung als String
        $isbn = $normalizer->normalize({
            field   => 'T0540',
            content => $isbn,
        });

    }
    else {
	# Sonst aus all_titles-Tabelle holen.
	my $isbns = $enrichmnt->get_schema->resultset('AllTitleByIsbn')->search(
	    {
		dbname  => $dbname,
		titleid => $titleid,
	    },
	    {
		select => ['isbn'],
		as     => ['thisisbn'],
		rows   => 1,
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',

	    }
	    );
	if ($isbns){
	    while (my $thisisbn = $isbns->next()){
		$isbn = $thisisbn->{thisisbn};
	    }

#	    $logger->info("$dbname - $titleid - $isbn");
	}
	
    }

    my $tstamp = "$year-$month-$day 00:00:00";
    
    my $thisrow_ref = {
	anon_userid  => $anon_userid,
	groupid      => $groupid,
	dbname       => $dbname,
	titleid      => $titleid,
	isbn         => $isbn,
	tstamp_year  => $year,
	tstamp_month => $month,
	tstamp_day   => $day,
	tstamp       => $tstamp,
    };

#    $logger->info(YAML::Dump($thisrow_ref));
    push @$rows_ref, $thisrow_ref;

    $idx++;

    if ($idx % 1000 == 0){
	$loans->populate($rows_ref);
	$rows_ref = [];
	$logger->info("$idx done");
    }

}

$loans->populate($rows_ref);

close(IN);

# Moegliche Auswertungen
#
# 1) Ausleihen pro Tag und Benutzergruppe fuer ein Jahr
#
#    select tstamp,groupid,count(tstamp) from loans where tstamp_year=2007 group by tstamp,groupid order by tstamp,groupid;
#
#
