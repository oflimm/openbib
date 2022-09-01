#!/usr/bin/perl
#####################################################################
#
#  update_all_titles_table.pl
#
#  Aktualisierung der all_titles_by-Tabellen, in der die ISBN's, ISSN's,
#  BibKeys und WorkKeys aller Titel in allen Kataloge nachgewiesen sind.
#
#  Dieses File ist (C) 2008-2022 Oliver Flimm <flimm@openbib.org>
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
use DBIx::Class::ResultClass::HashRefInflator;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use YAML;
use POSIX qw/strftime/;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Catalog;
use OpenBib::Normalizer;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my %char_replacements = (
    
    # Zeichenersetzungen
    "\n"     => "<br\/>",
    "\r"     => "\\r",
    ""     => "",
#    "\x{00}" => "",
#    "\x{80}" => "",
#    "\x{87}" => "",
);

my $chars_to_replace = join '|',
    keys %char_replacements;

$chars_to_replace = qr/$chars_to_replace/;

my $config     = new OpenBib::Config;
my $enrichment = new OpenBib::Enrichment;
my $normalizer = new OpenBib::Normalizer;

my ($database,$help,$logfile,$incremental,$bulkinsert,$keepfiles,$withtitlecache,$deletefilename,$insertfilename,$reducemem);

&GetOptions("database=s"        => \$database,
            "logfile=s"         => \$logfile,
            "incremental"       => \$incremental,
            "with-titlecache"   => \$withtitlecache,
            "bulk-insert"       => \$bulkinsert,
            "keep-files"        => \$keepfiles,
            "reduce-mem"        => \$reducemem,
            "delete-filename=s" => \$deletefilename,
            "insert-filename=s" => \$insertfilename,
	    "help"              => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/update_all_titles.log';

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

my $pgsqlexe      = "/usr/bin/psql -U $config->{'dbuser'} ";

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

    my $data_dir = $config->{autoconv_dir}."/data/$database";    

    my $catalog  = new OpenBib::Catalog({ database => $database });

    $logger->info("### $database: Locations bestimmen");
    
    my %locations_map = ();

    if ($reducemem){
	unlink "$data_dir/locations_map_${database}.db";
	
	eval {
	    tie %locations_map,        'MLDBM', "$data_dir/locations_map_${database}.db";
	};

	if ($@){
	    $logger->error_die("$@: Could not tie locations_map_${database}.db");
	}
    }
    
    my $all_locations = $catalog->get_schema->resultset('TitleField')->search_rs(
        {
            'field'    => 4230,
        },
        {
            select => ['titleid','content'],
            as     => ['thistitleid','thislocation'],
            group_by => ['titleid','content'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    my $loc_count = 0;
    while (my $this_location = $all_locations->next()){
        my $location = $this_location->{thislocation};
        my $titleid  = $this_location->{thistitleid};

        my $this_locations_ref = (defined $locations_map{$titleid})?$locations_map{$titleid}:[];
        push @{$this_locations_ref}, $location;
        $locations_map{$titleid} = $this_locations_ref;
        
        $loc_count++;
    }

    $logger->info("### $database: $loc_count Locations gefunden");
    
    my $deletefilename = ($deletefilename)?$deletefilename:$data_dir."/title.delete";
    my $insertfilename = ($insertfilename)?$insertfilename:$data_dir."/title.insert";
    
    if ($bulkinsert){
        # Temporaer Zugriffspassword setzen
        system("echo \"*:*:*:$config->{'dbuser'}:$config->{'dbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
        
        if (! -d $data_dir){
            system("mkdir -p $data_dir");
        }
        
        open(CONTROL,   ">$data_dir/all_title_control.sql");
        
        print CONTROL << "ALLTITLECONTROL";
DROP TABLE IF EXISTS all_titles_by_workkey_tmp;
CREATE TEMP TABLE all_titles_by_workkey_tmp (
 workkey       TEXT NOT NULL,
 edition       TEXT,
 dbname        VARCHAR(25) NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
 titlecache    TEXT,
 tstamp        TIMESTAMP
);

COPY all_titles_by_isbn    FROM '$data_dir/all_title_by_isbn.dump' WITH DELIMITER '' NULL AS '';
COPY all_titles_by_bibkey  FROM '$data_dir/all_title_by_bibkey.dump' WITH DELIMITER '' NULL AS '';
COPY all_titles_by_issn    FROM '$data_dir/all_title_by_issn.dump' WITH DELIMITER '' NULL AS '';
COPY all_titles_by_workkey_tmp FROM '$data_dir/all_title_by_workkey.dump' WITH DELIMITER '' NULL AS '';
INSERT INTO all_titles_by_workkey (workkey,edition,dbname,titleid,location,titlecache,tstamp) select workkey,edition,dbname,titleid,location,titlecache,tstamp from all_titles_by_workkey_tmp; 
DROP TABLE all_titles_by_workkey_tmp;
ALLTITLECONTROL

	close(CONTROL);
    
        open(ISBNOUT,   ">:utf8","$data_dir/all_title_by_isbn.dump");
        open(BIBKEYOUT, ">:utf8","$data_dir/all_title_by_bibkey.dump");
        open(ISSNOUT,   ">:utf8","$data_dir/all_title_by_issn.dump");
        open(WORKKEYOUT,">:utf8","$data_dir/all_title_by_workkey.dump");
    }
    
    my @titleids_to_delete = ();
    my @titleids_to_insert = ();
    
    if ($incremental){
        open(TITDEL, $deletefilename);
        open(TITINS, $insertfilename);

        my %seen_delids = ();

        my $insidx=0;
        while (my $titleid = <TITINS>){
            chomp($titleid);
            push @titleids_to_insert, $titleid;
            push @titleids_to_delete, $titleid; # Jede 'neue' ID wird zur Sicherheit auch geloescht
            $seen_delids{$titleid}++;
            $insidx++;
        }

        my $delidx=0;
        while (my $titleid = <TITDEL>){
            chomp($titleid);
            push @titleids_to_delete, $titleid unless(defined $seen_delids{$titleid});
            $seen_delids{$titleid}++;
            $delidx++;
        }

        $logger->info("### $database: $delidx Titel-ISBNs usw. zu loeschen");
        $logger->info("### $database: $insidx Titel-ISBNs usw. neu einzufuegen");
        
        close(TITDEL);
        close(TITINS);
    }

    my $where_ref = { dbname => $database };

    if ($incremental){
        $logger->info("### $database: Geloeschte oder geaenderte Daten entfernen");

        $where_ref->{titleid} = { -in => \@titleids_to_delete };
    }
    else {
        $logger->info("### $database: Bisherige Daten entfernen");
    }
    
    $enrichment->get_schema->resultset('AllTitleByIsbn')->search_rs(
        $where_ref
    )->delete;
    
    $enrichment->get_schema->resultset('AllTitleByBibkey')->search_rs(
        $where_ref
    )->delete;
    
    $enrichment->get_schema->resultset('AllTitleByIssn')->search_rs(
        $where_ref
    )->delete;
    
    $enrichment->get_schema->resultset('AllTitleByWorkkey')->search_rs(
        $where_ref
    )->delete;
    
    $where_ref = {
        -or => [
	     'title_fields.field' => '0540',
	     'title_fields.field' => '0553',
	     'title_fields.field' => '0541', # Testweise ff: ISBN_falsch
	     'title_fields.field' => '0547', # ISMN
	     'title_fields.field' => '0634', # ISBN Sekundaerform
	     'title_fields.field' => '1586', # ISBN_dat/www/mnt/_o/r/f
	     'title_fields.field' => '1587',
	     'title_fields.field' => '1588',
	     'title_fields.field' => '1590',
	     'title_fields.field' => '1591',
	     'title_fields.field' => '1592',
	     'title_fields.field' => '1594',
	     'title_fields.field' => '1595',
	     'title_fields.field' => '1596',
	     'title_fields.field' => '1780', # ISBN Parallelausgabe RDA
        ],
    };

    if ($incremental){
        $where_ref->{'title_fields.titleid'} = { -in => \@titleids_to_insert };
    }

    $logger->info("### $database: Getting ISBNs from database $database and adding to enrichmntdb");
    
    my $all_isbns = $catalog->get_schema->resultset('Title')->search_rs(
        $where_ref,
        {
            select => ['title_fields.titleid','title_fields.content','me.tstamp_create','me.titlecache'],
            as     => ['thistitleid', 'thisisbn','thisdate','thistitlecache'],
            join   => ['title_fields'],
        }
    );

    my $isbn_insertcount = 0;
    my @alltitlebyisbn = ();

    if ($reducemem){
	unlink "$data_dir/alltitlebyisbn_${database}.db";
	
	eval {
	    tie @alltitlebyisbn,        'MLDBM', "$data_dir/alltitlebyisbn_${database}.db";
	};
	  
	if ($@){
	    $logger->error("$@: Could not tie alltitlebyisbn_${database}.db");
	}
    }

    foreach my $item ($all_isbns->all){
        my $thistitleid       = $item->get_column('thistitleid');
        my $thisisbn          = $item->get_column('thisisbn');
        my $thistitlecache    = $item->get_column('thistitlecache');
        my $thisdate          = $item->get_column('thisdate') || strftime("%Y-%m-%d %T", localtime) ;


	if (!$withtitlecache){
	    $thistitlecache = "";
	}
	
	$thisisbn = cleanup_isbn($thisisbn);
	
        $logger->debug("Got Title with id $thistitleid and ISBN $thisisbn");
        
        # Normierung auf ISBN13
        my $isbn13 = Business::ISBN->new($thisisbn);
        
        if (defined $isbn13 && $isbn13->is_valid){
            $thisisbn = $isbn13->as_isbn13->as_string;
        }
        else {
            $logger->debug("ISBN $thisisbn nicht gueltig!");

            if ($thisisbn=~m/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/){
                $thisisbn="$1$2$3$4$5$6$7$8$9$10$11$12$13";
            }
            elsif ($thisisbn=~m/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/){
                $thisisbn="$1$2$3$4$5$6$7$8$9$10";
            }
            else {
                $logger->debug("ISBN $thisisbn hat auch nicht die Form einer ISBN. Ignoriert.");
                next;
            }
            
            $logger->debug("ISBN $thisisbn hat aber zumindest die Form einer ISBN. Verarbeitet.");
        }
        
        # Normierung als String
        $thisisbn = $normalizer->normalize({
            field => 'T0540',
            content  => $thisisbn,
        });

        
        if (defined $locations_map{$thistitleid}){
            foreach my $location (@{$locations_map{$thistitleid}}){
                push @alltitlebyisbn, {
                    isbn       => $thisisbn,
                    titleid    => $thistitleid,
                    dbname     => $database,
                    location   => $location,                    
                    tstamp     => $thisdate,
                    titlecache => $thistitlecache,
                };        
            }   
        }
        else {
            push @alltitlebyisbn, {
                isbn       => $thisisbn,
                titleid    => $thistitleid,
                dbname     => $database,
                location   => '',
                tstamp     => $thisdate,
                titlecache => $thistitlecache,
            };        
        }
        
        if ($isbn_insertcount && $isbn_insertcount % 10000 == 0 && @alltitlebyisbn){
            if ($bulkinsert){
                foreach my $this_row_ref (@alltitlebyisbn){
                    print ISBNOUT $this_row_ref->{isbn}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".$this_row_ref->{tstamp}."".cleanup_content($this_row_ref->{titlecache})."\n";
                }
                $logger->info("### $database: $isbn_insertcount ISBN's collected");
            }
            else {
                $enrichment->get_schema->resultset('AllTitleByIsbn')->populate(\@alltitlebyisbn);
                $logger->info("### $database: $isbn_insertcount ISBN's inserted");
            }
            @alltitlebyisbn = ();
        }
        
        $isbn_insertcount++;
    }

    if (@alltitlebyisbn){
        if ($bulkinsert){
            foreach my $this_row_ref (@alltitlebyisbn){
                print ISBNOUT $this_row_ref->{isbn}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".$this_row_ref->{tstamp}."".cleanup_content($this_row_ref->{titlecache})."\n";
            }
        }
        else {
            $enrichment->get_schema->resultset('AllTitleByIsbn')->populate(\@alltitlebyisbn);
        }
    }

    if ($bulkinsert){
        close(ISBNOUT);
        $logger->info("### $database: $isbn_insertcount ISBN's collected");
    }   
    else {
        $logger->info("### $database: $isbn_insertcount ISBN's inserted");
    }
    
    $logger->info("### $database: Getting Bibkeys from database $database and adding to enrichmntdb");

    $where_ref = {'title_fields.field' => '5050' };
    
    if ($incremental){
        $where_ref->{'title_fields.titleid'} = { -in => \@titleids_to_insert };
    }
    
    my $all_bibkeys = $catalog->get_schema->resultset('Title')->search_rs(
        $where_ref,
        {
            select => ['title_fields.titleid','title_fields.content','me.tstamp_create','me.titlecache'],
            as     => ['thistitleid', 'thisbibkey','thisdate','thistitlecache'],
            join   => ['title_fields'],
        }
    );

    my $bibkey_insertcount = 0;
    my @alltitlebybibkey = ();

    if ($reducemem){
	unlink "$data_dir/alltitlebybibkey_${database}.db";
	    
	eval {
	    tie @alltitlebybibkey,        'MLDBM', "$data_dir/alltitlebybibkey_${database}.db";
	};

	if ($@){
	    $logger->error("$@: Could not tie alltitlebybibkey_${database}.db");
	}
    }

    foreach my $item ($all_bibkeys->all){
        my $thistitleid    = $item->get_column('thistitleid');
        my $thisbibkey     = $item->get_column('thisbibkey');
        my $thistitlecache = $item->get_column('thistitlecache');
        my $thisdate       = $item->get_column('thisdate') || strftime("%Y-%m-%d %T", localtime) ;

	if (!$withtitlecache){
	    $thistitlecache = "";
	}
        
        if ($thisbibkey){
            $logger->debug("Got Title with id $thistitleid and bibkey $thisbibkey");

            if (defined $locations_map{$thistitleid}){
                foreach my $location (@{$locations_map{$thistitleid}}){
                    push @alltitlebybibkey, {
                        bibkey     => $thisbibkey,
                        titleid    => $thistitleid,
                        dbname     => $database,
                        location   => $location,
                        tstamp     => $thisdate,
                        titlecache => $thistitlecache,
                    };
                }
            }
            else {
                push @alltitlebybibkey, {
                    bibkey     => $thisbibkey,
                    titleid    => $thistitleid,
                    dbname     => $database,
                    location   => '',
                    tstamp     => $thisdate,
                    titlecache => $thistitlecache,
                };
            }
            
            $bibkey_insertcount++;
        }

        if ($bibkey_insertcount && $bibkey_insertcount % 10000 == 0 && @alltitlebybibkey){
            if ($bulkinsert){
                foreach my $this_row_ref (@alltitlebybibkey){
                    print BIBKEYOUT $this_row_ref->{bibkey}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".$this_row_ref->{tstamp}."".cleanup_content($this_row_ref->{titlecache})."\n";
                }
                $logger->info("### $database: $bibkey_insertcount Bibkeys collected");
            }
            else {
                $enrichment->get_schema->resultset('AllTitleByBibkey')->populate(\@alltitlebybibkey);
                $logger->info("### $database: $bibkey_insertcount Bibkeys inserted");
            }   
            @alltitlebybibkey = ();
        }

    }

    if (@alltitlebybibkey){
        if ($bulkinsert){
            foreach my $this_row_ref (@alltitlebybibkey){
                print BIBKEYOUT $this_row_ref->{bibkey}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".$this_row_ref->{tstamp}."".cleanup_content($this_row_ref->{titlecache})."\n";
            }
        }
        else {
            $enrichment->get_schema->resultset('AllTitleByBibkey')->populate(\@alltitlebybibkey);
        }
    }

    if ($bulkinsert){
        close(BIBKEYOUT);
        $logger->info("### $database: $bibkey_insertcount Bibkeys collected");
    }   
    else {
        $logger->info("### $database: $bibkey_insertcount Bibkeys inserted");
    }

    $logger->info("### $database: Getting ISSNs from database $database and adding to enrichmntdb");

    $where_ref = { 'title_fields.field' => '0543' };

    if ($incremental){
        $where_ref->{'title_fields.titleid'} = { -in => \@titleids_to_insert };
    }    
    
    my $all_issns = $catalog->get_schema->resultset('Title')->search_rs(
        $where_ref,
        {
            select => ['title_fields.titleid','title_fields.content','me.tstamp_create','me.titlecache'],
            as     => ['thistitleid', 'thisissn','thisdate','thistitlecache'],
            join   => ['title_fields'],
        }
    );
    
    my $issn_insertcount = 0;
    my @alltitlebyissn   = ();
    
    if ($reducemem){
	unlink "$data_dir/alltitlebyissn_${database}.db";

	eval {
	    tie @alltitlebyissn,        'MLDBM', "$data_dir/alltitlebyissn_${database}.db";
	};

	if ($@){
	    $logger->error("$@: Could not tie alltitlebyissn_${database}.db");
	}
    }

    foreach my $item ($all_issns->all){
        my $thistitleid    = $item->get_column('thistitleid');
        my $thistitlecache = $item->get_column('thistitlecache');
        my $thisissn       = $item->get_column('thisissn');
        my $thisdate       = $item->get_column('thisdate') || strftime("%Y-%m-%d %T", localtime) ;
        
	if (!$withtitlecache){
	    $thistitlecache = "";
	}

        if ($thisissn){
            # Normierung als String
            $thisissn = $normalizer->normalize({
                field => 'T0543',
                content  => $thisissn,
            });

            next unless (length($thisissn) == 8);
            
            $logger->debug("Got Title with id $thistitleid and ISSN $thisissn");

            if (defined $locations_map{$thistitleid}){
                foreach my $location (@{$locations_map{$thistitleid}}){
                    push @alltitlebyissn, {
                        issn       => $thisissn,
                        titleid    => $thistitleid,
                        dbname     => $database,
                        location   => $location,
                        tstamp     => $thisdate,
                        titlecache => $thistitlecache,
                    };
                }
            }
            else {
                push @alltitlebyissn, {
                    issn       => $thisissn,
                    titleid    => $thistitleid,
                    dbname     => $database,
                    location   => '',
                    tstamp     => $thisdate,
                    titlecache => $thistitlecache,
                };
            }
            
            $issn_insertcount++;

            if ($issn_insertcount && $issn_insertcount % 10000 == 0 && @alltitlebyissn){
                if ($bulkinsert){
                    foreach my $this_row_ref (@alltitlebyissn){
                        print ISSNOUT $this_row_ref->{issn}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".$this_row_ref->{tstamp}."".cleanup_content($this_row_ref->{titlecache})."\n";
                    }
                    $logger->info("### $database: $issn_insertcount ISSNs collected");
                }
                else {
                    $enrichment->get_schema->resultset('AllTitleByIssn')->populate(\@alltitlebyissn);
                    $logger->info("### $database: $issn_insertcount ISSNs inserted");
                }
                @alltitlebyissn = ();
            }
        }
    }

    if (@alltitlebyissn){
        if ($bulkinsert){
            foreach my $this_row_ref (@alltitlebyissn){
                print ISSNOUT $this_row_ref->{issn}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".$this_row_ref->{tstamp}."".cleanup_content($this_row_ref->{titlecache})."\n";
            }
        }
        else {
            $enrichment->get_schema->resultset('AllTitleByIssn')->populate(\@alltitlebyissn);
        }
    }

    if ($bulkinsert){
        close(ISSNOUT);
        $logger->info("### $database: $issn_insertcount ISSNs collected");
    }   
    else {
        $logger->info("### $database: $issn_insertcount ISSNs inserted");
    }
    
    $logger->info("### $database: Getting Workkeys from database $database and adding to enrichmntdb");

    $where_ref = { 'title_fields.field' => '5055' };

    if ($incremental){
        $where_ref->{'title_fields.titleid'} = { -in => \@titleids_to_insert };
    }    

    
    my $all_workkeys = $catalog->get_schema->resultset('Title')->search_rs(
        $where_ref,
        {
            select => ['title_fields.titleid','title_fields.content','me.tstamp_create','me.titlecache'],
            as     => ['thistitleid', 'thisworkkeybase','thisdate','thistitlecache'],
            join   => ['title_fields'],
        }
    );

    my $workkey_insertcount = 0;
    my @alltitlebyworkkey   = ();

    if ($reducemem){
	unlink "$data_dir/alltitlebyworkkey_${database}.db";
	    
	eval {
	    tie @alltitlebyworkkey,        'MLDBM', "$data_dir/alltitlebyworkkey_${database}.db";
	};

	if ($@){
	    $logger->error("$@: Could not tie alltitlebyworkkey_${database}.db");
	}
    }

    foreach my $item ($all_workkeys->all){
        my $thistitleid         = $item->get_column('thistitleid');
        my $thisworkkeybase     = $item->get_column('thisworkkeybase');

        my ($thisworkkey,$edition) = $thisworkkeybase =~m/^(.+)\s<(.*?)>/;
        
        my $thistitlecache      = $item->get_column('thistitlecache');
        my $thisdate            = $item->get_column('thisdate') || strftime("%Y-%m-%d %T", localtime) ;

	if (!$withtitlecache){
	    $thistitlecache = "";
	}
        
        if ($thisworkkey){
            $logger->debug("Got Title with id $thistitleid and workkey $thisworkkey");

            if (defined $locations_map{$thistitleid}){
                foreach my $location (@{$locations_map{$thistitleid}}){
                    push @alltitlebyworkkey, {
                        workkey    => $thisworkkey,
                        edition    => $edition || 1,
                        titleid    => $thistitleid,
                        dbname     => $database,
                        location   => $location,
                        tstamp     => $thisdate,
                        titlecache => $thistitlecache,
                    };
                }
            }
            else {
                push @alltitlebyworkkey, {
                    workkey    => $thisworkkey,
                    edition    => $edition || 1,
                    titleid    => $thistitleid,
                    dbname     => $database,
                    location   => '',
                    tstamp     => $thisdate,
                    titlecache => $thistitlecache,
                };
            }
            $workkey_insertcount++;
        }

        if ($workkey_insertcount && $workkey_insertcount % 10000 == 0 && @alltitlebyworkkey){
            if ($bulkinsert){
                foreach my $this_row_ref (@alltitlebyworkkey){
                    print WORKKEYOUT $this_row_ref->{workkey}."".$this_row_ref->{edition}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".cleanup_content($this_row_ref->{titlecache})."".$this_row_ref->{tstamp}."\n";
                }
                $logger->info("### $database: $workkey_insertcount Workkeys collected");
            }
            else {
                $enrichment->get_schema->resultset('AllTitleByWorkkey')->populate(\@alltitlebyworkkey);
                $logger->info("### $database: $workkey_insertcount Workkeys inserted");
            }
            @alltitlebyworkkey = ();
        }
    }

    if (@alltitlebyworkkey){
        if ($bulkinsert){
            foreach my $this_row_ref (@alltitlebyworkkey){
                print WORKKEYOUT $this_row_ref->{workkey}."".$this_row_ref->{edition}."".$this_row_ref->{dbname}."".$this_row_ref->{titleid}."".$this_row_ref->{location}."".cleanup_content($this_row_ref->{titlecache})."".$this_row_ref->{tstamp}."\n";
            }
        }
        else {
            $enrichment->get_schema->resultset('AllTitleByWorkkey')->populate(\@alltitlebyworkkey);
        }
    }

    if ($bulkinsert){
        close(WORKKEYOUT);
        $logger->info("### $database: $workkey_insertcount Workkeys collected");
    }   
    else {
        $logger->info("### $database: $workkey_insertcount Workkeys inserted");
    }
    
    if ($bulkinsert){
	
        $logger->info("### $database: Bulk inserting all keys to enrichment database");

	eval {
	    system("$pgsqlexe -f '$data_dir/all_title_control.sql' $config->{enrichmntdbname}");
	};

	if ($@){
	    $logger->error($@);
	    $keepfiles = 1;
	}
	
        unless ($keepfiles){
            unlink("$data_dir/all_title_control.sql");
            unlink("$data_dir/all_title_by_isbn.dump");
            unlink("$data_dir/all_title_by_bibkey.dump");
            unlink("$data_dir/all_title_by_issn.dump");
            unlink("$data_dir/all_title_by_workkey.dump");
        }
    }

    unlink("$data_dir/locations_map_${database}.db");

    if ($bulkinsert){
        # Temporaer Zugriffspassword setzen
        unlink("~/.pgpass");
    }
    
    $logger->info("### $database: Processing done");

}


sub print_help {
    print << "ENDHELP";
update_all_titles_table.pl - Aktualisierung der all_titles_by-Tabelle, in der die ISBN's aller Kataloge
                             nachgewiesen sind.


   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Datenbankname
   -bulk-insert          : Einladen mit DB-Systemtool (COPY)
   -incremental          : Nur geaenderte Titel aus vereinheitlichtem Incremental-Updateverfahren
   --delete-filename=aa  : Fuer -incremental: Dateiname mit IDs der geloeschten und geaenderten Titel
   --insert-filename=bb  : Fuer -incremental: Dateiname mit IDs der neuen und geaenderten Titel

   -keep-files           : Einladedateien (bei -bulk-insert) nicht loeschen


ENDHELP
    exit;
}

sub cleanup_content {
    my ($content) = @_;
    
    return '' unless (defined $content);
    
    # Make PostgreSQL Happy    
    $content =~ s/\\/\\\\/g;
    $content =~ s/($chars_to_replace)/$char_replacements{$1}/g;
    
    return $content;
}

sub cleanup_isbn {
    my ($isbn) = @_;

    $isbn=~s/[^-0-9xX]//g;
    
    return $isbn;
}
