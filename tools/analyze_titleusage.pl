#!/usr/bin/perl
#####################################################################
#
#  analyze_titleusage.pl
#
#  Dieses File ist (C) 2006-2022 Oliver Flimm <flimm@openbib.org>
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

use Business::ISBN;
use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use YAML;
use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Normalizer;;
use OpenBib::Statistics;
use OpenBib::Search::Util;
use OpenBib::Record::Title;

my ($statisticsdbname,$enrichmntdbname,$help,$logfile);

&GetOptions("statisticsdbname=s" => \$statisticsdbname,
            "enrichmntdbname=s"  => \$enrichmntdbname,
            "logfile=s"          => \$logfile,
	    "help"               => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/analyze_titleusage.log';

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

my $config     = new OpenBib::Config();
my $normalizer = new OpenBib::Normalizer;

unless ($statisticsdbname){
    $statisticsdbname = $config->{statisticsdbname};
}

unless ($enrichmntdbname){
    $enrichmntdbname = $config->{enrichmntdbname};
}

my $enrichmnt  = new OpenBib::Enrichment({enrichmntdbname => $enrichmntdbname });
my $statistics = new OpenBib::Statistics({statisticsdbname => $statisticsdbname });

# $enrichmnt->get_schema->storage->debug(1);

# "select distinct isbn from relevance where isbn != ''"
my $isbns = $statistics->get_schema->resultset('Titleusage')->search_rs(
    {
        isbn => { '!=' => '' }, 
    },
    {
        select   => ['isbn'],
        group_by => ['isbn'],
    }
       
);

$logger->info("Processing ".$isbns->count." ISBN's");

my $isbncount = 1;

# Bestimme Nutzungsinformationen fuer jede ISBN
foreach my $item ($isbns->all){
    my $processed_isbn13 = $item->isbn;
    my $processed_isbn   = $processed_isbn13;
    
    # Alternative ISBN zur Rechercheanreicherung
    my $isbnXX = Business::ISBN->new($processed_isbn);

    if (defined $isbnXX && $isbnXX->is_valid){
        $processed_isbn13 = $isbnXX->as_isbn13->as_string;
    }

    $processed_isbn13 = $normalizer->normalize({
        field => 'T0540',
        content  => $processed_isbn13,
    });

    $logger->debug("Processing ISBN $processed_isbn -> $processed_isbn13");

    # Bestimme alle Nutzer (=Sessions), die diese ISBN ausgeliehen/angeklickt haben

    # select distinct id from relevance where isbn=?;
    my $sessions = $statistics->get_schema->resultset('Sessioninfo')->search_rs(
        {
            'titleusages.isbn' => $processed_isbn,
        },
        {
            select => ['me.id'],
            as     => ['thisid'],
                
            join     => ['titleusages'],
        }
    );
    
    $logger->debug("ISBN belongs to ".$sessions->count." sessions");
    
    my $ids_ref= [];
    foreach my $session ($sessions->all){
        my $id = $session->get_column('thisid');
        push @$ids_ref, { 'me.id' => $id };
    }

#    my $idstring=join(",",@ids);
    
    # Bestimme alle ISBNs, die diese Nutzer ausgeliehen haben und erzeuge
    # daraus ein Nutzungshistogramm

    # "select isbn,dbname,katkey from relevance where isbn != ? and id in ($idstring)"
    my $titles = $statistics->get_schema->resultset('Sessioninfo')->search_rs(
        {
            -or                => $ids_ref,
            'titleusages.isbn' => { '!=' => $processed_isbn },             
        },
        {
            select => ['titleusages.isbn','titleusages.titleid','titleusages.dbname'],
            as     => ['titleisbn','titleid','titledbname'],
            join   => ['titleusages'],
        }
        
    );

    $logger->debug("ISBN connected to ".$titles->count." titles");
    
    my %isbnhist=();
  ISBNHIST:

    foreach my $title ($titles->all){
        my $titleisbn   = $title->get_column('titleisbn');
        my $titledbname = $title->get_column('titledbname');
        my $titleid     = $title->get_column('titleid');

        $logger->debug("Found related ISBN $titleisbn");

        next ISBNHIST if ("$processed_isbn" eq "$titleisbn");
        

        
        if (!exists $isbnhist{$titleisbn}){
            $isbnhist{$titleisbn}={
                count  => 0,
                dbname => $titledbname,
                id     => $titleid,
            };
        }
        $isbnhist{$titleisbn}{count}=$isbnhist{$titleisbn}{count}+1;
    }

    if ($logger->is_debug){
        $logger->debug("Collected Titles ".YAML::Dump(\%isbnhist));
        $logger->debug("Generating histogram");
    }
    
    my @histo=();
    foreach my $thisisbn (keys %isbnhist){
        push @{$histo[$isbnhist{$thisisbn}{count}]}, {
            isbn   => $thisisbn,
            dbname => $isbnhist{$thisisbn}{dbname},
            id     => $isbnhist{$thisisbn}{id},
        };
    }

    if ($logger->is_debug){
        $logger->debug("Histogram: ".YAML::Dump(\@histo));
    }
    
    if ($#histo >= 3){
        my $i=$#histo;

        my @references=();
        while ($i > 2){
            push @references, {
                references => $histo[$i],
                count      => $i,
            } if $histo[$i];
            last if ($#references > 5);
            $i--;
        }

        my $count=0;
        $i=0;

        # Anreicherungen fuer diese Kategorie entfernen,

        $logger->debug("Removing enriched content for isbn $processed_isbn");
        
        # DBI: 'delete from normdata where isbn=? and category=?'
        $enrichmnt->get_schema->resultset('EnrichedContentByIsbn')->search_rs(
            {
                -or => [
                    'field' => '4000',
                    'field' => '4001',
                ],
                isbn => $processed_isbn13,
            }
        )->delete;
        
            ;
        # 5 References werden bestimmt
        
      REFERENCES:
        foreach my $references_ref (@references){

            my $enriched_content_ref  = [];
        
            foreach my $item_ref (@{$references_ref->{references}}){
                my $record = OpenBib::Record::Title->new({database => $item_ref->{dbname}, id => $item_ref->{id}, config => $config})->load_brief_record();
                
                # Add user count
                $record->{user_count} = $references_ref->{count} ;

                my $content = $record->to_json;
                
                $count++;
               
                if ($record->get_field({ category => 'T0331' }) && $item_ref->{isbn}){

                    # ISBN
                    push @$enriched_content_ref, {
                        isbn    => $processed_isbn13,
                        origin  => 50,
                        field   => 4000,
                        subfield => $count,
                        content => $item_ref->{isbn},
                    };

                    # Title als JSON
                    push @$enriched_content_ref, {
                        isbn    => $processed_isbn13,
                        origin  => 50,
                        field   => 4001,
                        subfield => $count,
                        content => $content,
                    };
                }
                last if ($count > 5);
            }
            
            if ($logger->is_debug){
                $logger->debug("Adding enriched content for isbn $processed_isbn");
                $logger->debug(YAML::Dump($enriched_content_ref));
            }
            
            $enrichmnt->get_schema->resultset('EnrichedContentByIsbn')->populate($enriched_content_ref);

        }

    }
    else {
        $logger->debug("Related ISBN NOT relevant enought");
    }

    if ($isbncount % 1000 == 0){
        $logger->info("$isbncount processed");
    }
    
    $isbncount++;
}

