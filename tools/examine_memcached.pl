#!/usr/bin/perl

#####################################################################
#
#  examine_memcached.pl
#
#  Untersuchen des memached-Caches
#
#  Dieses File ist (C) 2018 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';
use utf8;

use Getopt::Long;
use YAML;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

my $config = new OpenBib::Config;

my ($help,$logfile,$loglevel,$memc_key,$list,$flush,$show);

&GetOptions(
    "logfile=s"         => \$logfile,
    "loglevel=s"        => \$loglevel,
    "key=s"             => \$memc_key,
    "flush"             => \$flush,
    "show"              => \$show,
    "list"              => \$list,
    "help"              => \$help
    );

if ($help || (!$show && !$flush && !$list)){
    print_help();
}

$loglevel=($loglevel)?$loglevel:'ERROR';
$logfile=($logfile)?$logfile:'/var/log/openbib/examine_memcached.log';

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


if ($memc_key){

    if ($show){
	my $value_ref = $config->{memc}->get($memc_key);
	
	print YAML::Dump($value_ref);
    }
    elsif ($flush){
	$config->{memc}->delete($memc_key);
    }

}
elsif ($list){
}

sub print_help {
    print << "ENDHELP";
examine_memcached.pl - Untersuchen von Inhalten in Memcached von OpenBib


   Optionen:
   -help                 : Diese Informationsseite
       
   -key=...              : Memcached Schluessel
   -show                 : Anzeigen des Inhaltes aus Memcached zum angegebenen Schluessel
   -flush                : Inhalte zum angegebenen Schluessel aus Memcached entfernen

ENDHELP
    exit;
}
