#!/usr/bin/perl
#####################################################################
#
#  update_tittag_sort.pl
#
#  Aktualisierung der Sortierungs-Informationen fuer vergebene Tags
#
#  Dieses File ist (C) 2014 Oliver Flimm <flimm@openbib.org>
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
use DBI;
use Getopt::Long;
use YAML;
use POSIX qw/strftime/;

use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::Common::Util;

my $config     = OpenBib::Config->new;

my ($help,$logfile,$incr);

&GetOptions(
    "logfile=s"       => \$logfile,
    "help"            => \$help
);

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/update_tittag_sort.log';

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

my $tittags = $config->get_schema->resultset('TitTag')->search_rs(
    {
        srt_person => \'IS NULL',
        srt_title  => \'IS NULL',
        srt_year   => \'IS NULL',
    },
);

while (my $tittag = $tittags->next()){
    my $record;
    
    eval {
        $record = OpenBib::Record::Title->new({database => $tittag->dbname, id => $tittag->titleid})->load_brief_record;
    };

    if ($@){
        $logger->error($@);
        next;
    }

    my $sortfields_ref = $record->get_sortfields;
    
    $tittag->update({
        srt_person => $sortfields_ref->{person},
        srt_title  => $sortfields_ref->{title},
        srt_year   => $sortfields_ref->{year},
    });
}

sub print_help {
    print << "ENDHELP";
update_tittag_sort.pl - Aktualisierung der Sortierungs-Informationen der getaggten Titel

   Optionen:
   -help                 : Diese Informationsseite
       
ENDHELP
    exit;
}

