#!/usr/bin/perl
#####################################################################
#
#  analyze_migration_holdings.pl
#
#  Analyse von Inkonsistenzen zwischen Exemplarinformationen in den
#  Titeldatenmultgruppen (5,14,16,1204) und den in den holdings-Tabellen
#  bei denen Buchdatensaetzen ein Vorrang eingeraeumt wird.
#
#  Dieses File ist (C) 2016 Oliver Flimm <flimm@openbib.org>
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
use JSON::XS qw/encode_json/;
use YAML;
use POSIX qw/strftime/;

use OpenBib::Config;
use OpenBib::Catalog::Factory;
use OpenBib::Common::Util;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my $config     = OpenBib::Config->new;

my ($database,$help,$logfile,$filename);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "filename=s"      => \$filename,
	    "help"            => \$help
	    );

if ($help || (!$database && !$filename)){
    print_help();
}

$logfile=($logfile)?$logfile:"/var/log/openbib/analyze_migration_holdings_${database}.log";
$filename=($filename)?$filename:"problematic_migration_holdings_$database.txt";

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

my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database});

open(OUT,">$filename");

my $title_marks_count_ref = {};

my $title_marks = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field'  => 14,
    },
    {
        select   => ['titleid',{ 'count' => 'titleid'}],
        as       => ['thistitleid','thiscount'],
        group_by => ['titleid'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

foreach my $title ($title_marks->all){
    my $titleid    = $title->{thistitleid};
    my $mark_count = $title->{thiscount};
    
    $title_marks_count_ref->{$titleid} = $mark_count;
}

my $title_holdings_count_ref = {};

my $title_holdings = $catalog->get_schema->resultset('TitleHolding')->search(
    undef,
    {
        select   => ['titleid',{ 'count' => 'holdingid'}],
        as       => ['thistitleid','thiscount'],
        group_by => ['titleid'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

foreach my $title ($title_holdings->all){
    my $titleid    = $title->{thistitleid};
    my $holding_count = $title->{thiscount};
    
    $title_holdings_count_ref->{$titleid} = $holding_count;
}

print OUT "Katkey\tExemplare_Titel\tExemplare_Buchdaten\n";

foreach my $titleid (keys %$title_marks_count_ref){
    my $this_marks_count    = $title_marks_count_ref->{$titleid};
    my $this_holdings_count = $title_holdings_count_ref->{$titleid};

    if ($this_marks_count ne $this_holdings_count){
	print OUT "$titleid\t$this_marks_count\t$this_holdings_count\n";
    }
}

close(OUT);

sub print_help {
    print << "ENDHELP";
analyze_migration_holdings.pl - Analyse der Konsistenz von Exemplarinformation


   Optionen:
   -help                 : Diese Informationsseite
       
   --database=inst001    : Datenbankname (USB=inst001)


ENDHELP
    exit;
}

