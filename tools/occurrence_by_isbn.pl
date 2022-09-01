#!/usr/bin/perl

#####################################################################
#
#  occurence_by_isbn.pl
#
#  Vorkommen eines Titels nach ISBN in einem Katalog
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

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Normalizer;

use Business::ISBN;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use YAML::Syck;

my $config      = OpenBib::Config->new;
my $normalizer  = OpenBib::Normalizer->new;

my ($database,$filename,$help,$logfile,$loglevel);

&GetOptions("database=s"            => \$database,
            "filename=s"            => \$filename,
            "logfile=s"             => \$logfile,
            "loglevel=s"            => \$loglevel,
	    "help"                  => \$help
	    );

if ($help || !$database){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/occurence_by_isbn.log';
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

my $enrichmnt = new OpenBib::Enrichment;

my @isbns = ();

open(IN,$filename);

while (my $thisisbn=<IN>){

    if ($thisisbn=~m/^\d\d\d\d.\d\d\d\:(.+)$/){
	$thisisbn=$1;
    }

    # Normierung auf ISBN13
    my $isbn13 = Business::ISBN->new($thisisbn);
    
    if (defined $isbn13 && $isbn13->is_valid){
	$thisisbn = $isbn13->as_isbn13->as_string;
    }
    else {
	$logger->debug("ISBN $thisisbn nicht gueltig!");
	
	if ($thisisbn=~m/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/){
	    $thisisbn="$1$2$3$4$5$6$7$8$9$10$11$12$13";
	}
	elsif ($thisisbn=~m/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/){
	    $thisisbn="$1$2$3$4$5$6$7$8$9$10";
	}
	else {
	    $logger->debug("ISBN $thisisbn hat auch nicht die Form einer ISBN. Ignoriert.");
	    next;
	}
	
	$logger->debug("ISBN $thisisbn hat aber zumindest die Form einer ISBN. Verarbeitet.");
    }

    $thisisbn = $normalizer->normalize({
        field => 'T0540',
        content  => $thisisbn,
    });

    push @isbns, $thisisbn;
}

close($filename);

# Testsatz @isbns=('9783658052362');

my $isbn_titles = $enrichmnt->get_schema->resultset('AllTitleByIsbn')->search(
    {
        dbname  => $database,
        isbn    => { -in => \@isbns },
    },
    {
	group_by => [ 'isbn','dbname' ],
        select   => [ 'isbn',{'count' => {'distinct' => 'titleid'}} ],
	as       => [ 'isbn','titlecount' ],
	result_class => 'DBIx::Class::ResultClass::HashRefInflator',	
    }
);

while (my $this_isbn_title = $isbn_titles->next()){
    my $titlecount = $this_isbn_title->{titlecount};
    my $isbn       = $this_isbn_title->{isbn};

    print "$isbn\t$titlecount\n";
}
