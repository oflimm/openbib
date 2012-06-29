#!/usr/bin/perl
#####################################################################
#
#  update_all_normdata_table.pl
#
#  Aktualisierung der all_normdata-Tabelle, in der die Ansetzungsformen
#  einzelner Normdatenarten aller Kataloge nachgewiesen sind.
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Common::Util;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my $config = OpenBib::Config->instance;

my ($database,$help,$logfile,$incr);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "incr"            => \$incr,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/update_all_normdata.log';

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

my @databases=();

# Wenn ein Katalog angegeben wurde, werden nur in ihm die Titel gezaehlt
# und der Counter aktualisiert

if ($database ne ""){
    @databases=("$database");
}
# Ansonsten werden alle als Aktiv markierten Kataloge aktualisiert
else {
    @databases = $config->get_active_databases();
}

# Haeufigkeit von ISBNs im KUG:
# select isbn,count(dbname) as dbcount from all_isbn group by isbn order by dbcount desc limit 10

my $enrichdbh         = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd}) or die "could not connect";
my $enrichrequest     = $enrichdbh->prepare("insert into all_normdata values (?,?,?,?)");
my $delrequest        = $enrichdbh->prepare("delete from all_normdata where dbname=?");

foreach my $database (@databases){
    $logger->info("Deleting entries of database $database in enrichmntdb");

    $delrequest->execute($database);

    $logger->info("Getting persons from database $database and adding to enrichmntdb");

    my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or die "could not connect";

    my $sqlrequest = "select distinct content from aut where category = 1";
    
    my $request=$dbh->prepare($sqlrequest);
    $request->execute();

    my $aut_insertcount = 0;
    while (my $result=$request->fetchrow_hashref()){
        my $content     = $result->{content};
        my $normcontent = OpenBib::Common::Util::grundform({
            content  => $content,
        });

        $enrichrequest->execute($normcontent,$content,2,$database);
        $aut_insertcount++;
    }
    
    $logger->info("$aut_insertcount Persons inserted");

    $logger->info("Getting subjects from database $database and adding to enrichmntdb");
    
    $sqlrequest = "select distinct content from swt where category = 1";
    
    $request=$dbh->prepare($sqlrequest);
    $request->execute();

    my $swt_insertcount = 0;
    while (my $result=$request->fetchrow_hashref()){
        my $content     = $result->{content};
        my $normcontent = OpenBib::Common::Util::grundform({
            content  => $content,
        });

        $enrichrequest->execute($normcontent,$content,4,$database);
        $swt_insertcount++;
    }
    
    $logger->info("$swt_insertcount subjects inserted");

    $request->finish;
    $dbh->disconnect();
}

$enrichrequest->finish();
$delrequest->finish();
$enrichdbh->disconnect();

sub print_help {
    print << "ENDHELP";
update_all_normdata_table.pl - Aktualisierung der all_normdata-Tabelle, in der ausgewaehlte Kategorien aller Kataloge zwecks Live-Search
                           nachgewiesen sind.


   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Datenbankname


ENDHELP
    exit;
}

