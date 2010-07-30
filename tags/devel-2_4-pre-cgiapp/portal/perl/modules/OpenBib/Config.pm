#####################################################################
#
#  OpenBib::Config
#
#  Dieses File ist (C) 2004-2010 Oliver Flimm <flimm@openbib.org>
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
        
    my $request;
    if ($profilename){
        $request=$self->{dbh}->prepare("select count(profiledbs.dbname) as rowcount from profiledbs,dbinfo where profilename = ? and dbinfo.dbname=profiledbs.dbname and dbinfo.active = 1") or $logger->error($DBI::errstr);
        $request->execute($profilename) or $logger->error($DBI::errstr);
    }
    else {
        $request=$self->{dbh}->prepare("select count(dbname) as rowcount from dbinfo where dbinfo.active = 1") or $logger->error($DBI::errstr);
        $request->execute() or $logger->error($DBI::errstr);
    }
    
    my $res    = $request->fetchrow_hashref;
    $alldbs = $res->{rowcount};
    $request->finish();
    
    return $alldbs;
}

sub get_number_of_all_dbs {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select count(dbname) as rowcount from dbinfo") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    my $res    = $request->fetchrow_hashref;
    my $alldbs = $res->{rowcount};
    $request->finish();
    
    return $alldbs;
}

sub get_number_of_views {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select count(viewname) as rowcount from viewinfo where active=1") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    my $res      = $request->fetchrow_hashref;
    my $allviews = $res->{rowcount};
    $request->finish();
    
    return $allviews;
}

sub get_number_of_all_views {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select count(viewname) as rowcount from viewinfo") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    my $res      = $request->fetchrow_hashref;
    my $allviews = $res->{rowcount};
    $request->finish();
    
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

    my $request;
    if ($database){
        $request=$self->{dbh}->prepare("select sum(count) as alltitcount, type from titcount,dbinfo where titcount.dbname = ? and titcount.dbname=dbinfo.dbname and dbinfo.active=1 group by titcount.type") or $logger->error($DBI::errstr);
        $request->execute($database) or $logger->error($DBI::errstr);
    }
    elsif ($view){
        $request=$self->{dbh}->prepare("select sum(count) as alltitcount, type from titcount,dbinfo,viewdbs where viewdbs.viewname = ? and viewdbs.dbname=titcount.dbname and titcount.dbname=dbinfo.dbname and dbinfo.active=1 group by titcount.type") or $logger->error($DBI::errstr);
        $request->execute($profile) or $logger->error($DBI::errstr);

    }
    elsif ($profile){
        $request=$self->{dbh}->prepare("select sum(count) as alltitcount, type from titcount,dbinfo,profiledbs where profiledbs.profilename = ? and profiledbs.dbname=titcount.dbname and titcount.dbname=dbinfo.dbname and dbinfo.active=1 group by titcount.type") or $logger->error($DBI::errstr);
        $request->execute($profile) or $logger->error($DBI::errstr);
    }
    else {
        $request=$self->{dbh}->prepare("select sum(count) as alltitcount, type from titcount,dbinfo where titcount.dbname=dbinfo.dbname and dbinfo.active=1 group by titcount.type") or $logger->error($DBI::errstr);
        $request->execute() or $logger->error($DBI::errstr);
    }

    my $alltitles_ref = {};
    
    while (my $result = $request->fetchrow_hashref){
        my $alltitles = $result->{alltitcount};
        my $type      = $result->{type};

        $alltitles_ref->{all}      = $alltitles if ($type == 1);
        $alltitles_ref->{serials}  = $alltitles if ($type == 2);
        $alltitles_ref->{articles} = $alltitles if ($type == 3);
    }
    
    $request->finish();
    
    return $alltitles_ref;
}

sub get_viewdesc_from_viewname {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select description from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
    $request->execute($viewname) or $logger->error($DBI::errstr);
    my $res       = $request->fetchrow_hashref;
    my $desc      = decode_utf8($res->{description}) if (defined($res->{'description'}));
    $request->finish();
    
    return $desc;
}

sub get_startpage_of_view {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select start_loc,start_stid from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
    $request->execute($viewname) or $logger->error($DBI::errstr);
    my $res            = $request->fetchrow_hashref;
    my $start_loc      = decode_utf8($res->{start_loc}) if (defined($res->{'start_loc'}));
    my $start_stid     = decode_utf8($res->{start_stid}) if (defined($res->{'start_stid'}));
    $request->finish();

    $logger->debug("Got Startpage $start_loc") if (defined $start_loc);
    $logger->debug("Got StartStid $start_stid") if (defined $start_stid);
    
    return {
        start_loc  => $start_loc,
        start_stid => $start_stid,
    };
}

sub db_exists {
    my $self   = shift;
    my $dbname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select count(dbname) as rowcount from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
    $request->execute($dbname) or $logger->error($DBI::errstr);
    my $res       = $request->fetchrow_hashref;
    my $rowcount  = $res->{rowcount};
    $request->finish();
    
    return $rowcount;
}

sub view_exists {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select count(viewname) as rowcount from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
    $request->execute($viewname) or $logger->error($DBI::errstr);
    my $res       = $request->fetchrow_hashref;
    my $rowcount  = $res->{rowcount};
    $request->finish();
    
    return $rowcount;
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
        ? $arg_ref->{expiretimedate}      : undef;

    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Bestimmung, ob ein valider Cacheeintrag existiert
    my $request=$self->{dbh}->prepare("select content from rsscache where dbname=? and type=? and subtype = ? and tstamp > ?");
    $request->execute($database,$type,$subtype,$expiretimedate);

    my $res=$request->fetchrow_arrayref;
    my $rss_content=(exists $res->[0])?$res->[0]:undef;

    $request->finish();
    
    return $rss_content;
}

sub get_dbs_of_view {
    my ($self,$view) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @dblist=();
    my $idnresult=$self->{dbh}->prepare("select viewdbs.dbname from viewdbs,dbinfo,profiledbs where viewdbs.viewname = ? and viewdbs.dbname=dbinfo.dbname and profiledbs.dbname=viewdbs.dbname and dbinfo.active=1 order by profiledbs.orgunitname ASC, dbinfo.description ASC") or $logger->error($DBI::errstr);
    $idnresult->execute($view) or $logger->error($DBI::errstr);

    my @idnres;
    while (@idnres=$idnresult->fetchrow) {
        push @dblist, decode_utf8($idnres[0]);
    }
    $idnresult->finish();
    $logger->debug("View-Databases:\n".YAML::Dump(\@dblist));
    return @dblist;
}

sub get_rssfeeds_of_view {
    my ($self,$viewname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $viewrssfeed_ref  = {};

    my $idnresult=$self->{dbh}->prepare("select rssfeed from viewrssfeeds where viewname=?") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);

    while (my $result=$idnresult->fetchrow_hashref()) {
        my $rssfeed = $result->{'rssfeed'};
        $viewrssfeed_ref->{$rssfeed}=1;
    }

    return $viewrssfeed_ref;
}

sub get_rssfeed_overview {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $rssfeed_ref=[];
    
    my $request=$self->{dbh}->prepare("select * from rssfeeds order by dbname,type,subtype") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    while (my $result=$request->fetchrow_hashref()){
        my $id           = decode_utf8($result->{'id'});
        my $type         = decode_utf8($result->{'type'});
        my $subtype      = decode_utf8($result->{'subtype'});
        my $subtypedesc  = decode_utf8($result->{'subtypedesc'});
        my $active       = decode_utf8($result->{'active'});
        
        push @$rssfeed_ref, {
            feedid      => decode_utf8($result->{'id'}),
            dbname      => decode_utf8($result->{'dbname'}),
            type        => decode_utf8($result->{'type'}),
            subtype     => decode_utf8($result->{'subtype'}),
            subtypedesc => decode_utf8($result->{'subtypedesc'}),
        };
    }
    
    $request->finish();
    
    return $rssfeed_ref;
}

sub get_rssfeeds_of_db {
    my ($self,$dbname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $rssfeed_ref=[];
    
    my $request=$self->{dbh}->prepare("select * from rssfeeds where dbname = ? order by type,subtype") or $logger->error($DBI::errstr);
    $request->execute($dbname) or $logger->error($DBI::errstr);
    while (my $result=$request->fetchrow_hashref()){
        my $id           = decode_utf8($result->{'id'});
        my $type         = decode_utf8($result->{'type'});
        my $subtype      = decode_utf8($result->{'subtype'});
        my $subtypedesc  = decode_utf8($result->{'subtypedesc'});
        my $active       = decode_utf8($result->{'active'});
        
        push @$rssfeed_ref, {
            id          => $id,
            type        => $type,
            subtype     => $subtype,
            subtypedesc => $subtypedesc,
            active      => $active
        };
    }
    
    $request->finish();
    
    return $rssfeed_ref;
}

sub get_rssfeeds_of_db_by_type {
    my ($self,$dbname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $rssfeed_ref  = {};

    my $request=$self->{dbh}->prepare("select * from rssfeeds where dbname = ? order by type,subtype") or $logger->error($DBI::errstr);
    $request->execute($dbname) or $logger->error($DBI::errstr);
    while (my $result=$request->fetchrow_hashref()){
        my $type         = $result->{'type'};
        my $subtype      = $result->{'subtype'};
        my $subtypedesc  = $result->{'subtypedesc'};
        my $active       = $result->{'active'};
        
        push @{$rssfeed_ref->{$type}}, {
            subtype     => $subtype,
            subtypedesc => $subtypedesc,
            active      => $active
        };
    }
    $request->finish();
    
    return $rssfeed_ref;
}

sub get_primary_rssfeed_of_view  {
    my ($self,$viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Assoziierten View zur Session aus Datenbank holen
    my $idnresult=$self->{dbh}->prepare("select rssfeeds.dbname as dbname,rssfeeds.type as type, rssfeeds.subtype as subtype from rssfeeds,viewinfo where viewname = ? and rssfeeds.id = viewinfo.rssfeed and rssfeeds.active = 1") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
  
    my $result=$idnresult->fetchrow_hashref();
  
    my $dbname  = decode_utf8($result->{'dbname'}) || '';
    my $type    = $result->{'type'}    || 0;
    my $subtype = $result->{'subtype'} || 0;

    foreach my $typename (keys %{$self->{rss_types}}){
        if ($self->{rss_types}{$typename} eq $type){
            $type=$typename;
            last;
        }
    }
    
    $idnresult->finish();

    my $primrssfeedurl="";

    if ($dbname && $type){
        $primrssfeedurl="http://".$self->{loadbalancerservername}.$self->{connector_rss_loc}."/$type/$dbname.rdf";
    }
    
    return $primrssfeedurl;
}

sub get_activefeeds_of_db  {
    my ($self,$dbname)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    
    my $activefeeds_ref = {};
    
    my $request=$self->{dbh}->prepare("select type from rssfeeds where dbname \
= ? and active = 1") or $logger->error($DBI::errstr);
    $request->execute($dbname) or $logger->error($DBI::errstr);
    
    while (my $result=$request->fetchrow_hashref()){
        my $type    = $result->{'type'}    || 0;
        
        $activefeeds_ref->{$type} = 1;
    }
    
    
    $request->finish();
    
    return $activefeeds_ref;
}

sub get_rssfeedinfo  {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $rssfeedinfo_ref = {};
    
    my $sql_select="select dbinfo.dbname,dbinfo.description,orgunitinfo.description as orgunitdescription,rssfeeds.type";

    my @sql_from  = ('dbinfo','rssfeeds','profiledbs','orgunitinfo');

    my @sql_where = ('dbinfo.active=1','rssfeeds.active=1','dbinfo.dbname=rssfeeds.dbname','rssfeeds.type = 1','orgunitinfo.orgunitname=profiledbs.orgunitname','profiledbs.dbname=dbinfo.dbname');

    my @sql_args  = ();

    if ($view){
        push @sql_from,  'viewrssfeeds';
        push @sql_where, ('viewrssfeeds.viewname = ?','viewrssfeeds.rssfeed=rssfeeds.id');
        push @sql_args,  $view;
    }
    
    my $sqlrequest = $sql_select.' from '.join(',',@sql_from).' where '.join(' and ',@sql_where).' order by orgunit ASC, description ASC';
    
    $logger->debug("SQL-Request: $sqlrequest");
    
    my $request=$self->{dbh}->prepare($sqlrequest);
    $request->execute(@sql_args);
    
    while (my $result=$request->fetchrow_hashref){
        my $orgunit    = decode_utf8($result->{'orgunitdescription'});
        my $name       = decode_utf8($result->{'description'});
        my $pool       = decode_utf8($result->{'dbname'});
        my $rsstype    = decode_utf8($result->{'type'});
        
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

    # Etwaig vorhandenen Eintrag loeschen
    my $request=$self->{dbh}->prepare("delete from rsscache where dbname=? and type=? and subtype = ?");
    $request->execute($database,$type,$subtype);
    
    $request=$self->{dbh}->prepare("insert into rsscache values (?,NULL,?,?,?)");
    $request->execute($database,$type,$subtype,$rssfeed);
    
    $request->finish();

    return $self;
}

sub get_dbinfo {
    my $self   = shift;
    my $dbname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select * from dbinfo where dbname=?") or die "Error -- $DBI::errstr";
    $request->execute($dbname);
    my $result=$request->fetchrow_hashref();

    my $dbinfo_ref;

    $dbinfo_ref = {
        description => decode_utf8($result->{'description'}),
        shortdesc   => decode_utf8($result->{'shortdesc'}),
        system      => decode_utf8($result->{'system'}),
        dbname      => decode_utf8($result->{'dbname'}),
        sigel       => decode_utf8($result->{'sigel'}),
        url         => decode_utf8($result->{'url'}),
        use_libinfo => decode_utf8($result->{'use_libinfo'}),
        active      => decode_utf8($result->{'active'}),
    };
    
    $request->finish();
    
    return $dbinfo_ref;
}

sub get_dbinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $dbinfo_ref = [];

    my $idnresult=$self->{dbh}->prepare("select dbinfo.*,titcount.count,dboptions.autoconvert from dbinfo,titcount,dboptions where dbinfo.dbname=titcount.dbname and titcount.dbname=dboptions.dbname and titcount.type = 1 order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    
    my $katalog;
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $autoconvert = decode_utf8($result->{'autoconvert'});
        
        my $description = decode_utf8($result->{'description'});
        my $system      = decode_utf8($result->{'system'});
        my $dbname      = decode_utf8($result->{'dbname'});
        my $sigel       = decode_utf8($result->{'sigel'});
        my $url         = decode_utf8($result->{'url'});
        my $active      = decode_utf8($result->{'active'});
        my $use_libinfo = decode_utf8($result->{'use_libinfo'});
        my $count       = decode_utf8($result->{'count'});
        
        if (!$description) {
            $description="Keine Bezeichnung";
        }
        
        $katalog={
            description => $description,
            system      => $system,
            dbname      => $dbname,
            sigel       => $sigel,
            active      => $active,
            url         => $url,
            use_libinfo => $use_libinfo,
            count       => $count,
            autoconvert => $autoconvert,
        };
        
        push @{$dbinfo_ref}, $katalog;
    }
    
    return $dbinfo_ref;
}

sub get_libinfo {
    my $self   = shift;
    my $dbname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sqlrequest;

    my $libinfo_ref={};

    return {} if (!$dbname);
    
    $libinfo_ref->{database} = $dbname;

    $sqlrequest="select category,content,indicator from libraryinfo where dbname = ?";
    my $request=$self->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($dbname);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "I".sprintf "%04d",$res->{category };
        my $indicator =         decode_utf8($res->{indicator});
        my $content   =         decode_utf8($res->{content  });

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

    my $sqlrequest;

    my $libinfo_ref={};

    return {} if (!$dbname);
    
    $libinfo_ref->{database} = $dbname;

    $sqlrequest="select count(dbname) as infocount from libraryinfo where dbname = ? and content != ''";
    my $request=$self->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($dbname);

    my $res=$request->fetchrow_hashref;

    return $res->{infocount};
}

sub get_viewinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $viewinfo_ref = [];

    my $view="";
    
    my $idnresult=$self->{dbh}->prepare("select * from viewinfo order by viewname") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $viewname    = decode_utf8($result->{'viewname'});
        my $description = decode_utf8($result->{'description'});
        my $active      = decode_utf8($result->{'active'});
        my $profile     = decode_utf8($result->{'profilename'});
        
        $description = (defined $description)?$description:'Keine Beschreibung';
        
        $active="Ja"   if ($active eq "1");
        $active="Nein" if ($active eq "0");
        
        my $idnresult2=$self->{dbh}->prepare("select * from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
        $idnresult2->execute($viewname);
        
        my @viewdbs=();
        while (my $result2=$idnresult2->fetchrow_hashref()) {
            my $dbname = decode_utf8($result2->{'dbname'});
            push @viewdbs, $dbname;
        }
        
        $idnresult2->finish();
        
        my $viewdb=join " ; ", @viewdbs;
        
        $view={
            viewname    => $viewname,
            description => $description,
            profile     => $profile,
            active      => $active,
            viewdb      => $viewdb,
        };
        
        push @{$viewinfo_ref}, $view;
        
    }
    
    return $viewinfo_ref;
}

sub get_profileinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $profileinfo_ref = [];

    my $profile="";
    
    my $idnresult=$self->{dbh}->prepare("select * from profileinfo order by profilename") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $profilename = decode_utf8($result->{'profilename'});
        my $description = decode_utf8($result->{'description'});
          
        $description = (defined $description)?$description:'Keine Beschreibung';
        
        my $idnresult2=$self->{dbh}->prepare("select * from profiledbs where profilename = ? order by dbname") or $logger->error($DBI::errstr);
        $idnresult2->execute($profilename);
        
        my @profiledbs=();
        while (my $result2=$idnresult2->fetchrow_hashref()) {
            my $dbname = decode_utf8($result2->{'dbname'});
            push @profiledbs, $dbname;
        }
        
        $idnresult2->finish();
        
        my $profiledb=join " ; ", @profiledbs;
        
        $profile={
            profilename => $profilename,
            description => $description,
            profiledb   => $profiledb,
        };
        
        push @{$profileinfo_ref}, $profile;
        
    }
    
    return $profileinfo_ref;
}

sub get_profileinfo {
    my $self        = shift;
    my $profilename = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select * from profileinfo where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    
    my $result=$idnresult->fetchrow_hashref();

    my $profileinfo_ref = {    
        profilename => decode_utf8($result->{'profilename'}),
        description => decode_utf8($result->{'description'}),
    };
    
    return $profileinfo_ref;
}

sub get_orgunits {
    my $self        = shift;
    my $profilename = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select * from orgunitinfo where profilename = ? order by nr ASC") or $logger->error($DBI::errstr);
    $request->execute($profilename) or $logger->error($DBI::errstr);
    
    my $orgunitinfo_ref = [];

    while (my $result=$request->fetchrow_hashref()){

        my $request2=$self->{dbh}->prepare("select dbname from profiledbs where profilename = ? and orgunitname = ? order by dbname ASC") or $logger->error($DBI::errstr);
        $request2->execute($profilename,$result->{'orgunitname'}) or $logger->error($DBI::errstr);

        my @orgunitdbs = ();
        while (my $result2=$request2->fetchrow_hashref()){
            push @orgunitdbs, $result2->{dbname};
        }        
        
        my $thisorgunitinfo_ref = {
            profilename => decode_utf8($result->{'profilename'}),
            orgunitname => decode_utf8($result->{'orgunitname'}),
            description => decode_utf8($result->{'description'}),
            nr          => decode_utf8($result->{'nr'}),
            dbnames     => \@orgunitdbs,
        };
        
        push @{$orgunitinfo_ref}, $thisorgunitinfo_ref;
    }
    
    return $orgunitinfo_ref;
}

sub get_orgunitinfo {
    my $self        = shift;
    my $profilename = shift;
    my $orgunitname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select * from orgunitinfo where profilename = ? and orgunitname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename,$orgunitname) or $logger->error($DBI::errstr);
    
    my $result=$idnresult->fetchrow_hashref();

    my $request2=$self->{dbh}->prepare("select dbname from profiledbs where profilename = ? and orgunitname = ? order by dbname ASC") or $logger->error($DBI::errstr);
    $request2->execute($profilename,$orgunitname) or $logger->error($DBI::errstr);
    
    my @orgunitdbs = ();
    while (my $result2=$request2->fetchrow_hashref()){
        push @orgunitdbs, $result2->{dbname};
    }
    

    my $orgunitinfo_ref = {
        profilename => decode_utf8($result->{'profilename'}),       
        orgunitname => decode_utf8($result->{'orgunitname'}),       
        description => decode_utf8($result->{'description'}),
        nr          => decode_utf8($result->{'nr'}),
        dbname      => \@orgunitdbs,
    };
    
    return $orgunitinfo_ref;
}

sub get_profiledbs {
    my $self        = shift;
    my $profilename = shift;
    my $orgunitname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sql="select * from profiledbs where profilename = ?";

    my @sql_args = ($profilename);
    
    if ($orgunitname){
        $sql.=" and orgunitname = ?";
        push @sql_args, $orgunitname;
    }
    
    my $idnresult=$self->{dbh}->prepare("$sql order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute(@sql_args) or $logger->error($DBI::errstr);
    
    my @profiledbs=();
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $dbname = decode_utf8($result->{'dbname'});
        push @profiledbs, $dbname;
    }
    
    return @profiledbs;
}

sub get_viewinfo {
    my $self     = shift;
    my $viewname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select * from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
    
    my $result=$idnresult->fetchrow_hashref();

    my $viewinfo_ref = {    
        viewname    => decode_utf8($result->{'viewname'}),
        description => decode_utf8($result->{'description'}),
        primrssfeed => decode_utf8($result->{'primrssfeed'}),
        start_loc   => decode_utf8($result->{'start_loc'}),
        start_stid  => decode_utf8($result->{'start_stid'}),
        profilename => decode_utf8($result->{'profilename'}),
        active      => decode_utf8($result->{'active'}),
    };
    
    return $viewinfo_ref;
}

sub get_viewdbs {
    my $self     = shift;
    my $viewname = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select viewdbs.dbname from viewdbs,dbinfo where viewdbs.viewname = ? and viewdbs.dbname = dbinfo.dbname and dbinfo.active=1 order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
    
    my @viewdbs=();
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $dbname = decode_utf8($result->{'dbname'});
        push @viewdbs, $dbname;
    }
    
    return @viewdbs;
}

sub get_dboptions {
    my $self   = shift;
    my $dbname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select * from dboptions where dbname=?") or die "Error -- $DBI::errstr";
    $request->execute($dbname);
    my $result=$request->fetchrow_hashref();

    my $dboptions_ref;

    $dboptions_ref = {
        host          => $result->{'host'},
        protocol      => $result->{'protocol'},
        remotepath    => $result->{'remotepath'},
        remoteuser    => $result->{'remoteuser'},
        remotepasswd  => $result->{'remotepasswd'},
        filename      => $result->{'filename'},
        titfilename   => $result->{'titfilename'},
        autfilename   => $result->{'autfilename'},
        korfilename   => $result->{'korfilename'},
        swtfilename   => $result->{'swtfilename'},
        notfilename   => $result->{'notfilename'},
        mexfilename   => $result->{'mexfilename'},
        autoconvert   => $result->{'autoconvert'},
        circ          => $result->{'circ'},
        circurl       => $result->{'circurl'},
        circcheckurl  => $result->{'circcheckurl'},
        circdb        => $result->{'circdb'},
    };
    
    $request->finish();
    
    return $dboptions_ref;
}

sub get_active_databases {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @dblist=();
    my $request=$self->{dbh}->prepare("select dbname from dbinfo where active=1 order by orgunit ASC, dbname ASC") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    while (my $res    = $request->fetchrow_hashref){
        push @dblist, $res->{dbname};
    }
    $request->finish();
    
    return @dblist;
}

sub get_active_databases_of_systemprofile {
    my $self = shift;
    my $view = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @dblist=();
    my $request=$self->{dbh}->prepare("select dbinfo.dbname as dbname from dbinfo,viewinfo,profiledbs where dbinfo.active=1 and dbinfo.dbname=profiledbs.dbname and profiledbs.profilename=viewinfo.profilename and viewinfo.viewname = ? order by dbname ASC") or $logger->error($DBI::errstr);
    $request->execute($view) or $logger->error($DBI::errstr);
    while (my $res    = $request->fetchrow_hashref){
        push @dblist, $res->{dbname};
    }
    $request->finish();
    
    return @dblist;
}

sub get_active_database_names {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @dblist=();
    my $request=$self->{dbh}->prepare("select dbname,description from dbinfo where active=1 order by dbname") or $logger->error($DBI::errstr);

    $request->execute() or $logger->error($DBI::errstr);
    while (my $result   = $request->fetchrow_hashref){
        my $dbname      = decode_utf8($result->{'dbname'});
        my $description = decode_utf8($result->{'description'});

        push @dblist, {
            dbname      => $dbname,
            description => $description,
        };
    }
    $request->finish();
    
    return @dblist;
}

sub get_active_views {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @viewlist=();
    my $request=$self->{dbh}->prepare("select viewname from viewinfo where active=1 order by description ASC") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    while (my $res    = $request->fetchrow_hashref){
        push @viewlist, $res->{viewname};
    }
    $request->finish();
    
    return @viewlist;
}

####################### TODO ###################### weg
sub get_active_databases_of_orgunit {
    my ($self,$orgunit) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @dblist=();
    my $request=$self->{dbh}->prepare("select dbname from dbinfo where active=1 and orgunit = ? order by dbname ASC") or $logger->error($DBI::errstr);
    $request->execute($orgunit) or $logger->error($DBI::errstr);
    while (my $res    = $request->fetchrow_hashref){
        push @dblist, $res->{dbname};
    }
    $request->finish();
    
    return @dblist;
}

sub get_system_of_db {
    my ($self,$dbname) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select system from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
    $request->execute($dbname) or $logger->error($DBI::errstr);
    my $systemtype = "";
    while (my $res    = $request->fetchrow_hashref){
        $systemtype = $res->{system};
    }
    $request->finish();
    
    return $systemtype;
}

sub get_infomatrix_of_active_databases {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $session           = exists $arg_ref->{session}
        ? $arg_ref->{session}           : undef;
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

    my $profile = $self->get_viewinfo($view)->{profilename};
    
    $maxcolumn=(defined $maxcolumn)?$maxcolumn:$self->{databasechoice_maxcolumn};
    
    my $sqlrequest = "select * from dbinfo where active=1 order by description ASC";

    my @sqlargs = ();

    if ($view){
        $sqlrequest = "select dbinfo.*,orgunitinfo.description as orgunitdescription, orgunitinfo.orgunitname from dbinfo,profiledbs,viewinfo,orgunitinfo where dbinfo.active=1 and dbinfo.dbname=profiledbs.dbname and profiledbs.profilename=viewinfo.profilename and profiledbs.orgunitname=orgunitinfo.orgunitname and orgunitinfo.profilename=profiledbs.profilename and viewinfo.viewname = ? order by orgunitinfo.nr ASC, dbinfo.description ASC";
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

sub get_loadbalancertargets {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $loadbalancertargets_ref = [];

    my $request=$self->{dbh}->prepare("select * from loadbalancertargets order by host") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    
    while (my $result=$request->fetchrow_hashref()){
        my $id            = decode_utf8($result->{'id'});
        my $host          = decode_utf8($result->{'host'});
        my $active        = decode_utf8($result->{'active'});
        
        push @{$loadbalancertargets_ref}, {
            id     => $id,
            host   => $host,
            active => $active,
        };
    }

    
    return $loadbalancertargets_ref;
}

sub get_active_loadbalancertargets {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my @activetargets = ();

    my $request=$self->{dbh}->prepare("select host from loadbalancertargets where active = 1 order by host") or $logger->error($DBI::errstr);
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
            = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect to database $self->{configdbname}");
    }

    $self->{dbh}->{RaiseError} = 1;

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
start_loc/start_stid, den zugeordneten Profilnamen profilename sowie
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
