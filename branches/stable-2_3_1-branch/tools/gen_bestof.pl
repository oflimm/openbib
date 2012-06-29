#!/usr/bin/perl
#####################################################################
#
#  gen_bestof.pl
#
#  Erzeugen von BestOf-Analysen aus Relevance-Statistik-Daten
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
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::User;

my ($type,$database,$view,$help,$logfile,$disablefilteryear);

&GetOptions("type=s"              => \$type,
            "database=s"          => \$database,
            "view=s"              => \$view,
            "logfile=s"           => \$logfile,
            "disable-filter-year" => \$disablefilteryear,
	    "help"                => \$help
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

my $config     = OpenBib::Config->instance;
my $user       = OpenBib::User->instance;
my $statistics = new OpenBib::Statistics();

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
    or $logger->error($DBI::errstr);

if (!$type){
  $logger->fatal("Kein Type mit --type= ausgewaehlt");
  exit;
}

# Typ 1 => Meistaufgerufene Titel pro Datenbank
if ($type == 1){
    my @databases = ();

    if ($database){
        push @databases, $database;
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
        my $request=$statisticsdbh->prepare("select katkey, count(id) as idcount from relevance where origin=2 and dbname=? and DATE_SUB(CURDATE(),INTERVAL 6 MONTH) <= tstamp group by id order by idcount desc limit 20");
        $request->execute($database);
        while (my $result=$request->fetchrow_hashref){
            my $katkey = $result->{katkey};
            my $count  = $result->{idcount};

            my $item=OpenBib::Record::Title->new({database => $database, id => $katkey})->load_brief_record({dbh => $dbh});

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
    my $request=$statisticsdbh->prepare("select dbname, count(katkey) as kcount from relevance where origin=2 group by dbname order by kcount desc limit 20");
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

    if ($database){
        push @databases, $database;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 3 BestOf-Values for database $database");

        my $maxcount=0;
	my $mincount=999999999;
	
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
        
            if ($mincount > $count){
                $mincount = $count;
            }
    
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

	$bestof_ref = gen_cloud_class({
				       items => $bestof_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{best_of}{$type}{cloud}});

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

    if ($database){
        push @databases, $database;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 4 BestOf-Values for database $database");

        my $maxcount=0;
	my $mincount=999999999;

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

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

	$bestof_ref = gen_cloud_class({
				       items => $bestof_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{best_of}{$type}{cloud}});

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

    if ($database){
        push @databases, $database;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 5 BestOf-Values for database $database");

        my $maxcount=0;
	my $mincount=999999999;

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

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

	$bestof_ref = gen_cloud_class({
				       items => $bestof_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{best_of}{$type}{cloud}});

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

    if ($database){
        push @databases, $database;
    }
    else {
        @databases=$config->get_active_databases();
    }

    foreach my $database (@databases){
        $logger->info("Generating Type 6 BestOf-Values for database $database");

        my $maxcount=0;
	my $mincount=999999999;

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

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

	$bestof_ref = gen_cloud_class({
				       items => $bestof_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{best_of}{$type}{cloud}});

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

# Typ 7 => Von Nutzern vergebene Tags
if ($type == 7){
    my @databases = ();

    if ($database){
        push @databases, $database;
    }
    else {
        @databases=$config->get_active_databases();
    }

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    foreach my $database (@databases){
        $logger->info("Generating Type 7 BestOf-Values for database $database");

        my $maxcount=0;
	my $mincount=999999999;
        
        my $bestof_ref=[];
        my $request=$dbh->prepare("select t.id,t.tag,count(tt.tagid) as scount from tags as t, tittag as tt where tt.titdb=? and tt.tagid=t.id group by tt.tagid");
        $request->execute($database);
        while (my $result=$request->fetchrow_hashref){
            my $content = decode_utf8($result->{tag});
            my $id      = $result->{id};
            my $count   = $result->{scount};
            if ($maxcount < $count){
                $maxcount = $count;
            }

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                id    => $id,
                count => $count,
            };
        }

	$bestof_ref = gen_cloud_class({
				       items => $bestof_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{best_of}{$type}{cloud}});

        my $sortedbestof_ref ;
        @{$sortedbestof_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$bestof_ref};
        
        $statistics->store_result({
            type => 7,
            id   => $database,
            data => $sortedbestof_ref,
        });
    }
}

# Typ 8 => Meistgenutzte Suchbegriffe pro View
if ($type == 8){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type 8 BestOf-Values for view $view");

	my $cat2type_ref = {
			    fs        => 1,
			    hst       => 2,
			    verf      => 3,
			    kor       => 4,
			    swt       => 5,
			    notation  => 6,
			    isbn      => 7,
			    issn      => 8,
			    sign      => 9,
			    mart      => 10,
			    hststring => 11,
			    gtquelle  => 12,
			    ejahr     => 13,
			   };

	my $bestof_ref={};
        foreach my $category (qw/all fs hst verf swt/){
	  my $thisbestof_ref=[];
	  my $sqlstring;

          my $maxcount=0;
	  my $mincount=999999999;

	  my @sqlargs = ($view);

	  if ($category eq 'all'){
	    $sqlstring="select content, count(content) as scount from queryterm where viewname=? group by content order by scount DESC limit 200";
	  }
	  else {
	    $sqlstring="select content, count(content) as scount from queryterm where viewname=? and type = ? group by content order by scount DESC limit 200";
	    push @sqlargs, $cat2type_ref->{$category}; 
	  }

	  my $request=$statisticsdbh->prepare($sqlstring);
	  $request->execute(@sqlargs);
	  while (my $result=$request->fetchrow_hashref){
            my $content = decode_utf8($result->{content});
            my $count   = $result->{scount};
            if ($maxcount < $count){
	      $maxcount = $count;
            }
            if ($mincount > $count){
	      $mincount = $count;
            }
            
            push @$thisbestof_ref, {
				item  => $content,
				count => $count,
            };
	  }

	  $thisbestof_ref = gen_cloud_class({
					     items => $thisbestof_ref, 
					     min   => $mincount, 
					     max   => $maxcount, 
					     type  => $config->{best_of}{$type}{cloud}});

	  my $sortedbestof_ref ;
	  @{$sortedbestof_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
	      map { [$_, $_->{item}] }
		@{$thisbestof_ref};


	  $bestof_ref->{$category}=$sortedbestof_ref;
	}

        $logger->debug(YAML::Dump($bestof_ref));

        $statistics->store_result({
            type => 8,
            id   => $view,
            data => $bestof_ref,
        });
    }
}

# Typ 9 => Meistvorkommende Erscheinungsjahre pro Datenbank
if ($type == 9){
    my @databases = ();

    if ($database){
        push @databases, $database;
    }
    else {
        @databases=$config->get_active_databases();
    }
    
    foreach my $database (@databases){
        $logger->info("Generating Type 9 BestOf-Values for database $database");

        my $maxcount=0;
	my $mincount=999999999;

        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $bestof_ref=[];

        my $sql_string = "select count(distinct id) as scount, content from tit where category=425 and content regexp ? group by content order by scount DESC";
        my @sql_args   = ("^[0-9][0-9][0-9][0-9]\$");
        if ($disablefilteryear){
            $sql_string = "select count(distinct id) as scount, content from tit where category=425 group by content order by scount DESC";
            pop @sql_args ;
        }
        
        my $request=$dbh->prepare($sql_string);
        $request->execute(@sql_args);

        while (my $result=$request->fetchrow_hashref){
            my $content = decode_utf8($result->{content});
            my $count   = $result->{scount};
            if ($maxcount < $count){
                $maxcount = $count;
            }

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$bestof_ref, {
                item  => $content,
                count => $count,
            };
        }

	$bestof_ref = gen_cloud_class({
				       items => $bestof_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{best_of}{$type}{cloud}});

        my $sortedbestof_ref ;
        @{$sortedbestof_ref} = map { $_->[0] }
            sort { $a->[1] cmp $b->[1] }
                map { [$_, $_->{item}] }
                    @{$bestof_ref};
        
        $statistics->store_result({
            type => 9,
            id   => $database,
            data => $sortedbestof_ref,
        });
    }
}

# Typ 10 => Titel nach BK pro View
if ($type == 10){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type 10 BestOf-Values for view $view");

        my @databases = $config->get_dbs_of_view($view);
        
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

        my $bk_ref = {};

        my $in_select_string = join(',',map {'?'} @databases);
        my $sqlstring="select count(distinct ai.dbname, ai.id) as bkcount,n.content as bk from all_isbn as ai, normdata as n where n.category=4100 and n.isbn=ai.isbn and ai.dbname in ($in_select_string) group by n.content";
        my $request=$enrichdbh->prepare($sqlstring) or $logger->error($DBI::errstr);
        $request->execute(@databases);

        while (my $result=$request->fetchrow_hashref){
            my $bk      = $result->{bk};
            my $bkcount = $result->{bkcount};

            my $base_bk = substr($bk,0,2);

            if (exists $bk_ref->{$base_bk}){
                $bk_ref->{$base_bk} = $bk_ref->{$base_bk}+$bkcount;
            }
            else {
                $bk_ref->{$base_bk} = $bkcount;
            }
            $bk_ref->{$bk}          = $bkcount;
        }
        
        $logger->debug(YAML::Dump($bk_ref));

        $statistics->store_result({
            type => 10,
            id   => $view,
            data => $bk_ref,
        });
    }
}

# Typ 11 => Titel nach BK pro Katalog pro Sicht
if ($type == 11){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
#        next if ($view eq "kug");
        $logger->info("Generating Type 11 BestOf-Values for view $view");

        my @databases = $config->get_dbs_of_view($view);
        
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

        my $bk_ref = {};

        foreach my $database (@databases){
            $logger->info("Generating BK's for database $database");
            my $sqlstring="select count(distinct ai.id) as bkcount,n.content as bk from all_isbn as ai, normdata as n where n.category=4100 and n.isbn=ai.isbn and ai.dbname=? group by n.content";
            my $request=$enrichdbh->prepare($sqlstring) or $logger->error($DBI::errstr);
            $request->execute($database);
            
            while (my $result=$request->fetchrow_hashref){
                my $bk      = $result->{bk};
                my $bkcount = $result->{bkcount};
                
                my $base_bk = substr($bk,0,2);
                
                if (exists $bk_ref->{$base_bk} && exists $bk_ref->{$base_bk}{$database}){
                    $bk_ref->{$base_bk}{$database} = $bk_ref->{$base_bk}{$database}+$bkcount;
                }
                else {
                    $bk_ref->{$base_bk}{$database} = $bkcount;
                }
                $bk_ref->{$bk}{$database} = $bkcount;
            }
        }

        foreach my $bk (keys %{$bk_ref}){
            $statistics->store_result({
                type   => 11,
                subkey => $bk,
                id     => $view,
                data   => $bk_ref->{$bk},
            });
            
            $logger->debug(YAML::Dump($bk_ref->{$bk}));
        }

    }
}

# Typ 12 => Meistaufgerufene Literaturlisten
if ($type == 12){

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
            or $logger->error_die($DBI::errstr);

    $logger->info("Generating Type 12 BestOf-Values");

    my $maxcount=0;
    my $mincount=999999999;
    
    my $bestof_ref=[];
    my $request = $dbh->prepare("select content as id, count(content) as scount from eventlog where type = 800 group by content order by scount DESC limit 200");
    $request->execute();
    while (my $result=$request->fetchrow_hashref){
        my $properties_ref = $user->get_litlist_properties({ litlistid => $result->{id}});
        my $content        = $properties_ref->{title};
        my $id             = $result->{id};
        my $count          = $result->{scount};
        if ($maxcount < $count){
            $maxcount = $count;
        }
        
        if ($mincount > $count){
            $mincount = $count;
        }

        $logger->debug(YAML::Dump($properties_ref));

        # Nur oeffentliche Literaturlisten verwenden
        push @$bestof_ref, {
            item       => $content,
            id         => $id,
            count      => $count,
            properties => $properties_ref,
        } if ($properties_ref->{type} == 1);
    }
    
    $bestof_ref = gen_cloud_class({
        items => $bestof_ref, 
        min   => $mincount, 
        max   => $maxcount, 
        type  => $config->{best_of}{$type}{cloud}});
    
    my $sortedbestof_ref ;
    @{$sortedbestof_ref} = map { $_->[0] }
        sort { $a->[1] cmp $b->[1] }
            map { [$_, $_->{item}] }
                @{$bestof_ref};
    
    $statistics->store_result({
        type => 12,
        id   => 'litlist_usage',
        data => $sortedbestof_ref,
    });
}

sub gen_cloud_class {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $items_ref    = exists $arg_ref->{items}
        ? $arg_ref->{items}   : [];
    my $mincount     = exists $arg_ref->{min}
        ? $arg_ref->{min}     : 0;
    my $maxcount     = exists $arg_ref->{max}
        ? $arg_ref->{max}     : 0;
    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}    : 'log';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($type eq 'log'){

      if ($maxcount-$mincount > 0){
	
	my $delta = ($maxcount-$mincount) / 6;
	
	my @thresholds = ();
	
	for (my $i=0 ; $i<=6 ; $i++){
	  $thresholds[$i] = 100 * log(($mincount + $i * $delta) + 2);
	}

        $logger->debug(YAML::Dump(\@thresholds)." - $delta");

	foreach my $item_ref (@$items_ref){
	  my $done = 0;
	
	  for (my $class=0 ; $class<=6 ; $class++){
	    if ((100 * log($item_ref->{count} + 2) <= $thresholds[$class]) && !$done){
	      $item_ref->{class} = $class;
              $logger->debug("Klasse $class gefunden");
	      $done = 1;
	    }
	  }
	}
      }
    }
    elsif ($type eq 'linear'){
      if ($maxcount-$mincount > 0){
	foreach my $item_ref (@$items_ref){
	  $item_ref->{class} = int(($item_ref->{count}-$mincount) / ($maxcount-$mincount) * 6);
	}
      }
    }

    $logger->debug(YAML::Dump($items_ref));
    return $items_ref;
}

sub print_help {
    print << "ENDHELP";
gen_bestof.pl - Erzeugen von BestOf-Analysen aus Relevance-Statistik-Daten

   Optionen:
   -help                 : Diese Informationsseite
   --database=...        : Einzelner Katalog
   --logfile=...         : Alternatives Logfile
   --type=...            : BestOf-Typ

   Typen:

   1 => Meistaufgerufene Titel pro Datenbank
   2 => Meistgenutzte Kataloge bezogen auf Titelaufrufe
   3 => Meistgenutzte Schlagworte pro Katalog (Wolke)
   4 => Meistgenutzte Notationen/Systematiken pro Katalog (Wolke)
   5 => Meistgenutzte Koerperschaften/Urheber pro Katalog (Wolke)
   6 => Meistgenutzte Verfasser/Personen pro Katalog (Wolke)
   7 => Nutzer-Tags pro Katalog (Wolke)
   8 => Suchbegriffe pro View (Wolke)
   9 => Meistvorkommende Erscheinungsjahre pro Katalog (Wolke)
  10 => Titel nach BK pro View
  11 => Titel nach BK pro Katalog pro Sicht
  12 => Meistaufgerufene Literaturlisten
       
ENDHELP
    exit;
}

