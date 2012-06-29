#!/usr/bin/perl
#####################################################################
#
#  gen_popularity.pl
#
#  Erzeugen von Popularitaetsinformationen zu Titeln und Anreicherung
#  im Katalog durch separate popularity-Tabelle
#
#  Dieses File ist (C) 2006-2008 Oliver Flimm <flimm@openbib.org>
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
use YAML;

use OpenBib::Config;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my $config = OpenBib::Config->instance;

my ($database,$help,$logfile);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/gen_popularity.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
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

my $statistics = new OpenBib::Statistics();

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

my $request=$statistics->{dbh}->prepare("select katkey, count(katkey) as kcount from relevance where origin=2 and dbname=? group by katkey");
$request->execute($database);

my @popularity=();
while (my $res    = $request->fetchrow_hashref){
  push @popularity, {
		     id      => $res->{katkey},
		     idcount => $res->{kcount},
		    };
}
$request->finish();

my $dbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
    or $logger->error_die($DBI::errstr);

$request=$dbh->do("truncate table popularity");
$request=$dbh->prepare("insert into popularity values (?,?)");

foreach my $item_ref (@popularity){
    $request->execute($item_ref->{id},$item_ref->{idcount});
}

$logger->info("Inserted ".($#popularity+1)." popularity titlesets into pool $database");

$request->finish();
$dbh->disconnect();

sub print_help {
    print << "ENDHELP";
gen_popularity.pl - Erzeugen Popularitaetsinformationen pro Titel

   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Datenbankname


ENDHELP
    exit;
}

