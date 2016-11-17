#!/usr/bin/perl
#####################################################################
#
#  analyze_loans.pl
#
#  Dieses File ist (C) 2016 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Statistics;
use OpenBib::Search::Util;
use OpenBib::Record::Title;

my ($statisticsdbname,$enrichmntdbname,$database,@groups,$help,$logfile);

&GetOptions("statisticsdbname=s" => \$statisticsdbname,
            "enrichmntdbname=s"  => \$enrichmntdbname,
	    "database=s"         => \$database,
	    "group=s@"           => \@groups,
            "logfile=s"          => \$logfile,
	    "help"               => \$help
	    );

if ($help ||!$database){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/analyze_loans.log';

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

# $enrichmnt->get_schema->storage->debug(1);

# "select distinct isbn from relevance where isbn != ''"
my $titleids = $statistics->get_schema->resultset('Loan')->search_rs(
    {
	dbname => $database,
	groupid  => {-in => \@groups},
    },
    {
        select   => ['titleid'],
        group_by => ['titleid'],
    }
       
);

$logger->info("Processing ".$titleids->count." Titels");

my $titlecount = 1;

# Bestimme Anonyme Nutzerinformationen fuer jede Titelid
foreach my $item ($titleids->all){
    # Bestimme alle Nutzer, die den Titel mit dieser ID ausgeliehen/angeklickt haben
    my $thistitleid = $item->get_column('titleid');
    
    my $users = $statistics->get_schema->resultset('Loans')->search_rs(
        {
            'titleid' => $thistitleid,
	    'groupid' => {-in => \@groups},	    
        },
        {
            select => ['anon_userid'],
            as     => ['thisuserid'],
        }
    );
    
    $logger->debug("Title belongs to ".$users->count." anon users");
    
    my $ids_ref= [];
    foreach my $user ($users->all){
        my $id = $user->get_column('thisuserid');
        push @$ids_ref, { 'anon_userid' => $id };
    }

    # Bestimme alle Titelids, die diese Nutzer ausgeliehen haben und erzeuge
    # daraus ein Nutzungshistogramm

    # "select isbn,dbname,katkey from relevance where isbn != ? and id in ($idstring)"
    my $titles = $statistics->get_schema->resultset('Loan')->search_rs(
        {
            -or                 => $ids_ref,
	    'dbname'            => $database,
	    'groupid'           => {-in => \@groups},	    	    
            'titleid'           => { '!=' => $thistitleid },             
        },
        {
            select => ['titleid'],
            as     => ['titleid'],
        }
        
    );

    $logger->debug("Titleid connected to ".$titles->count." titles");
    
    my %titlehist=();
  TITLEHIST:

    foreach my $title ($titles->all){
        my $titleid     = $title->get_column('titleid');

        $logger->debug("Found related Titleid $titleid");

        next TITLEHIST if ("$thistitleid" eq "$titleid");
        
        if (!exists $titlehist{$titleid}){
            $titlehist{$titleid}={
                count  => 0,
                dbname => $database,
                id     => $titleid,
            };
        }
        $titlehist{$titleid}{count}=$titlehist{$titleid}{count}+1;
    }

    if ($logger->is_debug){
        $logger->debug("Collected Titles ".YAML::Dump(\%titlehist));
        $logger->debug("Generating histogram");
    }
    
    my @histo=();
    foreach my $thisid (keys %titlehist){
        push @{$histo[$titlehist{$thisid}{count}]}, {
            dbname => $titlehist{$thisid}{dbname},
            id     => $titlehist{$thisid}{id},
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

        $logger->debug("Removing enriched content for titlid $thistitleid");
        
        # DBI: 'delete from normdata where isbn=? and category=?'
        $enrichmnt->get_schema->resultset('EnrichedContentByTitle')->search_rs(
            {
                -or => [
                    'field' => '4002',
                    'field' => '4003',
                ],
                titlid => $thistitleid,
            }
        )->delete;
        
            ;
        # 5 References werden bestimmt
        
      REFERENCES:
        foreach my $references_ref (@references){

            my $enriched_content_ref  = [];
        
            foreach my $item_ref (@{$references_ref->{references}}){
                my $record = OpenBib::Record::Title->new({database => $item_ref->{dbname}, id => $item_ref->{id}})->load_brief_record();
                
                # Add user count
                $record->{user_count} = $references_ref->{count} ;

                my $content = $record->to_json;
                
                $count++;
               
                if ($record->get_field({ category => 'T0331' }) && $item_ref->{isbn}){

                    # ID
                    push @$enriched_content_ref, {
                        titleid  => $thistitleid,
			dbname   => $database,
                        origin   => 50,
                        field    => 4002,
                        subfield => $count,
                        content  => $item_ref->{id},
                    };

                    # Title als JSON
                    push @$enriched_content_ref, {
                        titleid  => $thistitleid,
			dbname   => $database,			
                        origin   => 50,
                        field    => 4003,
                        subfield => $count,
                        content  => $content,
                    };
                }
                last if ($count > 5);
            }
            
            if ($logger->is_debug){
                $logger->debug("Adding enriched content for titleid $thistitleid");
                $logger->debug(YAML::Dump($enriched_content_ref));
            }
            
            $enrichmnt->get_schema->resultset('EnrichedContentByTitle')->populate($enriched_content_ref);

        }

    }
    else {
        $logger->debug("Related Titleid NOT relevant enought");
    }

    if ($titlecount % 1000 == 0){
        $logger->info("$titlecount processed");
    }
    
    $titlecount++;
}

sub print_help {
    print << "ENDHELP";
analyze_loans.pl - Erzeugen von Ausleih-Analysen aus Statistik-Daten

   Optionen:
   -help                 : Diese Informationsseite
   --statisticsdbname=...: Name der Statistikdatenbank
   --enrichmentdbname=...: Name der Anreicherungsdatenbank
   --database=...        : Einzelner Katalog, dessen Ausleihverhalten analysiert werden soll
   --group=... (mult)    : Gruppen, auf die sich die Analyse beziehen soll
   --logfile=...         : Alternatives Logfile

ENDHELP
    exit;
}

