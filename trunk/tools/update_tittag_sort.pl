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

my $config     = OpenBib::Config->instance;

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

my $tittags = $config->{schema}->resultset('TitTag')->search_rs(
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

    my $person_field = $record->get_field({ field => 'PC0001' });
    my $title_field  = $record->get_field({ field => 'T0331' });
    my $year_field   = $record->get_field({ field => 'T0425' });

    if (!defined $year_field->[0]{content}){
        $year_field   = $record->get_field({ field => 'T0424' });
    }

    my $srt_person = OpenBib::Common::Util::normalize({
        content => $person_field->[0]{content}
    });
    my $srt_title  =  OpenBib::Common::Util::normalize({
        content => $title_field->[0]{content},
        field   => 'T0331',
    });
    my $srt_year   =  OpenBib::Common::Util::normalize({
        content => $year_field->[0]{content},
        field   => 'T0425',
    });
                                                           
    $tittag->update({
        srt_person => $srt_person,
        srt_title  => $srt_title,
        srt_year   => $srt_year,
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

