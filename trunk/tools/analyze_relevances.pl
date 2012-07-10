#!/usr/bin/perl
#####################################################################
#
#  analyze_relevances.pl
#
#  Dieses File ist (C) 2006-2012 Oliver Flimm <flimm@openbib.org>
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

use Business::ISBN;
use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use YAML;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Statistics;
use OpenBib::Search::Util;
use OpenBib::Record::Title;

my ($statisticsdbname,$enrichmntdbname,$help,$logfile);

&GetOptions("statisticsdbname=s" => \$statisticsdbname,
            "enrichmntdbname=s"  => \$enrichmntdbname,
            "profile=s"          => \$profile,
            "view=s"             => \$view,
            "logfile=s"          => \$logfile,
	    "help"               => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/analyze_relevances.log';

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

my $config=new OpenBib::Config();

unless ($statisticsdbname){
    $statisticsdbname = $config->{statisticsdbname};
}

unless ($enrichmntdbname){
    $enrichmntdbname = $config->{enrichmntdbname};
}

my $enrichmnt  = new OpenBib::Enrichment({enrichmntdbname => $enrichmntdbname });
my $statistics = new OpenBib::Statistics({statisticsdbname => $statisticsdbname });


# "select distinct isbn from relevance where isbn != ''"
my $isbns = $statistics->{schema}->resultset('Titleusage')->search_rs(
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
    my $isbn13 = $isbn = $item->isbn;

    # Alternative ISBN zur Rechercheanrei
    my $isbnXX = Business::ISBN->new($isbn);

    if (defined $isbnXX && $isbnXX->is_valid){
        $isbn13 = $isbnXX->as_isbn13->as_string;
    }

    $isbn13 = OpenBib::Common::Util::grundform({
        category => '0540',
        content  => $isbn13,
    });

    # Bestimme alle Nutzer (=Sessions), die diese ISBN ausgeliehen/angeklickt haben

    # select distinct id from relevance where isbn=?;
    my $sessions = $statistics->{schema}->resultset('Sessioninfo')->search_rs(
        {
            'titleusages.isbn' => $isbn,
        },
        {
            join     => ['titleusages'],
        }
    );
    
#    my @ids=();
#    while (my $result=$request->fetchrow_hashref){
#        my $id = $result->{id};
#        push @ids, "'$id'";
#    }

#    my $idstring=join(",",@ids);
    
    # Bestimme alle ISBNs, die diese Nutzer ausgeliehen haben und erzeuge
    # daraus ein Nutzungshistogramm

    # "select isbn,dbname,katkey from relevance where isbn != ? and id in ($idstring)"
    my $titles = $sessions->search_rs(
        {
            isbn => { '!=' => $isbn },             
        },
        {
            select => ['titleusages.isbn','titleusages.id','titleusages.dbname'],
            as     => ['titleisbn','titleid','titledbname'],
            join   => ['titleusages'],
        }
        
    );

    my %isbnhist=();
  ISBNHIST:

    foreach my $title ($titles->all){
        my $isbn   = $title->titleisbn;
        my $dbname = $title->titledbname;
        my $id     = $title->titleid;
        
        if (!exists $isbnhist{$isbn}){
            $isbnhist{$isbn}={
                count  => 0,
                dbname => $dbname,
                id     => $id,
            };
        }
        $isbnhist{$isbn}{count}=$isbnhist{$isbn}{count}+1;
    }

    my @histo=();
    foreach my $isbn (keys %isbnhist){
        push @{$histo[$isbnhist{$isbn}{count}]}, {
            isbn   => $isbn,
            dbname => $isbnhist{$isbn}{dbname},
            id     => $isbnhist{$isbn}{id},
        };
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

        # DBI: 'delete from normdata where isbn=? and category=?'
        $enrichment->{schema}->resultset('EnrichedContentByIsbn')->search_rs(
            {
                -or => [
                    'field' => '4000',
                    'field' => '4001',
                ],
                isbn => $isbn,
            }
        )->delete;
        
            ;
        # 5 References werden bestimmt
#        my $request2=$enrichdbh->prepare('insert into normdata values (?,?,?,?,?)');

        my $enriched_content_ref  = [];
      REFERENCES:
        foreach my $references_ref (@references){

            foreach my $item_ref (@{$references_ref->{references}}){
                my $record = OpenBib::Record::Title->new({database => $item_ref->{dbname}, id => $item_ref->{id}})->load_full_record({dbh => $dbh});
                
                # Add user count
                $record->{user_count} = $references_ref->{count} ;

                my $content = $record->to_json;
                
                $count++;
               
                if ($record->get_category({ category => 'T0331' }) && $item_ref->{isbn}){

                    # ISBN
                    push @$enriched_content_ref, {
                        isbn    => $isbn13,
                        origin  => 50,
                        field   => 4000,
                        subfield => $count,
                        content => $item_ref->{isbn},
                    };

                    # Title als JSON
                    push @$enriched_content_ref, {
                        isbn    => $isbn13,
                        origin  => 50,
                        field   => 4001,
                        subfield => $count,
                        content => $content,
                    };
                }
                last if ($count > 5);
            }
        }

        $enrichment->{schema}->resultset('EnrichedContentByIsbn')->populatet($enriched_content_ref);
    }

    if ($isbncount % 1000 == 0){
        $logger->info("$isbncount processed");
    }
    
    $isbncount++;
}

