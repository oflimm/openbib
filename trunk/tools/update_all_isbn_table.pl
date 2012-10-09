#!/usr/bin/perl
#####################################################################
#
#  update_all_isbn_table.pl
#
#  Aktualisierung der all_isbn-Tabelle, in der die ISBN's aller Kataloge
#  nachgewiesen sind.
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Enrichment;
use OpenBib::Catalog;
use OpenBib::Common::Util;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my $config     = OpenBib::Config->instance;
my $enrichment = new OpenBib::Enrichment;

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


my $last_insertion_date = 0; # wird fuer inkrementelles Update benoetigt

foreach my $database (@databases){
    $logger->info("Getting ISBNs from database $database and adding to enrichmntdb");

    my $catalog = new OpenBib::Catalog($database);
    
    if ($incr){
        $last_insertion_date = $catalog->{schema}->resultset('Title')->get_column('tstamp_create')->max;
    }
    
    if (!$last_insertion_date && $incr){
        $logger->fatal("Inkrementelle Updates werden fuer die Datenbank $database nicht unterstuetzt");
        next;
    }
    else {
        $logger->info("Bisherige Daten entfernen");
        
        $enrichment->{schema}->resultset('AllTitleByIsbn')->search_rs(
            {
                dbname => $database
            }
        )->delete;

        $enrichment->{schema}->resultset('AllTitleByBibkey')->search_rs(
            {
                dbname => $database
            }
        )->delete;
        
        $enrichment->{schema}->resultset('AllTitleByIssn')->search_rs(
            {
                dbname => $database
            }
        )->delete;
    }

    my $all_isbns;
    
    if ($incr){
        $all_isbns = $catalog->{schema}->resultset('Title')->search_rs(
            {
                'me.tstamp_create'   => { '>' => $last_insertion_date },
                -or => [
                    'title_fields.field' => '0540',
                    'title_fields.field' => '0553',
                ],
            },
            {
                select => ['title_fields.titleid','title_fields.content','me.tstamp_create'],
                as     => ['thistitleid', 'thisisbn', 'thisdate'],
                join =>   ['title_fields'],
            }
        );
    }
    else {
        $all_isbns = $catalog->{schema}->resultset('Title')->search_rs(
            {
                -or => [
                    'title_fields.field' => '0540',
                    'title_fields.field' => '0553',
                ],
            },
            {
                select => ['title_fields.titleid','title_fields.content','me.tstamp_create'],
                as     => ['thistitleid', 'thisisbn','thisdate'],
                join   => ['title_fields'],
            }
        );
    }

    my $isbn_insertcount = 0;
    my $alltitlebyisbn_ref = [];
    
    foreach my $item ($all_isbns->all){
        my $thistitleid       = $item->get_column('thistitleid');
        my $thisisbn = $item->get_column('thisisbn');
        my $thisdate = $item->get_column('thisdate') || strftime("%Y-%m-%d %T", localtime) ;
        
        $logger->debug("Got Title with id $thistitleid and ISBN $thisisbn");
        
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
        $thisisbn = OpenBib::Common::Util::normalize({
            field => '0540',
            content  => $thisisbn,
        });

        push @$alltitlebyisbn_ref, {
            isbn    => $thisisbn,
            titleid => $thistitleid,
            dbname  => $database,
            tstamp  => $thisdate,
        };        

        $isbn_insertcount++;
    }

    if (@$alltitlebyisbn_ref){
        $enrichment->{schema}->resultset('AllTitleByIsbn')->populate($alltitlebyisbn_ref);
    }
    
    $logger->info("$isbn_insertcount ISBN's inserted");

    $logger->info("Getting Bibkeys from database $database and adding to enrichmntdb");
    
    if ($incr){
        $all_isbns = $catalog->{schema}->resultset('Title')->search_rs(
            {
                'me.tstamp_create'   => { '>' => $last_insertion_date },
                'title_fields.field' => '5050',
            },
            {
                select => ['title_fields.titleid','title_fields.content','me.tstamp_create'],
                as     => ['thistitleid', 'thisbibkey', 'thisdate'],
                join =>   ['title_fields'],
            }
        );
    }
    else {
        $all_isbns = $catalog->{schema}->resultset('Title')->search_rs(
            {
                'title_fields.field' => '5050',
            },
            {
                select => ['title_fields.titleid','title_fields.content','me.tstamp_create'],
                as     => ['thistitleid', 'thisbibkey','thisdate'],
                join   => ['title_fields'],
            }
        );
    }

    my $bibkey_insertcount = 0;
    my $alltitlebybibkey_ref = [];
    foreach my $item ($all_isbns->all){
        my $thistitleid         = $item->get_column('thistitleid');
        my $thisbibkey = $item->get_column('thisbibkey');
        my $thisdate   = $item->get_column('thisdate') || strftime("%Y-%m-%d %T", localtime) ;
        
        if ($thisbibkey){
            $logger->debug("Got Title with id $thistitleid and bibkey $thisbibkey");

            push @$alltitlebybibkey_ref, {
                bibkey  => $thisbibkey,
                titleid => $thistitleid,
                dbname  => $database,
                tstamp  => $thisdate,
            };
            $bibkey_insertcount++;
        }
    }

    if (@$alltitlebybibkey_ref){
        $enrichment->{schema}->resultset('AllTitleByBibkey')->populate($alltitlebybibkey_ref);
    }
    
    $logger->info("$bibkey_insertcount Bibkeys inserted");

    $logger->info("Getting ISSNs from database $database and adding to enrichmntdb");

    if ($incr){
        $all_isbns = $catalog->{schema}->resultset('Title')->search_rs(
            {
                'me.tstamp_create'   => { '>' => $last_insertion_date },
                'title_fields.field' => '0543',
            },
            {
                select => ['title_fields.titleid','title_fields.content','me.tstamp_create'],
                as     => ['thistitleid', 'thisissn', 'thisdate'],
                join =>   ['title_fields'],
            }
        );
    }
    else {
        $all_isbns = $catalog->{schema}->resultset('Title')->search_rs(
            {
                'title_fields.field' => '0543',
            },
            {
                select => ['title_fields.titleid','title_fields.content','me.tstamp_create'],
                as     => ['thistitleid', 'thisissn','thisdate'],
                join   => ['title_fields'],
            }
        );
    }
    
    my $issn_insertcount = 0;
    my $alltitlebyissn_ref = [];
    
    foreach my $item ($all_isbns->all){
        my $thistitleid = $item->get_column('thistitleid');
        my $thisissn    = $item->get_column('thisissn');
        my $thisdate    = $item->get_column('thisdate') || strftime("%Y-%m-%d %T", localtime) ;
        

        if ($thisissn){
            # Normierung als String
            $thisissn = OpenBib::Common::Util::normalize({
                field => '0543',
                content  => $thisissn,
            });

            next unless (length($thisissn) == 8);
            
            $logger->debug("Got Title with id $thistitleid and ISSN $thisissn");

            push @$alltitlebyissn_ref, {
                issn    => $thisissn,
                titleid => $thistitleid,
                dbname  => $database,
                tstamp  => $thisdate,
            };
            
            $issn_insertcount++;
        }
    }

    if (@$alltitlebyissn_ref){
        $enrichment->{schema}->resultset('AllTitleByIssn')->populate($alltitlebyissn_ref);
    }
    
    $logger->info("$issn_insertcount ISSNs inserted");
    
}

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

