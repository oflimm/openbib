#!/usr/bin/perl
#####################################################################
#
#  gen_bestof.pl
#
#  Erzeugen von BestOf-Analysen aus Relevance-Statistik-Daten
#
#  Dieses File ist (C) 2006-2007 Oliver Flimm <flimm@openbib.org>
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

my ($type,$singlepool,$help,$logfile);

&GetOptions("type=s"          => \$type,
            "single-pool=s"   => \$singlepool,
            "logfile=s"       => \$logfile,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/gen_bestof.log';

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
my $statistics = new OpenBib::Statistics();

if (!$type){
  $logger->fatal("Kein Type mit --type= ausgewaehlt");
  exit;
}

# Typ 1 => Meistaufgerufene Titel pro Datenbank
if ($type == 1){
    my @databases = ();

    if ($singlepool){
        push @databases, $singlepool;
    }
    else {
        @databases=$config->get_active_databases();
    }
    
    foreach my $database (@databases){
        $logger->info("Generating Type 1 BestOf-Values for database $database");
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $bestof_ref=[];
        my $request=$statistics->{dbh}->prepare("select katkey, count(id) as idcount from relevance where origin=2 and dbname=? group by id order by idcount desc limit 20");
        $request->execute($database);
        while (my $result=$request->fetchrow_hashref){
            my $katkey = $result->{katkey};
            my $count  = $result->{idcount};

            my $item = OpenBib::Search::Util::get_tit_listitem_by_idn({
                titidn            => $katkey,
                dbh               => $dbh,
                database          => $database,
            });

            push @$bestof_ref, {
                item  => $item,
                count => $count,
            };
        }

        $statistics->store_result({
            type => 1,
            id   => $database,
            data => $bestof_ref,
        });
    }
}

# Typ 2 => Meistgenutzte Datenbanken
if ($type == 2){
    $logger->info("Generating Type 2 BestOf-Values for all databases");
    
    my $bestof_ref=[];
    my $request=$statistics->{dbh}->prepare("select dbname, count(katkey) as kcount from relevance where origin=2 group by dbname order by kcount desc limit 20");
    $request->execute();
    while (my $result=$request->fetchrow_hashref){
        my $dbname = $result->{dbname};
        my $count  = $result->{kcount};

        push @$bestof_ref, {
            item  => $dbname,
            count => $count,
        };
    }

    $statistics->store_result({
        type => 2,
        id   => 'all',
        data => $bestof_ref,
    });
}

# Typ 3 => Meistgenutzte Schlagworte
if ($type == 3){
    my @databases = ();

    if ($singlepool){
        push @databases, $singlepool;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 3 BestOf-Values for database $database");

        my $maxcount=0;

        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $bestof_ref=[];
        my $request=$dbh->prepare("select swt.content , count(distinct sourceid) as scount from conn, swt where sourcetype=1 and targettype=4 and swt.category=1 and swt.id=conn.targetid group by targetid order by scount desc limit 200");
        $request->execute();
        while (my $result=$request->fetchrow_hashref){
            my $content = decode_utf8($result->{content});
            my $count   = $result->{scount};
            if ($maxcount < $count){
                $maxcount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

        if ($maxcount >= 6){
            for (my $i=0 ; $i < scalar (@$bestof_ref) ; $i++){
                $bestof_ref->[$i]->{class} = int($bestof_ref->[$i]->{count} / int($maxcount/6));
            }
        }

        my $sortedbestof_ref ;
        @{$sortedbestof_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$bestof_ref};
        
        $statistics->store_result({
            type => 3,
            id   => $database,
            data => $sortedbestof_ref,
        });
    }
}

# Typ 4 => Meistgenutzte Notationen/Systematiken
if ($type == 4){
    my @databases = ();

    if ($singlepool){
        push @databases, $singlepool;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 4 BestOf-Values for database $database");

        my $maxcount=0;

        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $bestof_ref=[];
        my $request=$dbh->prepare("select notation.content , count(distinct sourceid) as scount from conn, notation where sourcetype=1 and targettype=5 and notation.category=1 and notation.id=conn.targetid group by targetid order by scount desc limit 200");
        $request->execute();
        while (my $result=$request->fetchrow_hashref){
            my $content = decode_utf8($result->{content});
            my $count   = $result->{scount};
            if ($maxcount < $count){
                $maxcount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

        if ($maxcount >= 6){
            for (my $i=0 ; $i < scalar (@$bestof_ref) ; $i++){
                $bestof_ref->[$i]->{class} = int($bestof_ref->[$i]->{count} / int($maxcount/6));
            }
        }

        my $sortedbestof_ref ;
        @{$sortedbestof_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$bestof_ref};
        
        $statistics->store_result({
            type => 4,
            id   => $database,
            data => $sortedbestof_ref,
        });
    }
}

# Typ 5 => Meistgenutzte Koerperschaften/Urheber
if ($type == 5){
    my @databases = ();

    if ($singlepool){
        push @databases, $singlepool;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 5 BestOf-Values for database $database");

        my $maxcount=0;

        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $bestof_ref=[];
        my $request=$dbh->prepare("select kor.content , count(distinct sourceid) as scount from conn, kor where sourcetype=1 and targettype=3 and kor.category=1 and kor.id=conn.targetid group by targetid order by scount desc limit 200");
        $request->execute();
        while (my $result=$request->fetchrow_hashref){
            my $content = decode_utf8($result->{content});
            my $count   = $result->{scount};
            if ($maxcount < $count){
                $maxcount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

        if ($maxcount >= 6){
            for (my $i=0 ; $i < scalar (@$bestof_ref) ; $i++){
                $bestof_ref->[$i]->{class} = int($bestof_ref->[$i]->{count} / int($maxcount/6));
            }
        }

        my $sortedbestof_ref ;
        @{$sortedbestof_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$bestof_ref};
        
        $statistics->store_result({
            type => 5,
            id   => $database,
            data => $sortedbestof_ref,
        });
    }
}

# Typ 6 => Meistgenutzte Verfasser/Personen
if ($type == 6){
    my @databases = ();

    if ($singlepool){
        push @databases, $singlepool;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 6 BestOf-Values for database $database");

        my $maxcount=0;

        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $bestof_ref=[];
        my $request=$dbh->prepare("select aut.content , count(distinct sourceid) as scount from conn, aut where sourcetype=1 and targettype=2 and aut.category=1 and aut.id=conn.targetid group by targetid order by scount desc limit 200");
        $request->execute();
        while (my $result=$request->fetchrow_hashref){
            my $content = decode_utf8($result->{content});
            my $count   = $result->{scount};
            if ($maxcount < $count){
                $maxcount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

        if ($maxcount >= 6){
            for (my $i=0 ; $i < scalar (@$bestof_ref) ; $i++){
                $bestof_ref->[$i]->{class} = int($bestof_ref->[$i]->{count} / int($maxcount/6));
            }
        }

        my $sortedbestof_ref ;
        @{$sortedbestof_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$bestof_ref};
        
        $statistics->store_result({
            type => 6,
            id   => $database,
            data => $sortedbestof_ref,
        });
    }
}

sub print_help {
    print << "ENDHELP";
gen_bestof.pl - Erzeugen von BestOf-Analysen aus Relevance-Statistik-Daten

   Optionen:
   -help                 : Diese Informationsseite
   --single-pool=...     : Einzelner Katalog
   --logfile=...         : Alternatives Logfile
   --type=...            : BestOf-Typ

   Typen:

   1 => Meistaufgerufene Titel pro Datenbank
   2 => Meistgenutzte Kataloge bezogen auf Titelaufrufe
   3 => Meistgenutzte Schlagworte pro Katalog (Wolke)
   4 => Meistgenutzte Notationen/Systematiken pro Katalog (Wolke)
   5 => Meistgenutzte Koerperschaften/Urheber pro Katalog (Wolke)
   6 => Meistgenutzte Verfasser/Personen pro Katalog (Wolke)
       
ENDHELP
    exit;
}

