
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    # DBI: "select loginname,pin from user where userid = ?"
    my $credentials = $self->{schema}->resultset('Userinfo')->search(
        {
            id => $thisuserid,
        }
    )->single;

    if ($credentials){
        return ($credentials->loginname,$credentials->pin);
    }
    else {
        return (undef,undef);
    }
}

sub set_credentials {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $loginname   = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}             : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($loginname){
        # DBI: "update userinfo set pin = ? where loginname = ?"
        my $userinfo = $self->{schema}->resultset('Userinfo')->search(
            {
                loginname => $loginname,
            }
        )->update({ pin => $password });
    }
    elsif ($self->{ID}) {
        # DBI: "update userinfo set pin = ? where id = ?"
        my $userinfo = $self->{schema}->resultset('Userinfo')->search(
            {
                id => $self->{ID},
            }
        )->update({ pin => $password });
    }
    else {
        $logger->error("Neither loginname nor userid given");
    }

    return;
}

sub user_exists {
    my ($self,$loginname)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from user where loginname = ?"
    my $count = $self->{schema}->resultset('Userinfo')->search({ loginname => $loginname})->count;
    
    return $count;    
}

sub add {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $loginname   = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}             : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}              : undef;

    my $email       = exists $arg_ref->{email}
        ? $arg_ref->{email}                 : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "insert into user values (NULL,'',?,?,'','','','',0,'','','','','','','','','','','',?,'','','','','')"
    $self->{schema}->resultset('Userinfo')->create({
        loginname => $loginname,
        pin       => $password,
        email     => $email,
    });
    
    return;
}

sub add_confirmation_request {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $loginname   = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}             : undef;

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
        loginname => $loginname,
        pin       => $password,
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

    my ($loginname,$password);
    
    if ($confirmationinfo){
        $loginname = $confirmationinfo->loginname;
        $password  = $confirmationinfo->password;
    }
    
    my $confirmation_info_ref = {
        loginname => $loginname,
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

    # DBI: "select loginname from user where userid = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID},
        }
    )->single;

    my $username;
    
    if ($userinfo){
        $username=decode_utf8($userinfo->loginname);
    }
    
    return $username;
}

sub get_username_for_userid {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select loginname from user where userid = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            id => $userid,
        }
    )->single;

    my $username;

    if ($userinfo){
        $username = decode_utf8($userinfo->loginname);
    }
    
    return $username;
}

sub get_userid_for_username {
    my ($self,$username)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select userid from user where loginname = ?"
    my $userinfo = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            loginname => $username,
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
    )->update({
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
            select => 'targetid.type',
            as     => 'thistype',
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $idnresult=$dbh->prepare("select profilename from userdbprofile where profilid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profileid) or $logger->error($DBI::errstr);
      
    my $result=$idnresult->fetchrow_hashref();
    
    my $profilename = decode_utf8($result->{'profilename'});

    $idnresult->finish();

    return $profilename;
}

sub get_profiledbs_of_profileid {
    my ($self,$profileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    my $idnresult=$dbh->prepare("select profildb.dbname as dbname from profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid = ? and userdbprofile.profilid=profildb.profilid order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$profileid) or $logger->error($DBI::errstr);

    my @profiledbs=();
    while (my $result=$idnresult->fetchrow_hashref()){
        push @profiledbs, decode_utf8($result->{'dbname'});
    }
    
    $idnresult->finish();

    return @profiledbs;
}

sub get_number_of_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(*) as rowcount from treffer where userid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofitems = $res->{rowcount};
    $idnresult->finish();

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

    # DBI: "select count(distinct(loginname)) as rowcount from tittag"
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

    my $tag = $self->{schema}->resultset('Tag')->search_rs(
        {
            id => $tagid,
        }
    )->first;

    my $name;
    
    if ($tag){
        $name = $tag->name;
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    return undef if (!defined $tag);
    
    my $request=$dbh->prepare("select id from tags where tag=?") or $logger->error($DBI::errstr);
    $request->execute($tag) or $logger->error($DBI::errstr);
    my $result = $request->fetchrow_hashref();
    my $id     = $result->{id};

    $request->finish();

    return $id;
}

sub get_titles_of_tag {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $loginname   = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}             : undef;

    my $tagid       = exists $arg_ref->{tagid}
        ? $arg_ref->{tagid}                 : undef;

    my $database    = exists $arg_ref->{database}
        ? $arg_ref->{loginname}             : undef;

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
    
    if ($loginname) {
        $where_ref->{'userid.loginname'} = $loginname;
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
    
    if ($loginname) {
        $where_ref->{'userid.loginname'} = $loginname;
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
    my $numofprofiles = $self->{schema}->resultset('UserProfile')->search_rs(
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
    my $userprofiles = $self->{schema}->resultset('UserProfile')->search_rs(
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
    my $pin                 = exists $arg_ref->{pin}
        ? $arg_ref->{pin}                 : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select userid from user where loginname = ? and pin = ?"
    my $authentication = $self->{schema}->resultset('Userinfo')->search_rs(
        {
            loginname => $username,
            pin       => $pin,
        }
    )->single;
    
    my $userid = -1;

    if ($authentication){
        $userid = $authentication->id;
    }
  
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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;
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

    #return if (!$titid || !$titdb || !$loginname || !$tags);


    # Splitten der Tags
    my @taglist = split("\\s+",$tags);

    # Zuerst alle Verknuepfungen loeschen

    # DBI: "delete from tittag where loginname = ? and titid=? and titdb=?"
    $self->{schema}->resultset('TitTag')->search_rs(
        {
            'userid.loginname' => $loginname,
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
            #      "insert into tittag (tagid,titid,titisbn,titdb,loginname,type) values (?,?,?,?,?,?)"
            $new_tag->create_related(
                'tit_tags',
                {
                    titleid   => $titid,
                    titleisbn => $titisbn,
                    dbname    => $titdb,
                    userid    => $self->get_userid_for_username($loginname),
                    type      => $type,
                    
                }
            );
        }
        
        # Jetzt Verknuepfung mit Titel herstellen
        else {
            $logger->debug("Tag verhanden");
            
            # Neue Verknuepfungen eintragen
            $logger->debug("Verknuepfung zu Titel noch nicht vorhanden");

            # DBI: "insert into tittag (tagid,titid,titisbn,titdb,loginname,type) values (?,?,?,?,?,?)"
            $tag->create_related(
                'tit_tags',
                {
                    titleid   => $titid,
                    titleisbn => $titisbn,
                    dbname    => $titdb,
                    userid    => $self->get_userid_for_username($loginname),
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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

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
    # 3.) In tittag alle Vorkommen von oldid durch newid fuer loginname
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
        $request->execute($newtagid,$oldtagid,$self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);
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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    if ($tags){
        foreach my $tag (split("\\s+",$tags)){
            my $tagid = $self->get_id_of_tag({tag => $tag});
            my $request=$dbh->prepare("delete from tit_tag where titleid=? and dbname=? and userid=? and tagid=?") or $logger->error($DBI::errstr);
            $request->execute($titid,$titdb,$self->get_userid_for_username($loginname),$tagid) or $logger->error($DBI::errstr);
        }
    }
    else {
        my $request=$dbh->prepare("delete from tittag where titleid=? and dbname=? and userid=?") or $logger->error($DBI::errstr);
        $request->execute($titid,$titdb,$self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);
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

    #return if (!$titid || !$titdb || !$loginname || !$tags);

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

    #return if (!$titid || !$titdb || !$loginname || !$tags);

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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.id,t.name,tt.type from tag as t,tit_tag as tt where tt.userid=? and tt.titleid=? and tt.dbname=? and tt.tagid = t.id") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($loginname),$titid,$titdb) or $logger->error($DBI::errstr);

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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("loginname: $loginname");

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.name, t.id, count(tt.tagid) as tagcount from tag as t, tit_tag as tt where t.id=tt.tagid and tt.userid=? group by tt.tagid order by t.name") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);

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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("loginname: $loginname");

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.name, tt.titleid, tt.dbname, tt.type from tag as t, tit_tag as tt where t.id=tt.tagid and tt.userid=? group by tt.tagid order by t.name") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);

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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;
    my $rating              = exists $arg_ref->{rating}
        ? $arg_ref->{rating}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen
    $rating   =~s/[^0-9]//g;
    
    # Zuerst alle Verknuepfungen loeschen
    my $request=$dbh->prepare("select reviewid from reviewrating where userid = ? and reviewid=?") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($loginname), $reviewid) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $thisreviewid = $result->{reviewid};

    # Review schon vorhanden?
    if ($thisreviewid){
        return 1; # Review schon vorhanden! Es darf aber pro Nutzer nur einer abgegeben werden;
    }
    else {
        $request=$dbh->prepare("insert into reviewrating (reviewid,userid,rating) values (?,?,?)") or $logger->error($DBI::errstr);
        $request->execute($reviewid,$self->get_userid_for_username($loginname),$rating) or $logger->error($DBI::errstr);
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

    my $request=$dbh->prepare("select * from review where id = ?") or $logger->error($DBI::errstr);
    $request->execute($reviewid) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    my $title     = decode_utf8($result->{title});
    my $titid     = $result->{titleid};
    my $titdb     = $result->{dbname};
    my $titisbn   = $result->{titleisbn};
    my $tstamp    = $result->{tstamp};
    my $nickname  = $result->{nickname};
    my $review    = $result->{review};
    my $rating    = $result->{rating};
    my $userid    = $result->{userid};

    my $loginname = $self->get_username_for_userid($userid);

    
    my $review_ref = {
			id               => $reviewid,
			userid           => $userid,
                        loginname        => $loginname,
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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;
    my $nickname            = exists $arg_ref->{nickname}
        ? $arg_ref->{nickname}            : undef;
    my $title              = exists $arg_ref->{title}
        ? $arg_ref->{title}               : undef;
    my $review              = exists $arg_ref->{review}
        ? $arg_ref->{review}              : undef;
    my $rating              = exists $arg_ref->{rating}
        ? $arg_ref->{rating}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $rating   =~s/[^0-9]//g;
    $review   =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $nickname =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    
    # Zuerst alle Verknuepfungen loeschen
    my $request=$dbh->prepare("select id from review where userid = ? and titleid=? and dbname=?") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($loginname), $titid, $titdb) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $reviewid = $result->{id};

    # Review schon vorhanden?
    if ($reviewid){
        $request=$dbh->prepare("update review set titleid=?, titleisbn=?, dbname=?, userid=?, nickname=?, title=?, review=?, rating=? where id=?") or $logger->error($DBI::errstr);
        $request->execute($titid,$titisbn,$titdb,$self->get_userid_for_username($loginname),encode_utf8($nickname),encode_utf8($title),encode_utf8($review),$rating,$reviewid) or $logger->error($DBI::errstr);
    }
    else {
        $request=$dbh->prepare("insert into review (titleid,titleisbn,dbname,userid,nickname,title,review,rating) values (?,?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
        $request->execute($titid,$titisbn,$titdb,$self->get_userid_for_username($loginname),encode_utf8($nickname),encode_utf8($title),encode_utf8($review),$rating) or $logger->error($DBI::errstr);
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id,nickname,userid,title,review,rating from review where titleid=? and dbname=?") or $logger->error($DBI::errstr);
    $request->execute($titid,$titdb) or $logger->error($DBI::errstr);

    my $request2=$dbh->prepare("select count(id) as votecount from reviewrating where reviewid=?  group by id") or $logger->error($DBI::errstr);
    my $request3=$dbh->prepare("select count(id) as posvotecount from reviewrating where reviewid=? and rating > 0 group by id") or $logger->error($DBI::errstr);

    my $reviewlist_ref = [];

    while (my $result=$request->fetchrow_hashref){
        my $userid    = decode_utf8($result->{userid});
        my $loginname = $self->get_username_of_userid($userid);
        my $nickname  = decode_utf8($result->{nickname});
        my $title     = decode_utf8($result->{title});
        my $review    = decode_utf8($result->{review});
        my $id        = $result->{id};
        my $rating    = $result->{rating};

        $request2->execute($id) or $logger->error($DBI::errstr);

        my $result2      = $request2->fetchrow_hashref;
        my $votecount = $result2->{votecount};

        my $posvotecount = 0;
        
        if ($votecount){
            $request3->execute($id) or $logger->error($DBI::errstr);
        
            my $result3      = $request3->fetchrow_hashref;
            $posvotecount = $result3->{posvotecount};
        }
        
        push @$reviewlist_ref, {
            id        => $id,
            loginname => $loginname,
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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id from review where titleid=? and dbname=? and userid=?") or $logger->error($DBI::errstr);
    $request->execute($titid,$titdb,$self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    my $reviewid=$result->{id};

    return $reviewid;
}

sub get_review_of_user {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                  = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id,titleid,dbname,nickname,userid,title,review,rating from review where id=? and userid=?") or $logger->error($DBI::errstr);
    $request->execute($id,$self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);

    $logger->debug("Getting Review $id for User $loginname");
    
    my $review_ref = {};

    while (my $result=$request->fetchrow_hashref){
        my $userid    = decode_utf8($result->{userid});
        my $loginname = $self->get_username_of_userid($userid);
        my $nickname  = decode_utf8($result->{nickname});
        my $title     = decode_utf8($result->{title});
        my $review    = decode_utf8($result->{review});
        my $id        = $result->{id};
        my $titid     = $result->{titleid};
        my $titdb     = $result->{dbname};
        my $rating    = $result->{rating};

        $review_ref = {
            id        => $id,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
            nickname  => $nickname,
            title     => $title,
            review    => $review,
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
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("delete from review where id=? and userid=?") or $logger->error($DBI::errstr);
    $request->execute($id,$self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);

    return;
}

sub get_reviews {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $loginname           = exists $arg_ref->{loginname}
        ? $arg_ref->{loginname}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id,titleid,dbname,nickname,userid,title,review,rating from review where userid=?") or $logger->error($DBI::errstr);
    $request->execute($self->get_userid_for_username($loginname)) or $logger->error($DBI::errstr);

    my $reviewlist_ref = [];

    while (my $result=$request->fetchrow_hashref){
        my $userid    = decode_utf8($result->{userid});
        my $loginname = $self->get_username_of_userid($userid);
        my $nickname  = decode_utf8($result->{nickname});
        my $title     = decode_utf8($result->{title});
        my $review    = decode_utf8($result->{review});
        my $id        = $result->{id};
        my $titid     = $result->{titleid};
        my $titdb     = $result->{dbname};
        my $rating    = $result->{rating};

        push @$reviewlist_ref, {
            id        => $id,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    

    # Schon vorhanden
    my $request=$dbh->prepare("select id from litlist where userid = ? and title = ? and type = ?");
    $request->execute($self->{ID},$title,$type);

    my $result=$request->fetchrow_hashref;
    my $litlistid = $result->{id};

    return $litlistid if ($litlistid);

    $request=$dbh->prepare("insert into litlist (userid,title,type) values (?,?,?)") or $logger->error($DBI::errstr);
    $request->execute($self->{ID},$title,$type) or $logger->error($DBI::errstr);
    
    # Litlist-ID bestimmen und zurueckgeben

    $request=$dbh->prepare("select id from litlist where userid = ? and title = ? and type = ?");
    $request->execute($self->{ID},$title,$type);

    $result=$request->fetchrow_hashref;
    $litlistid = $result->{id};

    unless (ref($subjectids_ref) eq 'ARRAY') {
        $subjectids_ref = [ $subjectids_ref ];
    }

    if (@{$subjectids_ref}){
        $request=$dbh->prepare("insert into litlist_subject (litlistid,subjectid) values (?,?)") or $logger->error($DBI::errstr);

        foreach my $subjectid (@{$subjectids_ref}){
            $request->execute($litlistid,$subjectid) or $logger->error($DBI::errstr);
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$litlistid);

    my $litlist_properties_ref = $self->get_litlist_properties({litlistid => $litlistid});

    return unless ($litlist_properties_ref->{userid} eq $self->{ID});
    
    my $request=$dbh->prepare("delete from litlistitem where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("delete from litlist where id=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("delete from litlist_subject where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$litlistid || !$title || !$type);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    
    my $request=$dbh->prepare("update litlist set title=?, type=?, lecture=? where id=?") or $logger->error($DBI::errstr);
    $request->execute($title,$type,,$lecture,$litlistid) or $logger->error($DBI::errstr);

    unless (ref($subjectids_ref) eq 'ARRAY') {
        $subjectids_ref = [ $subjectids_ref ];
    }
    
    if (@{$subjectids_ref}){
        $request=$dbh->prepare("delete from litlist_subject where litlistid = ?") or $logger->error($DBI::errstr);
        $request->execute($litlistid) or $logger->error($DBI::errstr);

        $request=$dbh->prepare("insert into litlist_subject (litlistid,subjectid) values (?,?)") or $logger->error($DBI::errstr);

        foreach my $subjectid (@{$subjectids_ref}){
            $request->execute($litlistid,$subjectid) or $logger->error($DBI::errstr);
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$litlitid );

    my $request=$dbh->prepare("delete from litlistitem where litlistid=? and titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid,$titid,$titdb) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("insert into litlistitem (litlistid,titleid,dbname) values (?,?,?)") or $logger->error($DBI::errstr);
    $request->execute($litlistid,$titid,$titdb) or $logger->error($DBI::errstr);

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$litlistid || !$titid || !$titdb);

    my $request=$dbh->prepare("delete from litlistitem where litlistid=? and titleid=? and dbname=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid,$titid,$titdb) or $logger->error($DBI::errstr);

    return;
}

sub get_litlists {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    return [] if (!$self->{ID});

    my $sql_stmnt = "select id from litlist where userid=?";

    my $request=$dbh->prepare($sql_stmnt) or $logger->error($DBI::errstr);
    $request->execute($self->{ID}) or $logger->error($DBI::errstr);

    my $litlists_ref = [];

    while (my $result=$request->fetchrow_hashref){
      my $litlistid        = $result->{id};
      
      push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlistid});
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

    my $litlists_ref = [];

    my $litlist_not_empty = $self->{schema}->resultset('Litlistitem')->search(
        {
            'count(litlistid)' => { '>', 0 },
        }
    );
    
    if ($subjectid){
        # DBI: "select distinct(ls.litlistid) as id from litlist2subject as ls, litlists as l where ls.subjectid = ? and ls.litlistid = l.id and l.type = 1 and (select count(litlistid) from litlistitems where litlistid=l.id)  > 0 order by l.id DESC limit $count"
        my $litlists = $self->{schema}->resultset('LitlistSubject')->search(
            {
                'subjectid.id'  => $subjectid,
                'me.litlistid'  => 'litlistitems.litlistid',

                'litlistid.type' => 1,
                'me.litlistid' => { '-in' => $litlist_not_empty->get_column('litlistid')->as_query },
#                'count(litlistitem.id)' => { '>', 0},
            },
            {
                group_by => [ 'me.litlistid' ],
                having   => \[ 'count(litlistitems.litlistid) > ?', [ count => 0 ] ], #$litlist_not_empty->get_column('litlistid')->as_query,

                select   => ['litlistid.id'],
                as       => ['thislitlistid'],
                order_by => [ 'litlistid.id DESC' ],
                rows     => $count,
                prefetch => [ { 'litlistid' => 'litlistitems' } ],
                join     => [ 'subjectid', 'litlistid' ],
            }
        );
        
        foreach my $litlist ($litlists->all){
            push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->get_column('thislitlistid')});
        }
    }
    else {
        # DBI: "select l.id from litlists as l where l.type = 1 and (select count(litlistid) from litlistitems where litlistid=l.id)  > 0 order by id DESC limit $count";
        my $litlists = $self->{schema}->resultset('Litlist')->search(
            {
                'me.type' => 1,
                'me.id'   => 'litlistitems.litlistid',
#                'me.id'   => { '-in' => $litlist_not_empty->get_column('litlistid')->as_query },
#                'count(litlistitems.id)' => { '>', 0},
            },
            {
                group_by => [ 'me.id' ],
                having   => \[ 'count(litlistitems.litlistid) > ?', [ count => 0 ] ], #$litlist_not_empty->get_column('litlistid')->as_query,
            
                select   => ['me.id'],
                as       => ['thislitlistid'],
                order_by => [ 'me.id DESC' ],
                rows     => $count,
                join     => [ 'litlistitems' ],
            }
        );
        
        foreach my $litlist ($litlists->all){
            push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->get_column('thislitlistid')});
        }
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    my $sql_stmnt = "";
    my @sql_args  = ();
    
    if ($subjectid){
        $sql_stmnt = "select distinct(ls.litlistid) as id from litlist_subject as ls, litlist as l where ls.subjectid = ? and ls.litlistid = l.id and l.type = 1";
        push @sql_args, $subjectid;
    }
    else {
        $sql_stmnt = "select id from litlist where type = 1";
    }

    $logger->debug($sql_stmnt);
    
    my $request=$dbh->prepare($sql_stmnt) or $logger->error($DBI::errstr);
    $request->execute(@sql_args) or $logger->error($DBI::errstr);

    my $litlists_ref = [];

    while (my $result=$request->fetchrow_hashref){
      my $litlistid        = $result->{id};

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    my $litlists_ref = {
        same_user     => [],
        same_title    => [],
    };

    return $litlists_ref if (!defined $dbh || !$litlistid);

    # Gleicher Nutzer
    my $sql_stmnt = "select id,title from litlist where type = 1 and id != ? and userid in (select userid from litlist where id = ?) order by title";

    my $request=$dbh->prepare($sql_stmnt) or $logger->error($DBI::errstr);
    $request->execute($litlistid,$litlistid) or $logger->error($DBI::errstr);

    while (my $result=$request->fetchrow_hashref){
      my $litlistid        = $result->{id};
      
      push @{$litlists_ref->{same_user}}, $self->get_litlist_properties({litlistid => $litlistid});
    }

    # Gleicher Titel
    $sql_stmnt = "select distinct b.litlistid from litlistitems as a left join litlistitems as b on a.titdb=b.titdb where a.titid=b.titid and a.litlistid=? and b.litlistid!=?";

    $request=$dbh->prepare($sql_stmnt) or $logger->error($DBI::errstr);
    $request->execute($litlistid,$litlistid) or $logger->error($DBI::errstr);


    while (my $result=$request->fetchrow_hashref){
      my $litlistid        = $result->{litlistid};
      my $litlist_props    = $self->get_litlist_properties({litlistid => $litlistid});
      push @{$litlists_ref->{same_title}}, $litlist_props if ($litlist_props->{type} == 1);
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$litlistid);

    my $request=$dbh->prepare("select titleid,dbname,tstamp from litlistitem where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    my $recordlist = new OpenBib::RecordList::Title();

    while (my $result=$request->fetchrow_hashref){
      my $titelidn  = decode_utf8($result->{titleid});
      my $database  = decode_utf8($result->{dbname});
      my $tstamp    = decode_utf8($result->{tstamp});
      
      my $dbh
	= DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
	    or $logger->error_die($DBI::errstr);

      my $record = OpenBib::Record::Title->new({id =>$titelidn, database => $database})->load_brief_record;
      $record->{tstamp} = $tstamp;

      $recordlist->add($record);

      $dbh->disconnect();
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    #return if (!$litlistid);

    my $request=$dbh->prepare("select count(litlistid) as numofentries from litlistitem where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    return $result->{numofentries};
}

sub get_number_of_litlists {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $request=$dbh->prepare("select count(id) as numoflitlists from litlist where type = 1") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    my $public_lists = $result->{numoflitlists};

    $request=$dbh->prepare("select count(id) as numoflitlists from litlists where type = 2") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);

    $result=$request->fetchrow_hashref;

    my $private_lists = $result->{numoflitlists};

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);

    return {} if (!$litlistid);

    my $request=$dbh->prepare("select * from litlist where id = ?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    my $title     = decode_utf8($result->{title});
    my $type      = $result->{type};
    my $lecture   = $result->{lecture};
    my $tstamp    = $result->{tstamp};
    my $userid    = $result->{userid};
    my $itemcount = $self->get_number_of_litlistentries({litlistid => $litlistid});

    $request=$dbh->prepare("select s.* from litlist_subject as ls, subject as s where ls.litlistid=? and ls.subjectid=s.id") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    my $subjects_ref          = [];
    my $subject_selected_ref  = {};

    while (my $result=$request->fetchrow_hashref){
        my $subjectid   = $result->{id};
        my $name        = decode_utf8($result->{name});
        my $description = decode_utf8($result->{description});

        $subject_selected_ref->{$subjectid}=1;
        push @{$subjects_ref}, {
            id          => $subjectid,
            name        => $name,
            description => $description,
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
    my $subjects = $self->{schema}->resultset('Subject')->search(
        undef,        
        {
            'order_by' => ['name'],
        }
    );

    my $subjects_ref = [];
    
    while (my $subject=$subjects->all){
        push @{$subjects_ref}, {
            id           => $subject->id,
            name         => decode_utf8($subject->name),
            description  => decode_utf8($subject->description),
            litlistcount => OpenBib::User->get_number_of_litlists_by_subject({subjectid => $subject->id}),
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    my $request=$dbh->prepare("select * from subject order by name") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);

    my $subjects_ref = [];
    
    while (my $result=$request->fetchrow_hashref){
        push @{$subjects_ref}, {
            id           => $result->{id},
            name         => decode_utf8($result->{name}),
            description  => decode_utf8($result->{description}),
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh || !defined $subjectid);

    my $request=$dbh->prepare("select * from subjectclassification where subjectid = ? and type = ?") or $logger->error($DBI::errstr);
    $request->execute($subjectid,$type) or $logger->error($DBI::errstr);

    my $classifications_ref = [];
    
    while (my $result=$request->fetchrow_hashref){
        push @{$classifications_ref}, $result->{classification};
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);
    
    $logger->debug("Classifications4 ".YAML::Dump($classifications_ref));

    unless (ref($classifications_ref) eq 'ARRAY') {
        $classifications_ref = [ $classifications_ref ];
    }

    my $request=$dbh->prepare("delete from subjectclassification where subjectid=? and type = ?") or $logger->error($DBI::errstr);
    $request->execute($subjectid,$type) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("insert into subjectclassification values (?,?,?);") or $logger->error($DBI::errstr);

    foreach my $classification (@{$classifications_ref}){
        $logger->debug("Adding Classification $classification of type $type");
        $request->execute($classification,$subjectid,$type) or $logger->error($DBI::errstr);
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

    my $config = OpenBib::Config->instance;
    
#    return { all => 0, public => 0, private => 0} if (!defined $dbh);

    my $count_ref={};

    # DBI: "select count(distinct l2s.litlistid) as llcount from litlist_subject as l2s, litlist as l where l2s.litlistid=l.id and l2s.subjectid=? and l.type=1 and (select count(li.litlistid) > 0 from litlistitem as li where l2s.litlistid=li.litlistid)"
    $count_ref->{public} = $self->{schema}->resultset('LitlistSubject')->search(
        {
            'subjectid.id'  => $subjectid,
            'litlistid.type' => 1,
            'count(litlistitems.id)' => { '>', 0},
        },
        {
            prefetch => [ { 'litlistid' => 'litlistitems' } ],
            join     => [ 'subjectid', 'litlistid' ],
        }
    )->count;

    # "select count(distinct litlistid) as llcount from litlist2subject as l2s where subjectid=? and (select count(li.litlistid) > 0 from litlistitems as li where l2s.litlistid=li.litlistid)"
    $count_ref->{all}=$self->{schema}->resultset('LitlistSubject')->search(
        {
            'subjectid.id'  => $subjectid,
            'count(litlistitems.id)' => { '>', 0},
        },
        {
            prefetch => [ { 'litlistid' => 'litlistitems' } ],
            join     => [ 'subjectid', 'litlistid' ],
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    my $request=$dbh->prepare("delete from litlist_subject where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("insert into litlist_subject values (?,?);") or $logger->error($DBI::errstr);

    foreach my $subjectid (@{$subjectids_ref}){
        $request->execute($litlistid,$subjectid) or $logger->error($DBI::errstr);
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);

    my $request=$dbh->prepare("select * from subject where id = ?") or $logger->error($DBI::errstr);
    $request->execute($id) or $logger->error($DBI::errstr);

    my $subject_ref;
    
    while (my $result=$request->fetchrow_hashref){
        $subject_ref = {
            id           => $result->{id},
            name         => decode_utf8($result->{name}),
            description  => decode_utf8($result->{description}),
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    return [] if (!$titid || !$titdb);

    my $request=$dbh->prepare("select ll.* from litlistitem as lli, litlist as ll where ll.id=lli.litlistid and lli.titleid=? and lli.dbname=?") or $logger->error($DBI::errstr);
    $request->execute($titid,$titdb) or $logger->error($DBI::errstr);

    my $litlists_ref = [];

    while (my $result=$request->fetchrow_hashref){
        if ((defined $self->{ID} && defined $result->{userid} && $self->{ID} eq $result->{userid}) || (defined $result->{type} && $result->{type} eq "1")){
            push @$litlists_ref, $self->get_litlist_properties({litlistid => $result->{id}});
        };
    }

    return $litlists_ref;
}

sub get_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $recordlist = new OpenBib::RecordList::Title();

    return $recordlist if (!defined $dbh);

    my $idnresult=$dbh->prepare("select * from collection where userid = ? order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    while(my $result = $idnresult->fetchrow_hashref){
        my $database  = decode_utf8($result->{'dbname'});
        my $singleidn = decode_utf8($result->{'titleid'});
        
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $singleidn}));
    }
    
    $idnresult->finish();
    
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

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
    my $userresult=$dbh->prepare("select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($thisuserid,$item_ref->{dbname},$item_ref->{singleidn}) or $logger->error($DBI::errstr);
    my $res  = $userresult->fetchrow_hashref;
    my $rows = $res->{rowcount};
    if ($rows <= 0) {
        my $cached_title = new OpenBib::Record::Title({ database => $item_ref->{dbname} , id => $item_ref->{singleidn}});
        $cached_title->load_brief_record->to_json;

        $logger->debug("Adding Title to Collection: $cached_title");

        $userresult=$dbh->prepare("insert into treffer values (?,?,?,?)") or $logger->error($DBI::errstr);
        $userresult->execute($thisuserid,$item_ref->{dbname},$item_ref->{singleidn},$cached_title) or $logger->error($DBI::errstr);
    }

    return ;
}

sub delete_item_from_collection {
    my ($self,$arg_ref)=@_;

    my $userid         = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;

    my $item_ref       = exists $arg_ref->{item}
        ? $arg_ref->{item}                 : undef;
    
#    my ($self,$userid,$item_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    my $idnresult=$dbh->prepare("delete from collection where userid = ? and dbname = ? and titleid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($thisuserid,$item_ref->{dbname},$item_ref->{singleidn}) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return ;
}

sub logintarget_exists {
    my ($self,$arg_ref)=@_;

    my $description         = exists $arg_ref->{description}
        ? $arg_ref->{description}               : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(description) as rowcount from logintarget where description = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($description) or $logger->error($DBI::errstr);
    
    my $res=$idnresult->fetchrow_hashref;
    my $rows=$res->{rowcount};

    return ($rows > 0)?1:0;
}

sub delete_logintarget {
    my ($self,$targetid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $idnresult=$dbh->prepare("delete from logintarget where id = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($targetid) or $logger->error($DBI::errstr);
    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $idnresult=$dbh->prepare("insert into logintarget (hostname,port,user,db,description,type) values (?,?,?,?,?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($hostname,$port,$username,$dbname,$description,$type) or $logger->error($DBI::errstr);
    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $idnresult=$dbh->prepare("update logintarget set hostname = ?, port = ?, user =?, db = ?, description = ?, type = ? where id = ?") or $logger->error($DBI::errstr); # 
    $idnresult->execute($hostname,$port,$username,$dbname,$description,$type,$targetid) or $logger->error($DBI::errstr);
    $idnresult->finish();

    $logger->debug("Logintarget updated");
    
    return;
}

sub update_userrole {
    my ($self,$userinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    my $del_request    = $dbh->prepare("delete from user_role where userid=?") or $logger->error($DBI::errstr); # 
    my $insert_request = $dbh->prepare("insert into user_role values (?,?)") or $logger->error($DBI::errstr); # 

    $del_request->execute($userinfo_ref->{id});
    
    foreach my $roleid (@{$userinfo_ref->{roles}}){
        $logger->debug("Adding Role $roleid to user $userinfo_ref->{id}");
        $insert_request->execute($userinfo_ref->{id},$roleid);
    }

    $del_request->finish();
    $insert_request->finish();

    return;
}

sub dbprofile_exists {
    my ($self,$profilename)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult=$dbh->prepare("select profileid,count(profileid) as rowcount from user_profile where userid = ? and profilename = ? group by profileid") or $logger->error($DBI::errstr);
    $profilresult->execute($self->{ID},$profilename) or $logger->error($DBI::errstr);
    my $res=$profilresult->fetchrow_hashref();
    
    my $numrows=$res->{rowcount};
    
    my $profilid="";
    
    if ($numrows > 0){
        return decode_utf8($res->{'profileid'});
    }

    return 0;
}

sub new_dbprofile {
    my ($self,$profilename)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult2=$dbh->prepare("insert into user_profile values (NULL,?,?)") or $logger->error($DBI::errstr);
    
    $profilresult2->execute($profilename,$self->{ID}) or $logger->error($DBI::errstr);
    $profilresult2=$dbh->prepare("select profileid from user_profile where userid = ? and profilename = ?") or $logger->error($DBI::errstr);
    
    $profilresult2->execute($self->{ID},$profilename) or $logger->error($DBI::errstr);
    my $res=$profilresult2->fetchrow_hashref();
    my $profilid = decode_utf8($res->{'profileid'});
    
    $profilresult2->finish();

    return $profilid;
}

sub delete_dbprofile {
    my ($self,$profileid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult=$dbh->prepare("delete from user_profile where userid = ? and profileid = ?") or $logger->error($DBI::errstr);
    $profilresult->execute($self->{ID},$profileid) or $logger->error($DBI::errstr);
    $profilresult->finish();
    
    return;
}

sub delete_profiledbs {
    my ($self,$profileid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult=$dbh->prepare("delete from profildb where profilid = ?") or $logger->error($DBI::errstr);
    $profilresult->execute($profileid) or $logger->error($DBI::errstr);
    $profilresult->finish();
    
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

    # Zuerst werden die Datenbankprofile geloescht
    my $userresult;
    $userresult=$dbh->prepare("delete from profildb using profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid=profildb.profilid") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    $userresult=$dbh->prepare("delete from user_profile where user_profile.userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    # .. dann die Suchfeldeinstellungen
    $userresult=$dbh->prepare("delete from searchfield where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    # .. dann die Livesearcheinstellungen
    $userresult=$dbh->prepare("delete from livesearch where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    # .. dann die Merkliste
    $userresult=$dbh->prepare("delete from collection where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    # .. dann die Verknuepfung zur Session
    $userresult=$dbh->prepare("delete from user_session where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    # und schliesslich der eigentliche Benutzereintrag
    $userresult=$dbh->prepare("delete from userinfo where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    $userresult->finish();
    
    return;
}

sub add_profiledb {
    my ($self,$profileid,$profiledb)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult=$dbh->prepare("insert into profildb (profilid,dbname) values (?,?)") or $logger->error($DBI::errstr);
    $profilresult->execute($profileid,$profiledb) or $logger->error($DBI::errstr);
    $profilresult->finish();
   
    return;
}

sub disconnect_session {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("delete from user_session where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    $userresult->finish();
   
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("update userinfo set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where id = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    $userresult->finish();
   
    return;
}

sub set_private_info {
    my ($self,$loginname,$userinfo_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("update userinfo set nachname = ?, vorname = ?, strasse = ?, ort = ?, plz = ?, soll = ?, gut = ?, avanz = ?, branz = ?, bsanz = ?, vmanz = ?, maanz = ?, vlanz = ?, sperre = ?, sperrdatum = ?, gebdatum = ? where loginname = ?") or $logger->error($DBI::errstr);
    $userresult->execute($userinfo_ref->{'Nachname'},$userinfo_ref->{'Vorname'},$userinfo_ref->{'Strasse'},$userinfo_ref->{'Ort'},$userinfo_ref->{'PLZ'},$userinfo_ref->{'Soll'},$userinfo_ref->{'Guthaben'},$userinfo_ref->{'Avanz'},$userinfo_ref->{'Branz'},$userinfo_ref->{'Bsanz'},$userinfo_ref->{'Vmanz'},$userinfo_ref->{'Maanz'},$userinfo_ref->{'Vlanz'},$userinfo_ref->{'Sperre'},$userinfo_ref->{'Sperrdatum'},$userinfo_ref->{'Geburtsdatum'},$loginname) or $logger->error($DBI::errstr);
    $userresult->finish();
   
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
    $userinfo_ref->{'loginname'}  = decode_utf8($res->{'loginname'});
    $userinfo_ref->{'password'}   = decode_utf8($res->{'pin'});
    $userinfo_ref->{'masktype'}   = decode_utf8($res->{'masktype'});
    $userinfo_ref->{'autocompletiontype'} = decode_utf8($res->{'autocompletiontype'});
    $userinfo_ref->{'spelling_as_you_type'}   = decode_utf8($res->{'spelling_as_you_type'});
    $userinfo_ref->{'spelling_resultlist'}    = decode_utf8($res->{'spelling_resultlist'});
    # Rollen

    $userresult=$dbh->prepare("select * from role,user_role where user_role.userid = ? and user_role.roleid=role.id") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    while (my $res=$userresult->fetchrow_hashref()){
        $userinfo_ref->{role}{$res->{role}}=1;
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
            role => $res->{role},
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

    my $userresult=$dbh->prepare("select role.role from role,user_role where user_role.userid=? and user_role.roleid=role.id") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);

    my $role_ref = {};
    while (my $res=$userresult->fetchrow_hashref()){
        $role_ref->{$res->{role}}=1;
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("select * from userinfo where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    my $result=$targetresult->fetchrow_hashref();

    my $spelling_suggestion_ref = {
        as_you_type => decode_utf8($result->{'spelling_as_you_type'}),
        resultlist  => decode_utf8($result->{'spelling_resultlist'}),
    };
    
    $targetresult->finish();
    
    return $spelling_suggestion_ref;
}

sub set_default_spelling_suggestion {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);

    my $userresult=$dbh->prepare("update userinfo (spelling_as_you_type,spelling_resultlist) values (0,0) where userid=?") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);
    
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    $logger->debug("update userinfo set spelling_as_you_type = ?, spelling_resultlist = ?,$self->{ID}");
    my $targetresult=$dbh->prepare("update userinfo set spelling_as_you_type = ?, spelling_resultlist = ? where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($as_you_type,$resultlist,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->finish();
    
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("select bibsonomy_sync,bibsonomy_user,bibsonomy_key from userinfo where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    my $result=$targetresult->fetchrow_hashref();

    my $bibsonomy_ref = {
        sync      => decode_utf8($result->{'bibsonomy_sync'}),
        user      => decode_utf8($result->{'bibsonomy_user'}),
        key       => decode_utf8($result->{'bibsonomy_key'}),
    };
    
    $targetresult->finish();
    
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("update userinfo set bibsonomy_sync = ?, bibsonomy_user = ?, bibsonomy_key = ? where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($sync,$user,$key,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->finish();
    
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

    my $loginname  = $self->get_username;
    my $titles_ref = $self->get_private_tagged_titles({loginname => $loginname});

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
            'roleid.role' => 'admin',
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
            push @sql_where,"loginname = ?";
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
        $self->{schema} = OpenBib::Database::System->connect("DBI:$config->{systemdbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},{'mysql_enable_utf8'    => 0,}) or $logger->error_die($DBI::errstr);

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
