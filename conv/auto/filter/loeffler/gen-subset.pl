#!/usr/bin/perl

#####################################################################
#
#  gen-subset.pl
#
#  Extrahieren einer Titeluntermenge eines Katalogs
#  fuer die Erzeugung eines separaten neuen Katalogs
#
#  Dieses File ist (C) 2005-2011 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

use strict;
use warnings;
use utf8;

use Getopt::Long;
use OpenBib::Catalog::Subset;

use Log::Log4perl qw(get_logger :levels);

#if ($#ARGV < 0){
#    print_help();
#}

my ($help,$id);

my $pool=$ARGV[0];

&GetOptions(
	    "help" => \$help
	    );

if ($help){
    print_help();
}

my $logfile='/var/log/openbib/split-$pool.log';

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

my $subset = new OpenBib::Catalog::Subset("uni",$pool);
$subset->identify_by_field_content('title',([ { field => '0980', subfield => 's', content => '^Sammlung Klemens Löffler' } ]));
$subset->write_set;

sub print_help {
    print "gen-subset.pl - Erzeugen von Kataloguntermengen\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n\n";

    exit;
}
