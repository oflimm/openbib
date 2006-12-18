#!/usr/bin/perl
#####################################################################
#
#  analyze_relevances.pl
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use YAML;


use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Search::Util;

use vars qw(%config);

*config=\%OpenBib::Config::config;

my $logfile=($logfile)?$logfile:'/var/log/openbib/analyze_relevances.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d %p> %F{1}:%L %M - %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();


# Verbindung zur SQL-Datenbank herstellen
my $enrichdbh
    = DBI->connect("DBI:$config{dbimodule}:dbname=$config{enrichmntdbname};host=$config{enrichmntdbhost};port=$config{enrichmntdbport}", $config{enrichmntdbuser}, $config{enrichmntdbpasswd});

my $statdbh
    = DBI->connect("DBI:$config{dbimodule}:dbname=$config{statisticsdbname};host=$config{statisticsdbhost};port=$config{statisticsdbport}", $config{statisticsdbuser}, $config{statisticsdbpasswd});

my $request=$statdbh->prepare("select distinct isbn from relevance where isbn != ''");

$request->execute();

# Bestimme Nutzungsinformationen fuer jede ISBN
while (my $result=$request->fetchrow_hashref){
    my $isbn = $result->{isbn};

    # Bestimme alle Nutzer, die diese ISBN ausgeliehen haben
    my $request=$statdbh->prepare("select distinct id from relevance where isbn=?");
    $request->execute($isbn);

    my @ids=();
    while (my $result=$request->fetchrow_hashref){
        my $id = $result->{id};
        push @ids, "'$id'";
    }

    my $idstring=join(",",@ids);
    
    # Bestimme alle ISBNs, die diese Nutzer ausgeliehen haben und erzeuge
    # daraus ein Nutzungshistogramm

    my $request=$statdbh->prepare("select isbn,dbname,katkey from relevance where isbn != ? and id in ($idstring)");
    $request->execute($isbn);

    my %isbnhist=();
  ISBNHIST:
    while (my $result=$request->fetchrow_hashref){
        my $isbn   = $result->{isbn};
        my $dbname = $result->{dbname};
        my $katkey = $result->{katkey};
        
        if (!exists $isbnhist{$isbn}){
            $isbnhist{$isbn}={
                count  => 0,
                dbname => $dbname,
                katkey => $katkey,
            };
        }
        $isbnhist{$isbn}{count}=$isbnhist{$isbn}{count}+1;
    }

    my @histo=();
    foreach my $isbn (keys %isbnhist){
        push @{$histo[$isbnhist{$isbn}{count}]}, {
            isbn   => $isbn,
            dbname => $isbnhist{$isbn}{dbname},
            katkey => $isbnhist{$isbn}{katkey},
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
        # 5 References werden bestimmt
        my $request1=$enrichdbh->prepare('delete from normdata where isbn=? and category=?');
        my $request2=$enrichdbh->prepare('insert into normdata values (?,?,?,?,?)');

        $request1->execute($isbn,4000);
        $request1->execute($isbn,4001);
      REFERENCES:
        foreach my $references_ref (@references){

            foreach my $item_ref (@{$references_ref->{references}}){
                my $dbh;
                
                eval {
                    $dbh
                        = DBI->connect("DBI:$config{dbimodule}:dbname=$item_ref->{dbname};host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                            ;# or $logger->error_die($DBI::errstr);
                };
                
                if ($@){
                    print STDERR "$_";
                    next REFERENCES;
                }
                
		my $listitem_ref=OpenBib::Search::Util::get_tit_listitem_by_idn($item_ref->{katkey},"none",5,$dbh,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,$dbname,{},{},{},{},{},0);

		my $hst="<span class=\"rlauthor\">".$listitem_ref->{verfasser}."</span></strong><br /><strong><span class=\"rltitle\">".$listitem_ref->{title}."</span></strong>, <span class=\"rlpublisher\">".$listitem_ref->{publisher}."</span> <span class=\"rlyearofpub\">".$listitem_ref->{erschjahr}."</span> (".$references_ref->{count}."&nbsp;Nutzer)";
                                
                $count++;
                if ($hst && $item_ref->{isbn}){                
                    $request2->execute($isbn,50,4000,$count,$item_ref->{isbn});
                    $request2->execute($isbn,50,4001,$count,$hst);
                }
                last if ($count > 5);
            }
        }       
    }
}

