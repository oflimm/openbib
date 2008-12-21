#####################################################################
#
#  OpenBib::Config
#
#  Dieses File ist (C) 2004-2008 Oliver Flimm <flimm@openbib.org>
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

use Apache::Reload;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use YAML::Syck;

use OpenBib::Database::DBI;

sub new {
    my $class = shift;

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;
    
    # Ininitalisierung mit Config-Parametern
    my $self = YAML::Syck::LoadFile("/opt/openbib/conf/portal.yml");

    bless ($self, $class);

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
    
    return $self;
}

sub get_number_of_dbs {
    my $self = shift;
    my $profilename = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request;
    if ($profilename){
        $request=$dbh->prepare("select count(profiledbs.dbname) as rowcount from profiledbs,dbinfo where profilename = ? and dbinfo.dbname=profiledbs.dbname and dbinfo.active = 1") or $logger->error($DBI::errstr);
        $request->execute($profilename) or $logger->error($DBI::errstr);
    }
    else {
        $request=$dbh->prepare("select count(dbname) as rowcount from dbinfo where dbinfo.active = 1") or $logger->error($DBI::errstr);
        $request->execute() or $logger->error($DBI::errstr);
    }
    
    my $res    = $request->fetchrow_hashref;
    my $alldbs = $res->{rowcount};
    $request->finish();
    
    return $alldbs;
}

sub get_number_of_all_dbs {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $request=$dbh->prepare("select count(dbname) as rowcount from dbinfo") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select count(viewname) as rowcount from viewinfo where active=1") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select count(viewname) as rowcount from viewinfo") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    my $res      = $request->fetchrow_hashref;
    my $allviews = $res->{rowcount};
    $request->finish();
    
    return $allviews;
}

sub get_number_of_titles {
    my $self = shift;
    my $profilename = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request;
    if ($profilename){
        $request=$dbh->prepare("select sum(count) as alltitcount from titcount,dbinfo,profiledbs where profiledbs.profilename = ? and profiledbs.dbname=titcount.dbname and titcount.dbname=dbinfo.dbname and dbinfo.active=1") or $logger->error($DBI::errstr);
        $request->execute($profilename) or $logger->error($DBI::errstr);
    }
    else {
        $request=$dbh->prepare("select sum(count) as alltitcount from titcount,dbinfo where titcount.dbname=dbinfo.dbname and dbinfo.active=1") or $logger->error($DBI::errstr);
        $request->execute() or $logger->error($DBI::errstr);
    }

    my $res       = $request->fetchrow_hashref;
    my $alltitles = $res->{alltitcount};
    $request->finish();
    
    return $alltitles;
}

sub get_viewdesc_from_viewname {
    my $self     = shift;
    my $viewname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $request=$dbh->prepare("select description from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select start_loc,start_stid from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select count(dbname) as rowcount from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select count(viewname) as rowcount from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    # Bestimmung, ob ein valider Cacheeintrag existiert
    my $request=$dbh->prepare("select content from rsscache where dbname=? and type=? and subtype = ? and tstamp > ?");
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my @dblist=();
    my $idnresult=$dbh->prepare("select viewdbs.dbname from viewdbs,dbinfo where viewdbs.viewname = ? and viewdbs.dbname=dbinfo.dbname and dbinfo.active=1 order by dbinfo.orgunit ASC, dbinfo.description ASC") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $viewrssfeed_ref  = {};

    my $idnresult=$dbh->prepare("select rssfeed from viewrssfeeds where viewname=?") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $rssfeed_ref=[];
    
    my $request=$dbh->prepare("select * from rssfeeds order by dbname,type,subtype") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $rssfeed_ref=[];
    
    my $request=$dbh->prepare("select * from rssfeeds where dbname = ? order by type,subtype") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $rssfeed_ref  = {};

    my $request=$dbh->prepare("select * from rssfeeds where dbname = ? order by type,subtype") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    # Assoziierten View zur Session aus Datenbank holen
    my $idnresult=$dbh->prepare("select rssfeeds.dbname as dbname,rssfeeds.type as type, rssfeeds.subtype as subtype from rssfeeds,viewinfo where viewname = ? and rssfeeds.id = viewinfo.rssfeed and rssfeeds.active = 1") or $logger->error($DBI::errstr);
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
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select type from rssfeeds where dbname \
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
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $sql_select="select dbinfo.dbname,dbinfo.description,dbinfo.orgunit,rssfeeds.type";

    my @sql_from  = ('dbinfo','rssfeeds');

    my @sql_where = ('dbinfo.active=1','rssfeeds.active=1','dbinfo.dbname=rssfeeds.dbname','rssfeeds.type = 1');

    my @sql_args  = ();

    if ($view){
        push @sql_from,  'viewrssfeeds';
        push @sql_where, ('viewrssfeeds.viewname = ?','viewrssfeeds.rssfeed=rssfeeds.id');
        push @sql_args,  $view;
    }
    
    my $sqlrequest = $sql_select.' from '.join(',',@sql_from).' where '.join(' and ',@sql_where).' order by orgunit ASC, description ASC';
    
    $logger->debug("SQL-Request: $sqlrequest");
    
    my $request=$dbh->prepare($sqlrequest);
    $request->execute(@sql_args);
    
    while (my $result=$request->fetchrow_hashref){
        my $orgunit    = decode_utf8($result->{'orgunit'});
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    # Etwaig vorhandenen Eintrag loeschen
    my $request=$dbh->prepare("delete from rsscache where dbname=? and type=? and subtype = ?");
    $request->execute($database,$type,$subtype);
    
    $request=$dbh->prepare("insert into rsscache values (?,NULL,?,?,?)");
    $request->execute($database,$type,$subtype,$rssfeed);
    
    $request->finish();

    return $self;
}

sub get_dbinfo {
    my $self   = shift;
    my $dbname = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select * from dbinfo where dbname=?") or die "Error -- $DBI::errstr";
    $request->execute($dbname);
    my $result=$request->fetchrow_hashref();

    my $dbinfo_ref;

    $dbinfo_ref = {
        orgunit     => decode_utf8($result->{'orgunit'}),
        description => decode_utf8($result->{'description'}),
        shortdesc   => decode_utf8($result->{'shortdesc'}),
        system      => decode_utf8($result->{'system'}),
        dbname      => decode_utf8($result->{'dbname'}),
        sigel       => decode_utf8($result->{'sigel'}),
        url         => decode_utf8($result->{'url'}),
        active      => decode_utf8($result->{'active'}),
    };
    
    $request->finish();
    
    return $dbinfo_ref;
}

sub get_dbinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $dbinfo_ref = [];

    my $idnresult=$dbh->prepare("select dbinfo.*,titcount.count,dboptions.autoconvert from dbinfo,titcount,dboptions where dbinfo.dbname=titcount.dbname and titcount.dbname=dboptions.dbname order by orgunit,dbname") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    
    my $katalog;
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $orgunit     = decode_utf8($result->{'orgunit'});
        my $autoconvert = decode_utf8($result->{'autoconvert'});
        
        my $orgunits_ref = $self->{orgunits};
        
        my @orgunits=@$orgunits_ref;
        
        foreach my $unit_ref (@orgunits) {
            my %unit=%$unit_ref;
            if ($unit{short} eq $orgunit) {
                $orgunit=$unit{desc};
            }
        }
        
        my $description = decode_utf8($result->{'description'});
        my $system      = decode_utf8($result->{'system'});
        my $dbname      = decode_utf8($result->{'dbname'});
        my $sigel       = decode_utf8($result->{'sigel'});
        my $url         = decode_utf8($result->{'url'});
        my $active      = decode_utf8($result->{'active'});
        my $count       = decode_utf8($result->{'count'});
        
        if (!$description) {
            $description="Keine Bezeichnung";
        }
        
        $katalog={
            orgunit     => $orgunit,
            description => $description,
            system      => $system,
            dbname      => $dbname,
            sigel       => $sigel,
            active      => $active,
            url         => $url,
            count       => $count,
            autoconvert => $autoconvert,
        };
        
        push @{$dbinfo_ref}, $katalog;
    }
    
    return $dbinfo_ref;
}

sub get_viewinfo_overview {
    my $self   = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $viewinfo_ref = [];

    my $view="";
    
    my $idnresult=$dbh->prepare("select * from viewinfo order by viewname") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $viewname    = decode_utf8($result->{'viewname'});
        my $description = decode_utf8($result->{'description'});
        my $active      = decode_utf8($result->{'active'});
        my $profile     = decode_utf8($result->{'profilename'});
        
        $description = (defined $description)?$description:'Keine Beschreibung';
        
        $active="Ja"   if ($active eq "1");
        $active="Nein" if ($active eq "0");
        
        my $idnresult2=$dbh->prepare("select * from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $profileinfo_ref = [];

    my $profile="";
    
    my $idnresult=$dbh->prepare("select * from profileinfo order by profilename") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $profilename = decode_utf8($result->{'profilename'});
        my $description = decode_utf8($result->{'description'});
          
        $description = (defined $description)?$description:'Keine Beschreibung';
        
        my $idnresult2=$dbh->prepare("select * from profiledbs where profilename = ? order by dbname") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $idnresult=$dbh->prepare("select * from profileinfo where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    
    my $result=$idnresult->fetchrow_hashref();

    my $profileinfo_ref = {    
        profilename => decode_utf8($result->{'profilename'}),
        description => decode_utf8($result->{'description'}),
    };
    
    return $profileinfo_ref;
}

sub get_profiledbs {
    my $self        = shift;
    my $profilename = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $idnresult=$dbh->prepare("select * from profiledbs where profilename = ? order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $idnresult=$dbh->prepare("select * from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $idnresult=$dbh->prepare("select * from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select * from dboptions where dbname=?") or die "Error -- $DBI::errstr";
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my @dblist=();
    my $request=$dbh->prepare("select dbname from dbinfo where active=1 order by orgunit ASC, dbname ASC") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my @dblist=();
    my $request=$dbh->prepare("select dbinfo.dbname as dbname from dbinfo,viewinfo,profiledbs where dbinfo.active=1 and dbinfo.dbname=profiledbs.dbname and profiledbs.profilename=viewinfo.profilename and viewinfo.viewname = ? order by orgunit ASC, dbname ASC") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my @dblist=();
    my $request=$dbh->prepare("select dbname,description,orgunit from dbinfo where active=1 order by orgunit,description") or $logger->error($DBI::errstr);

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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my @viewlist=();
    my $request=$dbh->prepare("select viewname from viewinfo where active=1 order by description ASC") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    while (my $res    = $request->fetchrow_hashref){
        push @viewlist, $res->{viewname};
    }
    $request->finish();
    
    return @viewlist;
}

sub get_active_databases_of_orgunit {
    my ($self,$orgunit) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my @dblist=();
    my $request=$dbh->prepare("select dbname from dbinfo where active=1 and orgunit = ? order by dbname ASC") or $logger->error($DBI::errstr);
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

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select system from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
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
    
    $maxcolumn=(defined $maxcolumn)?$maxcolumn:$self->{databasechoice_maxcolumn};
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $sqlrequest = "select * from dbinfo where active=1 order by orgunit ASC, description ASC";

    my @sqlargs = ();
    
    if ($view){
        $sqlrequest = "select dbinfo.* from dbinfo,profiledbs,viewinfo where dbinfo.active=1 and dbinfo.dbname=profiledbs.dbname and profiledbs.profilename=viewinfo.profilename and viewinfo.viewname=? order by orgunit ASC, description ASC";
        push @sqlargs, $view;
    }
    
    my $idnresult=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $idnresult->execute(@sqlargs) or $logger->error($DBI::errstr);

    my @catdb=();
    
    while (my $result=$idnresult->fetchrow_hashref) {
        my $category   = decode_utf8($result->{'orgunit'});
        my $name       = decode_utf8($result->{'description'});
        my $systemtype = decode_utf8($result->{'system'});
        my $pool       = decode_utf8($result->{'dbname'});
        my $url        = decode_utf8($result->{'url'});
        my $sigel      = decode_utf8($result->{'sigel'});
	
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
        };
        $count++;
    }

    return @catdb;
}

sub get_infomatrix_of_all_databases {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $profile           = exists $arg_ref->{profile}
        ? $arg_ref->{profile      }     : undef;
    my $maxcolumn          = exists $arg_ref->{maxcolumn}
        ? $arg_ref->{maxcolumn}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $lastcategory="";
    my $count=0;
    
    $maxcolumn=(defined $maxcolumn)?$maxcolumn:$self->{databasechoice_maxcolumn};
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$self->{dbimodule}:dbname=$self->{configdbname};host=$self->{configdbhost};port=$self->{configdbport}", $self->{configdbuser}, $self->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select * from dbinfo order by orgunit ASC, description ASC") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);

    my @catdb=();
    
    while (my $result=$idnresult->fetchrow_hashref) {
        my $category   = decode_utf8($result->{'orgunit'});
        my $name       = decode_utf8($result->{'description'});
        my $systemtype = decode_utf8($result->{'system'});
        my $pool       = decode_utf8($result->{'dbname'});
        my $url        = decode_utf8($result->{'url'});
        my $sigel      = decode_utf8($result->{'sigel'});
	
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
                };
                $count++;
            }
            $count=0;
        }
        
        $lastcategory=$category;
        
        $rcolumn=($count % $maxcolumn)+1;
        
        my $checked="";
        if ($profile->contains($pool)) {
            $checked=1;
        }
        
        push @catdb, { 
            column     => $rcolumn,
            category   => $category,
            db         => $pool,
            name       => $name,
            systemtype => $systemtype,
            sigel      => $sigel,
            url        => $url,
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

1;
