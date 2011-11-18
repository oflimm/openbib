
#####################################################################
#
#  OpenBib::User
#
#  Dieses File ist (C) 2006-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::User;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);
use Digest::MD5;
use Encode qw(decode_utf8 encode_utf8);
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Database::DBI;
use OpenBib::Database::System;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    my $id          = exists $arg_ref->{ID}
        ? $arg_ref->{ID}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->connectDB();
    $self->connectMemcached();

    if (defined $sessionID){
        my $userid = $self->get_userid_of_session($sessionID);
        if (defined $userid){
            $self->{ID} = $userid ;
            $logger->debug("Got UserID $userid for session $sessionID");
        }

    }
    elsif (defined $id) {
        $self->{ID} = $id ;
        $logger->debug("Got UserID $id - NO session assiziated");
    }

    return $self;
}

sub _new_instance {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    my $id          = exists $arg_ref->{ID}
        ? $arg_ref->{ID}             : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->connectDB();
    $self->connectMemcached();

    if (defined $sessionID){
        my $userid = $self->get_userid_of_session($sessionID);
        if (defined $userid){
            $self->{ID} = $userid ;
            $logger->debug("Got UserID $userid for session $sessionID");
        }
    }
    elsif (defined $id){
         $self->{ID} = $id ;
         $logger->debug("Got UserID $id - NO session assiziated");
    }

    return $self;
}

sub userdb_accessible{
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{systemdbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    if ($dbh->ping()){
        return 1;
    }
    
    return 0;
}
    
sub get_credentials {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $userid    = exists $arg_ref->{userid}
        ? $arg_ref->{userid}             : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    # DBI: "select username,pin from user where userid = ?"
    my $credentials = $self->{schema}->resultset('Userinfo')->search(
        {
            id => $thisuserid,
        }
    )->single;

    if ($credentials){
        return ($credentials->username,$credentials->password);
    }
    else {
        return (undef,undef);
    }
}

sub set_credentials {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username   = exists $arg_ref->{username}
        ? $arg_ref->{username}             : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($username){
        # DBI: "update userinfo set pin = ? where username = ?"
        my $userinfo = $self->{schema}->resultset('Userinfo')->search(
            {
                username => $username,
            }
        )->single()->update({ password => $password });
    }
    elsif ($self->{ID}) {
        # DBI: "update userinfo set pin = ? where id = ?"
        my $userinfo = $self->{schema}->resultset('Userinfo')->search(
            {
                id => $self->{ID},
            }
        )->single->update({ password => $password });
    }
    else {
        $logger->error("Neither username nor userid given");
    }

    return;
}

sub user_exists {
    my ($self,$username)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from user where username = ?"
    my $count = $self->{schema}->resultset('Userinfo')->search({ username => $username})->count;
    
    return $count;    
}

sub add {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username   = exists $arg_ref->{username}
        ? $arg_ref->{username}             : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}              : undef;

    my $email       = exists $arg_ref->{email}
        ? $arg_ref->{email}                 : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "insert into user values (NULL,'',?,?,'','','','',0,'','','','','','','','','','','',?,'','','','','')"
    $self->{schema}->resultset('Userinfo')->create({
        username  => $username,
        password  => $password,
        email     => $email,
    });
    
    return;
}

sub add_confirmation_request {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username   = exists $arg_ref->{username}
        ? $arg_ref->{username}             : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $gmtime    = localtime(time);
    my $md5digest = Digest::MD5->new();
    
    $md5digest->add($gmtime . rand('1024'). $$);
    my $registrationid = $md5digest->hexdigest;

    # DBI: "insert into userregistration values (?,NULL,?,?)"
    $self->{schema}->resultset('Registration')->create({
        id        => $registrationid,
        username  => $username,
        password  => $password,
    });
    
    return;
}

sub get_confirmation_request {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $registrationid = exists $arg_ref->{registrationid}
        ? $arg_ref->{registrationid}             : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from userregistration where registrationid = ?"
    my $confirmationinfo = $self->{schema}->resultset('Registration')->search_rs(
        {
            id => $registrationid,
        }
    )->single;

    my ($username,$password);
    
    if ($confirmationinfo){
        $username = $confirmationinfo->username;
        $password  = $confirmationinfo->password;
    }
    
    my $confirmation_info_ref = {
        username  => $username,
        password  => $password,
    };
    
    return $confirmation_info_ref;
}

sub clear_confirmation_request {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $registrationid = exists $arg_ref->{registrationid}
        ? $arg_ref->{registrationid}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "delete from userregistration where registrationid = ?"
    my $confirmationinfo = $self->{schema}->resultset('Registration')->search_rs(
        {
            id => $registrationid,
        }
    )->delete_all;

    return;
}

sub get_username {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select username from user where userid = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->single;

    my $username;
    
    if ($userinfo){
        $username=decode_utf8($userinfo->username);
    }
    
    return $username;
}

sub get_username_for_userid {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select username from user where userid = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $userid,
        }
    )->single;

    my $username;

    if ($userinfo){
        $username = decode_utf8($userinfo->username);
    }
    
    return $username;
}

sub get_userid_for_username {
    my ($self,$username)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select userid from user where username = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            username => $username,
        }
    )->single;

    my $userid;

    if ($userinfo){
        $userid = $userinfo->id;
    }

    return $userid;
}

sub get_userid_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting UserID for SessionID $sessionID");
    
    # DBI: "select userid from user_session where sessionid = ?"
    my $usersession = $self->{schema}->resultset('UserSession')->search_rs(
        {
            'sid.sessionid' => $sessionID,
        },
        {
            join   => ['sid'],
            select => ['me.userid'],
            as     => ['thisuserid'],
        }
    )->single;


    my $userid;
    
    if ($usersession){
        $userid = $usersession->get_column('thisuserid');
    }
    
    $logger->debug("Got UserID $userid for SessionID $sessionID");
    
    return $userid;
}

sub clear_cached_userdata {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?"
    $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->single()->update({
        nachname => '',
        vorname  => '',
        strasse  => '',
        ort      => '',
        plz      => 0,
        soll     => '',
        gut      => '',
        avanz    => '',
        branz    => '',
        bsanz    => '',
        vmanz    => '',
        maanz    => '',
        vlanz    => '',
        sperre   => '',
        sperrdatum => '',
        gebdatum => '',
    });

    return;
}

sub get_targetdb_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: select db from user_session,logintarget where user_session.sessionid = ? and user_session.targetid = logintarget.targetid"
    my $logintarget = $self->{schema}->resultset('UserSession')->search_rs(
        {
            'sid.sessionid' => $sessionID,
        },
        {
            join   => ['sid','targetid'],
            select => ['targetid.db'],
            as     => ['thisdbname'],
        }
            
    )->single;
    
    my $targetdb;

    if ($logintarget){
        $targetdb = $logintarget->get_column('thisdbname');
    }
    
    return $targetdb;
}

sub get_targettype_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: select type from user_session,logintarget where user_session.sessionid = ? and user_session.targetid = logintarget.targetid"
    my $logintarget = $self->{schema}->resultset('UserSession')->search_rs(
        {
            'sid.sessionid' => $sessionID,
        },
        {
            join   => ['sid','targetid'],
            select => ['targetid.type'],
            as     => ['thistype'],
        }
            
    )->single;
    
    my $targettype;

    if ($logintarget){
        $targettype = decode_utf8($logintarget->get_column('thistype'));
    }

    return $targettype;
}


sub get_profilename_of_profileid {
    my ($self,$profileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $usersearchprofilename = $self->{schema}->resultset('UserSearchprofile')->search_rs(
        {
            id     => $profileid,
            userid => $self->{ID},
        },
        {
            columns => ['profilename'],
        }
    )->single()->profilename;
    

    return $usersearchprofilename;
}

sub get_profiledbs_of_profileid {
    my ($self,$profileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select profildb.dbname as dbname from profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid = ? and userdbprofile.profilid=profildb.profilid order by dbname"
    my $userprofile = $self->{schema}->resultset('UserSearchprofile')->search_rs(
        {
            'me.id'        => $profileid,
            'me.userid'    => $self->{ID},
        },
        {
            join   => ['profileid'],
            select => ['profileid.databases_as_json'],
            as     => ['thisdatabases_as_json'],
        }

    )->single();

    my $dbs_as_json = $userprofile->get_column('thisdatabases_as_json');

    my $dbs_ref = decode_json $dbs_as_json;

    my @profiledbs = @{$dbs_ref};

    return @profiledbs;
}

sub get_number_of_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $numofitems = $self->{schema}->resultset('Collection')->search_rs(
        {
            userid => $self->{ID},
        }
    )->count;

    return $numofitems;
}

sub get_number_of_tagged_titles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(titid)) as rowcount from tittag"
    my $numoftitles = $self->{schema}->resultset('TitTag')->search(
        undef,
        {
            group_by => ['titleid'],
        }
    )->count;

    return $numoftitles;
}

sub get_number_of_tagging_users {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(username)) as rowcount from tittag"
    my $numofusers = $self->{schema}->resultset('TitTag')->search(
        undef,
        {
            group_by => ['userid'],
        }
    )->count;

    return $numofusers;
}

sub get_number_of_tags {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(tagid)) as rowcount from tittag"
    my $numoftags = $self->{schema}->resultset('TitTag')->search(
        undef,
        {
            group_by => ['tagid'],
        }
    )->count;

    return $numoftags;
}

sub get_name_of_tag {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tagid       = exists $arg_ref->{tagid}
        ? $arg_ref->{tagid}                 : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Name for Tagid $tagid");
    my $tag = $self->{schema}->resultset('Tag')->search_rs(
        {
            id => $tagid,
        }
    )->first;

    my $name;
    
    if ($tag){
        $name = $tag->name;
        $logger->debug("Found Tag $name");
    }
    
    return $name;
}

sub get_id_of_tag {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tag         = exists $arg_ref->{tag}
        ? $arg_ref->{tag}                 : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $tag);

    # DBI: "select id from tag where name=?"
    my $id = $self->{schema}->resultset('Tag')->search_rs(
        {
            name => $tag
        }
    )->single->id;
    
    return $id;
}

sub get_titles_of_tag {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username   = exists $arg_ref->{username}
        ? $arg_ref->{username}             : undef;

    my $tagid       = exists $arg_ref->{tagid}
        ? $arg_ref->{tagid}                 : undef;

    my $database    = exists $arg_ref->{database}
        ? $arg_ref->{database}             : undef;

    my $offset      = exists $arg_ref->{offset}
        ? $arg_ref->{offset}                : '';

    my $hitrange    = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst Gesamtanzahl bestimmen
    my $where_ref     = {
        tagid => $tagid,
    };
    
    my $attribute_ref = {
        group_by => ['me.titleid','me.dbname']
    };
    
    if ($username) {
        $where_ref->{'userid.username'}  = $username;
        $attribute_ref->{'join'}         = [ 'userid' ];
    }

    if ($database) {
        $where_ref->{'me.dbname'} = $database;
    }

    # DBI: "select count(distinct titid,titdb) as conncount from tittag where tagid=?"
    my $hits = $self->{schema}->resultset('TitTag')->search_rs(
        $where_ref,
        $attribute_ref
    )->count;


    # Dann jeweilige Titelmenge bestimmen
    
    my $recordlist = new OpenBib::RecordList::Title();

    $where_ref     = {
        tagid => $tagid,
    };
    
    $attribute_ref = {
        select   => ['me.titleid','me.dbname'],
        as       => ['thistitleid','thisdbname'],
        group_by => ['me.titleid','me.dbname'],
    };
    
    if ($username) {
        $where_ref->{'userid.username'}  = $username;
        $attribute_ref->{'join'}         = [ 'userid' ];
    }

    if ($database) {
        $where_ref->{'me.dbname'} = $database;
    }

    if ($hitrange){
        $attribute_ref->{rows}   = $hitrange;
        $attribute_ref->{offset} = $offset;
    }
    
    # DBI: "select distinct titid,titdb from tittag where tagid=?";
    my $tagged_titles = $self->{schema}->resultset('TitTag')->search_rs(
        $where_ref,
        $attribute_ref
    );

    foreach my $title ($tagged_titles->all){
        $recordlist->add(new OpenBib::Record::Title({database => $title->get_column('thisdbname') , id => $title->get_column('thistitleid')}));
    }

    $recordlist->load_brief_records;
    
    return ($recordlist,$hits);
}

sub get_number_of_users {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from userinfo"
    my $numofusers = $self->{schema}->resultset('Userinfo')->search_rs(
        undef,
    )->count;

    return $numofusers;
}

sub get_number_of_dbprofiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI "select count(profilid) as rowcount from user_profile"
    my $numofprofiles = $self->{schema}->resultset('UserSearchprofile')->search_rs(
        undef,
    )->count;

    return $numofprofiles;
}

sub get_number_of_collections {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(userid)) as rowcount from collection"
    my $numofcollections = $self->{schema}->resultset('Collection')->search_rs(
        undef,
        {
            group_by => ['userid'], # distinct
        }
    )->count;

    return $numofcollections;
}

sub get_number_of_collection_entries {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from collection"
    my $numofentries = $self->{schema}->resultset('Collection')->search_rs(
        undef,
    )->count;

    return $numofentries;
}

sub get_all_profiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select profilid, profilename from userdbprofile where userid = ? order by profilename"
    my $userprofiles = $self->{schema}->resultset('UserSearchprofile')->search_rs(
        {
            userid => $self->{ID},
        },
        {
            order_by => ['profilename'],
        }
    );
            
    my @userdbprofiles=();
        
    foreach my $userprofile ($userprofiles->all){
        push @userdbprofiles, {
            profilid    => $userprofile->profileid,
            profilename => decode_utf8($userprofile->profilename),
        };
    }
    
    return @userdbprofiles;
}

sub authenticate_self_user {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username            = exists $arg_ref->{username}
        ? $arg_ref->{username}            : undef;
    my $password            = exists $arg_ref->{password}
        ? $arg_ref->{password}            : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select userid from user where username = ? and password = ?"
    my $authentication = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            username  => $username,
            password  => $password,
        }
    )->first;
    
    my $userid = -1;

    if ($authentication){
        $userid = $authentication->id;
    }

    $logger->debug("Got Userid $userid");

    return $userid;
}

sub authentication_exists {
    my ($self,$targetid) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(*) as rowcount from logintarget where targetid = ?"
    my $targetcount = $self->{schema}->resultset('Logintarget')->search_rs(
        {
            id => $targetid,
        }
    )->count;
    
    return $targetcount;
}

sub get_logintargets {
    my ($self) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from logintarget order by type DESC,description"
    my $logintargets = $self->{schema}->resultset('Logintarget')->search_rs(
        undef,
        {
            order_by => ['type DESC','description']
        }
    );

    my $logintargets_ref = [];

    foreach my $logintarget ($logintargets->all){
        push @$logintargets_ref, {
            id          => decode_utf8($logintarget->id),
            hostname    => decode_utf8($logintarget->hostname),
            port        => decode_utf8($logintarget->port),
            username    => decode_utf8($logintarget->user),
            dbname      => decode_utf8($logintarget->db),
            description => decode_utf8($logintarget->description),
            type        => decode_utf8($logintarget->type),
        };
    }

    return $logintargets_ref;
}

sub get_logintarget_by_id {
    my ($self,$targetid) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from logintarget where targetid = ?"
    my $logintarget = $self->{schema}->resultset('Logintarget')->search_rs(
        {
            id => $targetid,
        },
        {
            order_by => ['type DESC','description']
        }
    )->single;

    my $logintarget_ref = {};
    
    if ($logintarget){
        $logintarget_ref = {
            id          => decode_utf8($logintarget->id),
            hostname    => decode_utf8($logintarget->hostname),
            port        => decode_utf8($logintarget->port),
            username    => decode_utf8($logintarget->user),
            dbname      => decode_utf8($logintarget->db),
            description => decode_utf8($logintarget->description),
            type        => decode_utf8($logintarget->type),
        };
    }

    $logger->debug("Getting Info for Targetid: $targetid -> Got: ".YAML::Dump($logintarget_ref));
    return $logintarget_ref;
}

sub get_number_of_logintargets {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(targetid) as rowcount from logintarget"
    my $numoftargets = $self->{schema}->resultset('Logintarget')->search_rs(
        undef,
    )->count;

    return $numoftargets;
}

sub add_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tags                = exists $arg_ref->{tags}
        ? $arg_ref->{tags    }            : undef;
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;
    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);


    # Splitten der Tags
    my @taglist = split("\\s+",$tags);

    # Zuerst alle Verknuepfungen loeschen

    # DBI: "delete from tittag where username = ? and titid=? and titdb=?"
    $self->{schema}->resultset('TitTag')->search_rs(
        {
            'userid.username' => $username,
            'me.titleid'       => $titid,
            'me.dbname'        => $titdb,
        },
        {
            join => ['userid'],
        }
    )->delete_all;
    
    my $tags_ref = [];
    foreach my $tag (@taglist){

        # Normierung
        $tag = OpenBib::Common::Util::grundform({
            content  => $tag,
            tagging  => 1,
        });

        push @$tags_ref, $tag;

        # DBI: "select id from tags where tag = ?"
        my $tag = $self->{schema}->resulset('Tag')->search_rs(
            {
                name => $tag,
            }
        );

        # Wenn Tag nicht existiert, dann kann alles eintragen werden (tags/tittag)
        
        if (!$tag){
            $logger->debug("Tag $tag noch nicht verhanden");

            # DBI: "insert into tags (tag) values (?)"
            my $new_tag = $self->{schema}->resultset('Tag')->create({ name => encode_utf8($tag) });

            # DBI: "select id from tags where tag = ?"
            #      "insert into tittag (tagid,titid,titisbn,titdb,username,type) values (?,?,?,?,?,?)"
            $new_tag->create_related(
                'tit_tags',
                {
                    titleid   => $titid,
                    titleisbn => $titisbn,
                    dbname    => $titdb,
                    userid    => $self->get_userid_for_username($username),
                    type      => $type,
                    
                }
            );
        }
        
        # Jetzt Verknuepfung mit Titel herstellen
        else {
            $logger->debug("Tag verhanden");
            
            # Neue Verknuepfungen eintragen
            $logger->debug("Verknuepfung zu Titel noch nicht vorhanden");

            # DBI: "insert into tittag (tagid,titid,titisbn,titdb,username,type) values (?,?,?,?,?,?)"
            $tag->create_related(
                'tit_tags',
                {
                    titleid   => $titid,
                    titleisbn => $titisbn,
                    dbname    => $titdb,
                    userid    => $self->get_userid_for_username($username),
                    type      => $type,                    
                }
            );
        }
        
    }

    my $bibsonomy_ref = $self->get_bibsonomy;

    return unless ($bibsonomy_ref->{user} || $bibsonomy_ref->{key} || $bibsonomy_ref->{sync});
        
    my $bibsonomy = new OpenBib::BibSonomy({api_user => $bibsonomy_ref->{user}, api_key => $bibsonomy_ref->{key}});

    # Sync mit BibSonomy, falls gewuenscht
    $logger->debug("Syncing single title to BibSonomy");

    my $visibility =
        ($type == 1)?'public':
            ($type == 2)?'private':'private';
    
    # 1) Ueberpruefen, ob Titel bereits existiert
    
    my $record    = new OpenBib::Record::Title({ database => $titdb , id => $titid})->load_full_record;
    my $bibkey    = $record->to_bibkey;
    
    my $posts_ref = $bibsonomy->get_posts({ user => 'self', bibkey => $bibkey});
    
    $logger->debug("Bibkey: $bibkey");
    # 2) ja, dann Tags und Sichtbarkeit anpassen
    if (exists $posts_ref->{recordlist} && @{$posts_ref->{recordlist}}){
        $logger->debug("Syncing Tags and Visibility $titdb:$titid");
        $bibsonomy->change_post({ tags => $tags_ref, bibkey => $bibkey, visibility => $visibility });
    }
    # 3) nein, dann mit Tags neu anlegen
    else {
        if (@$tags_ref){
            $logger->debug("Syncing Record $titdb:$titid");
            $logger->debug("Tags".YAML::Dump($tags_ref));
            $bibsonomy->new_post({ tags => $tags_ref, record => $record, visibility => $visibility });
        }
    }

    return;
}

sub rename_tag {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $oldtag              = exists $arg_ref->{oldtag}
        ? $arg_ref->{oldtag  }            : undef;
    my $newtag              = exists $arg_ref->{newtag}
        ? $arg_ref->{newtag  }            : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    # Splitten der Tags
    my @oldtaglist = split("\\s+",$oldtag);
    my @newtaglist = split("\\s+",$newtag);

    # Normierung
    $oldtag = OpenBib::Common::Util::grundform({
        content  => $oldtaglist[0],
        tagging  => 1,
    });

    $newtag = OpenBib::Common::Util::grundform({
        content  => $newtaglist[0],
        tagging  => 1,
    });

    # Vorgehensweise
    # 1.) oldid von oldtag bestimmen
    # 2.) Uebepruefen, ob newtag schon existiert. Wenn nicht, dann anlegen
    #     und newid merken
    # 3.) In tittag alle Vorkommen von oldid durch newid fuer username
    #     ersetzen

    my $request=$dbh->prepare("select id from tag where name = ?") or $logger->error($DBI::errstr);
    $request->execute($oldtag) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $oldtagid = $result->{id};

    
    $request=$dbh->prepare("select id from tag where name = ?") or $logger->error($DBI::errstr);
    $request->execute($newtag) or $logger->error($DBI::errstr);

    $result=$request->fetchrow_hashref;

    my $newtagid=$result->{id};

    # Wenn NewTag nicht existiert
        
    if (!$newtagid){
        $logger->debug("Tag $newtag noch nicht verhanden");
        $request=$dbh->prepare("insert into tag (name) values (?)") or $logger->error($DBI::errstr);
        $request->execute(encode_utf8($newtag)) or $logger->error($DBI::errstr);

        $request=$dbh->prepare("select id from tag where name = ?") or $logger->error($DBI::errstr);
        $request->execute(encode_utf8($newtag)) or $logger->error($DBI::errstr);
        my $result=$request->fetchrow_hashref;
        $newtagid=$result->{id};
    }

    if ($oldtagid && $newtagid){
        $request=$dbh->prepare("update tit_tag set tagid = ? where tagid = ? and userid = ?") or $logger->error($DBI::errstr);
        $request->execute($newtagid,$oldtagid,$self->get_userid_for_username($username)) or $logger->error($DBI::errstr);
    }
    else {
        return 1;
    }

    return;
}

sub del_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tags                = exists $arg_ref->{tags}
        ? $arg_ref->{tags}                : undef;
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    if ($tags){
        foreach my $tag (split("\\s+",$tags)){
            my $tagid = $self->get_id_of_tag({tag => $tag});
            my $request=$dbh->prepare("delete from tit_tag where titleid=? and dbname=? and userid=? and tagid=?") or $logger->error($DBI::errstr);
            $request->execute($titid,$titdb,$self->get_userid_for_username($username),$tagid) or $logger->error($DBI::errstr);
        }
    }
    else {
        my $request=$dbh->prepare("delete from tittag where titleid=? and dbname=? and userid=?") or $logger->error($DBI::errstr);
        $request->execute($titid,$titdb,$self->get_userid_for_username($username)) or $logger->error($DBI::errstr);
    }
    
    return;
}

sub get_all_tags_of_db {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $dbname              = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    my $request=$dbh->prepare("select t.name, t.id, count(tt.tagid) as tagcount from tag as t, tit_tag as tt where tt.dbname=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.name") or $logger->error($DBI::errstr);

    $request->execute($dbname) or $logger->error($DBI::errstr);

    my $taglist_ref = [];
    my $maxcount = 0;
    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{name});
        my $id        = $result->{id};
        my $count     = $result->{tagcount};

        $logger->debug("Gefundene Tags: $tag - $id - $count");
        if ($maxcount < $count){
            $maxcount = $count;
        }
        
        push @$taglist_ref, {
            id    => $id,
            name  => $tag,
            count => $count,
        };

        for (my $i=0 ; $i < scalar (@$taglist_ref) ; $i++){
            $taglist_ref->[$i]->{class} = int($taglist_ref->[$i]->{count} / (int($maxcount/6)+1));
        }
    }
    
    return $taglist_ref;
}

sub get_all_tags_of_tit {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    my $request=$dbh->prepare("select t.name, t.id, count(tt.tagid) as tagcount from tag as t, tit_tag as tt where tt.titleid=? and tt.dbname=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.name") or $logger->error($DBI::errstr);

    $request->execute($titid,$titdb) or $logger->error($DBI::errstr);

    my $taglist_ref = [];
    my $maxcount = 0;
    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{name});
        my $id        = $result->{id};
        my $count     = $result->{tagcount};

        $logger->debug("Gefundene Tags: $tag - $id - $count");
        if ($maxcount < $count){
            $maxcount = $count;
        }
        
        push @$taglist_ref, {
            id    => $id,
            name  => $tag,
            count => $count,
        };

        for (my $i=0 ; $i < scalar (@$taglist_ref) ; $i++){
            $taglist_ref->[$i]->{class} = int($taglist_ref->[$i]->{count} / (int($maxcount/6)+1));
        }
    }
    
    return $taglist_ref;
}

sub get_private_tags_of_tit {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    my $request=$dbh->prepare("select t.id,t.name,tt.type from tag as t,tit_tag as tt where tt.userid=? and tt.titleid=? and tt.dbname=? and tt.tagid = t.id") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($username),$titid,$titdb) or $logger->error($DBI::errstr);

    my $taglist_ref = [];

    while (my $result=$request->fetchrow_hashref){
        my $tag  = decode_utf8($result->{name});
        my $id   = $result->{id};
        my $type = $result->{type};

        push @$taglist_ref, {
            id   => $id,
            name => $tag,
            type => $type,
        };
    }
    
    return $taglist_ref;
}

sub get_private_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("username: $username");

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    my $request=$dbh->prepare("select t.name, t.id, count(tt.tagid) as tagcount from tag as t, tit_tag as tt where t.id=tt.tagid and tt.userid=? group by tt.tagid order by t.name") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($username)) or $logger->error($DBI::errstr);

    my $taglist_ref = [];
    my $maxcount = 0;
    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{name});
        my $id        = $result->{id};
        my $count     = $result->{tagcount};

        $logger->debug("Gefundene Tags: $tag - $id - $count");
        if ($maxcount < $count){
            $maxcount = $count;
        }
        
        push @$taglist_ref, {
            id    => $id,
            name  => $tag,
            count => $count,
        };

        for (my $i=0 ; $i < scalar (@$taglist_ref) ; $i++){
            $taglist_ref->[$i]->{class} = int($taglist_ref->[$i]->{count} / (int($maxcount/6)+1));
        }
    }

    $logger->debug("Private Tags: ".YAML::Dump($taglist_ref));
    return $taglist_ref;
}

sub get_private_tagged_titles {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("username: $username");

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    my $request=$dbh->prepare("select t.name, tt.titleid, tt.dbname, tt.type from tag as t, tit_tag as tt where t.id=tt.tagid and tt.userid=? group by tt.tagid order by t.name") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($username)) or $logger->error($DBI::errstr);

    my $taglist_ref = {};

    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{name});
        my $id        = $result->{titleid};
        my $database  = $result->{dbname};
        my $type      = $result->{type};

        $taglist_ref->{$database}{$id}{visibility} = $type;
        
        unless (exists $taglist_ref->{$database}{$id}{tags}){
            $taglist_ref->{$database}{$id}{tags} = [];
        }
        
        push @{$taglist_ref->{$database}{$id}{tags}}, $tag;
    }

    $logger->debug("Private Tags: ".YAML::Dump($taglist_ref));
    return $taglist_ref;
}

sub get_recent_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $count        = exists $arg_ref->{count}
        ? $arg_ref->{count}           : 5;

    my $database     = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $tags_ref = [];
    
    if ($database){
        # DBI: "select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where tt.titdb= ? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by tt.ttid DESC limit $count"
        my $tags = $self->{schema}->resultset('TitTag')->search(
            {
                'me.type'   => 1,
                'me.dbname' => $database,
            },
            {
                group_by => ['me.tagid'],
                order_by => ['tagid.id DESC'],
                rows     => $count,
                select   => ['count(me.tagid)','tagid.id','tagid.name'],
                as       => ['thistagcount','thistagid','thistagname'],
                join     => ['tagid'],
            }
        );

        foreach my $singletag ($tags->all){
            my $id        = $singletag->get_column('thistagid');
            my $tag       = $singletag->get_column('thistagname');
            my $count     = $singletag->get_column('thistagcount');
            
            push @$tags_ref, {
                id        => $id,
                tag       => $tag,
                itemcount => $count,
            };
        }        
    }
    else {
        # DBI: "select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where t.id=tt.tagid and tt.type=1 group by tt.tagid order by tt.ttid DESC limit $count";
        my $tags = $self->{schema}->resultset('TitTag')->search(
            {
                'me.type'   => 1,
            },
            {
                group_by => ['me.tagid'],
                order_by => ['tagid.id DESC'],
                rows     => $count,
                select   => ['count(me.tagid)','tagid.id','tagid.name'],
                as       => ['thistagcount','thistagid','thistagname'],
                join     => ['tagid'],
            }
        );

        foreach my $singletag ($tags->all){
            my $id        = $singletag->get_column('thistagid');
            my $tag       = $singletag->get_column('thistagname');
            my $count     = $singletag->get_column('thistagcount');
            
            push @$tags_ref, {
                id        => $id,
                tag       => $tag,
                itemcount => $count,
            };
        }        
    }
    
    return $tags_ref;
}

sub vote_for_review {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $reviewid            = exists $arg_ref->{reviewid}
        ? $arg_ref->{reviewid}            : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;
    my $rating              = exists $arg_ref->{rating}
        ? $arg_ref->{rating}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # Ratings sind Zahlen
    $rating   =~s/[^0-9]//g;
    
    # DBI: "select reviewid from reviewrating where userid = ? and reviewid=?"
    my $reviewrating = $self->{schema}->resultset('Reviewrating')->search_rs(
        {
            userid   => $self->get_userid_for_username($username),
            reviewid => $reviewid,
        }
    )->first;

    if ($reviewrating){
        return 1; # Review schon vorhanden! Es darf aber pro Nutzer nur einer abgegeben werden;
    }
    else {
        # DBI: "insert into reviewrating (reviewid,userid,rating) values (?,?,?)"
        $self->{schema}->resultset('Reviewrating')->create(
            {
                reviewid => $reviewid,
                userid   => $self->get_userid_for_username($username),
                rating   => $rating,
            }
        );
    }

    return;
}

sub get_review_properties {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $reviewid           = exists $arg_ref->{reviewid}
        ? $arg_ref->{reviewid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);

    return {} if (!$reviewid);

    # DBI: "select * from review where id = ?"
    my $review = $self->{schema}->resultset('Review')->search_rs(
        id => $reviewid,
    )->first;

    if ($review){
        
        my $title     = decode_utf8($review->title);
        my $titid     = $review->titleid;
        my $titdb     = $review->dbname;
        my $titisbn   = $review->titleisbn;
        my $tstamp    = $review->tstamp;
        my $nickname  = $review->nickname;
        my $review    = $review->review;
        my $rating    = $review->rating;
        my $userid    = $review->userid;
        
        my $username = $self->get_username_for_userid($userid);
        
        my $review_ref = {
            id               => $reviewid,
            userid           => $userid,
            username         => $username,
            title            => $title,
            titdb            => $titdb,
            titid            => $titid,
            tstamp           => $tstamp,
            review           => $review,
            rating           => $rating,
        };

        $logger->debug("Review Properties: ".YAML::Dump($review_ref));

        return $review_ref;
    }
    else {
        return {};
    }
}

sub get_review_owner {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $reviewid           = exists $arg_ref->{reviewid}
        ? $arg_ref->{reviewid}           : undef;

    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return $self->get_review_properties({ reviewid => $reviewid })->{userid};
}

sub add_review {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;
    my $nickname            = exists $arg_ref->{nickname}
        ? $arg_ref->{nickname}            : undef;
    my $title              = exists $arg_ref->{title}
        ? $arg_ref->{title}               : undef;
    my $reviewtext         = exists $arg_ref->{review}
        ? $arg_ref->{review}              : undef;
    my $rating              = exists $arg_ref->{rating}
        ? $arg_ref->{rating}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $rating     =~s/[^0-9]//g;
    $reviewtext =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $title      =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $nickname   =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;

    # DBI: "select id from review where userid = ? and titleid=? and dbname=?"
    my $review = $self->{schema}->resultset('Review')->search_rs(
        {
            userid => $self->get_userid_for_username($username),
            titleid => $titid,
            dbname => $titdb,
        }
    )->single;

    # Review schon vorhanden?
    if ($review){
        # DBI: "update review set titleid=?, titleisbn=?, dbname=?, userid=?, nickname=?, title=?, review=?, rating=? where id=?"
        $review->update(
            {
                titleisbn  => $titisbn,
                nickname   => encode_utf8($nickname),
                title      => encode_utf8($title),
                reviewtext => encode_utf8($reviewtext),
                rating     => $rating,
            }
        );
    }
    else {
        # DBI: "insert into review (titleid,titleisbn,dbname,userid,nickname,title,review,rating) values (?,?,?,?,?,?,?,?)"
        $self->{schema}->create(
            titleid    => $titid,
            dbname     => $titdb,
            userid     => $self->get_userid_for_username($username),
            titleisbn  => $titisbn,
            nickname   => encode_utf8($nickname),
            title      => encode_utf8($title),
            reviewtext => encode_utf8($reviewtext),
            rating     => $rating,
            
        );
    }

    return;
}

sub get_reviews_of_tit {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select id,nickname,userid,title,review,rating from review where titleid=? and dbname=?"
    my $reviews = $self->{schema}->resultset('Review')->search_rs(
        {
            titleid => $titid,
            dbname  => $titdb,
        }
    );

    my $reviewlist_ref = [];

    foreach my $review ($reviews->all){
        my $userid    = decode_utf8($review->userid);
        my $username = $self->get_username_of_userid($userid);
        my $nickname  = decode_utf8($review->nickname);
        my $title     = decode_utf8($review->title);
        my $review    = decode_utf8($review->reviewtext);
        my $id        = $review->id;
        my $rating    = $review->rating;

        # DBI: "select count(id) as votecount from reviewrating where reviewid=?  group by id"
        my $votecount = $self->{schema}->resultset('Reviewrating')->search_rs(
            {
                reviewid => $review->id,
            },
            {
                group_by => 'reviewid',
            }                
        )->count;

        my $posvotecount = 0;
        
        if ($votecount){
            # DBI: "select count(id) as posvotecount from reviewrating where reviewid=? and rating > 0 group by id"
            $posvotecount = $self->{schema}->resultset('Reviewrating')->search_rs(
                {
                    reviewid => $review->id,
                    rating   => { '>' =>  0},
                },
                {
                    group_by => 'reviewid',
                }                
            )->count;
        }
        
        push @$reviewlist_ref, {
            id        => $id,
            username  => $username,
            nickname  => $nickname,
            title     => $title,
            review    => $review,
            rating    => $rating,
            votes     => {
                all      => $votecount,
                positive => $posvotecount,
            },
        };
    }
    
    return $reviewlist_ref;
}

sub tit_reviewed_by_user {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select id from review where titleid=? and dbname=? and userid=?"
    my $review = $self->{schema}->resultset('Review')->search_rs(
        {
            titleid => $titid,
            dbname  => $titdb,
            userid  => $self->get_userid_for_username($username),
        }
    )->first;

    my $reviewid;
    
    if ($review){
        $reviewid = $review->id;
    }

    return $reviewid;
}

sub get_review_of_user {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                  = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select id,titleid,dbname,nickname,userid,title,review,rating from review where id=? and userid=?"
    my $review = $self->{schema}->resultset('Review')->search_rs(
        {
            id => $id,
            userid => $self->get_userid_for_username($username),
        }
    )->first;

    my $review_ref = {};
    
    if ($review){
        $logger->debug("Found Review $id for User $username");

        my $userid     = decode_utf8($review->userid);
        my $username   = $self->get_username_of_userid($userid);
        my $nickname   = decode_utf8($review->nickname);
        my $title      = decode_utf8($review->title);
        my $reviewtext = decode_utf8($review->reviewtext);
        my $id         = $review->id;
        my $titid      = $review->titleid;
        my $titdb      = $review->dbname;
        my $rating     = $review->rating;

        $review_ref = {
            id        => $id,
            titid     => $titid,
            titdb     => $titdb,
            username  => $username,
            nickname  => $nickname,
            title     => $title,
            review    => $reviewtext,
            rating    => $rating,
        };
    }

    $logger->debug("Got Review: ".YAML::Dump($review_ref));

    return $review_ref;
}

sub del_review_of_user {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                  = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "delete from review where id=? and userid=?"
    $self->{schema}->resultset('Review')->search_rs(
        {
            id     => $id,
            userid => $self->get_userid_for_username($username),
        }
    )->delete;

    return;
}

sub get_reviews {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$username || !$tags);

    my $request=$dbh->prepare("select id,titleid,dbname,nickname,userid,title,review,rating from review where userid=?") or $logger->error($DBI::errstr);

    my $reviews = $self->{schema}->resultset('Review')->search_rs(
        {
            userid => $self->get_userid_for_username($username),
        }
    );

    my $reviewlist_ref = [];
    
    foreach my $review ($reviews->all){
        my $userid     = decode_utf8($review->userid);
        my $username   = $self->get_username_of_userid($userid);
        my $nickname   = decode_utf8($review->nickname);
        my $title      = decode_utf8($review->title);
        my $reviewtext = decode_utf8($review->reviewtext);
        my $id         = $review->id;
        my $titid      = $review->titleid;
        my $titdb      = $review->dbname;
        my $rating     = $review->rating;

        push @$reviewlist_ref, {
            id        => $id,
            titid     => $titid,
            titdb     => $titdb,
            username  => $username,
            nickname  => $nickname,
            title     => $title,
            review    => $review,
            rating    => $rating,
        };
    }
    
    return $reviewlist_ref;
}

sub add_litlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $title               = exists $arg_ref->{title}
        ? $arg_ref->{title}               : 'Literaturliste';
    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 1;
    my $subjectids_ref      = exists $arg_ref->{subjectids}
        ? $arg_ref->{subjectids}          : 1;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;

    # Schon vorhanden
    # DBI: "select id from litlist where userid = ? and title = ? and type = ?"
    my $litlist = $self->{schema}->resultset('Litlist')->search_rs(
        {
            userid => $self->{ID},
            title  => $title,
            type   => $type,
        }
    )->single();

    if ($litlist){
        return $litlist->id;
    }

    # DBI: "insert into litlist (userid,title,type) values (?,?,?)"
    # DBI: "select id from litlist where userid = ? and title = ? and type = ?"
    my $new_litlist = $self->{schema}->resultset('Litlist')->create(
        userid => $self->{ID},
        title  => $title,
        type   => $type,
    );

    my $litlistid;
    
    if ($new_litlist){
        $litlistid = $new_litlist->id;
    }
    
    # Litlist-ID bestimmen und zurueckgeben

    unless (ref($subjectids_ref) eq 'ARRAY') {
        $subjectids_ref = [ $subjectids_ref ];
    }

    if (@{$subjectids_ref}){
        foreach my $subjectid (@{$subjectids_ref}){
            # DBI "insert into litlist_subject (litlistid,subjectid) values (?,?)") or $logger->error($DBI::errstr);
            $new_litlist->insert_related('litlist_subjects',
                                         {
                    subjectid => $subjectid,
                }
            );
        }
    }

    return $litlistid;
}

sub del_litlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return if (!$litlistid);

    my $litlist = $self->{schema}->resultlist('Litlist')->search_rs(
        {
            id     => $litlistid,
            userid => $self->{ID},
        }
    );

    return unless ($litlist);

    # DBI: "delete from litlistitem where litlistid=?"
    $litlist->delete_related('litlistitems');

    # DBI: "delete from litlist_subject where litlistid=?"
    $litlist->delete_related('litlist_subjects');
    
    # DBI: "delete from litlist where id=?"
    $litlist->delete;

    return;
}

sub change_litlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;
    my $title               = exists $arg_ref->{title}
        ? $arg_ref->{title}               : 'Literaturliste';
    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : undef;
    my $lecture             = exists $arg_ref->{lecture}
        ? $arg_ref->{lecture}                : 0;
    my $subjectids_ref      = exists $arg_ref->{subjectids}
        ? $arg_ref->{subjectids}          : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return if (!$litlistid || !$title || !$type);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;

    my $litlist = $self->{schema}->resultlist('Litlist')->search_rs(
        {
            id     => $litlistid,
        }
    )->single();
    
    return unless ($litlist);

    # DBI: "update litlist set title=?, type=?, lecture=? where id=?"
    $litlist->update(
        {
            title   => $title,
            type    => $type,
            lecture => $lecture,
        }
    );
    
    unless (ref($subjectids_ref) eq 'ARRAY') {
        $subjectids_ref = [ $subjectids_ref ];
    }
    
    if (@{$subjectids_ref}){
        # DBI: "delete from litlist_subject where litlistid = ?"

        $litlist->delete_related('litlist_subjects');

        foreach my $subjectid (@{$subjectids_ref}){
            # DBI: "insert into litlist_subject (litlistid,subjectid) values (?,?)"
            $litlist->create_related('litlist_subjects',
                                     {
                                         subjectid => $subjectid,
                                     }      
                                 );
        }
    }

    return;
}

sub add_litlistentry {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "delete from litlistitem where litlistid=? and titid=? and titdb=?"
    my $litlistitem = $self->{schema}->search_rs({        
        litlistid => $litlistid,
        dbname    => $titdb,
        titleid   => $titid,
    });

    return if ($litlistitem);

    my $cached_title = OpenBib::Record::Title->new({ id => $titid, database => $titdb })->load_brief_record->to_json;
    
    # DBI: "insert into litlistitem (litlistid,titleid,dbname) values (?,?,?)"
    $self->{schema}->resultset('Litlistitem')->create(
        {
            litlistid  => $litlistid,
            dbname     => $titdb,
            titleid    => $titid,
            titlecache => $cached_title,
        }
    );

    return;
}

sub del_litlistentry {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;
    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return if (!$litlistid || !$titid || !$titdb);

    # DBI: "delete from litlistitem where litlistid=? and titleid=? and dbname=?"
    my $litlistitem = $self->{schema}->search_rs({        
        litlistid => $litlistid,
        dbname    => $titdb,
        titleid   => $titid,
    });

    if ($litlistitem){
        $litlistitem->delete;
    }

    return;
}

sub get_litlists {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return [] if (!$self->{ID});

    my $litlists_ref = [];

    # DBI: "select id from litlist where userid=?"
    my $litlists = $self->{schema}->resultset('Litlist')->search_rs(
        {
            userid => $self->{ID},
        }
    );

    foreach my $litlist ($litlists->all){
      push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->id});
    }
    
    return $litlists_ref;
}

sub get_recent_litlists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $count        = exists $arg_ref->{count}
        ? $arg_ref->{count}           : 5;

    my $subjectid      = exists $arg_ref->{subjectid}
        ? $arg_ref->{subjectid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $litlists;
    
    if ($subjectid){
        $litlists = $self->{schema}->resultset('Litlist')->search(
            {
                'subjectid.id'  => $subjectid,
                'me.type'       => 1,
            },
            {
#                select   => [ {distinct => 'me.id'} ],
                select   => [ 'me.id' ],
                as       => ['thislitlistid'],
                order_by => [ 'me.id DESC' ],
                rows     => $count,                
                prefetch => [{ 'litlist_subjects' => 'subjectid' }],
                join     => [ 'litlist_subjects' ],
            }
        );
    }
    else {
        $litlists = $self->{schema}->resultset('Litlist')->search(
            {
                'type' => 1,
            },
            {
                select   => ['id'],
                as       => ['thislitlistid'],
                order_by => [ 'id DESC' ],
                rows     => $count,

            }
        );

        # $sql_stmnt = "select id from litlist where type = 1";
    }

    my $litlists_ref = [];

    foreach my $litlist ($litlists->all){
        $logger->debug("Found Listlist with ID ".$litlist->get_column('thislitlistid'));
        push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->get_column('thislitlistid')});
    }
    
    return $litlists_ref;
}

sub get_public_litlists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $subjectid      = exists $arg_ref->{subjectid}
        ? $arg_ref->{subjectid}        : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $litlists;
    
    if ($subjectid){
        $litlists = $self->{schema}->resultset('Litlist')->search(
            {
                'subjectid.id'  => $subjectid,
                'me.type'       => 1,
            },
            {
#                select   => [ {distinct => 'me.id'} ],
                select   => [ 'me.id' ],
                as       => ['thislitlistid'],
                prefetch => [{ 'litlist_subjects' => 'subjectid' }],
                join     => [ 'litlist_subjects' ],
            }
        );

#        $sql_stmnt = "select distinct(ls.litlistid) as id from litlist_subject as ls, litlist as l where ls.subjectid = ? and ls.litlistid = l.id and l.type = 1";
#        push @sql_args, $subjectid;
    }
    else {
        $litlists = $self->{schema}->resultset('Litlist')->search(
            {
                'type' => 1,
            },
            {
                select   => ['id'],
                as       => ['thislitlistid'],
            }
        );

        # $sql_stmnt = "select id from litlist where type = 1";
    }

    my $litlists_ref = [];

    foreach my $litlist ($litlists->all){
      my $litlistid        = $litlist->get_column('thislitlistid');

      my $properties_ref = $self->get_litlist_properties({litlistid => $litlistid});
      push @$litlists_ref, $properties_ref if ($properties_ref->{itemcount});
    }

    # Sortieren nach Titeln via Schwartz'ian Transform
    
    my $sorted_litlists_ref = [];
    
    @{$sorted_litlists_ref} = map { $_->[0] }
        sort { $a->[1] cmp $b->[1] }
            map { [$_, lc($_->{title})] }
                @{$litlists_ref};
    
    return $sorted_litlists_ref;
}

sub get_other_litlists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $litlists_ref = {
        same_user     => [],
        same_title    => [],
    };

    return $litlists_ref if (!$litlistid);

    # Gleicher Nutzer
    # DBI: "select id,title from litlist where type = 1 and id != ? and userid in () order by title";

    my $inside_same_user = $self->{schema}->resultset('Litlist')->search_rs({ id => $litlistid});
    my $same_user = $self->{schema}->resultset('Litlist')->search_rs(
        {
            id   => { '!=' => $litlistid },
            type => 1,
            userid => { -in => $inside_same_user->get_column('userid')->as_query },
        }
    );
    
    foreach my $litlist ($same_user->all){
      my $litlistid        = $litlist->id;
      
      push @{$litlists_ref->{same_user}}, $self->get_litlist_properties({litlistid => $litlistid});
    }

    # Gleicher Titel
    # DBI: "select distinct b.litlistid from litlistitems as a left join litlistitems as b on a.titdb=b.titdb where a.titid=b.titid and a.litlistid=? and b.litlistid!=?";

    my $inside_same_title = $self->{schema}->resultset('Litlistitem')->search_rs({ litlistid => $litlistid});
    my $same_title = $self->{schema}->resultset('Litlistitem')->search_rs(
        {
            'me.litlistid'   => { '!=' => $litlistid },
            'litlistid.type' => 1,
            'me.titleid'     => { -in => $inside_same_title->get_column('titleid')->as_query },
            'me.dbname'      => { -in => $inside_same_title->get_column('dbname')->as_query },
        },
        {
            select => ['me.litlistid'],
            as     => ['thislitlistid'],
            join   => ['litlistid'],
        }
    );

    foreach my $litlist ($same_title->all){
        my $litlistid        = $litlist->litlistid;
        my $litlist_props    = $self->get_litlist_properties({litlistid => $litlistid});
        push @{$litlists_ref->{same_title}}, $litlist_props; # if ($litlist_props->{type} == 1);
    }

    return $litlists_ref;
}

sub get_litlistentries {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    my $sorttype            = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}            : undef;

    my $sortorder           = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select titleid,dbname,tstamp from litlistitem where litlistid=?"
    my $litlistitems = $self->{schema}->resultset('Litlistitem')->search_rs(
        {
            litlistid => $litlistid,
        }
    );

    my $recordlist = new OpenBib::RecordList::Title();

    foreach my $litlistitem ($litlistitems->all){
        my $titelidn  = decode_utf8($litlistitem->titleid);
        my $database  = decode_utf8($litlistitem->dbname);
        my $tstamp    = decode_utf8($litlistitem->tstamp);
        
        my $record = OpenBib::Record::Title->new({id =>$titelidn, database => $database})->load_brief_record;
        $record->{tstamp} = $tstamp;
        
        $recordlist->add($record);
    }
    
    $recordlist->sort({order=>$sortorder,type=>$sorttype});
        
    return $recordlist;
}

sub get_number_of_litlistentries {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(litlistid) as numofentries from litlistitem where litlistid=?"
    my $numofentries = $self->{schema}->resultset('Litlistitem')->search(
        {
            litlistid => $litlistid,
        }
    )->count;
    
    return $numofentries;
}

sub get_number_of_litlists {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(id) as numoflitlists from litlist where type = 1"
    my $public_lists = $self->{schema}->resultset('Litlist')->search(
        {
            type => 1,
        }
    )->count;
    
    # DBI: "select count(id) as numoflitlists from litlists where type = 2"
    my $private_lists = $self->{schema}->resultset('Litlist')->search(
        {
            type => 2,
        }
    )->count;

    return {
        public  => $public_lists,
        private => $private_lists,
    }
}

sub get_litlist_properties {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return {} if (!$litlistid);

    # DBI: "select * from litlist where id = ?"
    my $litlist = $self->{schema}->resultset('Litlist')->search_rs(
        {
            id => $litlistid,
        }   
    )->first;

    return {} if (!$litlist);

    my $title     = decode_utf8($litlist->title);
    my $type      = $litlist->type;
    my $lecture   = $litlist->lecture;
    my $tstamp    = $litlist->tstamp;
    my $userid    = $litlist->userid;
    my $itemcount = $self->get_number_of_litlistentries({litlistid => $litlistid});

    # DBI: "select s.* from litlist_subject as ls, subject as s where ls.litlistid=? and ls.subjectid=s.id"
    my $subjects = $self->{schema}->resultset('LitlistSubject')->search_rs(
        {
            'litlistid.id' => $litlistid,
        },
        {
            select => ['subjectid.id','subjectid.description','subjectid.name'],
            as     => ['thissubjectid','thissubjectdescription','thissubjectname'],
            
            join => ['litlistid','subjectid'],
        }
    );
    
    my $subjects_ref          = [];
    my $subject_selected_ref  = {};

    foreach my $subject ($subjects->all){
        my $subjectid   = $subject->get_column('thissubjectid');
        my $name        = $subject->get_column('thissubjectname');
        my $description = $subject->get_column('thissubjectdescription');

        $subject_selected_ref->{$subjectid}=1;
        push @{$subjects_ref}, {
            id          => $subjectid,
            name        => $name,
            description => $description,
            litlistcount => $self->get_number_of_litlists_by_subject({subjectid => $subjectid}),
        };
    }
    
    my $litlist_ref = {
			id               => $litlistid,
			userid           => $userid,
                        userrole         => $self->get_roles_of_user($userid),
			title            => $title,
			type             => $type,
                        lecture          => $lecture,
		        itemcount        => $itemcount,
			tstamp           => $tstamp,
                        subjects         => $subjects_ref,
                        subject_selected => $subject_selected_ref,
		       };

    return $litlist_ref;
}

sub get_subjects {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from subjects order by name"
    my $subjects = $self->{schema}->resultset('Subject')->search_rs(
        undef,        
        {
            'order_by' => ['name'],
        }
    );

    my $subjects_ref = [];
    
    foreach my $subject ($subjects->all){
        push @{$subjects_ref}, {
            id           => $subject->id,
            name         => decode_utf8($subject->name),
            description  => decode_utf8($subject->description),
            litlistcount => $self->get_number_of_litlists_by_subject({subjectid => $subject->id}),
        };
    }

    return $subjects_ref;
}

sub get_subjects_of_litlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $subjects = $self->{schema}->resultset('LitlistSubject')->search_rs(
        {
            'litlistid.id' => $litlistid,
        },
        {
            select => ['subjectid.id','subjectid.description','subjectid.name'],
            as     => ['thissubjectid','thissubjectdescription','thissubjectname'],
            
            join => ['litlistid','subjectid'],
        }
    );
    
    my $subjects_ref = [];
    
    foreach my $subject ($subjects->all){
        my $subjectid   = $subject->get_column('thissubjectid');
        my $name        = decode_utf8($subject->get_column('thissubjectname'));
        my $description = decode_utf8($subject->get_column('thissubjectdescription'));

        push @{$subjects_ref}, {
            id          => $subjectid,
            name        => $name,
            description => $description,
            litlistcount => $self->get_number_of_litlists_by_subject({subjectid => $subjectid}),
        };
    }

    return $subjects_ref;
}

sub get_classifications_of_subject {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $subjectid           = exists $arg_ref->{subjectid}
        ? $arg_ref->{subjectid}           : undef;

    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'BK';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return [] if (!defined $subjectid);

    # DBI: "select * from subjectclassification where subjectid = ? and type = ?"
    my $classifications = $self->{schema}->resultset('Subjectclassification')->search_rs(
        {
            subjectid => $subjectid,
            type      => $type,
        }   
    );
    
    my $classifications_ref = [];

    foreach my $classification ($classifications->all){
        push @{$classifications_ref}, $classification->classification;
    }

    $logger->debug("Got classifications ".YAML::Dump($classifications_ref));

    return $classifications_ref;
}

sub set_classifications_of_subject {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $subjectid           = exists $arg_ref->{subjectid}
        ? $arg_ref->{subjectid}           : undef;

    my $classifications_ref = exists $arg_ref->{classifications}
        ? $arg_ref->{classifications}     : undef;

    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'BK';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("Classifications4 ".YAML::Dump($classifications_ref));

    unless (ref($classifications_ref) eq 'ARRAY') {
        $classifications_ref = [ $classifications_ref ];
    }

    # DBI: "delete from subjectclassification where subjectid=? and type = ?"
    my $subjectclassifications = $self->{schema}->resultset('Subjectclassification')->search_rs(
        {
            subjectid => $subjectid,
            type      => $type,
        }
    )->delete_all;

    foreach my $classification (@{$classifications_ref}){
        $logger->debug("Adding Classification $classification of type $type");
        
        # DBI: "insert into subjectclassification values (?,?,?);"
        $self->{schema}->resultset('Subjectclassification')->create(
            {
                classification => $classification,
                subjectid      => $subjectid,
                type           => $type,
            }
        );
    }
    
    return;
}

sub get_number_of_litlists_by_subject {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $subjectid           = exists $arg_ref->{subjectid}
        ? $arg_ref->{subjectid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $count_ref={};

    $self->{schema}->storage->debug(1);
    # DBI: "select count(distinct l2s.litlistid) as llcount from litlist_subject as l2s, litlist as l where l2s.litlistid=l.id and l2s.subjectid=? and l.type=1 and (select count(li.litlistid) > 0 from litlistitem as li where l2s.litlistid=li.litlistid)"
    $count_ref->{public} = $self->{schema}->resultset('Litlist')->search(
        {
            'subjectid.id'  => $subjectid,
            'me.type' => 1,
        },
        {
            prefetch => [{ 'litlist_subjects' => 'subjectid' }],
            join     => [ 'litlist_subjects', 'litlistitems' ],
        }
    )->count;

    # "select count(distinct litlistid) as llcount from litlist2subject as l2s where subjectid=? and (select count(li.litlistid) > 0 from litlistitems as li where l2s.litlistid=li.litlistid)"
    $count_ref->{all}=$self->{schema}->resultset('Litlist')->search(
        {
            'subjectid.id'  => $subjectid,
        },
        {
            prefetch => [{ 'litlist_subjects' => 'subjectid' }],
            join     => [ 'litlist_subjects', 'litlistitems' ],
        }
    )->count;

    $count_ref->{private} = $count_ref->{all} - $count_ref->{public};
    
    return $count_ref;
}

sub set_subjects_of_litlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    my $subjectids_ref      = exists $arg_ref->{subjectids}
        ? $arg_ref->{subjectids}          : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "delete from litlist_subject where litlistid=?"
    $self->{schema}->resultset('LitlistSubject')->search_rs(
        {
            litlistid => $litlistid,
        }   
    )->delete_all;
    
    # DBI: "insert into litlist_subject values (?,?);"

    foreach my $subjectid (@{$subjectids_ref}){
        $self->{schema}->resultset('LitlistSubject')->create(
            {
                litlistid => $litlistid,
                subjectid => $subjectid,
            }
        );
    }

    return;
}

sub get_subject {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id           = exists $arg_ref->{id}
        ? $arg_ref->{id}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from subject where id = ?"
    my $subject = $self->{schema}->resultset('Subject')->search_rs(
        {
            id => $id,
        }
    )->first;

    my $subject_ref = {};
    
    if ($subject){
        $subject_ref = {
            id           => $subject->id,
            name         => decode_utf8($subject->name),
            description  => decode_utf8($subject->description),
        };
    }

    return $subject_ref;
}

sub is_authenticated {
    my ($self)=@_;

    return (exists $self->{ID})?1:0;
}

sub litlist_is_public {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return ($self->get_litlist_properties({ litlistid => $litlistid })->{type} == 1)?1:0;;
}

sub get_litlist_owner {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return $self->get_litlist_properties({ litlistid => $litlistid })->{userid};
}

sub get_litlists_of_tit {
    my ($self,$arg_ref)=@_;

    my $titid               = exists $arg_ref->{titid}
        ? $arg_ref->{titid}               : undef;
    my $titdb               = exists $arg_ref->{titdb}
        ? $arg_ref->{titdb}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return [] if (!$titid || !$titdb);

    # DBI: "select ll.* from litlistitem as lli, litlist as ll where ll.id=lli.litlistid and lli.titleid=? and lli.dbname=?") or $logger->error($DBI::errstr);

    my $litlists = $self->{schema}->resultset('Litlistitem')->search_rs(
        {
            'me.titleid'       => $titid,
            'me.dbname'        => $titdb,
        },
        {
            select => ['me.litlistid','litlistid.userid','litlistid.type'],
            as     => ['thislitlistid','thisuserid','thistype'],
            join   => ['litlistid']
        }
    );

    my $litlists_ref = [];

    foreach my $litlist ($litlists->all){
        if ((defined $self->{ID} && defined $litlist->get_column('thisuserid') && $self->{ID} eq $litlist->get_column('userid')) || (defined $litlist->get_column('thistype') && $litlist->get_column('thistype') eq "1")){
            push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->get_column('thislitlistid')});
        };
    }

    return $litlists_ref;
}

sub get_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $recordlist = new OpenBib::RecordList::Title();

    # DBI: "select * from collection where userid = ? order by dbname"
    my $collectionitems = $self->{schema}->resultset('Collection')->search_rs(
        userid => $self->{ID},
    );

    foreach my $collectionitem ($collectionitems->all){
        my $database  = decode_utf8($collectionitem->dbname);
        my $singleidn = decode_utf8($collectionitem->titleid);
        
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $singleidn}));
    }
    
    return $recordlist;
}

sub add_item_to_collection {
    my ($self,$arg_ref)=@_;

    my $userid         = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;

    my $item_ref       = exists $arg_ref->{item}
        ? $arg_ref->{item}                 : undef;
    
#    my ($self,$userid,$item_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
    
    # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
    my $have_title = $self->{schema}->resultset('Collection')->search_rs(
        {
            userid  => $thisuserid,
            dbname  => $item_ref->{dbname},
            titleid => $item_ref->{singleidn},
        }
    )->count;

    if (!$have_title) {
        my $cached_title = new OpenBib::Record::Title({ database => $item_ref->{dbname} , id => $item_ref->{singleidn}});
        $cached_title->load_brief_record->to_json;

        $logger->debug("Adding Title to Collection: $cached_title");

        # DBI "insert into treffer values (?,?,?,?)"
        $self->{schema}->resultset('Collection')->create(
            {
                userid     => $thisuserid,
                dbname     => $item_ref->{dbname},
                titleid    => $item_ref->{singleidn},
                titlecache => $cached_title,
            }
        );
    }

    return ;
}

sub delete_item_from_collection {
    my ($self,$arg_ref)=@_;

    my $userid         = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;

    my $item_ref       = exists $arg_ref->{item}
        ? $arg_ref->{item}                 : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    # DBI: "delete from collection where userid = ? and dbname = ? and titleid = ?"
    $self->{schema}->resultset('Collection')->search_rs(
        {
            userid  => $thisuserid,
            dbname  => $item_ref->{dbname},
            titleid => $item_ref->{singleidn},
        }
    )->delete;
    
    return ;
}

sub logintarget_exists {
    my ($self,$arg_ref)=@_;

    my $description         = exists $arg_ref->{description}
        ? $arg_ref->{description}               : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(description) as rowcount from logintarget where description = ?"
    my $targetcount = $self->{schema}->resultset('Logintarget')->search_rs(
        {
            description => $description,
        }   
    )->count;

    return $targetcount;
}

sub delete_logintarget {
    my ($self,$targetid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $self->{schema}->resultset('Logintarget')->search_rs(
        {
            id => $targetid,
        }   
    )->delete;

    return;
}

sub new_logintarget {
    my ($self,$arg_ref)=@_;
    
    my $hostname         = exists $arg_ref->{hostname}
        ? $arg_ref->{hostname}               : undef;

    my $port             = exists $arg_ref->{port}
        ? $arg_ref->{port}                   : undef;

    my $username         = exists $arg_ref->{username}
        ? $arg_ref->{username}               : undef;

    my $dbname           = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}                 : undef;

    my $description      = exists $arg_ref->{description}
        ? $arg_ref->{description}            : undef;

    my $type             = exists $arg_ref->{type}
        ? $arg_ref->{type}                   : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "insert into logintarget (hostname,port,user,db,description,type) values (?,?,?,?,?,?)"
    $self->{schema}->resultset('Logintarget')->create(
        {
            hostname    => $hostname,
            port        => $port,
            userid      => $self->get_userid_for_username($username),
            dbname      => $dbname,
            description => $description,
            type        => $type,
        }   
    );

    return;
}

sub update_logintarget {
    my ($self,$arg_ref)=@_;
    
    my $hostname         = exists $arg_ref->{hostname}
        ? $arg_ref->{hostname}               : undef;

    my $port             = exists $arg_ref->{port}
        ? $arg_ref->{port}                   : undef;

    my $username         = exists $arg_ref->{username}
        ? $arg_ref->{username}               : undef;

    my $dbname           = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}                 : undef;

    my $description      = exists $arg_ref->{description}
        ? $arg_ref->{description}            : undef;

    my $type             = exists $arg_ref->{type}
        ? $arg_ref->{type}                   : undef;

    my $targetid         = exists $arg_ref->{targetid}
        ? $arg_ref->{targetid}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "update logintarget set hostname = ?, port = ?, user =?, db = ?, description = ?, type = ? where id = ?"
    $self->{schema}->resultset('Logintarget')->search_rs(
        {
            id => $targetid,
        }   
    )->single()->update(
        {
            hostname    => $hostname,
            port        => $port,
            userid      => $self->get_userid_for_username($username),
            dbname      => $dbname,
            description => $description,
            type        => $type,
        }
    );

    $logger->debug("Logintarget updated");
    
    return;
}

sub update_userrole {
    my ($self,$userinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "delete from user_role where userid=?"
    $self->{schema}->resultset('UserRole')->search_rs(
        userid => $userinfo_ref->{id},
    )->delete_all;
    
    foreach my $roleid (@{$userinfo_ref->{roles}}){
        $logger->debug("Adding Role $roleid to user $userinfo_ref->{id}");

        # DBI: "insert into user_role values (?,?)"
        $self->{schema}->resultset('UserRole')->search_rs(
            userid => $userinfo_ref->{id},
        )->create(
            {
                userid => $userinfo_ref->{id},
                roleid => $roleid,
            }
        );
    }

    return;
}

sub dbprofile_exists {
    my ($self,$profilename)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select profileid,count(profileid) as rowcount from user_profile where userid = ? and profilename = ? group by profileid"
    my $profile = $self->{schema}->resultset('UserSearchprofile')->search_rs(
        {
            profilename => $profilename,
            userid      => $self->{ID},
        }   

    )->first;

    if ($profile){
        return $profile->profileid,
    }
    else {
        return 0;
    }
    
}

sub new_dbprofile {
    my ($self,$profilename,$databases_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $dbs_as_json = encode_json $databases_ref;

    my $searchprofile = $self->{schema}->resultset('Searchprofile')->search(
        {
            databases_as_json => $dbs_as_json,
        }
    )->single();

    my $searchprofileid;
    
    if ($searchprofile){
        $searchprofileid = $searchprofile->id;
    }
    else {
            my $new_searchprofile = $self->{schema}->resultset('Searchprofile')->create(
                {
                    databases_as_json => $dbs_as_json,
                }
            );

            $searchprofileid = $new_searchprofile->id;
    }

    # DBI: "insert into user_profile values (NULL,?,?)"
    my $new_profile = $self->{schema}->resultset('UserSearchprofile')->create(
        {
            profilename => $profilename,
            userid      => $self->{ID},
            profileid   => $searchprofileid,
        }
    );
    
    return $new_profile->id;
}

sub update_dbprofile {
    my ($self,$profileid,$profilename,$databases_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $dbs_as_json = encode_json $databases_ref;

    my $searchprofile = $self->{schema}->resultset('Searchprofile')->search(
        {
            databases_as_json => $dbs_as_json,
        }
    )->single();

    my $searchprofileid;
    
    if ($searchprofile){
        $searchprofileid = $searchprofile->id;
    }
    else {
            my $new_searchprofile = $self->{schema}->resultset('Searchprofile')->create(
                {
                    databases_as_json => $dbs_as_json,
                }
            );

            $searchprofileid = $new_searchprofile->id;
    }

    # DBI: "insert into user_profile values (NULL,?,?)"
    my $profile = $self->{schema}->resultset('UserSearchprofile')->search_rs(
        {
            userid      => $self->{ID},
            id          => $profileid,

        }
    )->single()->update(
        {
            profilename => $profilename,
            userid      => $self->{ID},
            profileid   => $searchprofileid,
        }
    );
    
    return;
}

sub delete_dbprofile {
    my ($self,$profileid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "delete from user_profile where userid = ? and profileid = ?"
    $self->{schema}->resultset('UserSearchprofile')->search_rs(
        {
            id     => $profileid,
            userid => $self->{ID},
        }
    )->delete;

    return;
}

sub wipe_account {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        id => $self->{ID}
    );

    if ($userinfo){
        # Zuerst werden die Datenbankprofile geloescht
        # DBI: "delete from profildb using profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid=profildb.profilid"
        $userinfo->delete_related('user_searchprofiles');
    
        # .. dann die Suchfeldeinstellungen
        # DBI: "delete from searchfield where userid = ?"
        $userinfo->delete_related('searchfields');

        # .. dann die Livesearcheinstellungen
        # DBI: "delete from livesearch where userid = ?"
        $userinfo->delete_related('livesearches');

        # .. dann die Merkliste
        # DBI: "delete from collection where userid = ?"
        $userinfo->delete_related('collections');

        # .. dann die Verknuepfung zur Session
        # DBI: "delete from user_session where userid = ?"
        $userinfo->delete_related('user_sessions');
    
        # und schliesslich der eigentliche Benutzereintrag
        # DBI: "delete from userinfo where userid = ?"
        $userinfo->delete;
    }
    
    return;
}

sub disconnect_session {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        id => $self->{ID}
    )->first;

    if ($userinfo){
        # Verbindung zur Session loeschen
        # DBI: "delete from user_session where userid = ?"
        $userinfo->delete_related('user_sessions');
    }
   
    return;
}

sub connect_session {
    my ($self,$arg_ref)=@_;
    
    my $sessionID        = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}              : undef;

    my $userid           = exists $arg_ref->{userid}
        ? $arg_ref->{userid}                 : undef;

    my $targetid         = exists $arg_ref->{targetid}
        ? $arg_ref->{targetid}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # Es darf keine Session assoziiert sein. Daher stumpf loeschen

    # DBI: "delete from user_session where sessionid = ?"
    $self->{schema}->resultset('UserSession')->search_rs(
        {
            'sid.sessionid' => $sessionID,
        },
        {
            join => ['sid'],
        }
    )->delete;
    
    my $sid = $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $sessionID })->single->id;

    # DBI: "insert into user_session values (?,?,?)"
    $self->{schema}->resultset('UserSession')->create(
        {
            sid      => $sid,
            userid   => $userid,
            targetid => $targetid,
        },
        {
            join => ['sid'],
        }
    );

    return;
}

sub delete_private_info {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "update userinfo set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where id = ?"
    $self->{schema}->resultset('Userinfo')->search_rs(
        id => $self->{ID},
    )->single()->update(
        {
            nachname   => '',
            vorname    => '',
            strasse    => '',
            ort        => '',
            plz        => '',
            soll       => '',
            gut        => '',
            avanz      => '',
            branz      => '',
            bsanz      => '',
            vmanz      => '',
            maanz      => '',
            vlanz      => '',
            sperre     => '',
            sperrdatum => '',
            gebdatum   => '',
        }
    );
   
    return;
}

sub set_private_info {
    my ($self,$username,$userinfo_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "update userinfo set nachname = ?, vorname = ?, strasse = ?, ort = ?, plz = ?, soll = ?, gut = ?, avanz = ?, branz = ?, bsanz = ?, vmanz = ?, maanz = ?, vlanz = ?, sperre = ?, sperrdatum = ?, gebdatum = ? where username = ?"
    #      $userinfo_ref->{'Nachname'},$userinfo_ref->{'Vorname'},$userinfo_ref->{'Strasse'},$userinfo_ref->{'Ort'},$userinfo_ref->{'PLZ'},$userinfo_ref->{'Soll'},$userinfo_ref->{'Guthaben'},$userinfo_ref->{'Avanz'},$userinfo_ref->{'Branz'},$userinfo_ref->{'Bsanz'},$userinfo_ref->{'Vmanz'},$userinfo_ref->{'Maanz'},$userinfo_ref->{'Vlanz'},$userinfo_ref->{'Sperre'},$userinfo_ref->{'Sperrdatum'},$userinfo_ref->{'Geburtsdatum'},$username
    $self->{schema}->resultset('Userinfo')->search_rs(
        id => $self->get_username_of_userid($self->{ID}),
    )->single()->update(
        {
            nachname   => $userinfo_ref->{'Nachname'},
            vorname    => $userinfo_ref->{'Vorname'},
            strasse    => $userinfo_ref->{'Strasse'},
            ort        => $userinfo_ref->{'Ort'},
            plz        => $userinfo_ref->{'PLZ'},
            soll       => $userinfo_ref->{'Soll'},
            gut        => $userinfo_ref->{'Guthaben'},
            avanz      => $userinfo_ref->{'Avanz'},
            branz      => $userinfo_ref->{'Branz'},
            bsanz      => $userinfo_ref->{'Bsanz'},
            vmanz      => $userinfo_ref->{'Vmanz'},
            maanz      => $userinfo_ref->{'Maanz'},
            vlanz      => $userinfo_ref->{'Vlanz'},
            sperre     => $userinfo_ref->{'Sperre'},
            sperrdatum => $userinfo_ref->{'Sperrdatum'},
            gebdatum   => $userinfo_ref->{'Geburtsdatum'},
        }
    );

    return;
}

sub get_info {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return {} if (!defined $dbh);

    my $userresult=$dbh->prepare("select * from userinfo where id = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    my $res=$userresult->fetchrow_hashref();
    
    my $userinfo_ref={};

    $userinfo_ref->{'id'}         = decode_utf8($self->{'ID'});
    $userinfo_ref->{'nachname'}   = decode_utf8($res->{'nachname'});
    $userinfo_ref->{'vorname'}    = decode_utf8($res->{'vorname'});
    $userinfo_ref->{'strasse'}    = decode_utf8($res->{'strasse'});
    $userinfo_ref->{'ort'}        = decode_utf8($res->{'ort'});
    $userinfo_ref->{'plz'}        = decode_utf8($res->{'plz'});
    $userinfo_ref->{'soll'}       = decode_utf8($res->{'soll'});
    $userinfo_ref->{'gut'}        = decode_utf8($res->{'gut'});
    $userinfo_ref->{'avanz'}      = decode_utf8($res->{'avanz'}); # Ausgeliehene Medien
    $userinfo_ref->{'branz'}      = decode_utf8($res->{'branz'}); # Buchrueckforderungen
    $userinfo_ref->{'bsanz'}      = decode_utf8($res->{'bsanz'}); # Bestellte Medien
    $userinfo_ref->{'vmanz'}      = decode_utf8($res->{'vmanz'}); # Vormerkungen
    $userinfo_ref->{'maanz'}      = decode_utf8($res->{'maanz'}); # ueberzogene Medien
    $userinfo_ref->{'vlanz'}      = decode_utf8($res->{'vlanz'}); # Verlaengerte Medien
    $userinfo_ref->{'sperre'}     = decode_utf8($res->{'sperre'});
    $userinfo_ref->{'sperrdatum'} = decode_utf8($res->{'sperrdatum'});
    $userinfo_ref->{'email'}      = decode_utf8($res->{'email'});
    $userinfo_ref->{'gebdatum'}   = decode_utf8($res->{'gebdatum'});
    $userinfo_ref->{'username'}   = decode_utf8($res->{'username'});
    $userinfo_ref->{'password'}   = decode_utf8($res->{'password'});
    $userinfo_ref->{'masktype'}   = decode_utf8($res->{'masktype'});
    $userinfo_ref->{'autocompletiontype'} = decode_utf8($res->{'autocompletiontype'});
    $userinfo_ref->{'spelling_as_you_type'}   = decode_utf8($res->{'spelling_as_you_type'});
    $userinfo_ref->{'spelling_resultlist'}    = decode_utf8($res->{'spelling_resultlist'});
    # Rollen

    $userresult=$dbh->prepare("select * from role,user_role where user_role.userid = ? and user_role.roleid=role.id") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    while (my $res=$userresult->fetchrow_hashref()){
        $userinfo_ref->{role}{$res->{name}}=1;
    }

    return $userinfo_ref;
}

sub get_all_roles {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    $logger->debug("Getting roles");

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return [] if (!defined $dbh);

    my $userresult=$dbh->prepare("select * from role") or $logger->error($DBI::errstr);
    $userresult->execute() or $logger->error($DBI::errstr);

    my $roles_ref = [];
    while (my $res=$userresult->fetchrow_hashref()){
        push @$roles_ref, {
            id   => $res->{id},
            role => $res->{name},
        };
    }

    $logger->debug("Available roles ".YAML::Dump($roles_ref));
    
    return $roles_ref;
}

sub get_roles_of_user {
    my ($self,$userid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    $logger->debug("Getting roles");

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return [] if (!defined $dbh);

    my $userresult=$dbh->prepare("select role.name from role,user_role where user_role.userid=? and user_role.roleid=role.id") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);

    my $role_ref = {};
    while (my $res=$userresult->fetchrow_hashref()){
        $role_ref->{$res->{name}}=1;
    }

    $logger->debug("Available roles ".YAML::Dump($role_ref));
    
    return $role_ref;
}

sub fieldchoice_exists {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);
    
    # Ueberpruefen, ob der Benutzer schon ein Suchprofil hat
    my $userresult=$dbh->prepare("select count(userid) as rowcount from searchfield where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);
    my $res=$userresult->fetchrow_hashref;

    my $rows=$res->{rowcount};
    
    return ($rows > 0)?1:0;
}

sub set_default_fieldchoice {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);

    my $request2=$dbh->prepare("insert into searchfield values (?,?,?)") or $logger->error($DBI::errstr);
    $request2->execute($userid,'freesearch',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'title',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'titlestring',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'classification',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'corporatebody',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'subject',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'source',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'person',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'year',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'isbn',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'issn',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'content',1) or $logger->error($DBI::errstr);
    $request2->execute($userid,'mediatype',0) or $logger->error($DBI::errstr);
    $request2->execute($userid,'mark',1) or $logger->error($DBI::errstr);
    
    return;
}

sub get_fieldchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("select * from searchfield where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    my $searchfield_ref = {};
        
    while (my $result=$targetresult->fetchrow_hashref()){
        my $field  = $result->{searchfield};
        my $active = $result->{active};

        $searchfield_ref->{$field}=$active;
    };
    
    $targetresult->finish();
    
    return $searchfield_ref;
}

sub set_fieldchoice {
    my ($self,$arg_ref)=@_;

    my $fs        = exists $arg_ref->{fs}
        ? $arg_ref->{fs}              : undef;
    my $hst       = exists $arg_ref->{hst}
        ? $arg_ref->{hst}             : undef;
    my $hststring = exists $arg_ref->{hststring}
        ? $arg_ref->{hststring}       : undef;
    my $verf      = exists $arg_ref->{verf}
        ? $arg_ref->{verf}            : undef;
    my $kor       = exists $arg_ref->{kor}
        ? $arg_ref->{kor}             : undef;
    my $swt       = exists $arg_ref->{swt}
        ? $arg_ref->{swt}             : undef;
    my $notation  = exists $arg_ref->{notation}
        ? $arg_ref->{notation}        : undef;
    my $isbn      = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}            : undef;
    my $issn      = exists $arg_ref->{issn}
        ? $arg_ref->{issn}            : undef;
    my $sign      = exists $arg_ref->{sign}
        ? $arg_ref->{sign}            : undef;
    my $mart      = exists $arg_ref->{mart}
        ? $arg_ref->{mart}            : undef;
    my $ejahr     = exists $arg_ref->{ejahr}
        ? $arg_ref->{ejahr}           : undef;
    my $inhalt    = exists $arg_ref->{inhalt}
        ? $arg_ref->{inhalt}          : undef;
    my $gtquelle  = exists $arg_ref->{gtquelle}
        ? $arg_ref->{gtquelle}        : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    $logger->debug("update searchfield set searchfield = ?, active = ? where userid = ? - $fs,$hst,$hststring,$verf,$kor,$swt,$notation,$isbn,$issn,$sign,$mart,$ejahr,$inhalt,$gtquelle,$self->{ID}");

    my $request2=$dbh->prepare("update searchfield set searchfield = ?, active = ? where userid = ?") or $logger->error($DBI::errstr);

    $request2->execute($self->{ID},'freesearch',$fs) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'title',$hst) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'titlestring',$hststring) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'classification',$notation) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'corporatebody',$kor) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'subject',$swt) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'source',$gtquelle) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'person',$verf) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'year',$ejahr) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'isbn',$isbn) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'issn',$issn) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'content',$inhalt) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'mediatype',$mart) or $logger->error($DBI::errstr);
    $request2->execute($self->{ID},'mark',$sign) or $logger->error($DBI::errstr);

    $request2->finish();
    
    return;
}

sub get_spelling_suggestion {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from userinfo where userid = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->first;

    my $spelling_suggestion_ref = {};
    
    if ($userinfo){
        $spelling_suggestion_ref->{as_you_type} = decode_utf8($userinfo->{'spelling_as_you_type'});
        $spelling_suggestion_ref->{resultlist}  = decode_utf8($userinfo->{'spelling_resultlist'});
    };
    
    return $spelling_suggestion_ref;
}

sub set_default_spelling_suggestion {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->single;

    if ($userinfo){
        # DBI: "update userinfo (spelling_as_you_type,spelling_resultlist) values (0,0) where userid=?"
        $userinfo->update(
            {
                spelling_as_you_type => 0,
                spelling_resultlist  => 0,
            }
        );
    }
    
    return;
}

sub set_spelling_suggestion {
    my ($self,$arg_ref)=@_;

    my $as_you_type = exists $arg_ref->{as_you_type}
        ? $arg_ref->{as_you_type}     : undef;
    my $resultlist  = exists $arg_ref->{resultlist}
        ? $arg_ref->{resultlist}      : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->single;

    if ($userinfo){
        # DBI: "update userinfo set spelling_as_you_type = ?, spelling_resultlist = ?,$self->{ID}"
        $userinfo->update(
            {
                spelling_as_you_type => $as_you_type,
                spelling_resultlist  => $resultlist,
            }
        );
    }
    
    return;
}

sub get_livesearch {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("select * from livesearch where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    my $livesearch_ref = {};
    
    while (my $result=$targetresult->fetchrow_hashref()){
        my $searchfield = $result->{searchfield};
        my $exact       = $result->{exact};
        my $active      = $result->{active};

        $livesearch_ref->{$searchfield}={
            active => $active,
            exact  => $exact,
        };
    }
    
    $targetresult->finish();
    
    return $livesearch_ref;
}

sub livesearch_exists {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);
    
    my $userresult=$dbh->prepare("select count(userid) as rowcount from livesearch where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);
    my $res=$userresult->fetchrow_hashref;

    my $rows=$res->{rowcount};
    
    return ($rows > 0)?1:0;
}

sub set_default_livesearch {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);

    # DBI: "insert into livesearch values (?,0,0,0,1)"
    my $userresult=$dbh->prepare("insert into livesearch values (?,?,?)") or $logger->error($DBI::errstr);
    $userresult->execute($userid,'freesearch',0,1,0) or $logger->error($DBI::errstr);
    $userresult->execute($userid,'person',0,1,0) or $logger->error($DBI::errstr);
    $userresult->execute($userid,'subject',0,1,0) or $logger->error($DBI::errstr);
    
    return;
}

sub set_livesearch {
    my ($self,$arg_ref)=@_;

    my $fs    = exists $arg_ref->{fs}
        ? $arg_ref->{fs}      : undef;
    my $verf  = exists $arg_ref->{verf}
        ? $arg_ref->{verf}    : undef;
    my $swt   = exists $arg_ref->{swt}
        ? $arg_ref->{swt}     : undef;
    my $exact = exists $arg_ref->{exact}
        ? $arg_ref->{exact}   : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    $logger->debug("update livesearch set fs = ?, verf = ?, swt = ?, exact = ?, $self->{ID}");
    my $targetresult=$dbh->prepare("update livesearch set searchfield = ?, exact = ?, active = ? where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute('freesearch',$exact,$fs,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->execute('person',$exact,$verf,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->execute('subject',$exact,$swt,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->finish();
    
    return;
}

sub get_bibsonomy {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select bibsonomy_sync,bibsonomy_user,bibsonomy_key from userinfo where userid = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->first;

    my $bibsonomy_ref = {
        sync      => '',
        user      => '',
        key       => '',
    };
    
    if ($userinfo){        
        $bibsonomy_ref->{sync} = decode_utf8($userinfo->bibsonomy_sync);
        $bibsonomy_ref->{user} = decode_utf8($userinfo->bibsonomy_user);
        $bibsonomy_ref->{key}  = decode_utf8($userinfo->bibsonomy_key);
    };
    
    return $bibsonomy_ref;
}

sub set_bibsonomy {
    my ($self,$arg_ref)=@_;

    my $sync      = exists $arg_ref->{sync}
        ? $arg_ref->{sync}            : 'off';
    my $user      = exists $arg_ref->{user}
        ? $arg_ref->{user}            : undef;
    my $key       = exists $arg_ref->{key}
        ? $arg_ref->{key}             : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "update userinfo set bibsonomy_sync = ?, bibsonomy_user = ?, bibsonomy_key = ? where userid = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->single()->update(
        {
            bibsonomy_sync => $sync,
            bibsonomy_user => $user,
            bibsonomy_key  => $key,
            
        }
    );

    return;
}

sub sync_all_to_bibsonomy {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $bibsonomy_ref = $self->get_bibsonomy;

    return unless ($bibsonomy_ref->{user} || $bibsonomy_ref->{key});
        
    my $bibsonomy = new OpenBib::BibSonomy({api_user => $bibsonomy_ref->{user}, api_key => $bibsonomy_ref->{key}});

    $logger->debug("Syncing all to BibSonomy");
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    my $username  = $self->get_username;
    my $titles_ref = $self->get_private_tagged_titles({username => $username});

    foreach my $database (keys %$titles_ref){
        foreach my $id (keys %{$titles_ref->{$database}}){
            my $tags_ref   = $titles_ref->{$database}{$id}{tags};
            my $visibility =
                ($titles_ref->{$database}{$id}{visibility} == 1)?'public':
                    ($titles_ref->{$database}{$id}{visibility} == 2)?'private':'private';

            # 1) Ueberpruefen, ob Titel bereits existiert

            my $record    = new OpenBib::Record::Title({ database => $database , id => $id})->load_full_record;
            my $bibkey    = $record->to_bibkey;
            
            my $posts_ref = $bibsonomy->get_posts({ user => 'self', bibkey => $bibkey});

            $logger->debug("Bibkey: $bibkey");
            # 2) ja, dann unangetastet lassen
            if (exists $posts_ref->{recordlist} && @{$posts_ref->{recordlist}}){
                $logger->debug("NOT syncing Record $database:$id");
            }
            # 3) nein, dann mit Tags neu anlegen
            else {
                if (@$tags_ref){
                    $logger->debug("Syncing Record $database:$id");
                    $logger->debug("Tags".YAML::Dump($tags_ref));
                    $bibsonomy->new_post({ tags => $tags_ref, record => $record, visibility => $visibility });
                }
            }
        }
    }
    
    return;
}

sub get_id_of_selfreg_logintarget {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("select id from logintarget where type = 'self'") or $logger->error($DBI::errstr);
    $userresult->execute() or $logger->error($DBI::errstr);
    
    my $res=$userresult->fetchrow_hashref();
    
    my $targetid = $res->{'id'};

    return $targetid;
}

sub get_mask {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid=($userid)?$userid:$self->{ID};
    
    # Bestimmen des Recherchemasken-Typs
    my $userresult=$dbh->prepare("select masktype from userinfo where id = ?") or $logger->error($DBI::errstr);

    $userresult->execute($thisuserid) or $logger->error($DBI::errstr);

    my $maskresult=$userresult->fetchrow_hashref();
    my $masktype = decode_utf8($maskresult->{'masktype'});

    $userresult->finish();

    return ($masktype)?$masktype:'simple';
}

sub set_mask {
    my ($self,$masktype)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    # Update des Recherchemasken-Typs
    my $targetresult=$dbh->prepare("update userinfo set masktype = ? where id = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($masktype,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->finish();

    return;
}

sub get_autocompletion {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid=($userid)?$userid:$self->{ID};
    
    # Bestimmen des Recherchemasken-Typs
    my $userresult=$dbh->prepare("select autocompletiontype from userinfo where id = ?") or $logger->error($DBI::errstr);

    $userresult->execute($thisuserid) or $logger->error($DBI::errstr);

    my $maskresult=$userresult->fetchrow_hashref();
    my $autocompletiontype = decode_utf8($maskresult->{'autocompletiontype'});

    $userresult->finish();

    return ($autocompletiontype)?$autocompletiontype:'livesearch';
}

sub set_autocompletion {
    my ($self,$autocompletiontype)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    $logger->debug("Setting autocompletion type to $autocompletiontype");
    
    # Update des Autovervollstaendigung-Typs
    my $targetresult=$dbh->prepare("update userinfo set autocompletiontype = ? where id = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($autocompletiontype,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->finish();

    return;
}

sub is_admin {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Statischer Admin-User aus portal.yml
    return 1 if ($self->{ID} eq $config->{adminuser});

    # Sonst: Normale Nutzer mit der der Admin-Role
    
    # DBI: "select count(ur.userid) as rowcount from userrole as ur, role as r where ur.userid = ? and r.role = 'admin' and r.id=ur.roleid"
    my $count = $self->{schema}->resultset('UserRole')->search(
        {
            'roleid.name' => 'admin',
            'userid.id'   => $self->{ID},
        },
        {
            join => ['roleid','userid'],
        }
    )->count;
    
    return $count;
}

sub del_subject {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("delete from subject where id = ?") or $logger->error($DBI::errstr);
    $request->execute($id) or $logger->error($DBI::errstr);
    $request->finish();

    return;
}

sub update_subject {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $name                     = exists $arg_ref->{name}
        ? $arg_ref->{name}                : undef;
    my $description              = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $classifications_ref      = exists $arg_ref->{classifications}
        ? $arg_ref->{classifications}     : [];
    my $type                      = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'BK';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst die Aenderungen in der Tabelle Profileinfo vornehmen
    
    my $request=$self->{dbh}->prepare("update subject set name = ?, description = ? where id = ?") or $logger->error($DBI::errstr);
    $request->execute(encode_utf8($name),encode_utf8($description),$id) or $logger->error($DBI::errstr);
    $request->finish();

    if (@{$classifications_ref}){       
        $logger->debug("Classifications5 ".YAML::Dump($classifications_ref));

        OpenBib::User->set_classifications_of_subject({
            subjectid       => $id,
            classifications => $classifications_ref,
            type            => $type,
        });
    }

    return;
}

sub new_subject {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $name                   = exists $arg_ref->{name}
        ? $arg_ref->{name}                : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select count(*) as rowcount from subject where name = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($name) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;
    my $rows=$res->{rowcount};
    
    if ($rows > 0) {
      $idnresult->finish();
      return -1;
    }
    
    $idnresult=$self->{dbh}->prepare("insert into subject (name,description) values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute(encode_utf8($name),encode_utf8($description)) or $logger->error($DBI::errstr);
    
    return 1;
}

sub subject_exists {
    my ($self,$name) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select count(*) as rowcount from subjects where name = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($name) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;
    my $rows=$res->{rowcount};
    
    return ($rows > 0)?1:0;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $roleid                 = exists $arg_ref->{roleid}
        ? $arg_ref->{roleid}              : undef;
    my $username               = exists $arg_ref->{username}
        ? $arg_ref->{username}            : undef;
    my $surname                = exists $arg_ref->{surname}
        ? $arg_ref->{surname}             : undef;
    my $commonname             = exists $arg_ref->{commonname}
        ? $arg_ref->{commonname}          : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $userlist_ref = [];
    
    my $sql_stmt = "select id from userinfo where ";
    my @sql_where = ();
    my @sql_args = ();
    
    if ($roleid) {
        $sql_stmt = "select userid from user_role where roleid=?";
        push @sql_args, $roleid;
    }
    else {
        if ($username) {
            push @sql_where,"username = ?";
            push @sql_args, $username;
        }
        
        if ($commonname) {
            push @sql_where, "nachname = ?";
            push @sql_args, $commonname;
        }
        
        if ($surname) {
            push @sql_where, "vorname = ?";
            push @sql_args, $surname;
        }
        
        $sql_stmt.=join(" and ",@sql_where);
    }
    
    
    $logger->debug($sql_stmt);
    
    my $request = $self->{dbh}->prepare($sql_stmt);
    $request->execute(@sql_args);
    
    $logger->debug("Looking up user $username/$surname/$commonname");
    
    while (my $result=$request->fetchrow_hashref){
        $logger->debug("Found ID $result->{id}");
        my $single_user = new OpenBib::User({ID => $result->{id}});
        push @$userlist_ref, $single_user->get_info;
    }

    return $userlist_ref;
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    eval {
        # Verbindung zur SQL-Datenbank herstellen
        $self->{dbh}
            = OpenBib::Database::DBI->connect("DBI:$config->{systemdbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect to database $config->{systemdbname}");
    }
    
    $self->{dbh}->{RaiseError} = 1;

    eval {        
        $self->{schema} = OpenBib::Database::System->connect("DBI:$config->{systemdbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);

    };

    if ($@){
        $logger->fatal("Unable to connect to database $config->{systemdbname}");
    }

    return;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    return unless ($config->{memcached});
    
    # Verbindung zu Memchached herstellen
    $self->{memc} = new Cache::Memcached($config->{memcached});

    if (!$self->{memc}->set('isalive',1)){
        $logger->fatal("Unable to connect to memcached");
    }

    return;
}

1;
