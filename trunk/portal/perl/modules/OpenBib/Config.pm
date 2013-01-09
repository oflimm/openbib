#####################################################################
#
#  OpenBib::Config
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use LWP;
use URI::Escape qw(uri_escape);
use YAML::Syck;

use OpenBib::Schema::DBI;
use OpenBib::Schema::System;

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

    my $alldbs;

    if ($self->{memc}){
      $alldbs = $self->{memc}->get($memc_key);
      return $alldbs if ($alldbs);
    }

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

    $logger->debug("Parameters: Database = $database / View = $view / Profile = $profile");
    
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
                join     => [ 'orgunitid', 'dbid', { 'orgunitid' => 'profileid' } ],
                select   => [ {'sum' => 'dbid.allcount'}, {'sum' => 'dbid.journalcount'}, {'sum' => 'dbid.articlecount'}, {'sum' => 'dbid.digitalcount'}],
                as       => ['allcount', 'journalcount', 'articlecount', 'digitalcount'],
                group_by => ['orgunitid.id'],
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

    if ($counts){
        my $alltitles_ref = {   
            allcount     => $counts->get_column('allcount'),
            journalcount => $counts->get_column('journalcount'),
            articlecount => $counts->get_column('articlecount'),
            digitalcount => $counts->get_column('digitalcount'),
        };
        
        return $alltitles_ref;
    };

    return {
        allcount     => 0,
        journalcount => 0,
        articlecount => 0,
        digitalcount => 0,
    };
}

sub get_viewdesc_from_viewname {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select description from viewinfo where viewname = ?"
    my $desc = $self->{schema}->resultset('Viewinfo')->single({ viewname => $viewname})->description;
    
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

sub location_exists {
    my $self       = shift;
    my $identifier = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(dbname) as rowcount from databaseinfo where dbname = ?"
    my $count = $self->{schema}->resultset('Locationinfo')->search({ identifier => $identifier})->count;
    
    return $count;
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
    my $rss_content = $self->{schema}->resultset('Rssinfo')->search_rs(
        {
            'dbid.dbname'  => $database,
            'type'         => $type,
            'subtype'      => $subtype,
            'cache_tstamp' => { '>' => $expiretimedate },
        },
        {
            select => ['cache_content'],
            as     => ['thiscache_content'],
            join   => 'dbid',
        }
    )->single;

    my $rss;
    if ($rss_content){
        $rss = $rss_content->get_column('thiscache_content');
    }
    return $rss;
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

sub get_locationinfo_of_database {
    my $self   = shift;
    my $dbname = shift;

    my $databaseinfo = $self->{schema}->resultset('Databaseinfo')->single(
        {
            'dbname' => $dbname,
        },
    );

    if ($databaseinfo && $databaseinfo->locationid){
        return $self->get_locationinfo_fields($databaseinfo->locationid->identifier);
    }

    return {};
}

sub get_locationinfo {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->{schema}->resultset('Locationinfo');
    
    return $object;
}

sub get_locationinfo_fields {
    my $self        = shift;
    my $locationid  = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return {} if (!$locationid);

    # DBI: "select category,content,indicator from libraryinfo where dbname = ?"
    my $locationinfo = $self->get_locationinfo->single(
        {
            'identifier' => $locationid,
        },
    );

    my $locationinfo_ref= {};

    foreach my $item ($locationinfo->locationinfo_fields->all){
        my $field    = "L".sprintf "%04d",$item->field;
        my $subfield =                    $item->subfield || '';
        my $mult     =                    $item->mult     || 1;
        my $content  =                    $item->content;

        next if ($content=~/^\s*$/);

        push @{$locationinfo_ref->{$field}}, {
            mult     => $mult,
            subfield => $subfield,
            content  => $content,
        };
    }

    return $locationinfo_ref;
}

sub get_locationinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $locations = $self->get_locationinfo->search_rs(
        undef,
        {
            order_by => 'identifier',
        }
    );

    my $locations_ref = [];

    foreach my $location ($locations->all){
        my $thislocation_ref = {
            id          => $location->id,
            identifier  => $location->identifier,
            description => $location->description,
            type        => $location->type,
            fields      => $self->get_locationinfo_fields($location->identifier),
            
        };
        
        push @$locations_ref, $thislocation_ref;
    }
    
    return $locations_ref;
}

sub have_locationinfo {
    my $self   = shift;
    my $dbname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return 0 if (!$dbname);
    
    # DBI: "select count(dbid) as infocount from libraryinfo,databaseinfo where libraryinfo.dbid=databaseinfo.id and databaseinfo.dbname = ? and content != ''"
    my $haveinfos = $self->{schema}->resultset('Databaseinfo')->search(
        {
            'dbname'     => $dbname,
            'locationid' => { '>' => 0 },
        },
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


sub get_orgunitname_of_db_in_view {
    my ($self,$dbname,$viewname) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $orgunitinfo = $self->get_orgunitinfo->search_rs(
        {
            'viewinfos.viewname' => $viewname,
            'dbid.dbname'        => $dbname,
            
        },
        {
            select => ['me.orgunitname'],
            as     => ['thisname'],
            join => ['profileid',{'profileid' => 'viewinfos'},'orgunit_dbs',{'orgunit_dbs' => 'dbid'}],
        }
    )->first;

    if ($orgunitinfo){
        return $orgunitinfo->get_column('thisname');
    }
    
    return -1;
}

sub get_profiledbs {
    my $self        = shift;
    my $profilename = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @profiledbs=();
    my %profiledbs_done = ();
    foreach my $orgunit ($self->get_orgunitinfo_overview($profilename)->all){
        $logger->debug("Getting DBs for Orgunit ".$orgunit->orgunitname);
        foreach my $item ($orgunit->orgunit_dbs->all){
            my $dbname      = $item->dbid->dbname;

            $logger->debug("Getting DB $dbname");

            push @profiledbs, $dbname unless ($profiledbs_done{$dbname});
            $profiledbs_done{$dbname} = 1;
        }
    }

    $logger->debug("Profile $profilename: ".YAML::Dump(\@profiledbs));
    return @profiledbs;
}

sub get_profilename_of_view {
    my $self        = shift;
    my $viewname    = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profilename = "";

    eval {
        $profilename = $self->{schema}->resultset('Viewinfo')->single({ viewname => $viewname })->profileid->profilename;
    };

    $logger->debug("Got system profilename $profilename");
    
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
            select => ['system'],
        }
    )->first;

    return ($system)?$system->system:'';
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

    my $dbinfos;

    if ($view){
        # DBI: "select databaseinfo.*,orgunitinfo.description as orgunitdescription, orgunitinfo.orgunitname from databaseinfo,orgunit_db,viewinfo,orgunitinfo,profileinfo where databaseinfo.active is true and databaseinfo.id=orgunit_db.dbid and orgunit_db.orgunitid=orgunitinfo.id and orgunitinfo.profileid=profileinfo.id and profileinfo.id=viewinfo.profileid and viewinfo.viewname = ? order by orgunitinfo.nr ASC, databaseinfo.description ASC"
        $dbinfos = $self->{schema}->resultset('Viewinfo')->search(
            {
                'me.viewname' => $view,
                'dbid.active' => 1,
            },
            {
                join   => [ 'profileid', { 'profileid' => { 'orgunitinfos' => { 'orgunit_dbs' => 'dbid' }}} ],
                select => [ 'orgunitinfos.description', 'dbid.description', 'dbid.system', 'dbid.dbname', 'dbid.url', 'dbid.sigel', 'dbid.locationid' ],
                as     => [ 'thisorgunitdescription', 'thisdescription', 'thissystem', 'thisdbname', 'thisurl', 'thissigel', 'thislocationid' ],
                order_by => [ 'orgunitid ASC', 'dbid.description ASC' ],
            }
        );
    }
    else {
        # DBI: "select * from databaseinfo where active is true order by description ASC"
        $dbinfos = $self->{schema}->resultset('Databaseinfo')->search(
            {
                active => 1,
            },
            {
                select => [ 'description', 'system', 'dbname', 'url', 'sigel', 'locationid' ],
                as     => [ 'thisdescription', 'thissystem', 'thisdbname', 'thisurl', 'thissigel', 'thislocationid' ],
                order_by => [ 'description ASC' ],
            }
        );

    }

    my @catdb=();

    foreach my $item ($dbinfos->all){
        my $category   = decode_utf8($item->get_column('thisorgunitdescription'));
        my $name       = decode_utf8($item->get_column('thisdescription'));
        my $systemtype = decode_utf8($item->get_column('thissystem'));
        my $pool       = decode_utf8($item->get_column('thisdbname'));
        my $url        = decode_utf8($item->get_column('thisurl'));
        my $sigel      = decode_utf8($item->get_column('thissigel'));
        my $locationid = decode_utf8($item->get_column('thislocationid'));
	
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
                    locationid => '',
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
            locationid => $locationid,
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
            locationid => '',
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

sub load_lcc {
    my ($self) = @_;

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;

    return YAML::Syck::LoadFile("/opt/openbib/conf/lcc.yml");
}

sub get_geoposition {
    my ($self,$address)=@_;

    my $ua = LWP::UserAgent->new;

    my $url = "http://maps.google.com/maps/geo?q=".uri_escape($address)."&output=csv&key=".$self->{google_maps_api_key};
        
    my $response = $ua->get($url)->decoded_content(charset => 'utf8');
    return $response;
}

sub get_serverinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->get_serverinfo->search(
        undef,
        {
            order_by => 'hostip',
        }
    );
    
    return $object;
}

sub get_serverinfo {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select * from loadbalancertargets order by host"
    my $object = $self->{schema}->resultset('Serverinfo');

    return $object;
}

sub get_clusterinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->get_clusterinfo->search(
        undef,
        {
            order_by => 'id',
        }
    );
    
    return $object;
}

sub get_clusterinfo {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $object = $self->{schema}->resultset('Clusterinfo');

    return $object;
}

sub update_local_clusterstatus {
    my ($self,$status) = @_;

    my $local_cluster = $self->get_clusterinfo->search_rs(
	{
	    'serverinfos.hostip' => $self->{local_ip},
	},
	{
	    join => ['serverinfos'],
	}
    )->single;

    if ($local_cluster){
        $local_cluster->update({ status => $status });
        $local_cluster->serverinfos->update({ status => $status });
    }

    return;
}

sub update_local_serverstatus {
    my ($self,$status) = @_;

    $self->get_serverinfo->search_rs(
	{
	    hostip => $self->{local_ip},
	},
	)->update({ status => $status });

    return;
}

sub local_server_belongs_to_updatable_cluster {
    my ($self) = @_;

    my $is_updatable = $self->get_clusterinfo->search_rs(
	{
	    'me.status'          => { '!=' => 'searchable'},
	    'serverinfos.status' => { '!=' => 'searchable'},
	    'serverinfos.hostip' => $self->{local_ip},
	},
	{
	    join => ['serverinfos'],
	}
	)->count;

    return $is_updatable;
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # UTF8: {'pg_enable_utf8'    => 1}
    eval {        
        $self->{schema} = OpenBib::Schema::System->connect("DBI:Pg:dbname=$self->{systemdbname};host=$self->{systemdbhost};port=$self->{systemdbport}", $self->{systemdbuser}, $self->{systemdbpasswd},{'pg_enable_utf8'    => 1}) or $logger->error_die($DBI::errstr);
        
    };
    
    if ($@){
        $logger->fatal("Unable to connect to database $self->{systemdbname}");
    }
    
    return;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (!exists $self->{memcached}){
      $logger->debug("No memcached configured");
      return;
    }

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
        my $databaseinfo =  $self->{schema}->resultset('Databaseinfo')->single({ dbname => $dbname});

        if ($databaseinfo){
            $databaseinfo->libraryinfos->delete;
            $databaseinfo->orgunit_dbs->delete;
            $databaseinfo->searchprofile_dbs->delete;
            $databaseinfo->view_dbs->delete;
            $databaseinfo->delete
        }
    };
    
    if ($@){
        $logger->fatal("Error deleting Record $@");
    }

    # SQL-Datenbank, Suchmaschinenindex etc. werden per Cron auf allen
    # Servern geloescht

    $logger->debug("Database $dbname deleted");
    
    return;
}

sub update_databaseinfo {
    my ($self,$dbinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Databaseinfo')->single({ dbname => $dbinfo_ref->{dbname}})->update($dbinfo_ref);
    
    return;
}

sub new_databaseinfo {
    my ($self,$dbinfo_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $new_database = $self->{schema}->resultset('Databaseinfo')->create($dbinfo_ref);

    if ($self->get_system_of_db($dbinfo_ref->{dbname}) ne "Z39.50"){
        # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
        system("$self->{tool_dir}/destroypool.pl $dbinfo_ref->{dbname} > /dev/null 2>&1");
        
        # ... und dann wieder anlegen
        system("$self->{tool_dir}/createpool.pl $dbinfo_ref->{dbname} > /dev/null 2>&1");
    }

    if ($new_database){
        return $new_database->id;
    }

    return;
}

sub update_databaseinfo_rss {
    my ($self,$rss_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Rssinfo')->single({ id => $rss_ref->{id}})->update($rss_ref);

    return;
}

sub new_databaseinfo_rss {
    my ($self,$rss_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $new_rss = $self->{schema}->resultset('Rssinfo')->create($rss_ref);

    if ($new_rss){
        return $new_rss->id;
    }

    return;
}

sub del_databaseinfo_rss {
    my ($self,$id)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Rssinfo')->single({ id => $id})->delete;

    return;
}

sub del_view {
    my ($self,$viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Viewinfo')->single({ viewname => $viewname})->delete;

    return;
}

sub new_locationinfo {
    my ($self,$locationinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $create_args = {};

    if ($locationinfo_ref->{identifier}){
        $create_args->{identifier} = $locationinfo_ref->{identifier};
    }
    if ($locationinfo_ref->{type}){
        $create_args->{type} = $locationinfo_ref->{type};
    }
    if ($locationinfo_ref->{description}){
        $create_args->{description} = $locationinfo_ref->{description};
    }

    my $new_location = $self->{schema}->resultset('Locationinfo')->create($create_args);

    if (defined $locationinfo_ref->{field}){
        my $create_fields_ref = [];
        
        foreach my $field_ref (@$locationinfo_ref->{field}){
            my $thisfield = {
                locationid => $new_location->id,
                field      => $field_ref->{field},
                subfield   => $field_ref->{subfield},
                content    => $field_ref->{content},
            };

            push @$create_fields_ref, $thisfield;
        }

        if (@$create_fields_ref){
            $self->{schema}->resultset('LocationinfoField')->populare($create_fields_ref);
        }

    }
    
    if ($new_location){
        return $new_location->id;
    }
    
    return;
}

sub update_locationinfo {
    my ($self,$locationinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug(YAML::Dump($locationinfo_ref));

    my $update_args = {};

    if ($locationinfo_ref->{type}){
        $update_args->{type} = $locationinfo_ref->{type};
    }
    if ($locationinfo_ref->{description}){
        $update_args->{description} = $locationinfo_ref->{description};
    }

    my $locationinfo = $self->{schema}->resultset('Locationinfo')->single({ identifier => $locationinfo_ref->{identifier} });

    $locationinfo->update($update_args);
    
    eval {
        $locationinfo->locationinfo_fields->delete;
    };

    if ($@){
        $logger->error("Can't delete Fields: ".$@);
    }
    
    if (defined $locationinfo_ref->{fields}){
        my $update_fields_ref = [];
        
        foreach my $field (keys %{$locationinfo_ref->{fields}}){
            foreach my $field_ref (@{$locationinfo_ref->{fields}{$field}}){
                my $thisfield = {
                    locationid => $locationinfo->id,
                    field      => $field,
                    subfield   => $field_ref->{subfield},
                    mult       => $field_ref->{mult},
                    content    => $field_ref->{content},
                };
                
                push @$update_fields_ref, $thisfield;
            }
        }
        
        if (@$update_fields_ref){
            $self->{schema}->resultset('LocationinfoField')->populate($update_fields_ref);
        }
    }
    
    return;
}

sub delete_locationinfo {
    my ($self,$locationid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $locationinfo = $self->{schema}->resultset('Locationinfo')->single({ identifier => $locationid });

    eval {
        $locationinfo->databaseinfos->update({ locationid => \'NULL' });
        $locationinfo->locationinfo_fields->delete;
        $locationinfo->delete;
    };

    if ($@){
        $logger->error("Can't delete locationinfo: ".$@);
    }
    
    return;
}

sub update_view {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $viewname               = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}            : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $active                 = exists $arg_ref->{active}
        ? $arg_ref->{active}              : undef;
    my $primrssfeed            = exists $arg_ref->{rssid}
        ? $arg_ref->{primrssfeed}         : undef;
    my $start_loc              = exists $arg_ref->{start_loc}
        ? $arg_ref->{start_loc}           : undef;
    my $servername             = exists $arg_ref->{servername}
        ? $arg_ref->{servername}          : undef;
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}         : undef;
    my $stripuri               = exists $arg_ref->{stripuri}
        ? $arg_ref->{stripuri}            : undef;

    my $databases_ref          = exists $arg_ref->{databases}
        ? $arg_ref->{databases}           : [];

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profileinfo_ref = $self->get_profileinfo->single({ 'profilename' => $profilename });
    
    my $viewid = $self->get_viewinfo->single({ viewname => $viewname })->id;

    # Zuerst die Aenderungen in der Tabelle Viewinfo vornehmen
    $self->{schema}->resultset('Viewinfo')->single({ viewname => $viewname})->update(
        {
            profileid   => $profileinfo_ref->id,
            viewname    => $viewname,
            description => $description,
            start_loc   => $start_loc,
            servername  => $servername,
            stripuri    => $stripuri,
            active      => $active
        }
    );
    
    # Datenbanken zunaechst loeschen
    $self->{schema}->resultset('ViewDb')->search_rs({ viewid => $viewid})->delete;

    if (@$databases_ref){
        my $this_db_ref = [];
        foreach my $dbname (@$databases_ref){
            my $dbid = $self->get_databaseinfo->single({ dbname => $dbname })->id;
                
            push @$this_db_ref, {
                viewid => $viewid,
                dbid   => $dbid,
            };
        }
        
        # Dann die zugehoerigen Datenbanken eintragen
        $self->{schema}->resultset('ViewDb')->populate($this_db_ref);
    }
        
    return;
}

sub update_view_rss {
    my ($self,$viewname,$arg_ref) = @_;

    my $rssfeeds_ref           = exists $arg_ref->{rssfeeds}
        ? $arg_ref->{rssfeeds}            : [];
    my $primrssfeed            = exists $arg_ref->{primrssfeed}
        ? $arg_ref->{primrssfeed}         : undef;

    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $viewid = $self->get_viewinfo->single({ viewname => $viewname })->id;

    # Zuerst die Aenderungen des primaeren RSS-Feeds in der Tabelle Viewinfo vornehmen
    $self->{schema}->resultset('Viewinfo')->single({ viewname => $viewname})->update({ rssid => $primrssfeed });
    
    # RSS-Feeds zunaechst loeschen
    $self->{schema}->resultset('ViewRss')->search({ viewid => $viewid })->delete;

    if (@$rssfeeds_ref){
        my $this_rss_ref = [];
        
        foreach my $rssfeed (@$rssfeeds_ref){
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
    my $stripuri_rs = $self->{schema}->resultset('Viewinfo')->single({ viewname => $viewname});

    my $stripuri = 0;

    if ($stripuri_rs){
       $stripuri = $stripuri_rs->stripuri;
    }

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
    my $active                 = exists $arg_ref->{active}
        ? $arg_ref->{active}              : undef;

    my $databases_ref          = exists $arg_ref->{databases}
        ? $arg_ref->{databases}           : [];

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Argumente".YAML::Dump($arg_ref));
    
    my $profileinfo_ref = $self->get_profileinfo->single({ 'profilename' => $profilename });
    
    my $new_view = $self->{schema}->resultset('Viewinfo')->create(
        {
            profileid   => $profileinfo_ref->id,
            viewname    => $viewname,
            description => $description,
            start_loc   => $start_loc,
            servername  => $servername,
            stripuri    => $stripuri,
            active      => $active
        }
    );

    my $viewid = $new_view->id;
    
    # Datenbanken zunaechst loeschen
    $self->{schema}->resultset('ViewDb')->search_rs({ viewid => $viewid})->delete;

    my @profiledbs = $self->get_profiledbs($profilename);

    my $profile_lookup_ref = {};

    foreach my $profiledb (@profiledbs){
        $profile_lookup_ref->{$profiledb} = 1;
    }

    $logger->debug("Valide Kataloge".YAML::Dump($profile_lookup_ref));
    
    if (@$databases_ref){
        my $this_db_ref = [];
        foreach my $dbname (@$databases_ref){
            next unless ($profile_lookup_ref->{$dbname} == 1);
            
            my $dbid = $self->get_databaseinfo->single({ dbname => $dbname })->id;
                
            push @$this_db_ref, {
                viewid => $viewid,
                dbid   => $dbid,
            };
        }
        
        # Dann die zugehoerigen Datenbanken eintragen
        $self->{schema}->resultset('ViewDb')->populate($this_db_ref);
    }

    if ($viewid){
        return $viewid;
    }
    
    return;
}

sub del_profile {
    my ($self,$profilename)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "delete from profileinfo where profilename = ?"
    $self->{schema}->resultset('Profileinfo')->single(
        {
            profilename => $profilename,
        }
    )->delete;
    
    my $orgunits_ref=$self->get_orgunitinfo_overview($profilename);

    foreach my $thisorgunit ($orgunits_ref->all){
        $self->del_orgunit($profilename,$thisorgunit->orgunitname);
    }

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

    $self->{schema}->resultset('Profileinfo')->single({ profilename => $profilename })->update($arg_ref);

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

    my $new_profile = $self->{schema}->resultset('Profileinfo')->create($arg_ref);

    if ($new_profile){
        return $new_profile->id;
    }

    return;
}

sub del_orgunit {
    my ($self,$profilename,$orgunitname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "delete from orgunit_db where profilename = ? and orgunitname = ?"
    eval {
        my $orgunitinfo = $self->{schema}->resultset('Orgunitinfo')->search_rs(
            {
                'me.orgunitname' => $orgunitname,
                'profileid.profilename' => $profilename,
            },
            {
                join => 'profileid',
            }
        )->single;

        if ($orgunitinfo){
            $orgunitinfo->orgunit_dbs->delete;
            $orgunitinfo->delete
        }
    };

    if ($@){
        $logger->error("Can't delete $profilename -> $orgunitname: ".$@);
    }

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
    my $databases_ref          = exists $arg_ref->{databases}
        ? $arg_ref->{databases}           : [];
    my $nr                     = exists $arg_ref->{nr}
        ? $arg_ref->{nr}                  : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst die Aenderungen in der Tabelle Orgunit vornehmen

    my $profileinfo_ref = $self->get_profileinfo->single({ 'profilename' => $profilename });
    my $orgunitinfo_ref = $self->get_orgunitinfo->search_rs({ 'orgunitname' => $orgunitname, 'profileid' => $profileinfo_ref->id })->single();

    $orgunitinfo_ref->update({ description => $description, nr => $nr });

    # DBI: "delete from orgunit_db where profilename = ? and orgunitname = ?"
    # Datenbanken zunaechst loeschen
    $self->{schema}->resultset('OrgunitDb')->search_rs({ orgunitid => $orgunitinfo_ref->id})->delete;

    # DBI: "insert into orgunit_db values (?,?,?)"
    if (@$databases_ref){

        $logger->debug("Datenbanken ".YAML::Dump($databases_ref));

        my $this_db_ref = [];
        foreach my $dbname (@$databases_ref){
            my $dbinfo_ref = $self->get_databaseinfo->single({ 'dbname' => $dbname });
            push @$this_db_ref, {
                orgunitid   => $orgunitinfo_ref->id,
                dbid      => $dbinfo_ref->id,
            };
        }
        
        # Dann die zugehoerigen Datenbanken eintragen
        $self->{schema}->resultset('OrgunitDb')->populate($this_db_ref);
    }

    return;
}

sub new_orgunit {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}            : undef;
    my $orgunitname            = exists $arg_ref->{orgunitname}
        ? $arg_ref->{orgunitname}            : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}            : undef;
    my $nr                     = exists $arg_ref->{nr}
        ? $arg_ref->{nr}                     : undef;

    my $databases_ref          = exists $arg_ref->{databases}
        ? $arg_ref->{databases}              : [];

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profileinfo_ref = $self->get_profileinfo->single({ 'profilename' => $profilename });

    my $new_orgunit = $self->{schema}->resultset('Orgunitinfo')->create({ profileid => $profileinfo_ref->id, orgunitname => $orgunitname, description => $description, nr => $nr});

    my $orgunitid = $new_orgunit->id;

    # DBI: "delete from orgunit_db where profilename = ? and orgunitname = ?"
    # Datenbanken zunaechst loeschen
    $self->{schema}->resultset('OrgunitDb')->search_rs({ orgunitid => $orgunitid})->delete;

    # DBI: "insert into orgunit_db values (?,?,?)"
    if (@$databases_ref){

        $logger->debug("Datenbanken ".YAML::Dump($databases_ref));
        
        my $this_db_ref = [];
        foreach my $dbname (@$databases_ref){
            my $dbinfo_ref = $self->get_databaseinfo->single({ 'dbname' => $dbname });
            push @$this_db_ref, {
                orgunitid  => $orgunitid,
                dbid       => $dbinfo_ref->id,
            };
        }
        
        # Dann die zugehoerigen Datenbanken eintragen
        $self->{schema}->resultset('OrgunitDb')->populate($this_db_ref);
    }

    if ($new_orgunit){
        return $new_orgunit->id;
    }

    return;
}

sub del_server {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("About to delete id $id");

    # DBI: "delete from serverinfo where id = ?"
    $self->{schema}->resultset('Serverinfo')->single({ id => $id })->delete;

    return;
}

sub update_server {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    my $update_args = {};
    
    if ($arg_ref->{hostip}){
        $update_args->{hostip} = $arg_ref->{hostip};
    }

    if ($arg_ref->{description}){
        $update_args->{description} = $arg_ref->{description};
    }

    if ($arg_ref->{status}){
        $update_args->{status} = $arg_ref->{status};
    }
    
    if ($arg_ref->{clusterid}){
        $update_args->{clusterid} = $arg_ref->{clusterid};
    }

    if ($arg_ref->{active}){
        $update_args->{active} = $arg_ref->{active};
    }

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Updating ID $id".YAML::Dump($update_args));
    
    # DBI: "update serverinfo set active = ? where id = ?"
    $self->{schema}->resultset('Serverinfo')->search_rs({ id => $id })->update($update_args);

    return;
}

sub new_server {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $hostip                   = exists $arg_ref->{hostip}
        ? $arg_ref->{hostip}             : undef;
    my $description                   = exists $arg_ref->{description}
        ? $arg_ref->{description}        : undef;
    my $status                   = exists $arg_ref->{status}
        ? $arg_ref->{status}             : undef;
    my $clusterid                = exists $arg_ref->{clusterid}
        ? $arg_ref->{clusterid}          : undef;
    my $active                 = exists $arg_ref->{active}
        ? $arg_ref->{active}             : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (!$hostip){
        return -1;
    }

    # DBI: "insert into serverinfo (id,host,active) values (NULL,?,?)"
    my $new_server = $self->{schema}->resultset('Serverinfo')->create({ hostip => $hostip, description => $description, status => $status, clusterid => $clusterid, active => $active });

    if ($new_server){
        return $new_server->id;
    }

    return;
}

sub del_cluster {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("About to delete id $id");

    # DBI: "delete from clusterinfo where id = ?"
    $self->{schema}->resultset('Clusterinfo')->single({ id => $id })->delete;

    return;
}

sub update_cluster {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    my $update_args = {};
    
    if ($arg_ref->{description}){
        $update_args->{description} = $arg_ref->{description};
    }

    if ($arg_ref->{status}){
        $update_args->{status} = $arg_ref->{status};
    }
    
    if ($arg_ref->{active}){
        $update_args->{active} = $arg_ref->{active};
    }

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update clusterinfo set active = ? where id = ?"
    my $cluster = $self->{schema}->resultset('Clusterinfo')->single({ id => $id });

    $cluster->update($update_args);
    $cluster->serverinfos->update({status => $arg_ref->{status}});

    return;
}

sub new_cluster {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $description                   = exists $arg_ref->{description}
        ? $arg_ref->{description}        : undef;
    my $status                        = exists $arg_ref->{status}
        ? $arg_ref->{status}             : undef;
    my $active                        = exists $arg_ref->{active}
        ? $arg_ref->{active}             : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "insert into clusterinfo (id,host,active) values (NULL,?,?)"
    my $new_cluster = $self->{schema}->resultset('Clusterinfo')->create({ description => $description, status => $status, active => $active });

    if ($new_cluster){
        return $new_cluster->id;
    }

    return;
}

sub authentication_exists {
    my ($self,$targetid) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(*) as rowcount from authenticator where targetid = ?"
    my $targetcount = $self->{schema}->resultset('Authenticator')->search_rs(
        {
            id => $targetid,
        }
    )->count;
    
    return $targetcount;
}

sub get_authenticators {
    my ($self) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from authenticator order by type DESC,description"
    my $authenticators = $self->{schema}->resultset('Authenticator')->search_rs(
        undef,
        {
            order_by => ['type DESC','description']
        }
    );

    my $authenticators_ref = [];

    foreach my $authenticator ($authenticators->all){
        push @$authenticators_ref, {
            id          => $authenticator->id,
            hostname    => $authenticator->hostname,
            port        => $authenticator->port,
            remoteuser  => $authenticator->remoteuser,
            dbname      => $authenticator->dbname,
            description => $authenticator->description,
            type        => $authenticator->type,
        };
    }

    return $authenticators_ref;
}

sub get_authenticator_by_id {
    my ($self,$targetid) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from authenticator where targetid = ?"
    my $authenticator = $self->{schema}->resultset('Authenticator')->single(
        {
            id => $targetid,
        },
    );

    my $authenticator_ref = {};
    
    if ($authenticator){
        $authenticator_ref = {
            id          => $authenticator->id,
            hostname    => $authenticator->hostname,
            port        => $authenticator->port,
            remoteuser  => $authenticator->remoteuser,
            dbname      => $authenticator->dbname,
            description => $authenticator->description,
            type        => $authenticator->type,
        };
    }

    $logger->debug("Getting Info for Targetid: $targetid -> Got: ".YAML::Dump($authenticator_ref));
    return $authenticator_ref;
}

sub get_authenticator_self {
    my ($self) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from authenticator where type = ?"
    my $authenticator = $self->{schema}->resultset('Authenticator')->single(
        {
            type => 'self',
        },
    );

    my $authenticator_ref = {};
    
    if ($authenticator){
        $authenticator_ref = {
            id          => $authenticator->id,
            hostname    => $authenticator->hostname,
            port        => $authenticator->port,
            remoteuser  => $authenticator->remoteuser,
            dbname      => $authenticator->dbname,
            description => $authenticator->description,
            type        => $authenticator->type,
        };
    }

    $logger->debug("Getting Info for Type self:  -> Got: ".YAML::Dump($authenticator_ref));
    return $authenticator_ref;
}

sub get_number_of_authenticators {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(targetid) as rowcount from authenticator"
    my $numoftargets = $self->{schema}->resultset('Authenticator')->search_rs(
        undef,
    )->count;

    return $numoftargets;
}

sub authenticator_exists {
    my ($self,$arg_ref)=@_;

    my $description         = exists $arg_ref->{description}
        ? $arg_ref->{description}               : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(description) as rowcount from authenticator where description = ?"
    my $targetcount = $self->{schema}->resultset('Authenticator')->search_rs(
        {
            description => $description,
        }   
    )->count;

    return $targetcount;
}

sub delete_authenticator {
    my ($self,$targetid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $self->{schema}->resultset('Authenticator')->search_rs(
        {
            id => $targetid,
        }   
    )->delete;

    return;
}

sub new_authenticator {
    my ($self,$arg_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug(YAML::Dump($arg_ref));
    # DBI: "insert into authenticator (hostname,port,user,db,description,type) values (?,?,?,?,?,?)"
    my $new_authenticator = $self->{schema}->resultset('Authenticator')->create(
        $arg_ref,
    );

    if ($new_authenticator){
        return $new_authenticator->id;
    }

    return;
}

sub update_authenticator {
    my ($self,$arg_ref)=@_;
    
    my $logger = get_logger();

    # DBI: "update authenticator set hostname = ?, port = ?, user =?, db = ?, description = ?, type = ? where id = ?"
    $self->{schema}->resultset('Authenticator')->single(
        {
            id => $arg_ref->{id},
        }   
    )->update(
        $arg_ref,
    );

    $logger->debug("Authenticator updated");
    
    return;
}

sub get_id_of_selfreg_authenticator {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    # DBI: "select id from authenticator where type = 'self'"
    my $authenticator = $self->{schema}->resultset('Authenticator')->search_rs(
        {
            type => 'self',
        }
    )->single();

    my $targetid;
    
    if ($authenticator){
        $targetid = $authenticator->id;
    }
    
    return $targetid;
}

sub get_searchprofile_or_create {
    my ($self,$dbs_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $dbs_as_json = encode_json $dbs_ref;

    $logger->debug("Databases of Searchprofile as JSON: $dbs_as_json");

    # Simplified lookup via JSON-Representation
    my $searchprofile = $self->{schema}->resultset('Searchprofile')->single(
        {
            databases_as_json => $dbs_as_json,
        }
    );

    my $searchprofileid;
    
    if ($searchprofile){
        $searchprofileid = $searchprofile->id;
        $logger->debug("Searchprofile-ID $searchprofileid found for databases $dbs_as_json");
    }
    else {
        $logger->debug("Creating new Searchprofile for databases $dbs_as_json");
        my $new_searchprofile = $self->{schema}->resultset('Searchprofile')->create(
            {
                databases_as_json => $dbs_as_json,
            }
        );

        $searchprofileid = $new_searchprofile->id;
        
        foreach my $database (@{$dbs_ref}){
            my $dbinfo = $self->{schema}->resultset('Databaseinfo')->single({dbname => $database});

            if ($dbinfo){            
                $new_searchprofile->create_related(
                    'searchprofile_dbs',
                    {
                        searchprofileid => $searchprofileid,
                        dbid            => $dbinfo->id,
                    }
                );
            }
            else {
                $logger->error("Can't get Databaseinfo for database $database");
            }
        }
    }

    return $searchprofileid 
}

sub get_searchprofiles {
    my ($self,$searchprofileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @searchprofiles;
    
    my $searchprofiles = $self->{schema}->resultset('Searchprofile')->search_rs(undef,{ sort_by => ['id'] });

    foreach my $thissearchprofile ($searchprofiles->all){
        push @searchprofiles, $thissearchprofile;
    }
        
    return @searchprofiles;
}

sub get_databases_of_searchprofile {
    my ($self,$searchprofileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $searchprofiledbs = $self->{schema}->resultset('SearchprofileDb')->search_rs(
        {
            'me.searchprofileid' => $searchprofileid,
            'dbid.active'        => 1,
        },
        {
            join     => ['dbid'],
            select   => ['dbid.dbname'],
            as       => ['thisdbname'],
            order_by => ['dbid.dbname ASC'],
        }
    );

    my @databases = ();
    
    foreach my $searchprofiledb ($searchprofiledbs->all){
        push @databases, $searchprofiledb->get_column('thisdbname');

    }

    $logger->debug("Searchprofile $searchprofileid: ".join(',',@databases));
    return @databases;
}

sub get_searchprofile_of_database {
    my ($self,$database)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting searchprofile of databases $database");
    
    return $self->get_searchprofile_or_create([ $database ]);
}

sub get_searchprofile_of_view {
    my ($self,$viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @databases = $self->get_dbs_of_view($viewname);

    $logger->debug("Databases of View $viewname: ".join(',',@databases));
    
    return $self->get_searchprofile_or_create(\@databases);
}

sub get_searchprofile_of_orgunit {
    my ($self,$profilename,$orgunitname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @databases = $self->get_active_databases_of_orgunit($profilename,$orgunitname);

    $logger->debug("Databases of Orgunit $orgunitname in Profile $profilename: ".join(',',@databases));

    return $self->get_searchprofile_or_create(\@databases);
}

sub get_searchprofile_of_systemprofile {
    my ($self,$view)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @databases = $self->get_active_databases_of_systemprofile($view);

    $logger->debug("Databases of Systemprofile for view $view: ".join(',',@databases));

    return $self->get_searchprofile_or_create(\@databases);
}

sub searchprofiles_exists {
    my $self            = shift;
    my $searchprofileid = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $count = $self->{schema}->resultset('Searchprofile')->search({ id => $searchprofileid})->count;
    
    return $count;
}

sub update_searchprofile {
    my ($self,$searchprofileid,$own_index) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $searchprofile = $self->{schema}->resultset('Searchprofile')->single({ id => $searchprofileid});
        
    if ($searchprofile){
        $searchprofile->update({own_index => $own_index});
    }
        
    return;
}

sub get_searchprofile {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{schema}->resultset('Searchprofile');

}

sub get_searchprofiles_with_own_index {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @searchprofiles;
    
    my $searchprofiles = $self->{schema}->resultset('Searchprofile')->search_rs({ own_index => 1 });

    foreach my $thissearchprofile ($searchprofiles->all){
        push @searchprofiles, $thissearchprofile->id;
    }
        
    return @searchprofiles;
}

sub delete_stale_searchprofile_indexes {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $searchprofiles = $self->{schema}->resultset('Searchprofile');

    foreach my $searchprofile ($searchprofiles->all){
        my $profileindex_path = $self->{xapian_index_base_path}."/_searchprofile/".$searchprofile->id;        

        $logger->debug("Deleting stale Index for searchprofile $searchprofile->id with path $profileindex_path");
    
        # Delete joind profile index
        if ($searchprofile->own_index eq "false" && -d $profileindex_path){
            eval {
                opendir (DIR, $profileindex_path);
                my @files = readdir(DIR);
                closedir DIR;
                
                foreach my $file (@files) {
                    unlink ("$profileindex_path/$file");
                }
                
                rmdir $profileindex_path;
            };
            
            if ($@){
                $logger->error("Couldn't delete profileindex $profileindex_path");
            }
        }        
    }

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

=item get_databaseinfo

Liefert ein Databaseinfo-Objekt (DBIx::Class) aus der Config-Datenbank.

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

=item get_locationinfo($dbname)

Liefert eine Hashreferenz auf die allgemeinen Nutzungs-Informationen
(Öffnungszeigen, Adresse, usw.)  der zur Datenbank $dbname zugehörigen
Bibliothek. Zu jeder Kategorie category sind dies ein möglicher
Indikator indicator und der eigentliche Kategorieinhalt content.

=item have_locationinfo($dbname)

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

=item get_viewinfo

Liefert ein Viewinfo-Objekt (DBIx::Class) aus der Config-Datenbank.

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

=item get_profileinfo

Liefert ein Profileinfo-Objekt (DBIx::Class) aus der Config-Datenbank.

=item get_profiledbs($profilename)

Liefert zu einem Profil $profilename eine Liste aller zugeordneten
Datenbanken sortiert nach den Datenbanknamen zurück.

=item get_active_databases_of_systemprofile($viewname)

Liefert zu einem View $viewname eine Liste aller Datenbanken, die im
zugehörigen systemseitigen Profil definiert sind.

=item get_orgunitinfo

Liefert ein Orgunitinfo-Objekt (DBIx::Class) aus der Config-Datenbank.

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

=item get_serverinfo

Liefert ein Serverinfo-Objekt (DBIx::Class) aus der Config-Datenbank.

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
