#####################################################################
#
#  OpenBib::Config
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Config;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton::Process);

use Apache2::Reload;
use Apache2::Const -compile => qw(:common);
use Cache::Memcached;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use LWP;
use URI::Escape qw(uri_escape);
use YAML::Syck;

use OpenBib::Database::DBI;
use OpenBib::Database::Config;
#use OpenBib::EZB;
#use OpenBib::DBIS;
#use OpenBib::Enrichment;

sub new {
    my $class = shift;

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;
    
    # Ininitalisierung mit Config-Parametern
    my $self = YAML::Syck::LoadFile("/opt/openbib/conf/portal.yml");

    bless ($self, $class);

    $self->connectDB();
    $self->connectMemcached();
    
    return $self;
}

sub _new_instance {
    my $class = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;

    # Ininitalisierung mit Config-Parametern
    my $self = YAML::Syck::LoadFile("/opt/openbib/conf/portal.yml");

    bless ($self, $class);

    $self->connectDB();
    $self->connectMemcached();

    return $self;
}

sub get_number_of_dbs {
    my $self = shift;
    my $profilename = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $memc_key = "config:number_of_dbs:active:";

    if ($profilename){
        $memc_key.=$profilename;
    }
    else {
        $memc_key.='all';
    }
    
    my $alldbs = $self->{memc}->get($memc_key);
    return $alldbs if ($alldbs);

    # $self->{schema}->storage->debug(1);

    if ($profilename){
        # DBI: "select count(orgunit_db.dbid) as rowcount from orgunit_db,databaseinfo,profileinfo,orgunitinfo where profileinfo.profilename = ? and profileinfo.id=orgunitinfo.profileid and orgunitinfo.id=orgunit_db.orgunitid and databaseinfo.id=orgunit_db.dbid and databaseinfo.active is true"
        $alldbs = $self->{schema}->resultset('OrgunitDb')->search(
            {
                'dbid.active'           => 1,
                'profileid.profilename' => $profilename,
            }, 
            {
                join => [ 'orgunitid', 'dbid',  ],
                prefetch => [ { 'orgunitid' => 'profileid' } ],
                columns  => [ qw/dbid.dbname/ ], # columns/group_by -> versch. dbid.dbname 
                group_by => [ qw/dbid.dbname/ ], # via group_by und nicht via distinct (Performance)
            }
        )->count;
        
    }
    else {
        # DBI: "select count(distinct dbname) from databaseinfo where active=true"
        $alldbs = $self->{schema}->resultset('Databaseinfo')->search(
            {
                'active' => 1
            }, 
            {
                columns => [ qw/dbname/ ],
                group_by => [ qw/dbname/ ],
            }
        )->count;
    }
    
    return $alldbs;
}

sub get_number_of_all_dbs {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(id) as rowcount from databaseinfo"
    my $alldbs = $self->{schema}->resultset('Databaseinfo')->search(
        undef,
        {
            columns => [ qw/dbname/ ],
            group_by => [ qw/dbname/ ],

        })->count;
    
    return $alldbs;
}

sub get_number_of_views {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(viewid) as rowcount from viewinfo where active is true"
    my $allviews = $self->{schema}->resultset('Viewinfo')->search(
        {
            'active' => 1,
        },
        {
            columns => [ qw/viewname/ ],
            group_by => [ qw/viewname/ ],

        }
    )->count;
    
    return $allviews;
}

sub get_number_of_all_views {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(viewid) as rowcount from viewinfo"
    my $allviews = $self->{schema}->resultset('Viewinfo')->search(
        undef,
        {
            columns => [ qw/viewname/ ],
            group_by => [ qw/viewname/ ],
            
        }
    )->count;
    
    return $allviews;
}

sub get_number_of_titles {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}        : undef;

    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}            : undef;

    my $profile            = exists $arg_ref->{profile}
        ? $arg_ref->{profile}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $counts;
    my $request;

#     $self->{schema}->storage->debug(1);

    if ($database){
        # DBI: "select allcount, journalcount, articlecount, digitalcount from databaseinfo where dbname = ? and databaseinfo.active is true"
        $counts = $self->{schema}->resultset('Databaseinfo')->search(
            {
                'active' => 1,
                'dbname' => $database,
            },
            {
                columns => [qw/ allcount journalcount articlecount digitalcount /],
            }
        )->first;
        
    }
    elsif ($view){
        # DBI: "select sum(allcount) as allcount, sum(journalcount) as journalcount, sum(articlecount) as articlecount, sum(digitalcount) as digitalcount from databaseinfo,view_db,viewinfo where viewinfo.viewname=? and view_db.viewid=viewinfo.id and view_db.dbid=databaseinfo.id and databaseinfo.active is true"
        $counts = $self->{schema}->resultset('ViewDb')->search_rs(
            {
                'dbid.active'     => 1,
                'viewid.viewname' => $view,
            },
            {
                join => ['dbid','viewid'],

                select => [ {'sum' => 'dbid.allcount'}, {'sum' => 'dbid.journalcount'}, {'sum' => 'dbid.articlecount'}, {'sum' => 'dbid.digitalcount'}],
                as     => ['allcount', 'journalcount', 'articlecount', 'digitalcount'],
            }
        )->first;
    }
    elsif ($profile){
        # DBI: "select sum(allcount) as allcount, sum(journalcount) as journalcount, sum(articlecount) as articlecount, sum(digitalcount) as digitalcount from databaseinfo,orgunit_db,profileinfo,orgunitinfo where profileinfo.profilename = ? and orgunitinfo.profileid=profileinfo.id and orgunit_db.orgunitid=orgunitinfo.id and orgunit_db.dbid=databaseinfo.id and databaseinfo.active is true"
        $counts = $self->{schema}->resultset('OrgunitDb')->search(
            {
                'dbid.active'           => 1,
                'profileid.profilename' => $profile,
            }, 
            {
                join => [ 'orgunitid', 'dbid',  ],
                prefetch => [ { 'orgunitid' => 'profileid' } ],
                select => [ {'sum' => 'dbid.allcount'}, {'sum' => 'dbid.journalcount'}, {'sum' => 'dbid.articlecount'}, {'sum' => 'dbid.digitalcount'}],
                as     => ['allcount', 'journalcount', 'articlecount', 'digitalcount'],

            }
        )->first;

    }
    else {
        # DBI: "select sum(allcount) as allcount, sum(journalcount) as journalcount, sum(articlecount) as articlecount, sum(digitalcount) as digitalcount from databaseinfo where databaseinfo.active is true"
        $counts = $self->{schema}->resultset('Databaseinfo')->search(
            {
                'active' => 1,
            },
            {
                select => [ {'sum' => 'allcount'}, {'sum' => 'journalcount'}, {'sum' => 'articlecount'}, {'sum' => 'digitalcount'}],
                as     => ['allcount', 'journalcount', 'articlecount', 'digitalcount'],
            })->first;
    }

    my $alltitles_ref = {   
        allcount     => $counts->get_column('allcount'),
        journalcount => $counts->get_column('journalcount'),
        articlecount => $counts->get_column('articlecount'),
        digitalcount => $counts->get_column('digitalcount'),
    };
        
    return $alltitles_ref;
}

sub get_viewdesc_from_viewname {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select description from viewinfo where viewname = ?"
    my $desc = $self->{schema}->resultset('Viewinfo')->search({ viewname => $viewname}, { select => 'description' })->first->description;
    
    return $desc;
}

sub get_startpage_of_view {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select start_loc from viewinfo where viewname = ?"
    my $start_loc = $self->{schema}->resultset('Viewinfo')->search({ viewname => $viewname}, { select => 'start_loc' })->first->start_loc;

    $logger->debug("Got Startpage $start_loc") if (defined $start_loc);
    
    return $start_loc;
}

sub get_servername_of_view {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select servername from viewinfo where viewname = ?"
    my $servername = $self->{schema}->resultset('Viewinfo')->search({ viewname => $viewname}, { select => 'servername' })->first->servername;

    $logger->debug("Got Startpage $servername") if (defined $servername);
    
    return $servername;
}

sub db_exists {
    my $self   = shift;
    my $dbname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(dbname) as rowcount from databaseinfo where dbname = ?"
    my $count = $self->{schema}->resultset('Databaseinfo')->search({ dbname => $dbname})->count;
    
    return $count;
}

sub view_exists {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(viewname) as rowcount from viewinfo where viewname = ?"
    my $count = $self->{schema}->resultset('Viewinfo')->search({ viewname => $viewname})->count;
    
    return $count;
}

sub profile_exists {
    my $self     = shift;
    my $profilename = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(profilename) as rowcount from profileinfo where profilename = ?"
    my $count = $self->{schema}->resultset('Profileinfo')->search({ profilename => $profilename})->count;
    
    return $count;
}

sub orgunit_exists {
    my $self     = shift;
    my $profilename = shift;
    my $orgunitname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(orgunitname) as rowcount from orgunitinfo,profileinfo where profileinfo.profilename = ? and orgunitinfo.orgunitname = ? and orgunitinfo.profileid = profileinfo.id"
    my $count = $self->{schema}->resultset('Orgunitinfo')->search(
        {
            orgunitname             => $orgunitname,
            'profileid.profilename' => $profilename
        },
        {
            join => 'profileid',
        }
    )->count;
    
    return $count;
}


sub get_valid_rsscache_entry {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database               = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;
    my $type                   = exists $arg_ref->{type}
        ? $arg_ref->{type}                : undef;
    my $subtype                = exists $arg_ref->{subtype}
        ? $arg_ref->{subtype}             : undef;
    my $expiretimedate         = exists $arg_ref->{expiretimedate}
        ? $arg_ref->{expiretimedate}      : 20110101;

    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->storage->debug(1);
    
    # Bestimmung, ob ein valider Cacheeintrag existiert

    # DBI ehemals: "select content from rsscache where dbname=? and type=? and subtype = ? and tstamp > ?"
    my $rss_content = $self->{schema}->resultset('Rssinfo')->search(
        {
            'dbid.dbname'  => $database,
            'type'         => $type,
            'subtype'      => $subtype,
            'cache_tstamp' => { '>' => $expiretimedate },
        },
        {
            select => 'cache_content',
            join   => 'dbid',
        }
    )->get_column('cache_content');
    
    return $rss_content;
}

sub get_dbs_of_view {
    my ($self,$view) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select databaseinfo.dbname from view_db,databaseinfo,orgunit_db,viewinfo,orgunitinfo where viewinfo.viewname = ? and view_db.viewid=viewinfo.id and view_db.dbid=databaseinfo.id and orgunit_db.dbid=view_db.dbid and databaseinfo.active is true order by orgunitinfo.orgunitname ASC, databaseinfo.description ASC"
    my $dbnames = $self->{schema}->resultset('ViewDb')->search(
        {
            'dbid.active'           => 1,
            'viewid.viewname'       => $view,
        }, 
        {
            join => [ 'viewid', 'dbid',  ],
            select => 'dbid.dbname',
            as     => 'thisdbname',
            order_by => 'dbid.dbname',
        }
    );

    my @dblist=();

    foreach my $item ($dbnames->all){
        push @dblist, $item->get_column('thisdbname');
    }

    $logger->debug("View-Databases:\n".YAML::Dump(\@dblist));

    return @dblist;
}

sub get_rssfeeds_of_view {
    my ($self,$viewname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select view_rss.rssid from view_rss,viewinfo where view_rss.viewid = viewinfo.id and viewinfo.viewname=?"
    my $rssinfos = $self->{schema}->resultset('ViewRss')->search(
        {
            'viewid.viewname' => $viewname,
        },
        {
            select => 'rssid.id',
            as     => 'thisrssid',
            join   => ['viewid','rssid'],
        }
    );
    
    my $viewrssfeed_ref  = {};

    foreach my $item ($rssinfos->all){
        $viewrssfeed_ref->{$item->get_column('thisrssid')}=1;
    }

    return $viewrssfeed_ref;
}

sub get_rssfeed_overview {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select rssinfo.*,databaseinfo.dbname from rssinfo, databaseinfo where rssinfo.dbid=databaseinfo.id order by databaseinfo.dbname,rssinfo.type,rssinfo.subtype"
    my $rssinfos = $self->{schema}->resultset('Rssinfo')->search(
        undef,
        {
            select => [ 'me.id', 'me.type', 'me.subtype', 'me.subtypedesc', 'dbid.dbname'],
            as     => [ 'id', 'type', 'subtype', 'subtypedesc', 'dbname'],
            join   => 'dbid',
            order_by => ['dbid.dbname','type','subtype'],
        }
    );
    
    my $rssfeed_ref=[];
    
    foreach my $item ($rssinfos->all){
        push @$rssfeed_ref, {
            feedid      => $item->get_column('id'),
            dbname      => $item->get_column('dbname'),
            type        => $item->get_column('type'),
            subtype     => $item->get_column('subtype'),
            subtypedesc => $item->get_column('subtypedesc'),
        };
    }
    
    return $rssfeed_ref;
}

sub get_rssfeed_by_id {
    my ($self,$id) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select * from rssinfo where id = ? order by type,subtype"
    my $rssinfo = $self->{schema}->resultset('Rssinfo')->search(
        {
            'me.id' => $id,
        },
        {
            select => [ 'me.id', 'me.type', 'me.subtype', 'me.subtypedesc', 'me.active', 'dbid.dbname'],
            as     => [ 'id', 'type', 'subtype', 'subtypedesc', 'active', 'dbname'],
            join   => 'dbid',
            order_by => ['dbid.dbname','type','subtype'],
        }
    )->first;

    my $rssfeed_ref = {
        id          => $rssinfo->get_column('id'),
        dbname      => $rssinfo->get_column('dbname'),
        type        => $rssinfo->get_column('type'),
        subtype     => $rssinfo->get_column('subtype'),
        subtypedesc => $rssinfo->get_column('subtypedesc'),
        active      => $rssinfo->get_column('active'),
    };

    return $rssfeed_ref;
}

sub get_rssfeeds_of_db {
    my ($self,$dbname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select * from rssinfo where dbname = ? order by type,subtype"
    my $rssinfos = $self->{schema}->resultset('Rssinfo')->search(
        {
            'dbid.dbname' => $dbname
        },
        {
            select => [ 'me.id', 'me.type', 'me.subtype', 'me.subtypedesc', 'me.active', 'dbid.dbname'],
            as     => [ 'id', 'type', 'subtype', 'subtypedesc', 'active', 'dbname'],
            join   => 'dbid',
            order_by => ['dbid.dbname','type','subtype'],
        }
    );
    
    my $rssfeed_ref=[];
    
    foreach my $item ($rssinfos->all){
        push @$rssfeed_ref, {
            id          => $item->get_column('id'),
            dbname      => $item->get_column('dbname'),
            type        => $item->get_column('type'),
            subtype     => $item->get_column('subtype'),
            subtypedesc => $item->get_column('subtypedesc'),
            active      => $item->get_column('active'),
        };
    }

    return $rssfeed_ref;
}

sub get_rssfeeds_of_db_by_type {
    my ($self,$dbname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select * from rssinfo where dbname = ? order by type,subtype"
    my $rssinfos = $self->{schema}->resultset('Rssinfo')->search(
        {
            'dbid.dbname' => $dbname
        },
        {
            select => [ 'me.id', 'me.type', 'me.subtype', 'me.subtypedesc', 'me.active', 'dbid.dbname'],
            as     => [ 'id', 'type', 'subtype', 'subtypedesc', 'active', 'dbname'],
            join   => 'dbid',
            order_by => ['type','subtype'],
        }
    );

    my $rssfeed_ref  = {};

    foreach my $item ($rssinfos->all){
        push @{$rssfeed_ref->{$item->get_column('type')}}, {
            id          => $item->get_column('id'),
            subtype     => $item->get_column('subtype'),
            subtypedesc => $item->get_column('subtypedesc'),
            active      => $item->get_column('active'),
            dbname      => $item->get_column('dbname'),
        };
    }

    return $rssfeed_ref;
}

sub get_primary_rssfeed_of_view  {
    my ($self,$viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Assoziierten View zur Session aus Datenbank holen
    # DBI: "select databaseinfo.dbname as dbname,rssinfo.type as type, rssinfo.subtype as subtype from rssinfo,databaseinfo,viewinfo where rssinfo.dbid=databaseinfo.id and viewinfo.viewname = ? and rssinfo.id = viewinfo.rssid and rssinfo.active is true"
    my $rssinfos = $self->{schema}->resultset('Viewinfo')->search(
        {
            'me.viewname'  => $viewname,
            'rssid.active' => 1,
        },
        {
            select => [ 'rssid.type', 'rssid.subtype', 'dbid.dbname'],
            as     => [ 'type', 'subtype', 'dbname'],
            join   => [ 'rssid', { 'rssid' => 'dbid' } ],
        }
    )->first;
    
    my $dbname  = decode_utf8($rssinfos->get_column('dbname')) || '';
    my $type    = $rssinfos->get_column('type')    || 0;
    my $subtype = $rssinfos->get_column('subtype') || 0;

    foreach my $typename (keys %{$self->{rss_types}}){
        if ($self->{rss_types}{$typename} eq $type){
            $type=$typename;
            last;
        }
    }
    
    my $primrssfeedurl="";

    if ($dbname && $type){
        $primrssfeedurl=$self->{connector_rss_loc}."/$type/$dbname.rdf";
    }
    
    return $primrssfeedurl;
}

sub get_activefeeds_of_db  {
    my ($self,$dbname)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select type from rssinfo where dbname = ? and active is true"
    my $feeds = $self->{schema}->resultset('Rssinfo')->search(
        {
            'dbid.dbname' => $dbname,
            'dbid.active' => 1,
        },
        {
            select => 'type',
            join   => 'dbid',
        }
    );
    
    my $activefeeds_ref = {};

    foreach my $item ($feeds->all){
        $activefeeds_ref->{$item->get_column('type')} = 1;
    }
    
    return $activefeeds_ref;
}

sub get_rssfeedinfo  {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select databaseinfo.dbname,databaseinfo.description,orgunitinfo.description as orgunitdescription,rssinfo.type"
    # DBI:  @sql_from  = ('databaseinfo','rssinfo','orgunit_db','orgunitinfo');
    # DBI:  @sql_where = ('databaseinfo.active is true','rssinfo.active is true','databaseinfo.id=rssinfo.dbid','rssinfo.type = 1','orgunitinfo.id=orgunit_db.orgunitid','orgunit_db.dbid=databaseinfo.id');
    # DBI:  order by description ASC'

    my $feedinfos;
    
    if ($view){
        # DBI: push @sql_from,  'view_rss';
        # DBI: push @sql_where, ('view_rss.viewname = ?','view_rss.rssfeed=rssinfo.id');
        # DBI: push @sql_args,  $view;

        $feedinfos = $self->{schema}->resultset('Rssinfo')->search(
            {
                'me.active'       => 1,
                'me.type'         => 1,
                'dbid.active'     => 1,
                'viewid.viewname' => $view,
            },
            {
                join   => [ 'dbid', { 'dbid' => { 'orgunit_dbs' => 'orgunitid' } }, 'view_rsses', { 'view_rsses' => 'viewid' } ],
                select => [ 'dbid.dbname', 'dbid.description', 'orgunitid.description', 'me.type' ],
                as     => [ 'thisdbname', 'thisdbdescription', 'thisorgunitdescription', 'thisrsstype' ],
                order_by => [ 'dbid.description ASC' ],
            }
        );
    }
    else {
        $feedinfos = $self->{schema}->resultset('Rssinfo')->search(
            {
                'me.active'   => 1,
                'me.type'     => 1,
                'dbid.active' => 1,
            },
            {
                join   => [ 'dbid', { 'dbid' => { 'orgunit_dbs' => 'orgunitid' } } ],
                select => [ 'dbid.dbname', 'dbid.description', 'orgunitid.description', 'me.type' ],
                as     => [ 'thisdbname', 'thisdbdescription', 'thisorgunitdescription', 'thisrsstype' ],
                order_by => [ 'dbid.description ASC' ],
            }
        );
    }
    
    my $rssfeedinfo_ref = {};

    foreach my $item ($feedinfos->all){
        my $orgunit    = decode_utf8($item->get_column('thisorgunitdescription'));
        my $name       = decode_utf8($item->get_column('thisdbdescription'));
        my $pool       = decode_utf8($item->get_column('thisdbname'));
        my $rsstype    = decode_utf8($item->get_column('thisrsstype'));
        
        push @{$rssfeedinfo_ref->{$orgunit}},{
            pool     => $pool,
            pooldesc => $name,
            type     => 'neuzugang',
        };
    }
    
    return $rssfeedinfo_ref;
}

sub update_rsscache {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $database               = exists $arg_ref->{database}
        ? $arg_ref->{database}        : undef;
    my $type                   = exists $arg_ref->{type}
        ? $arg_ref->{type}            : undef;
    my $subtype                = exists $arg_ref->{subtype}
        ? $arg_ref->{subtype}         : undef;
    my $rssfeed                = exists $arg_ref->{rssfeed}
        ? $arg_ref->{rssfeed}         : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update rssinfo,databaseinfo set rssinfo.cache_content = ? where databaseinfo.dbname = ? and rssinfo.type = ? and rssinfo.subtype = ? and databaseinfo.id=rssinfo.dbid"
    $self->{schema}->resultset('Rssinfo')->search(
        {
            'dbid.dbname' => $database,
            'me.type'     => $type,
            'me.subtype'  => $subtype,
        },
        {
            join => 'dbid',
        }
    )->single->update({ cache_content => $rssfeed, cache_tstamp => \'NOW()' });

    return $self;
}

sub get_dbinfo {
    my ($self,$args_ref) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $dbinfo = $self->{schema}->resultset('Databaseinfo')->search(
        $args_ref
    );
    
    return $dbinfo;
}

sub get_databaseinfo {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->{schema}->resultset('Databaseinfo');
    
    return $object;
}

# sub get_profiledbs {
#     my ($self,@args) = @_;
    
#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $object = $self->{schema}->resultset('ProfileDB');
    
#     return $object;
# }

sub get_dbinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->get_databaseinfo->search(
        undef,
        {
            order_by => 'dbname',
        }
    );
    
    return $object;
}

sub get_libinfo {
    my $self   = shift;
    my $dbname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return {} if (!$dbname);

    # DBI: "select category,content,indicator from libraryinfo where dbname = ?"
    my $libraryinfos = $self->{schema}->resultset('Libraryinfo')->search(
        {
            'dbid.dbname' => $dbname,
        },
        {
            join => 'dbid',
        }
    );

    my $libinfo_ref= {};

    $libinfo_ref->{database} = $dbname;

    foreach my $item ($libraryinfos->all){
        my $category  = "I".sprintf "%04d",$item->category;
        my $indicator =         decode_utf8($item->indicator);
        my $content   =         decode_utf8($item->content);
#        my $indicator = $item->indicator;
#        my $content   = $item->content;

        next if ($content=~/^\s*$/);
#        $content =~s/"/%22/g;
        push @{$libinfo_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    return $libinfo_ref;
}

sub have_libinfo {
    my $self   = shift;
    my $dbname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return 0 if (!$dbname);
    
    # DBI: "select count(dbid) as infocount from libraryinfo,databaseinfo where libraryinfo.dbid=databaseinfo.id and databaseinfo.dbname = ? and content != ''"
    my $haveinfos = $self->{schema}->resultset('Libraryinfo')->search(
        {
            'dbid.dbname' => $dbname,
            'me.content' => { '!=' => '' },
        },
        {
            join => 'dbid',
        }
    )->count;

    return $haveinfos;
}

sub get_viewinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->get_viewinfo->search_rs(
        undef,
        {
            order_by => 'viewname',
        }
    );
    
    return $object;

#     my $idnresult=$self->{dbh}->prepare("select * from viewinfo order by viewname") or $logger->error($DBI::errstr);
#     $idnresult->execute() or $logger->error($DBI::errstr);
#     while (my $result=$idnresult->fetchrow_hashref()) {
#         my $viewname    = decode_utf8($result->{'viewname'});
#         my $description = decode_utf8($result->{'description'});
#         my $active      = decode_utf8($result->{'active'});
#         my $profile     = decode_utf8($result->{'profilename'});
        
#         $description = (defined $description)?$description:'Keine Beschreibung';
        
#         $active="Ja"   if ($active eq "1");
#         $active="Nein" if ($active eq "0");
        
#         my $idnresult2=$self->{dbh}->prepare("select * from view_db where viewname = ? order by dbname") or $logger->error($DBI::errstr);
#         $idnresult2->execute($viewname);
        
#         my @viewdbs=();
#         while (my $result2=$idnresult2->fetchrow_hashref()) {
#             my $dbname = decode_utf8($result2->{'dbname'});
#             push @viewdbs, $dbname;
#         }
        
#         $idnresult2->finish();
        
#         my $viewdb=join " ; ", @viewdbs;
        
#         $view={
#             viewname    => $viewname,
#             description => $description,
#             profile     => $profile,
#             active      => $active,
#             viewdb      => $viewdb,
#         };
        
#         push @{$viewinfo_ref}, $view;
        
#     }
    
#     return $viewinfo_ref;
}

sub get_profileinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profileinfo_ref = [];

    my $profile="";

    my $object = $self->get_profileinfo->search_rs(
        undef,
        {
            order_by => 'profilename',
        }
    );
    
    return $object;

#     my $idnresult=$self->{dbh}->prepare("select * from profileinfo order by profilename") or $logger->error($DBI::errstr);
#     $idnresult->execute() or $logger->error($DBI::errstr);
#     while (my $result=$idnresult->fetchrow_hashref()) {
#         my $profilename = decode_utf8($result->{'profilename'});
#         my $description = decode_utf8($result->{'description'});
          
#         $description = (defined $description)?$description:'Keine Beschreibung';
        
#         my $idnresult2=$self->{dbh}->prepare("select * from orgunit_db where profilename = ? order by dbname") or $logger->error($DBI::errstr);
#         $idnresult2->execute($profilename);
        
#         my @orgunitdbs=();
#         while (my $result2=$idnresult2->fetchrow_hashref()) {
#             my $dbname = decode_utf8($result2->{'dbname'});
#             push @orgunitdbs, $dbname;
#         }
        
#         $idnresult2->finish();
        
#         my $profiledb=join " ; ", @orgunitdbs;
        
#         $profile={
#             profilename => $profilename,
#             description => $description,
#             profiledb   => $profiledb,
#         };
        
#         push @{$profileinfo_ref}, $profile;
        
#     }
    
#     return $profileinfo_ref;
}

sub get_profileinfo {
    my ($self,$args_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profileinfo = $self->{schema}->resultset('Profileinfo');

    return $profileinfo;
}

# sub get_profileinfo {
#     my $self        = shift;
#     my $profilename = shift;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $idnresult=$self->{dbh}->prepare("select * from profileinfo where profilename = ?") or $logger->error($DBI::errstr);
#     $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    
#     my $result=$idnresult->fetchrow_hashref();

#     my $profileinfo_ref = {    
#         profilename => decode_utf8($result->{'profilename'}),
#         description => decode_utf8($result->{'description'}),
#     };
    
#     return $profileinfo_ref;
# }

sub get_orgunitinfo_overview {
    my $self        = shift;
    my $profilename = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->get_orgunitinfo->search_rs(
        {
            'profileid.profilename' => $profilename,
        },
        {
            join     => 'profileid',
            order_by => 'nr',
        }
    );
    
    return $object;
}

sub get_orgunitinfo {
    my $self        = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $orgunitinfo = $self->{schema}->resultset('Orgunitinfo');
    
    return $orgunitinfo;
}

sub get_profiledbs {
    my $self        = shift;
    my $profilename = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @profiledbs=();

    foreach my $orgunit ($self->get_orgunitinfo_overview($profilename)->all){
        foreach my $item ($self->{schema}->resultset('OrgunitDb')->search_rs({ orgunitid => $orgunit->id },{ join => 'dbid', group_by => 'dbid.dbname', order_by => 'dbid.dbname' })->all){
            push @profiledbs, $item->dbid->dbname;
        }
    }
    return @profiledbs;
}

sub get_profilename_of_view {
    my $self        = shift;
    my $viewname    = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profilename = "";

    eval {
        $profilename = $self->{schema}->resultset('Viewinfo')->search({ viewname => $viewname })->single->profileid->profilename;
    };
    
    return $profilename;
}

sub get_orgunitdbs {
    my $self        = shift;
    my $profilename = shift;
    my $orgunitname = shift;    

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $orgunitid = $self->get_orgunitinfo->search_rs({ 'profileid.profilename' => $profilename, orgunitname => $orgunitname},{ join => 'profileid'})->single->id;
    
    my @orgunitdbs=();

    foreach my $item ($self->{schema}->resultset('OrgunitDb')->search_rs({ 'orgunitid' => $orgunitid },{ join => 'dbid', order_by => 'dbid.dbname' })->all){
        $logger->debug("Found");
        push @orgunitdbs, $item->dbid->dbname;
    }

    return @orgunitdbs;
}

sub get_viewinfo {
    my ($self,$viewname) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $viewinfo = $self->{schema}->resultset('Viewinfo');

    return $viewinfo;
}

sub get_viewdbs {
    my $self     = shift;
    my $viewname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select databaseinfo.dbname from view_db,databaseinfo,viewinfo where viewinfo.viewname = ? and viewinfo.id=view_db.viewid and view_db.dbid = databaseinfo.dbname and databaseinfo.active is true order by dbname"
    my $dbnames = $self->{schema}->resultset('Viewinfo')->search(
        {
            'me.viewname' => $viewname,
            'dbid.active' => 1,
        },
        {
            select   => 'dbid.dbname',
            as       => 'thisdbname',
            join     => [ 'view_dbs', { 'view_dbs' => 'dbid' } ],
            order_by => 'dbid.dbname',
            group_by => 'dbid.dbname',
        }
    );

    my @viewdbs=();

    foreach my $item ($dbnames->all){
        push @viewdbs, $item->get_column('thisdbname');
    }

    return @viewdbs;
}

sub get_active_databases {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select dbname from databaseinfo where active is true order by dbname ASC"
    my $dbnames = $self->{schema}->resultset('Databaseinfo')->search(
        {
            'active' => 1,
        },
        {
            select   => 'dbname',
            order_by => [ 'dbname ASC' ],
        }
    );
    
    my @dblist=();

    foreach my $item ($dbnames->all){
        push @dblist, $item->dbname;
    }
    
    return @dblist;
}

sub get_active_databases_of_systemprofile {
    my $self = shift;
    my $view = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profilename = $self->get_profilename_of_view($view);

    # DBI: "select databaseinfo.dbname as dbname from databaseinfo,viewinfo,orgunit_db where databaseinfo.active is true and databaseinfo.id=orgunit_db.dbid and orgunit_db.profileid=viewinfo.profileid and viewinfo.viewname = ? order by dbname ASC"
    my $dbnames = $self->{schema}->resultset('OrgunitDb')->search(
        {
            'dbid.active'           => 1,
            'profileid.profilename' => $profilename,
        }, 
        {
            select => 'dbid.dbname',
            as     => 'thisdbname',
            join => [ 'orgunitid', 'dbid',  ],
            prefetch => [ { 'orgunitid' => 'profileid' } ],
            order_by => 'dbid.dbname',
#            columns  => [ qw/dbid.dbname/ ], # columns/group_by -> versch. dbid.dbname 
#            group_by => [ qw/dbid.dbname/ ], # via group_by und nicht via distinct (Performance)
        }
    );

    my @dblist=();

    foreach my $item ($dbnames->all){
        push @dblist, $item->get_column('thisdbname');
    }

    return @dblist;
}

sub get_active_database_names {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->get_databaseinfo->search(
        {
            'active' => 1,
        },
        {
            order_by => 'dbname',
        }
    );
    
    return $object;
}

sub get_active_views {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select viewname from viewinfo where active is true order by description ASC"
    my $views = $self->{schema}->resultset('Viewinfo')->search(
        {
            'active' => 1,
        },
        {
            select   => 'viewname',
            order_by => [ 'description ASC' ],
        }
    );
    
    my @viewlist=();

    foreach my $item ($views->all){
        push @viewlist, $item->viewname;
    }

    return @viewlist;
}

sub get_active_databases_of_orgunit {
    my ($self,$profile,$orgunit) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select databaseinfo.dbname from databaseinfo,orgunit_db where databaseinfo.active is true and databaseinfo.id=orgunit_db.dbid and orgunit_db.orgunitid=orgunitinfo.id and orgunitinfo.profileid=profileinfo.id and profileinfo.profilename = ? and orgunitinfo.orgunitname = ? order by databaseinfo.description ASC"
    my $dbnames = $self->{schema}->resultset('OrgunitDb')->search(
        {
            'dbid.active'           => 1,
            'profileid.profilename' => $profile,
            'orgunitid.orgunitname' => $orgunit,
        }, 
        {
            select => 'dbid.dbname',
            as     => 'thisdbname',
            join => [ 'orgunitid', 'dbid',  ],
            prefetch => [ { 'orgunitid' => 'profileid' } ],
            order_by => 'dbid.description',
#            columns  => [ qw/dbid.dbname/ ], # columns/group_by -> versch. dbid.dbname 
#            group_by => [ qw/dbid.dbname/ ], # via group_by und nicht via distinct (Performance)
        }
    );

    my @dblist=();

    foreach my $item ($dbnames->all){
        push @dblist, $item->get_column('thisdbname');
    }

    return @dblist;
}

sub get_system_of_db {
    my ($self,$dbname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select system from databaseinfo where dbname = ?"
    my $system = $self->{schema}->resultset('Databaseinfo')->search(
        {
           dbname => $dbname,
        },
        {
            select => 'system',
        }
    )->first->system;

    return $system;
}

sub get_infomatrix_of_active_databases {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $checkeddb_ref     = exists $arg_ref->{checkeddb_ref}
        ? $arg_ref->{checkeddb_ref}     : undef;
    my $maxcolumn         = exists $arg_ref->{maxcolumn}
        ? $arg_ref->{maxcolumn}         : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $lastcategory="";
    my $count=0;

    my $profile = $self->get_profilename_of_view($view);
    
    $maxcolumn=(defined $maxcolumn)?$maxcolumn:$self->{databasechoice_maxcolumn};
    
    my $sqlrequest = "select * from databaseinfo where active is true order by description ASC";

    my @sqlargs = ();

    if ($view){
        $sqlrequest = "select databaseinfo.*,orgunitinfo.description as orgunitdescription, orgunitinfo.orgunitname from databaseinfo,orgunit_db,viewinfo,orgunitinfo,profileinfo where databaseinfo.active is true and databaseinfo.id=orgunit_db.dbid and orgunit_db.orgunitid=orgunitinfo.id and orgunitinfo.profileid=profileinfo.id and profileinfo.id=viewinfo.profileid and viewinfo.viewname = ? order by orgunitinfo.nr ASC, databaseinfo.description ASC";
        push @sqlargs, $view;
    }

    $logger->debug("View: $view - Profile: $profile - SQL-Request: $sqlrequest");
    
    my $idnresult=$self->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $idnresult->execute(@sqlargs) or $logger->error($DBI::errstr);

    my @catdb=();
    
    while (my $result=$idnresult->fetchrow_hashref) {
        my $category   = decode_utf8($result->{'orgunitdescription'});
        my $name       = decode_utf8($result->{'description'});
        my $systemtype = decode_utf8($result->{'system'});
        my $pool       = decode_utf8($result->{'dbname'});
        my $url        = decode_utf8($result->{'url'});
        my $sigel      = decode_utf8($result->{'sigel'});
        my $use_libinfo= decode_utf8($result->{'use_libinfo'});
	
        my $rcolumn;
        
        if ($category ne $lastcategory) {
            while ($count % $maxcolumn != 0) {
                $rcolumn=($count % $maxcolumn)+1;
                
                # 'Leereintrag erzeugen'
                push @catdb, { 
                    column     => $rcolumn, 
                    category   => $lastcategory,
                    db         => '',
                    name       => '',
                    systemtype => '',
                    sigel      => '',
                    url        => '',
                    use_libinfo=> '',
                };
                $count++;
            }
            $count=0;
        }
        
        $lastcategory=$category;
        
        $rcolumn=($count % $maxcolumn)+1;
        
        my $checked="";
        if (defined $checkeddb_ref->{$pool}) {
            $checked=$checkeddb_ref->{$pool};
        }
        
        push @catdb, { 
            column     => $rcolumn,
            category   => $category,
            db         => $pool,
            name       => $name,
            systemtype => $systemtype,
            sigel      => $sigel,
            url        => $url,
            use_libinfo=> $use_libinfo,
            checked    => $checked,
        };
        
        
        $count++;
    }

    while ($count % $maxcolumn != 0) {
        my $rcolumn=($count % $maxcolumn)+1;
        
        # 'Leereintrag erzeugen'
        push @catdb, { 
            column     => $rcolumn, 
            category   => $lastcategory,
            db         => '',
            name       => '',
            systemtype => '',
            sigel      => '',
            url        => '',
            use_libinfo=> '',
        };
        $count++;
    }

    return @catdb;
}

sub load_bk {
    my ($self) = @_;

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;

    return YAML::Syck::LoadFile("/opt/openbib/conf/bk.yml");
}

sub get_enrichmnt_object {
    my ($self) = @_;

    return OpenBib::Enrichment->instance;
}

sub get_ezb_object {
    my ($self) = @_;

    return OpenBib::EZB->new;
}

sub get_dbis_object {
    my ($self) = @_;

    return OpenBib::DBIS->new;
}

sub get_geoposition {
    my ($self,$address)=@_;

    my $ua = LWP::UserAgent->new;

    my $url = "http://maps.google.com/maps/geo?q=".uri_escape($address)."&output=csv&key=".$self->{google_maps_api_key};
        
    my $response = $ua->get($url)->decoded_content(charset => 'utf8');
    return $response;
}

sub get_serverinfo {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select * from loadbalancertargets order by host"
    my $object = $self->{schema}->resultset('Serverinfo');

    return $object;
}

sub get_active_loadbalancertargets {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select host from loadbalancertargets where active is true order by host"
    my $serverinfos = $self->{schema}->resultset('Serverinfo')->search(
        {
            active => 1,
        },
        {
            select => 'host',
            order_by => 'host',
        }
    );
    
    my $loadbalancertargets_ref = [];

    foreach my $item ($serverinfos->all){
        my $id            = $item->id;
        my $host          = $item->host;
        my $active        = $item->active;
        
        push @{$loadbalancertargets_ref}, {
            id     => $id,
            host   => $host,
            active => $active,
        };
    }

    my @activetargets = ();

    my $request=$self->{dbh}->prepare() or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    
    while (my $result=$request->fetchrow_hashref()){
        my $host          = decode_utf8($result->{'host'});
        
        push @activetargets, $host;
    }
    
    return @activetargets;
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        # Verbindung zur SQL-Datenbank herstellen
        $self->{dbh}
            = OpenBib::Database::DBI->connect("DBI:$self->{configdbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect to database $self->{configdbname}");
    }
    
    $self->{dbh}->{RaiseError} = 1;

    eval {        
#        $self->{schema} = OpenBib::Database::Config->connect("DBI:$self->{configdbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd}) or $logger->error_die($DBI::errstr)
        $self->{schema} = OpenBib::Database::Config->connect("DBI:$self->{configdbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);

    };

    if ($@){
        $logger->fatal("Unable to connect to database $self->{configdbname}");
    }

    return;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zu Memchached herstellen
    $self->{memc} = new Cache::Memcached($self->{memcached});

    if (!$self->{memc}->set('isalive',1)){
        $logger->fatal("Unable to connect to memcached");
    }

    return;
}

#### Manipulationen via WebAdmin

sub del_databaseinfo {
    my ($self,$dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        $self->{schema}->resultset('Databaseinfo')->search({ dbname => $dbname})->single->delete;
    };
    
    if ($@){
        $logger->fatal("Error deleting Record $@");
    }
    
    if ($self->get_system_of_db($dbname) ne "Z39.50"){
        # Und nun auch die Datenbank komplett loeschen
        system("$self->{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
    }

    $logger->debug("Database $dbname deleted");
    
    return;
}

sub update_databaseinfo {
    my ($self,$dbinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Databaseinfo')->search({ dbname => $dbinfo_ref->{dbname}})->single->update($dbinfo_ref);
    
    return;
}

sub new_databaseinfo {
    my ($self,$dbinfo_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Databaseinfo')->create($dbinfo_ref);
    
    if ($self->get_system_of_db($dbinfo_ref->{dbname}) ne "Z39.50"){
        # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
        system("$self->{tool_dir}/destroypool.pl $dbinfo_ref->{dbname} > /dev/null 2>&1");
        
        # ... und dann wieder anlegen
        system("$self->{tool_dir}/createpool.pl $dbinfo_ref->{dbname} > /dev/null 2>&1");
    }
    return;
}

sub update_databaseinfo_rss {
    my ($self,$rss_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Rssinfo')->search({ id => $rss_ref->{id}})->single->update($rss_ref);

    return;
}

sub new_databaseinfo_rss {
    my ($self,$rss_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Rssinfo')->create($rss_ref);

    return;
}

sub del_databaseinfo_rss {
    my ($self,$id)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Rssinfo')->search({ id => $id})->single->delete;

    return;
}

sub del_view {
    my ($self,$viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Viewinfo')->search({ viewname => $viewname})->single->delete;

    return;
}

sub update_libinfo {
    my ($self,$dbname,$libinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Libraryinfo')->search({ dbname => $dbname })->single->delete;

    my $category_contents_ref = [];
    foreach my $category (keys %$libinfo_ref){
        my ($category_num)=$category=~/^I(\d+)$/;

        push @$category_contents_ref, {
            dbname   => $dbname,
            category => $category_num,
            content  => $libinfo_ref->{$category},
        };
        
        $logger->debug("Changing Category $category_num to $libinfo_ref->{$category}");
    }
    
    $self->{schema}->resultset('Libraryinfo')->populate($category_contents_ref);
    
    return;
}

sub update_view {
    my ($self,$view_ref,$db_ref,$rss_ref) = @_;

    # Set defaults
    my $viewname               = exists $view_ref->{viewname}
        ? $view_ref->{viewname}            : undef;
    my $description            = exists $view_ref->{description}
        ? $view_ref->{description}         : undef;
    my $active                 = exists $view_ref->{active}
        ? $view_ref->{active}              : undef;
    my $primrssfeed            = exists $view_ref->{rssid}
        ? $view_ref->{primrssfeed}         : undef;
    my $start_loc              = exists $view_ref->{start_loc}
        ? $view_ref->{start_loc}           : undef;
    my $servername             = exists $view_ref->{servername}
        ? $view_ref->{servername}          : undef;
    my $profilename            = exists $view_ref->{profilename}
        ? $view_ref->{profilename}         : undef;
    my $joinindex              = exists $view_ref->{joinindex}
        ? $view_ref->{joinindex}           : undef;
    my $stripuri               = exists $view_ref->{stripuri}
        ? $view_ref->{stripuri}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    delete $view_ref->{viewname};
    
    my $viewid = $self->get_viewinfo->search_rs({ viewname => $viewname })->single()->id;

    # Zuerst die Aenderungen in der Tabelle Viewinfo vornehmen
    $self->{schema}->resultset('Viewinfo')->search_rs({ viewname => $viewname})->single->update($view_ref);
    
    # Datenbanken zunaechst loeschen
    $self->{schema}->resultset('ViewDb')->search_rs({ viewid => $viewid})->delete;

    if (@$db_ref){
        my $this_db_ref = [];
        foreach my $dbname (@$db_ref){
            my $dbid = $self->get_databaseinfo->search_rs({ dbname => $dbname })->single()->id;
                
            push @$this_db_ref, {
                viewid => $viewid,
                dbid   => $dbid,
            };
        }
        
        # Dann die zugehoerigen Datenbanken eintragen
        $self->{schema}->resultset('ViewDb')->populate($this_db_ref);
    }
    
    # RSS-Feeds zunaechst loeschen
    $self->{schema}->resultset('ViewRss')->search({ viewid => $viewid })->delete;

    if (@$rss_ref){
        my $this_rss_ref = [];
        
        foreach my $rssfeed (@$rss_ref){
            push @$this_rss_ref, {
                viewid => $viewid,
                rssid  => $rssfeed,
            };
        }
        
        # Dann die zugehoerigen Feeds eintragen
        $self->{schema}->resultset('ViewRss')->populate($this_rss_ref);
    }
    
    return;
}

sub strip_view_from_uri {
    my ($self,$viewname) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst die Aenderungen in der Tabelle Viewinfo vornehmen
    my $stripuri = $self->{schema}->resultset('Viewinfo')->search({ viewname => $viewname})->single->stripuri;

    $stripuri = ($stripuri == 1)?1:0;

    return $stripuri;
}

sub new_view {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $viewname               = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}            : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}         : undef;
    my $start_loc              = exists $arg_ref->{start_loc}
        ? $arg_ref->{start_loc}           : undef;
    my $servername             = exists $arg_ref->{stid_loc}
        ? $arg_ref->{servername}          : undef;
    my $stripuri               = exists $arg_ref->{stripuri}
        ? $arg_ref->{stripuri}            : undef;
    my $joinindex              = exists $arg_ref->{joinindex}
        ? $arg_ref->{joinindex}           : undef;
    my $active                 = exists $arg_ref->{active}
        ? $arg_ref->{active}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profileinfo_ref = $self->get_profileinfo->search_rs({ 'profilename' => $profilename })->single();
    
    $self->{schema}->resultset('Viewinfo')->create({
        profileid   => $profileinfo_ref->id,
        viewname    => $viewname,
        description => $description,
        start_loc   => $start_loc,
        servername  => $servername,
        stripuri    => $stripuri,
        joinindex   => $joinindex,
        active      => $active
    });

    return 1;
}

sub update_view_rss {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $viewname               = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname }           : undef;
    my $rsstype                = exists $arg_ref->{rsstype}
        ? $arg_ref->{rsstype }            : undef;
    my $rssid                  = exists $arg_ref->{rssid}
        ? $arg_ref->{rssid}               : undef;
    my $rssids_ref             = exists $arg_ref->{rssids}
        ? $arg_ref->{rssids}              : undef;

    my @rssids = (defined $rssids_ref)?@$rssids_ref:();

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($rsstype eq "primary"){
      my $request=$self->{dbh}->prepare("update viewinfo set rssfeed = ? where viewname = ?") or $logger->error($DBI::errstr);
      $request->execute($rssid,$viewname) or $logger->error($DBI::errstr);
      $request->finish();
    }
    elsif ($rsstype eq "all") {
      my $request=$self->{dbh}->prepare("delete from view_rss where viewname = ?");
      $request->execute($viewname);
      
      $request=$self->{dbh}->prepare("insert into view_rss values (?,?)") or $logger->error($DBI::errstr);
      foreach my $rssid (@rssids){
	$request->execute($viewname,$rssid) or $logger->error($DBI::errstr);
      }
      $request->finish();
    }
    
    return;
}

sub del_profile {
    my ($self,$profilename)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("delete from profileinfo where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);

    my $orgunits_ref=$self->get_orgunitinfo_overview($profilename);

    foreach my $thisorgunit ($orgunits_ref->all){
        $self->del_orgunit($profilename,$thisorgunit->orgunitname);
    }
    
    $idnresult->finish();

    return;
}

sub update_profile {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}         : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst die Aenderungen in der Tabelle Profileinfo vornehmen

    $self->{schema}->resultset('Profileinfo')->search({ profilename => $profilename })->single->update($arg_ref);

    return;
}

sub new_profile {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}            : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Profileinfo')->create($arg_ref);

    return 1;
}

sub del_orgunit {
    my ($self,$profilename,$orgunit)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("delete from orgunitinfo where profilename = ? and orgunitname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename,$orgunit) or $logger->error($DBI::errstr);
    $idnresult=$self->{dbh}->prepare("delete from orgunit_db where profilename = ? and orgunitname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename,$orgunit) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub update_orgunit {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}         : undef;
    my $orgunitname            = exists $arg_ref->{orgunitname}
        ? $arg_ref->{orgunitname}         : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $orgunitdb_ref          = exists $arg_ref->{orgunitdb}
        ? $arg_ref->{orgunitdb}           : [];
    my $nr                     = exists $arg_ref->{nr}
        ? $arg_ref->{nr}                  : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst die Aenderungen in der Tabelle Orgunit vornehmen

    my $profileinfo_ref = $self->get_profileinfo->search_rs({ 'profilename' => $profilename })->single();
    my $orgunitinfo_ref = $self->get_orgunitinfo->search_rs({ 'orgunitname' => $orgunitname, 'profileid' => $profileinfo_ref->id })->single();

    $orgunitinfo_ref->update({ description => $description, nr => $nr });
        
    # Datenbanken zunaechst loeschen
    $self->{schema}->resultset('OrgunitDb')->search_rs({ orgunitid => $orgunitinfo_ref->id})->delete;

    if (@$orgunitdb_ref){
        my $this_db_ref = [];
        foreach my $dbname (@$orgunitdb_ref){
            my $dbinfo_ref = $self->get_databaseinfo->search_rs({ 'dbname' => $dbname })->single();
            push @$this_db_ref, {
                orgunitid   => $orgunitinfo_ref->id,
                dbid      => $dbinfo_ref->id,
            };
        }
        
        # Dann die zugehoerigen Datenbanken eintragen
        $self->{schema}->resultset('OrgunitDb')->populate($this_db_ref);
    }

    
#     $idnresult=$self->{dbh}->prepare("delete from orgunit_db where profilename = ? and orgunitname = ?") or $logger->error($DBI::errstr);
#     $idnresult->execute($profilename,$orgunit) or $logger->error($DBI::errstr);
    
    
#     # Dann die zugehoerigen Datenbanken eintragen
#     foreach my $singleorgunitdb (@orgunitdb) {
#         $idnresult=$self->{dbh}->prepare("insert into orgunit_db values (?,?,?)") or $logger->error($DBI::errstr);
#         $idnresult->execute($profilename,$orgunit,$singleorgunitdb) or $logger->error($DBI::errstr);
#     }
    
#     $idnresult->finish();

    return;
}

sub new_orgunit {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}            : undef;
    my $orgunit                = exists $arg_ref->{orgunit}
        ? $arg_ref->{orgunit}                : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}            : undef;
    my $nr                     = exists $arg_ref->{nr}
        ? $arg_ref->{nr}                     : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profileinfo_ref = $self->get_profileinfo->search_rs({ 'profilename' => $profilename })->single();

    $self->{schema}->resultset('Orgunitinfo')->create({ profileid => $profileinfo_ref->id, orgunitname => $orgunit, description => $description, nr => $nr});

    return 1;
}

sub del_server {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("About to delete id $id");
    
    my $request=$self->{dbh}->prepare("delete from loadbalancertargets where id = ?") or $logger->error($DBI::errstr);
    $request->execute($id) or $logger->error($DBI::errstr);
    $request->finish();

    return;
}

sub update_server {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $active                   = exists $arg_ref->{active}
        ? $arg_ref->{active}              : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst die Aenderungen in der Tabelle Profileinfo vornehmen
    
    my $request=$self->{dbh}->prepare("update loadbalancertargets set active = ? where id = ?") or $logger->error($DBI::errstr);
    $request->execute($active,$id) or $logger->error($DBI::errstr);
    $request->finish();

    return;
}

sub new_server {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $host                   = exists $arg_ref->{host}
        ? $arg_ref->{host}                : undef;
    my $active                 = exists $arg_ref->{active}
        ? $arg_ref->{active}              : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (!$host){
        return -1;
    }
    
    my $idnresult=$self->{dbh}->prepare("select count(*) as rowcount from loadbalancertargets where host = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($host) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;
    my $rows=$res->{rowcount};
    
    if ($rows > 0) {
      $idnresult->finish();
      return -1;
    }
    
    $idnresult=$self->{dbh}->prepare("insert into loadbalancertargets (id,host,active) values (NULL,?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($host,$active) or $logger->error($DBI::errstr);
    
    return 1;
}

sub del_logintarget {
    my ($self,$targetid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $user = OpenBib::User->instance;

    $user->delete_logintarget($targetid);

    return;
}

sub update_logintarget {
    my ($self,$logintarget_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug(YAML::Dump($logintarget_ref));
    
    my $user = OpenBib::User->instance;

    $user->update_logintarget({
        targetid    => $logintarget_ref->{id},
        hostname    => $logintarget_ref->{hostname},
        port        => $logintarget_ref->{port},
        username    => $logintarget_ref->{username},
        dbname      => $logintarget_ref->{dbname},
        description => $logintarget_ref->{description},
        type        => $logintarget_ref->{type}
    });
    
    return;
}

sub new_logintarget {
    my ($self,$logintarget_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $user = OpenBib::User->instance;

    $user->new_logintarget({
        hostname    => $logintarget_ref->{hostname},
        port        => $logintarget_ref->{port},
        username    => $logintarget_ref->{username},
        dbname      => $logintarget_ref->{dbname},
        description => $logintarget_ref->{description},
        type        => $logintarget_ref->{type}
    });

    return;
}


1;
__END__

=head1 NAME

OpenBib::Config - Apache-Singleton mit Informationen über die allgemeine Portal-Konfiguration

=head1 DESCRIPTION

Dieses Apache-Singleton enthält Informationen über alle grundlegenden
Konfigurationseinstellungen des Portals. Diese werden in YAML-Datei
portal.yml definiert.  Darüber hinaus werden verschiedene Methoden
bereitgestellt, mit denen auf die Einstellungen in der
Konfigurations-Datenbank zugegriffen werden kann. Dort sind u.a. die
Kataloge, Sichten, Profile usw. definiert.

=head1 SYNOPSIS

 use OpenBib::Config;

 my $config = OpenBib::Config->instance;

 # Zugriff auf Konfigurationsvariable aus portal.yml
 my $servername = $config->get('servername'); # Zugriff über Accessor-Methode
 my $servername = $config->{'servername'};    # direkter Zugriff


=head1 METHODS

=over 4

=item new

Erzeugung als herkömmliches Objektes und nicht als
Apache-Singleton. Damit kann auch ausserhalb des Apache mit mod_perl
auf die Konfigurationseinstellungen in Perl-Skripten zugegriffen werden.

=item instance

Instanziierung als Apache-Singleton.

=item get($key)

Accessor für Konfigurationsinformationen des Servers aus portal.yml.

=back

=head2 Datenbanken

=over 4

=item get_number_of_dbs($profilename)

Liefert die Anzahl aktiver Datenbanken im Profil $profilename
zurück. Wird kein $profilename übergeben, so wird die Anzahl aller
aktiven Datenbanken zurückgeliefert.

=item get_number_of_all_dbs

Liefert die Anzahl aller vorhandenen eingerichteten Datenbanken -
aktiv oder nicht - zurück.

=item db_exists($dbname)

Liefert einen Wert ungleich Null zurück, wenn die Datenbank $dbname
existiert bzw. eingerichtet wurde - aktiv oder nicht.

=item get_dbinfo($dbname)

Liefert zu einer Datenbank $dbname eine Hashreferenz mit den
zugehörigen konfigurierten Informationen zurück. Es sind dies die
Organisationseinheit orgunit, die Beschreibung description, die
Kurzbeschreibung shortdesc, des (Bibliotheks-)Systems system, des
Datenbanknamens dbname, des Sigels sigel, des Weiterleitungs-URLs zu
etwaigen Kataloginformationen sowie der Information zurück, ob die
Datenbank aktiv ist (active) und anstelle von url lokale
Bibliotheksinformationen angezeigt werden sollen (use_libinfo).

=item get_dbinfo_overview

Liefert eine Listenreferenz auf Hashreferenzen mit Informationen über
alle Datenbanken zurück.  Es sind dies die Organisationseinheit
orgunit, die Beschreibung description, des (Bibliotheks-)Systems
system, des Datenbanknamens dbname, des Sigels sigel, des
Weiterleitungs-URLs zu etwaigen Kataloginformationen sowie der
Information zurück, ob die Datenbank aktiv ist (active) und anstelle
von url lokale Bibliotheksinformationen angezeigt werden sollen
(use_libinfo). Zusätzlich wird auch noch die Titelanzahl count sowie
die Informatione autoconvert zurückgegeben, ob der Katalog automatisch
aktualisiert werden soll.

=item get_libinfo($dbname)

Liefert eine Hashreferenz auf die allgemeinen Nutzungs-Informationen
(Öffnungszeigen, Adresse, usw.)  der zur Datenbank $dbname zugehörigen
Bibliothek. Zu jeder Kategorie category sind dies ein möglicher
Indikator indicator und der eigentliche Kategorieinhalt content.

=item have_libinfo($dbname)

Gibt zurück, ob zu der Datenbank $dbname lokale Nutzungs-Informationen
(Öffnungszeiten, Adresse, usw.) vorhanden sind.

=item get_dboptions($dbname)

Liefert eine Hashreferenz mit den grundlegenden Informatione für die
automatische Migration der Daten sowie der Kopplung zu den
zugrundeliegenden (Bibliotheks-)Systemen. Die Informationen sind host,
protocol, remotepath, remoteuser, remotepasswd, filename, titfilename,
autfilename, korfilename, swtfilename, notfilename, mexfilename,
autoconvert, circ, circurl, circcheckurl sowie circdb.

=item get_active_databases

Liefert eine Liste aller aktiven Datenbanken zurück.

=item get_active_database_names

Liefert eine Liste mit Hashreferenzen (Datenbankname dbname,
Beschreibung description) für alle aktiven Datenbanken zurück.

=item get_active_databases_of_orgunit($orgunit)

Liefert eine Liste aller aktiven Datenbanken zu einer
Organisationseinheit $orgunit zurück.

=item get_system_of_db($dbname)

Liefert das verwendete (Bibliotheks-)System einer Datenbank $dbname
zurück.

=item get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref, maxcolumn => $maxcolumn, view => $view })

Liefert eine Liste grundlegender Datenbankinformationen (orgunit, db,
name, systemtype, sigel, url) aller Datenbanke bzw. aller Datenbanken
eines Views $view mit zusätzlich generierten Indizes column für die
Aufbereitung in einer Tabelle mit $maxcolumn Spalten. Zusätzlich wird
entsprechend $checkeddb_ref die Information über eine Auswahl checked
der jeweiligen Datenbank mit übergeben.

=item get_infomatrix_of_all_databases({ profile => $profile, maxcolumn => $maxcolumn })

Liefert eine Liste grundlegender Datenbankinformationen (orgunit, db,
name, systemtype, sigel, url) aller Datenbanke mit zusätzlich
generierten Indizes column für die Aufbereitung in einer Tabelle mit
$maxcolumn Spalten. Zusätzlich wird entsprechend der Zugehörigkeit
einer Datenbank zum Profil $profile die Vorauswahl checked der
jeweiligen Datenbank gesetzt.

=back

=head2 Views

=over 4

=item get_number_of_views

Liefert die Anzahl aktiven Views zurück.

=item get_number_of_all_views

Liefert die Anzahl aller vorhandenen eingerichteten Views -
aktiv oder nicht - zurück.

=item get_viewdesc_from_viewname($viewname)

Liefert die Beschreibung des Views $viewname zurück.

=item get_startpage_of_view($viewname)

Liefert das Paar start_loc und start_id zu einem Viewname
zurück. Dadurch kann beim Aufruf eines einem View direkt zu einer
anderen Seite als der Eingabemaske gesprungen werden. Mögliche
Parameter sind die in portal.yml definierte Location *_loc und eine
Sub-Template-Id. Weitere Parameter sind nicht möglich. Typischerweise
wird zu einer allgemeinen Informationsseite via info_loc gesprungen,
in der allgemeine Informationen z.B. zum Projekt als allgemeine
Startseite hinterlegt sind.

=item view_exists($viewname)

Liefert einen Wert ungleich Null zurück, wenn der View $viewname
existiert bzw. eingerichtet wurde - aktiv oder nicht.

=item get_dbs_of_view($viewname)

Liefert die Liste der Namen aller im View $viewname vorausgewählter
aktiven Datenbanken sortiert nach Organisationseinheit und
Datenbankbeschreibung zurück.

=item get_viewinfo_overview

Liefert eine Listenreferenz mit einer Übersicht aller Views
zurück. Neben dem Namen $viewname, der Beschreibung description, des
zugehörigen Profils profile sowie der Aktivität active gehört dazu
auch eine Liste aller zugeordneten Datenbanken viewdb.

=item get_viewinfo($viewname)

Liefert zu einem View $viewname eine Hashreferenz mit allen
konfigurierten Informationen zu diesem View zurück. Es sind dies der
Viewname viewname, seine Beschreibung description, der primäre
RSS-Feed primrssfeed, etwaige alternative Startseiten
start_loc/servername, den zugeordneten Profilnamen profilename sowie
der Aktivität active.

=item get_viewdbs($viewname)

Liefert zu einem View $viewname eine Liste aller zugehörigen
Datenbanken, sortiert nach Datenbanknamen zurück.

=item get_active_views

Liefert eine Liste aller aktiven Views zurück.

=back


=head2 Systemseitige Katalogprofile

=over 4

=item get_number_of_dbs($profilename)

Liefert die Anzahl aktiver Datenbanken im Profil $profilename
zurück. Wird kein $profilename übergeben, so wird die Anzahl aller
aktiven Datenbanken zurückgeliefert.

=item get_profileinfo_overview

Liefert eine Listenreferenz mit einer Übersicht aller systemweiten Katalogprofile
zurück. Neben dem Namen profilename, der Beschreibung description gehört dazu
auch eine Liste aller zugeordneten Datenbanken profiledb.

=item get_profileinfo($profilename)

Liefert zu einem Profil $profilename eine Hashreferenz mit dem
Profilnamen profilename sowie dessen Beschreibung description zurück.

=item get_profiledbs($profilename)

Liefert zu einem Profil $profilename eine Liste aller zugeordneten
Datenbanken sortiert nach den Datenbanknamen zurück.

=item get_active_databases_of_systemprofile($viewname)

Liefert zu einem View $viewname eine Liste aller Datenbanken, die im
zugehörigen systemseitigen Profil definiert sind.

=back

=head2 RSS

=over 4

=item valid_rsscache_entry({ database => $database, type => $type, subtype => $subtype, expiretimedate => $expiretimedate })

Liefert einen zwischengespeicherten RSS-Feed für die Datenbank
$database des Typs $type und Untertyps $subtype zurück, falls dieser
neuer als $expiretimedate ist.

=item get_rssfeeds_of_view($viewname)

Liefert für einen View $viewname einen Hash mit allen RSS-Feeds
zurück, die für diesen View konfiguriert wurden.

=item get_rssfeed_overview

Liefert eine Listenreferenz zurück mit allen Informationen über
vorhandene RSS-Feeds. Es sind dies die ID feedid, der zugehörige
Datenbankname dbname, die Spezifizierung der Feed-Art mit type und
subtype, sowie eine Beschreibung subtypedesc.

=item get_rssfeeds_of_db($dbname)

Liefert alle Feeds zu einer Datenbank $dbname sortiert nach type und
subtype in einer Listenreferenz zurück. Jeder Eintrag der Liste
besteht aus Feed-ID id, der Spezifikation des Typs mit type und
subtype nebst Beschreibung subtypedesc sowie der Information active,
ob der Feed überhaupt aktiv ist.

=item get_rssfeeds_of_db_by_type($dbname)

Liefert zu einer Datenbank $dbname eine Hashreferenz zurück, in der zu
jedem Type type eine Listenreferenz mit vorhandenen Informationen
subtype, subtypedesc sowie der Aktivität active existiert.

=item get_primary_rssfeed_of_view($viewname)

Liefert zu einem View $viewname den URL des definierten primären Feed
zurück.

=item get_activefeeds_of_db($dbname)

Liefert zu einer Datenbank $dbname eine Hashreferenz zurück, in der
alle aktiven Typen type eingetragen wurden.

=item get_rssfeedinfo({ view => $viewname })

Liefert zu einem View $viewname eine Hashreferenz zurück, in der zu
jeder Organisationseinheit orgunit eine Listenreferenz mit
Informationen über den Datenbankname pool, der Datenbankbeschreibung
pooldesc sowie des Typs (type) neuzugang. Wird kein View übergeben, so
werden diese Informationen für alle Datenbanken bestimmt.

=item update_rsscache({ database => $database, type => $type, subtype => $subtype, rssfeed => $rssfeed })

Speichert den Inhalt $rssfeed des Feeds einer Datenbank $database,
spezifiziert durch $type und $subtype in einem Cache zwischen. Auf
diesen Inhalt kann dann später effizient mit get_valid_rsscache_entry
zugegriffen werden.

=back

=head2 Lastverteilung

=over 4

=item get_loadbalancertargets

Liefert eine Listenreferenz mit Informationen zu allen konfigurierten
Servern, die für eine Lastverteilung definiert wurden. Diese
Informationen in einer Hashreferenz umfassen die interne ID id, den
Servernamen host sowie ob dieser Server aktiv ist oder nicht (active).

=item get_active_loadbalancertargets

Liefert eine Liste der Namen aller aktivierten Server für eine
Lastverteilung zurück.

=back

=head2 Verschiedenes

=over 4

=item get_number_of_titles({ database => $database, view => $view, profile => $profile })

Liefert entsprechend eines übergebenen Parameters die entsprechende
Gesamtzahl aller Titel der aktiven Datenbank $database, der
ausgewählten aktiven Datenbanken eines Views $view oder aller aktiven
vorhandenen Datenbanken in einem Datenbank-Profil $profile
zurück. Wenn kein Parameter übergeben wird, dann erhält man die
Gesamtzahl aller eingerichteten aktiven Datenbanken.

=item load_bk

Lädt die Basisklassifikation (BK) aus bk.yml und liefert eine
Hashreferenz auf diese Informationen zurück.  Auf diese kann dadurch
speziell in Templates zugegriffen werden.

=item get_enrichmnt_object

Liefert eine Instanz des Anreicherungs-Objectes OpenBib::Enrichment
zurück. Auf dieses kann dadurch speziell in Templates zugegriffen
werden.

=item get_ezb_object

Liefert eine Instanz des EZB-Objectes OpenBib::EZB zurück. Auf dieses
kann dadurch speziell in Templates zugegriffen werden.

=item get_dbis_object

Liefert eine Instanz des DBIS-Objectes OpenBib::DBIS zurück. Auf dieses
kann dadurch speziell in Templates zugegriffen werden.

=item get_geoposition($address)

Liefert zu einer Adresse die Geo-Position via Google-Maps zurück.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=head1 SEE ALSO

[[OpenBib::Config::DatabaseInfoTable]], [[OpenBib::Config::CirculationInfoTable]]

=cut
