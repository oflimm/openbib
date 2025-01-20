#!/usr/bin/perl
#####################################################################
#
#  gen_metrics.pl
#
#  Erzeugen von Metriken aus Katalog- sowie Relevance-Statistik-Daten
#
#  Dieses File ist (C) 2006-2024 Oliver Flimm <flimm@openbib.org>
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
use DBIx::Class::ResultClass::HashRefInflator;
use Getopt::Long;
use POSIX qw(strftime);
use Unicode::Collate;
use YAML;

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Catalog;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::System;
use OpenBib::Statistics;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::User;

my ($type,$database,$scheme,$profile,$field,$view,$help,$num,$logfile,$loglevel);

&GetOptions("type=s"          => \$type,
            "database=s"      => \$database,
            "profile=s"       => \$profile,
            "view=s"          => \$view,
            "scheme=s"        => \$scheme,
            "loglevel=s"      => \$loglevel,
            "logfile=s"       => \$logfile,	    
            "field=s"         => \$field,
            "num=s"           => \$num,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$num=($num)?$num:200;

$logfile  = ($logfile)?$logfile:'/var/log/openbib/gen_metrics.log';
$loglevel = ($loglevel)?$loglevel:'INFO';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
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

my $config     = OpenBib::Config->new;
my $user       = new OpenBib::User;
my $statistics = OpenBib::Statistics->instance;
my $dbinfo     = new OpenBib::Config::DatabaseInfoTable;

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh = DBI->connect("DBI:Pg:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd},{'pg_enable_utf8'    => 1})
    or $logger->error($DBI::errstr);

if (!$type){
  $logger->fatal("Kein Type mit --type= ausgewaehlt");
  exit;
}

$scheme = (defined $scheme)?$scheme:(defined $database)?$dbinfo->get('schema')->{$database}:'';

my $is_person_field_ref = {
    '0100' => 1,
    '0101' => 1,
    '0102' => 1,
    '0103' => 1,
    '1800' => 1,
    '4308' => 1,
};

my $is_corporatebody_field_ref = {
    '0200' => 1,
    '0201' => 1,
    '1802' => 1,
    '4307' => 1,
};

my $is_classification_field_ref = {
    '0700' => 1,
};

my $is_subject_field_ref = {
    '0710' => 1,
    '0902' => 1,
    '0907' => 1,
    '0912' => 1,
    '0917' => 1,
    '0922' => 1,
    '0927' => 1,
    '0932' => 1,
    '0937' => 1,
    '0942' => 1,
    '0947' => 1,
};

if ($scheme && $scheme eq "marc21"){
    $is_person_field_ref = {
	'0100' => 1,
	    '0700' => 1,
#	    '4308' => 1,
    };
    
    $is_corporatebody_field_ref = {
	'0110' => 1,
	    '0111' => 1,
	    '0710' => 1,
#	    '4307' => 1,
    };
    
    $is_classification_field_ref = {
	'0082' => 1,
	    '0084' => 1,
    };
    
    $is_subject_field_ref = {
	'0600' => 1,
	    '0610' => 1,
	    '0610' => 1,
	    '0648' => 1,
	    '0650' => 1,
	    '0651' => 1,
	    '0655' => 1,
	    '0688' => 1,
	    '0689' => 1,
    };
}

# Datumsangaben

my $current_year  = strftime "%Y", localtime;
my $last_year     = $current_year - 1;
my $current_month = strftime "%m", localtime;
my $today         = strftime "%d", localtime;

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
        $logger->info("Generating Type 1 metrics for database $database");

        my $metrics_ref=[];

        # DBI "select id, count(sid) as sidcount from titleusage where origin=2 and dbname=? and DATE_SUB(CURDATE(),INTERVAL 6 MONTH) <= tstamp group by id order by idcount desc limit 20"
        my $titleusage = $statistics->get_schema->resultset('Titleusage')->search_rs(
            {
                dbname => $database,
                origin => 1,
#                tstamp => { '>' => 20110101000000 },
                tstamp => { '>' => \'CURRENT_TIMESTAMP - INTERVAL \'180 days\'' },
                
            },
            {
                select   => ['titleid', {'count' => 'sid'}],
                as       => ['titleid','sidcount'],
                group_by => ['titleid'],
                order_by => { -desc => \'count(sid)' },
                rows     => 20,
            }
        );
        foreach my $item ($titleusage->all){
            my $titleid  = $item->get_column('titleid');
            my $count    = $item->get_column('sidcount');

            $logger->debug("Got Title with id $titleid and Session-Count $count");
            
            my $item=OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config})->load_brief_record->to_hash;

            push @$metrics_ref, {
                item  => $item,
                count => $count,
            };
        }

        $config->set_datacache({
            type => 1,
            id   => $database,
            data => $metrics_ref,
        });
    }
}

# Typ 2 => Meistgenutzte Datenbanken
if ($type == 2){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (sort @views){
        $logger->info("Generating Type 2 metrics for view $view");

        my $viewdb_ref = [];
        foreach my $dbname ($config->get_viewdbs($view)){
            push @$viewdb_ref, {dbname => $dbname };
        }

        next unless (@$viewdb_ref);
        
        my $metrics_ref=[];
        # DBI: "select dbname, count(katkey) as kcount from titleusage where origin=2 group by dbname order by kcount desc limit 20"
        my $databaseusage = $statistics->get_schema->resultset('Titleusage')->search_rs(
            {
                -or    => $viewdb_ref,
                origin => 1,
                #                tstamp => { '>' => 20110101000000 },
                tstamp => { '>' => \'CURRENT_TIMESTAMP - INTERVAL \'180 days\'' },
                
            },
            {
                select   => ['dbname', {'count' => 'titleid'}],
                as       => ['dbname','kcount'],
                group_by => ['dbname'],
                order_by => { -desc => \'count(titleid)' },
                rows     => 20,
            }
        );
        
        foreach my $item ($databaseusage->all){
            my $dbname = $item->get_column('dbname');
            my $count  = $item->get_column('kcount');
            
            push @$metrics_ref, {
                item  => $dbname,
                count => $count,
            };
        }
        
        $config->set_datacache({
            type => 2,
            id   => $view,
            data => $metrics_ref,
        });
    }
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
        $logger->info("Generating Type 3 metrics for database $database");

        my $maxcount=0;
	my $mincount=999999999;

        my $catalog = new OpenBib::Catalog({ database => $database });
        
        my $metrics_ref=[];

        # DBI: "select subject.content , count(distinct sourceid) as scount from conn, subject where sourcetype=1 and targettype=4 and subject.category=1 and subject.id=conn.targetid group by targetid order by scount desc limit 200"
        my $usage = $catalog->get_schema->resultset('Subject')->search_rs(
            {
                'subject_fields.field' => 800,
                'subject_fields.mult'  => 1,
            },
            {
                select   => ['subject_fields.content', {'count' => 'title_subjects.titleid'}],
                as       => ['thiscontent','titlecount'],
                join     => ['subject_fields','title_subjects'],
                group_by => ['title_subjects.subjectid','subject_fields.content'],
                order_by => { -desc => \'count(title_subjects.titleid)' },
                rows     => $num,
            }
        );

        foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $count   = $item->get_column('titlecount');
            
            if ($maxcount < $count){
                $maxcount = $count;
            }
            
            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$metrics_ref, {
                item  => $content,
                count => $count,
            };
        }
        
	$metrics_ref = gen_cloud_class(
            {
                items => $metrics_ref, 
                min   => $mincount, 
                max   => $maxcount, 
                type  => $config->{metrics}{$type}{cloud}
            }
        );

        my $sortedmetrics_ref ;
        my $collator = Unicode::Collate->new();
        
        @{$sortedmetrics_ref} = map { $_->[0] }
            sort { $collator->cmp($a->[1],$b->[1]) }
                map { [$_, $_->{item}] }
                    @{$metrics_ref};
        
        $config->set_datacache({
            type => 3,
            id   => $database,
            data => $sortedmetrics_ref,
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
        $logger->info("Generating Type 4 metrics for database $database");

        my $maxcount=0;
	my $mincount=999999999;

        my $catalog = new OpenBib::Catalog({ database => $database });

        my $metrics_ref=[];

        # DBI: "select classification.content , count(distinct sourceid) as scount from conn, classification where sourcetype=1 and targettype=5 and classification.category=1 and classification.id=conn.targetid group by targetid order by scount desc limit 200"
        my $usage = $catalog->get_schema->resultset('Classification')->search_rs(
            {
                'classification_fields.field' => 800,
            },
            {
                select   => ['classification_fields.content', {'count' => 'title_classifications.titleid'}],
                as       => ['thiscontent','titlecount'],
                join     => ['classification_fields','title_classifications'],
                group_by => ['title_classifications.classificationid','classification_fields.content'],
                order_by => { -desc => \'count(title_classifications.titleid)' },
                rows     => $num,
            }
        );

        foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $count   = $item->get_column('titlecount');

            if ($maxcount < $count){
                $maxcount = $count;
            }

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$metrics_ref, {
                item  => $content,
                count => $count,
            };
        }

	$metrics_ref = gen_cloud_class({
				       items => $metrics_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{metrics}{$type}{cloud}});


        my $sortedmetrics_ref ;
        my $collator = Unicode::Collate->new();
        
        @{$sortedmetrics_ref} = map { $_->[0] }
            sort { $collator->cmp($a->[1],$b->[1]) }
                map { [$_, $_->{item}] }
                    @{$metrics_ref};
        
        $config->set_datacache({
            type => 4,
            id   => $database,
            data => $sortedmetrics_ref,
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
        $logger->info("Generating Type 5 metrics for database $database");

        my $maxcount=0;
	my $mincount=999999999;

        my $catalog = new OpenBib::Catalog({ database => $database });

        my $metrics_ref=[];

        # DBI: "select corporatebody.content , count(distinct sourceid) as scount from conn, corporatebody where sourcetype=1 and targettype=3 and corporatebody.category=1 and corporatebody.id=conn.targetid group by targetid order by scount desc limit 200"
        my $usage = $catalog->get_schema->resultset('Corporatebody')->search_rs(
            {
                'corporatebody_fields.field' => 800,
            },
            {
                select   => ['corporatebody_fields.content', {'count' => 'title_corporatebodies.titleid'}],
                as       => ['thiscontent','titlecount'],
                join     => ['corporatebody_fields','title_corporatebodies'],
                group_by => ['title_corporatebodies.corporatebodyid','corporatebody_fields.content'],
                order_by => { -desc => \'count(title_corporatebodies.titleid)' },
                rows     => $num,
            }
        );

        foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $count   = $item->get_column('titlecount');

            if ($maxcount < $count){
                $maxcount = $count;
            }

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$metrics_ref, {
                item  => $content,
                count => $count,
            };
        }

	$metrics_ref = gen_cloud_class({
				       items => $metrics_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{metrics}{$type}{cloud}});

        my $sortedmetrics_ref ;
        my $collator = Unicode::Collate->new();
        
        @{$sortedmetrics_ref} = map { $_->[0] }
            sort { $collator->cmp($a->[1],$b->[1]) }
                map { [$_, $_->{item}] }
                    @{$metrics_ref};
        
        $config->set_datacache({
            type => 5,
            id   => $database,
            data => $sortedmetrics_ref,
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
        $logger->info("Generating Type 6 metrics for database $database");

        my $maxcount=0;
	my $mincount=999999999;

        my $catalog = new OpenBib::Catalog({ database => $database });

        my $metrics_ref=[];

        # DBI: "select person.content , count(distinct sourceid) as scount from conn, person where sourcetype=1 and targettype=2 and person.category=1 and person.id=conn.targetid group by targetid order by scount desc limit 200"
        my $usage = $catalog->get_schema->resultset('Person')->search_rs(
            {
                'person_fields.field' => 800,
            },
            {
                select   => ['person_fields.content', {'count' => 'title_people.titleid'}],
                as       => ['thiscontent','titlecount'],
                join     => ['person_fields','title_people'],
                group_by => ['title_people.personid','person_fields.content'],
                order_by => { -desc => \'count(title_people.titleid)' },
                rows     => $num,
            }
        );

        while (my $item = $usage->next()){
#        foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $count   = $item->get_column('titlecount');
        
            if ($maxcount < $count){
                $maxcount = $count;
            }

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$metrics_ref, {
                item  => $content,
                count => $count,
            };
        }

	$metrics_ref = gen_cloud_class({
				       items => $metrics_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{metrics}{$type}{cloud}});


        my $sortedmetrics_ref ;
        my $collator = Unicode::Collate->new();
        
        @{$sortedmetrics_ref} = map { $_->[0] }
            sort { $collator->cmp($a->[1],$b->[1]) }
                map { [$_, $_->{item}] }
                    @{$metrics_ref};

        $config->set_datacache({
            type => 6,
            id   => $database,
            data => $sortedmetrics_ref,
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

    foreach my $database (@databases){
        $logger->info("Generating Type 7 metrics for database $database");

        my $maxcount=0;
	my $mincount=999999999;

        my $metrics_ref=[];
        
        # DBI: "select t.id,t.tag,count(tt.tagid) as scount from tags as t, tittag as tt where tt.dbname=? and tt.tagid=t.id group by tt.tagid"
        my $usage = $user->get_schema->resultset('Tag')->search_rs(
            {
                'tit_tags.dbname' => $database,
            },
            {
                select   => ['me.name', 'me.id',{'count' => 'tit_tags.tagid'}],
                as       => ['thiscontent','thisid','titlecount',],
                join     => ['tit_tags'],
                group_by => ['tit_tags.tagid','me.name','me.id'],
                rows     => $num,
            }
        );
        
        foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $id      = $item->get_column('thisid');
            my $count   = $item->get_column('titlecount');

            if ($maxcount < $count){
                $maxcount = $count;
            }

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$metrics_ref, {
                item  => $content,
                id    => $id,
                count => $count,
            };
        }

	$metrics_ref = gen_cloud_class({
				       items => $metrics_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{metrics}{$type}{cloud}});


        my $sortedmetrics_ref ;
        my $collator = Unicode::Collate->new();
        
        @{$sortedmetrics_ref} = map { $_->[0] }
            sort { $collator->cmp($a->[1],$b->[1]) }
                map { [$_, $_->{item}] }
                    @{$metrics_ref};
        
        $config->set_datacache({
            type => 7,
            id   => $database,
            data => $sortedmetrics_ref,
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
        $logger->info("Generating Type 8 metrics for view $view");

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

	my $metrics_ref={};
        foreach my $category (qw/all fs hst verf swt/){
	  my $thismetrics_ref=[];
	  my $sqlstring;

          my $maxcount=0;
	  my $mincount=999999999;

	  my @sqlargs = ($view);

	  if ($category eq 'all'){
	    $sqlstring="select content, count(content) as scount from searchterms where DATE_SUB(CURDATE(),INTERVAL 6 MONTH) <= tstamp and viewname=? group by content order by scount DESC limit 200";
	  }
	  else {
	    $sqlstring="select content, count(content) as scount from searchterms where DATE_SUB(CURDATE(),INTERVAL 6 MONTH) <= tstamp and viewname=? and type = ? group by content order by scount DESC limit 200";
	    push @sqlargs, $cat2type_ref->{$category}; 
	  }

	  my $request=$statisticsdbh->prepare($sqlstring);
	  $request->execute(@sqlargs);
	  while (my $result=$request->fetchrow_hashref){
            my $content = $result->{content};
            my $count   = $result->{scount};
            if ($maxcount < $count){
	      $maxcount = $count;
            }
            if ($mincount > $count){
	      $mincount = $count;
            }
            
            push @$thismetrics_ref, {
				item  => $content,
				count => $count,
            };
	  }

	  $thismetrics_ref = gen_cloud_class({
              items => $thismetrics_ref, 
              min   => $mincount, 
              max   => $maxcount, 
              type  => $config->{metrics}{$type}{cloud}});
          
          
          my $sortedmetrics_ref ;
          my $collator = Unicode::Collate->new();
          
          @{$sortedmetrics_ref} = map { $_->[0] }
              sort { $collator->cmp($a->[1],$b->[1]) }
                  map { [$_, $_->{item}] }
                      @{$thismetrics_ref};
          
          
	  $metrics_ref->{$category}=$sortedmetrics_ref;
      }
        
        if ($logger->is_debug){
            $logger->debug(YAML::Dump($metrics_ref));
        }
        
        $config->set_datacache({
            type => 8,
            id   => $view,
            data => $metrics_ref,
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
        $logger->info("Generating Type 9 metrics for database $database");

        my $maxcount=0;
	my $mincount=999999999;

        my $catalog = new OpenBib::Catalog({ database => $database });

        my $metrics_ref=[];

        # DBI: "select count(distinct id) as scount, content from title where category=425 and content regexp ? group by content order by scount DESC" mit RegEXP "^[0-9][0-9][0-9][0-9]\$"

	my $where_ref = {
	    'title_fields.field' => 425,
	};

	if ($scheme && $scheme eq "marc21"){
	    $where_ref = {
		'title_fields.field' => 264,
		    'title_fields.subfield' => 'c',
	    };
	}

        my $usage = $catalog->get_schema->resultset('Title')->search_rs(
	    $where_ref,
            {
                select   => ['title_fields.content', {'count' => 'title_fields.titleid'}],
                as       => ['thiscontent','titlecount'],
                join     => ['title_fields'],
                group_by => ['title_fields.content'],
                order_by => { -desc => \'count(title_fields.titleid)' },
                rows     => $num,
            }
        );

        foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $count   = $item->get_column('titlecount');

            if ($maxcount < $count){
                $maxcount = $count;
            }

            if ($mincount > $count){
                $mincount = $count;
            }
            
            push @$metrics_ref, {
                item  => $content,
                count => $count,
            };
        }

	$metrics_ref = gen_cloud_class({
				       items => $metrics_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{metrics}{$type}{cloud}});

        my $sortedmetrics_ref ;
        my $collator = Unicode::Collate->new();
        
        @{$sortedmetrics_ref} = map { $_->[0] }
            sort { $collator->cmp($a->[1],$b->[1]) }
                map { [$_, $_->{item}] }
                    @{$metrics_ref};
        
        $config->set_datacache({
            type => 9,
            id   => $database,
            data => $sortedmetrics_ref,
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
        $logger->info("Generating Type 10 metrics for view $view");

        my @databases = $config->get_dbs_of_view($view);
        
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:Pg:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

        my $bk_ref = {};

        my $in_select_string = join(',',map {'?'} @databases);
        my $sqlstring="select count(distinct ai.titleid) as bkcount,n.content as bk from all_titles_by_isbn as ai, enriched_content_by_isbn as n where n.field=4100 and n.isbn=ai.isbn and ai.dbname in ($in_select_string) group by n.content,ai.dbname";

        $logger->debug("$sqlstring");
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
        
        if ($logger->is_debug){
            $logger->debug(YAML::Dump($bk_ref));
        }
        
        $config->set_datacache({
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
        $logger->info("Generating Type 11 metrics for view $view");

        my @databases = $config->get_dbs_of_view($view);
        
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:Pg:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

        my $bk_ref = {};

        foreach my $database (@databases){
            $logger->info("Generating BK's for database $database");
            my $sqlstring="select count(distinct ai.isbn) as bkcount,n.content as bk from all_titles_by_isbn as ai, enriched_content_by_isbn as n where n.field=4100 and n.isbn=ai.isbn and ai.dbname=? group by n.content";
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
            $config->set_datacache({
                type   => 11,
                subkey => $bk,
                id     => $view,
                data   => $bk_ref->{$bk},
            });
            
            if ($logger->is_debug){
                $logger->debug(YAML::Dump($bk_ref->{$bk}));
            }
        }

    }
}

# Typ 12 => Meistaufgerufene Literaturlisten
if ($type == 12){

    my $dbh
        = DBI->connect("DBI:Pg:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
            or $logger->error_die($DBI::errstr);

    $logger->info("Generating Type 12 metrics");

    my $maxcount=0;
    my $mincount=999999999;
    
    my $metrics_ref=[];
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

        if ($logger->is_debug){
            $logger->debug(YAML::Dump($properties_ref));
        }

        # Nur oeffentliche Literaturlisten verwenden
        push @$metrics_ref, {
            item       => $content,
            id         => $id,
            count      => $count,
            properties => $properties_ref,
        } if ($properties_ref->{type} == 1);
    }
    
    $metrics_ref = gen_cloud_class({
        items => $metrics_ref, 
        min   => $mincount, 
        max   => $maxcount, 
        type  => $config->{metrics}{$type}{cloud}});

    my $sortedmetrics_ref ;
    my $collator = Unicode::Collate->new();
    
    @{$sortedmetrics_ref} = map { $_->[0] }
        sort { $collator->cmp($a->[1],$b->[1]) }
            map { [$_, $_->{item}] }
                @{$metrics_ref};
    
    $config->set_datacache({
        type => 12,
        id   => 'litlist_usage',
        data => $sortedmetrics_ref,
    });
}

# Typ 13 => Meistaufgerufene Titel allgemein
if ($type == 13){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (sort @views){
        $logger->info("Generating Type 13 metrics for view $view");

        my $viewdb_ref = [];
        foreach my $dbname ($config->get_viewdbs($view)){
            push @$viewdb_ref, {dbname => $dbname };
        }

        next unless (@$viewdb_ref);

        my $metrics_ref=[];

        my $titleusage = $statistics->get_schema->resultset('Titleusage')->search_rs(
            {
                -or    => $viewdb_ref,
                origin => 1,
                tstamp => { '>' => \'CURRENT_TIMESTAMP - INTERVAL \'180 days\'' },
                
            },
            {
                select   => ['titleid','dbname', {'count' => 'sid'}],
                as       => ['titleid','dbname','sidcount'],
                group_by => ['titleid','dbname'],
                order_by => { -desc => \'count(sid)' },
                rows     => 20,
            }
        );
        foreach my $item ($titleusage->all){
            my $titleid  = $item->get_column('titleid');
            my $count    = $item->get_column('sidcount');
            my $database = $item->get_column('dbname');

            my $item=OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config})->load_brief_record()->to_hash;

            push @$metrics_ref, {
                item  => $item,
                count => $count,
            };
        }

        $config->set_datacache({
            type => 13,
            id   => $view,
            data => $metrics_ref,
        });
    }
}

# Typ 14 => Meistvorkommender Feldinhalt pro Datenbank
if ($type == 14 && $field){

    my $subfield = "";
    
    if ($field =~m/:/){
	($field,$subfield) = $field =~m/^([^:]+):(.)$/
    }

    my @databases = ();
    
    if ($database){
        push @databases, $database;
    }
    else {
        @databases=$config->get_active_databases();
    }
    
    foreach my $database (@databases){
        $logger->info("Generating Type 14 metrics for database $database in field $field and subfield $subfield");

        my $maxcount=0;
	my $mincount=999999999;
	
        my $catalog = new OpenBib::Catalog({ database => $database });
	
        my $metrics_ref=[];
	
	my $usage;
	
	if (defined $is_person_field_ref->{$field}){
	    $usage = $catalog->get_schema->resultset('Person')->search_rs(
		{
		    'person_fields.field' => 800,
		    'title_people.field' => $field,
		     
		},
		{
		    select   => ['person_fields.content', {'count' => 'title_people.titleid'}],
		    as       => ['thiscontent','titlecount'],
		    join     => ['person_fields','title_people'],
		    group_by => ['title_people.personid','person_fields.content'],
		    order_by => { -desc => \'count(title_people.titleid)' },
		}
		);
	    
        }
	elsif (defined $is_corporatebody_field_ref->{$field}){
	    $usage = $catalog->get_schema->resultset('Corporatebody')->search_rs(
		{
		    'corporatebody_fields.field' => 800,
		    'title_corporatebodies.field' => $field,
		     
		},
		{
		    select   => ['corporatebody_fields.content', {'count' => 'title_corporatebodies.titleid'}],
		    as       => ['thiscontent','titlecount'],
		    join     => ['corporatebody_fields','title_corporatebodies'],
		    group_by => ['title_corporatebodies.corporatebodyid','corporatebody_fields.content'],
		    order_by => { -desc => \'count(title_corporatebodies.titleid)' },
		}
		);
        }
	elsif (defined $is_classification_field_ref->{$field}){
	    $usage = $catalog->get_schema->resultset('Classification')->search_rs(
		{
		    'classification_fields.field' => 800,
		    'title_classifications.field' => $field,
		     
		},
		{
		    select   => ['classification_fields.content', {'count' => 'title_classifications.titleid'}],
		    as       => ['thiscontent','titlecount'],
		    join     => ['classification_fields','title_classifications'],
		    group_by => ['title_classifications.classificationid','classifications_field.content'],
		    order_by => { -desc => \'count(title_classifications.titleid)' },
		}
		);
        }
	elsif (defined $is_subject_field_ref->{$field}){
	    $usage = $catalog->get_schema->resultset('Subject')->search_rs(
		{
		    'subject_fields.field' => 800,
		    'title_subjects.field' => $field,
                     'subject_fields.mult'  => 1,
		     
		},
		{
		    select   => ['subject_fields.content', {'count' => 'title_subjects.titleid'}],
		    as       => ['thiscontent','titlecount'],
		    join     => ['subject_fields','title_subjects'],
		    group_by => ['title_subjects.subjectid','subject_fields.content'],
		    order_by => { -desc => \'count(title_subjects.titleid)' },
		}
		);
        }	
        else {
	    # DBI: "select count(distinct id) as scount, content from title where category=425 and content regexp ? group by content order by scount DESC" mit RegEXP "^[0-9][0-9][0-9][0-9]\$"

  	    my $where_ref = {
		    'title_fields.field' => $field,
	    };

	    if ($subfield){
	       $where_ref->{'title_fields.subfield'} = $subfield;
	    }      				  

	    $usage = $catalog->get_schema->resultset('Title')->search_rs( # 
	        $where_ref,
		{
		    select   => ['title_fields.content', {'count' => 'title_fields.titleid'}],
		    as       => ['thiscontent','titlecount'],
		    join     => ['title_fields'],
		    group_by => ['title_fields.content'],
		    order_by => { -desc => \'count(title_fields.titleid)' },
		    rows     => $num,
		}
		);
        }
	
	if ($usage){
	    foreach my $item ($usage->all){
		my $content = $item->get_column('thiscontent');
		my $count   = $item->get_column('titlecount');

		if ($maxcount < $count){
		    $maxcount = $count;
		}
		
		if ($mincount > $count){
		    $mincount = $count;
		}
		
		push @$metrics_ref, {
		    item  => $content,
		    count => $count,
		};
	    }

	}

	$metrics_ref = gen_cloud_class({
				       items => $metrics_ref, 
				       min   => $mincount, 
				       max   => $maxcount, 
				       type  => $config->{metrics}{$type}{cloud}});

        my $sortedmetrics_ref ;
        my $collator = Unicode::Collate->new();
        
        @{$sortedmetrics_ref} = map { $_->[0] }
            sort { $collator->cmp($a->[1],$b->[1]) }
                map { [$_, $_->{item}] }
                    @{$metrics_ref};

        if ($subfield){
          $field = $field.":".$subfield;
        }

        $config->set_datacache({
            type => 14,
            id   => "$database-$field",
            data => $sortedmetrics_ref,
        });
    }
}

# Typ 15 => Besetzungszahlen der Titel in der USB LS-Systematik
if ($type == 15){

    unless ($database){
       $logger->error("Die Besetzungszahlen koennen nur fuer einen Katalog bestimmt werden. Ende.");
       exit;
    }

    my $cls = $config->load_yaml('/opt/openbib/conf/usbls.yml');
    
    my $counter_ref = {};

    foreach my $base (keys %$cls){
       foreach my $group (keys %{$cls->{$base}{sub}}){
         $counter_ref->{$group} = 0;
       }
    }

    $logger->info("Generating Type 15 metrics for database $database");

    my $catalog = new OpenBib::Catalog({ database => $database });

    my $where_ref = {
       'title_fields.field' => 351,
    };

    if ($scheme && $scheme eq "marc21"){
       $where_ref->{'title_fields.field'} = 1002;
    }

    my $usage = $catalog->get_schema->resultset('Title')->search_rs(
            $where_ref,
            {
                select   => ['title_fields.content', {'count' => 'title_fields.titleid'}],
                as       => ['thiscontent','titlecount'],
                join     => ['title_fields'],
                group_by => ['title_fields.content'],
                order_by => { -desc => \'count(title_fields.titleid)' },
            }
        );

    foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $count   = $item->get_column('titlecount');

            $counter_ref->{$content} = $count;
    }
        
    $config->set_datacache({
            type => 15,
            id   => $database,
            data => $counter_ref,
    });

}

# Typ 16 => Besetzungszahlen der Titel in der USB LBS-Systematik
if ($type == 16){

    unless ($database){
       $logger->error("Die Besetzungszahlen koennen nur fuer einen Katalog bestimmt werden. Ende.");
       exit;
    }

    my $cls = $config->load_yaml('/opt/openbib/conf/usblbs.yml');
    
    my $counter_ref = {};

    foreach my $base (keys %$cls){
       foreach my $group (keys %{$cls->{$base}{sub}}){
         $counter_ref->{$group} = 0; # 
       }
    }

    $logger->info("Generating Type 16 metrics for database $database");

    my $catalog = new OpenBib::Catalog({ database => $database });

    my $where_ref = {
       'title_fields.field' => 351,
    };

    if ($scheme && $scheme eq "marc21"){
       $where_ref->{'title_fields.field'} = 1002;
    }

    my $usage = $catalog->get_schema->resultset('Title')->search_rs(
            $where_ref,
            {
                select   => ['title_fields.content', {'count' => 'title_fields.titleid'}],
                as       => ['thiscontent','titlecount'],
                join     => ['title_fields'],
                group_by => ['title_fields.content'],
                order_by => { -desc => \'count(title_fields.titleid)' },
            }
        );

    foreach my $item ($usage->all){
            my $content = $item->get_column('thiscontent');
            my $count   = $item->get_column('titlecount');

            $counter_ref->{$content} = $count;
    }
        
    $config->set_datacache({
            type => 16,
            id   => $database,
            data => $counter_ref,
    });

}

# Typ 17 => Besetzungszahlen der Merklisten 
if ($type == 17){
    
    my $metrics_ref=[];

    my $histogram_ref = {};
    
    my $cartitemusage = $config->get_schema->resultset('UserCartitem')->search_rs(
	{
	},
	{
	    select   => [{'count' => 'me.userid'}],
	    as       => ['cartitemcount'],
	    group_by => ['me.userid'],
	    join     => ['cartitemid'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
	}
	);
    
    while (my $thiscount = $cartitemusage->next()){
	my $count    = $thiscount->{'cartitemcount'};
	
	my $current_count = (defined $histogram_ref->{$count})?$histogram_ref->{$count}:0;

	$current_count++;
	$histogram_ref->{$count} = $current_count;
    }

    foreach my $count (sort { $a <=> $b }  keys %$histogram_ref){
	push @$metrics_ref, {
	    cartitemcount  => $count,
	    usercount => $histogram_ref->{$count},
	};
    }
    
    $config->set_datacache({
	type => 17,
	id   => 'cartitems',
	data => $metrics_ref,
			    });
}

# Typ 18 => Sessions pro View aktuelles Jahr (monatlich, taeglich)
if ($type == 18){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type $type metrics for view $view");

	# monthly
	my $metrics_ref = $statistics->get_sequencestat_of_event({ type => 100 , subtype => 'monthly', content => $view, year => $current_year, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Monthly $current_year ".YAML::Dump($metrics_ref));
        }

	# daily
	$metrics_ref = $statistics->get_sequencestat_of_event({ type => 100 , subtype => 'monthly', content => $view, year => $current_year, month => $current_month, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Daily $current_month/$current_year ".YAML::Dump($metrics_ref));
        }
    }
}

# Typ 19 => Sessions pro View vergangenes Jahr (monatlich)
if ($type == 19){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type $type metrics for view $view");

	# monthly
	my $metrics_ref = $statistics->get_sequencestat_of_event({ type => 100 , subtype => 'monthly', content => $view, year => $last_year, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Monthly $last_year ".YAML::Dump($metrics_ref));
        }
    }
}

# Typ 20 => Suchanfragen pro View aktuelles Jahr (monatlich, taeglich)
if ($type == 20){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type $type metrics for view $view");

	# monthly
	my $metrics_ref = $statistics->get_sequencestat_of_event({ type => 1 , subtype => 'monthly', content => $view, year => $current_year, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Monthly $current_year ".YAML::Dump($metrics_ref));
        }

	# daily
	$metrics_ref = $statistics->get_sequencestat_of_event({ type => 1 , subtype => 'monthly', content => $view, year => $current_year, month => $current_month, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Daily $current_month/$current_year ".YAML::Dump($metrics_ref));
        }
    }
}

# Typ 21 => Suchanfragen pro View vergangenes Jahr (monatlich)
if ($type == 21){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type $type metrics for view $view");

	# monthly
	my $metrics_ref = $statistics->get_sequencestat_of_event({ type => 1 , subtype => 'monthly', content => $view, year => $last_year, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Monthly $last_year ".YAML::Dump($metrics_ref));
        }
    }
}

# Typ 22 => Trefferaufrufe pro View aktuelles Jahr (monatlich, taeglich)
if ($type == 22){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type $type metrics for view $view");

	# monthly
	my $metrics_ref = $statistics->get_sequencestat_of_event({ type => 10 , subtype => 'monthly', content => $view, year => $current_year, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Monthly $current_year ".YAML::Dump($metrics_ref));
        }

	# daily
	$metrics_ref = $statistics->get_sequencestat_of_event({ type => 10 , subtype => 'monthly', content => $view, year => $current_year, month => $current_month, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Daily $current_month/$current_year ".YAML::Dump($metrics_ref));
        }
    }
}

# Typ 23 => Trefferaufrufe pro View vergangenes Jahr (monatlich)
if ($type == 23){
    my @views = ();

    if ($view){
        push @views, $view;
    }
    else {
        @views=$config->get_active_views();
    }

    foreach my $view (@views){
        $logger->info("Generating Type $type metrics for view $view");

	# monthly
	my $metrics_ref = $statistics->get_sequencestat_of_event({ type => 10 , subtype => 'monthly', content => $view, year => $last_year, refresh => 1 }) ;

        if ($logger->is_debug){
            $logger->debug("Monthly $last_year ".YAML::Dump($metrics_ref));
        }
    }
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

        if ($logger->is_debug){
            $logger->debug(YAML::Dump(\@thresholds)." - $delta");
        }

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

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($items_ref));
    }
    
    return $items_ref;
}

sub print_help {
    print << "ENDHELP";
gen_metrics.pl - Erzeugen und Cachen von Metriken aus Katalog- oder Statistik-Daten

   Optionen:
   -help                 : Diese Informationsseite
   --database=...        : Einzelner Katalog
   --logfile=...         : Alternatives Logfile
   --type=...            : Metrik-Typ

   Typen:

   1 => Meistaufgerufene Titel pro Datenbank
   2 => Meistgenutzte Kataloge bezogen auf Titelaufrufe pro View
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
  13 => Meistaufgerufene Titel allgemein       
  14 => Meistvorkommender Feldinhalt pro Datenbank
  15 => Besetzungszahlen der Titel in der USB LS-Systematik
  16 => Besetzungszahlen der Titel in der USB LBS-Systematik
  17 => Besetzungszahlen der Merklisten
  18 => Sessions pro View aktuelles Jahr (monatlich, taeglich)
  19 => Sessions pro View vergangenes Jahr (monatlich)
  20 => Suchanfragen pro View aktuelles Jahr (monatlich, taeglich)
  21 => Suchanfragen pro View vergangenes Jahr (monatlich)
  22 => Trefferaufrufe pro View aktuelles Jahr (monatlich, taeglich)
  23 => Trefferaufrufe pro View vergangenes Jahr (monatlich)
ENDHELP
    exit;
}

