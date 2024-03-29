#!/usr/bin/perl
#####################################################################
#
#  dump_pool.pl
#
#  Export eines Katalogs (DB+Index) als OpenBib Pool Package Datei (.opp)
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@openbib.org>
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

my ($database,$filename,$help,$loglevel,$logfile);

&GetOptions(
    "database=s"      => \$database,
    "filename=s"      => \$filename,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "help"            => \$help
    );

if ($help){
    print_help();
}

$loglevel = ($loglevel)?$loglevel:"INFO";
$logfile  = ($logfile)?$logfile:'/var/log/openbib/dump_pool.log';
$filename = ($filename)?$filename:"${database}.opp";

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

my $tmpdir     = "/opt/openbib/autoconv/data/$database";

my $pg_dump    = "/usr/bin/pg_dump";
my $gzip       = "/bin/gzip";
my $tar        = "/bin/tar";

if (!$config->db_exists($database)){
    $logger->error("Katalog $database existiert nicht");
    exit;
}

if (!-d $tmpdir){
    mkdir $tmpdir;
}

unlink $filename;

system("echo \"*:*:*:$config->{'dbuser'}:$config->{'dbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");

$logger->info("Dumping database $database");

system("$pg_dump -U $config->{'dbuser'} -F c -b -f  $tmpdir/pool.dump $database");

$logger->info("Dumping done");

if (! -d "$config->{'base_dir'}/ft/xapian/index/$database"){
    $logger->error("No xapian index directory. Exiting. ");
    exit;
}

$logger->info("Dumping index of database $database");

system("cd $config->{'base_dir'}/ft/xapian/index/ ; tar czf $tmpdir/index.tgz $database ${database}_authority");

$logger->info("Dumping done");

if (! -f "$tmpdir/pool.dump" || ! -f "$tmpdir/index.tgz"){
    $logger->error("Dump von Katalog oder Index existiert nicht. Cleanup.");
    unlink  "$tmpdir/pool.dump";
    unlink  "$tmpdir/index.tgz";
    exit;
}

$logger->info("Generating opp package file $filename");

system("tar --directory=$tmpdir -cf ./${filename} pool.dump index.tgz ; rm $tmpdir/pool.dump $tmpdir/index.tgz");

$logger->info("Dumping done");


sub print_help {
    print << "ENDHELP";
dump_pool.pl - Export eines Pools (DB+Index) als OpenBib Pool Package Archiv (.opp)

   Optionen:
   -help                 : Diese Informationsseite
   --database=...        : Name des Katalogs
   --filename=...        : Ausgabedatei (default: <databasename>.opp)
   --logfile=...         : Alternatives Logfile
   --loglevel=...        : Alternatives Loglevel
ENDHELP
    exit;
}

