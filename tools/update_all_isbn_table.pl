#!/usr/bin/perl
#####################################################################
#
#  update_all_isbn_table.pl
#
#  Aktualisierung der all_isbn-Tabelle, in der die ISBN's aller Kataloge
#  nachgewiesen sind.
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

$logfile=($logfile)?$logfile:'/var/log/openbib/update_all_isbn.log';

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
my $enrichrequest     = $enrichdbh->prepare("insert into all_isbn values (?,?,?,?)");
my $delrequest        = $enrichdbh->prepare("delete from all_isbn where dbname=?");

my $insertion_date_available = 0; # wird fuer inkrementelles Update benoetigt

foreach my $database (@databases){
    $logger->info("Getting ISBNs from database $database and adding to enrichmntdb");

    my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or die "could not connect";

    my $enriched_id_ref = {};

    if ($incr){
        my $insertdaterequest = $dbh->prepare("select count(*) as insertdatecount from tit where category=2");
        $insertdaterequest->execute();
        
        my $insertdateresult=$insertdaterequest->fetchrow_hashref;
        $insertion_date_available = $insertdateresult->{insertdatecount};
        
        $insertdaterequest->finish;
    }
    
    if (!$insertion_date_available && $incr){
        $logger->fatal("Inkrementelle Updates werden fuer die Datenbank $database nicht unterstuetzt");
        next;
    }

    my $sqlrequest = "select t1.id as id,t1.content as isbn,t2.content as thisdate from tit_string as t1 left join tit_string as t2 on t1.id=t2.id where t2.category = 2 and t1.category in (540,553)";

    if (!$insertion_date_available){
        $sqlrequest = "select id, content as isbn from tit where category in (540,553)";
    }

    my @sqlargs    = ();
    my $lastdate   = "";

    if ($incr){
        my $request=$enrichdbh->request("select max(tstamp) as lastdate from all_isbn where database=?");
        
        my $result=$request->fetchrow_hashref;
        
        $lastdate=$result->{'lastdate'};
        
        $sqlrequest.=" and t2.content > ?";
        push @sqlargs, $lastdate;
    }
    else {
        $delrequest->execute($database);
    }

    $logger->debug("SQL-Request: $sqlrequest");
    
    my $request=$dbh->prepare($sqlrequest);
    $request->execute(@sqlargs);

    my $isbn_insertcount = 0;
    while (my $result=$request->fetchrow_hashref()){
        my $id       = $result->{id};
        my $thisisbn = $result->{isbn};
        my $date     = $result->{thisdate} || 0;

        # Normierung auf ISBN13
        my $isbn13 = Business::ISBN->new($thisisbn);

        if (defined $isbn13 && $isbn13->is_valid){
            $thisisbn = $isbn13->as_isbn13->as_string;
        }
        else {
            $logger->error("ISBN $thisisbn nicht gueltig!");
            next;
        }

        # Normierung als String
        $thisisbn = OpenBib::Common::Util::grundform({
            category => '0540',
            content  => $thisisbn,
        });

        $enrichrequest->execute($thisisbn,$database,$id,$date);

        $enriched_id_ref->{$id}=1;

        $isbn_insertcount++;
    }

    $logger->info("$isbn_insertcount ISBN's inserted");
    
    $logger->info("Getting Bibkeys from database $database and adding to enrichmntdb");

    $sqlrequest = "select t1.id as id,t1.content as bibkey,t2.content as thisdate from tit as t1 left join tit as t2 on t1.id=t2.id where t2.category = 2 and t1.category=5050";

    if (!$insertion_date_available){
        $sqlrequest = "select id, content as bibkey from tit where category=5050";
    }

    $logger->debug("SQL-Request: $sqlrequest");
    
    $request=$dbh->prepare($sqlrequest);
    $request->execute();
    
    my $bibkey_insertcount = 0;
    while (my $result=$request->fetchrow_hashref()){
        my $id       = $result->{id};
        my $bibkey   = $result->{bibkey};
        my $date     = $result->{thisdate} || 0;

        if ($bibkey){
            $enrichrequest->execute($bibkey,$database,$id,$date);
            $bibkey_insertcount++;
        }
    }

    $logger->info("$bibkey_insertcount Bibkeys inserted");

    $request->finish;
    $dbh->disconnect();
}

$enrichrequest->finish();
$delrequest->finish();
$enrichdbh->disconnect();

sub print_help {
    print << "ENDHELP";
update_all_isbn_table.pl - Aktualisierung der all_isbn-Tabelle, in der die ISBN's aller Kataloge
                           nachgewiesen sind.


   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Datenbankname
   -incr                 : Incrementell (sonst alles)


ENDHELP
    exit;
}

