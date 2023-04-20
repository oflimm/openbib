#!/usr/bin/perl
#####################################################################
#
#  check_meta.pl
#
#  Ueberpruefung der JSON-Einladedateien im Metaformat auf potentielle Probleme
#  beim Import
#
#  Dieses File ist (C) 2023 Oliver Flimm <flimm@openbib.org>
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
use Getopt::Long;
use IO::File;
use IO::Uncompress::Gunzip;
use IO::Uncompress::Bunzip2;
use JSON::XS;
use Unicode::Collate;
use YAML;

use OpenBib::Config;
use OpenBib::Catalog;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::System;
use OpenBib::Statistics;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::User;

my ($filename,$help,$loglevel,$logfile);

&GetOptions(
    "filename=s"      => \$filename,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "help"            => \$help
    );

if ($help || !$filename){
    print_help();
}

$loglevel = ($loglevel)?$loglevel:"INFO";
$logfile  = ($logfile)?$logfile:'/var/log/openbib/check_meta.log';

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

my $config     = OpenBib::Config->new;

unless (-f $filename){
    $logger->error("Datei $filename existiert nicht.");
    exit;
}

my $input_io;

if ($filename){
    if ($filename =~/\.gz$/){
        $input_io = IO::Uncompress::Gunzip->new($filename);
    }
    elsif ($filename =~/\.bz2$/){
        $input_io = IO::Uncompress::Bunzip2->new($filename);
    }
    else {
        $input_io = IO::File->new($filename);
    }
}

while (<$input_io>){
    my $data_ref = decode_json $_;

    my $id = $data_ref->{id};
    
    if (!$id){
	$logger->error("ID fehlt bei $_");
    }

    foreach my $field (keys %{$data_ref->{fields}}){
	foreach my $field_ref (@{$data_ref->{fields}{$field}}){
	    if (!$field_ref->{content}){
		$logger->error("Feldinhalte zu $field in ID $id fehlt bei $_");
	    }
	}
    }
    
}
close $input_io;

sub print_help {
    print << "ENDHELP";
check_meta.pl - #  Ueberpruefung der JSON-Einladedateien im Metaformat auf potentielle Probleme beim Import


   Optionen:
   -help                 : Diese Informationsseite
   --filename=...        : Dateiname
   --logfile=...         : Alternatives Logfile
   --loglevel=...        : Alternatives Loglevel
ENDHELP
    exit;
}

