#!/usr/bin/perl
#####################################################################
#
#  gen_graphs.pl
#
#  Erzeugen von Graphen aus Statistik-Daten
#
#  Dieses File ist (C) 2007-2008 Oliver Flimm <flimm@openbib.org>
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
use Getopt::Long;
use Template;
use YAML;

use OpenBib::Config;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my ($type,$graph,$year,$month,$day,$help,$logfile);

&GetOptions("type=s"          => \$type,
	    "graph=s"         => \$graph,
	    "year=s"          => \$year,
	    "month=s"         => \$month,
	    "day=s"           => \$day,
	    
            "logfile=s"       => \$logfile,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/gen_graphs.log';

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

my $config     = OpenBib::Config->instance;
my $statistics = new OpenBib::Statistics();

if (!$type && !$graph){
  $logger->fatal("Kein Typ mit --type= und Graph mit --graph= ausgewaehlt");
  exit;
}

my ($thisday, $thismonth, $thisyear) = (localtime)[3,4,5];
$thisyear  += 1900;
$thismonth += 1;

$year   = $thisyear  if (!$year);
$month  = $thismonth if (!$month);
$day    = $thisday   if (!$day);

$month  = sprintf "%02d",$month;
$day    = sprintf "%02d",$day;

my $template = Template->new({ 
	    LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path}."/graph",

	    ABSOLUTE       => 1,
        }) ],
         OUTPUT_PATH   => $config->{image_root_path}."/graph",
         RECURSION      => 1,
    });

if (! -e "$config->{tt_include_path}/graph/$graph/$type"){
  $logger->fatal("Es existiert kein Template vom Typ $type und Graph $graph");
  exit;

}

if (! -e "$config->{image_root_path}/graph/$graph/$type"){
  mkdir "$config->{image_root_path}/graph/$graph/$type";
  $logger->info("Erstelle Verzeichnis "."$config->{image_root_path}/graph/$graph/$type");
}

# TT-Data erzeugen
my $ttdata={
	    statistics => $statistics,
	    year       => $year,
	    month      => $month,
	    day        => $day,

	    type       => $type,
	    graph      => $graph,
	    config     => $config,
	   };
  
$template->process("$graph/$type", $ttdata) || do {
  $logger->error($template->error());
};


sub print_help {
    print << "ENDHELP";
gen_bestof.pl - Erzeugen von Graphen aus Statistik-Daten

   Optionen:
   -help                 : Diese Informationsseite
   --logfile=...         : Alternatives Logfile
   --type=...            : Typ   ('sessions',...) 
   --graph=...           : Graph ('monthly',...)
   --year=, --month=, --day=

   Typen:

   'sessions' => Sessions
       
ENDHELP
    exit;
}

