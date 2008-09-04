#####################################################################
#
#  OpenBib::User
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

package OpenBib::User;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);

use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Database::DBI;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    if (defined $sessionID){
      my $userid = $self->get_userid_of_session($sessionID);
      if (defined $userid){
          $self->{ID} = $userid ;
          $logger->debug("Got UserID $userid for session $sessionID");
      }
  }

    return $self;
}

sub _new_instance {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    if (defined $sessionID){
        my $userid = $self->get_userid_of_session($sessionID);
        if (defined $userid){
            $self->{ID} = $userid ;
            $logger->debug("Got UserID $userid for session $sessionID");
        }
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    my $userresult = $dbh->prepare("select loginname,pin from user where userid = ?") or $logger->error($DBI::errstr);

    $userresult->execute($thisuserid) or $logger->error($DBI::errstr);
  
    my @cred=();
  
    while(my $res=$userresult->fetchrow_hashref()){
        $cred[0] = decode_utf8($res->{loginname});
        $cred[1] = decode_utf8($res->{pin});
    }

    $userresult->finish();

    return @cred;

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $sqlrequest="update user set pin = ? where ";

    my @sqlargs=();

    push @sqlargs, $password;
    
    if ($loginname){
        $sqlrequest.="loginname = ?";
        push @sqlargs, $loginname;
    }
    else {
        $sqlrequest.="userid = ?";
        push @sqlargs, $self->{ID};
    }
    
    my $userresult=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $userresult->execute(@sqlargs) or $logger->error($DBI::errstr);

    return;
}

sub user_exists {
    my ($self,$loginname)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("select count(userid) as rowcount from user where loginname = ?") or $logger->error($DBI::errstr);
    $userresult->execute($loginname) or $logger->error($DBI::errstr);
    my $res=$userresult->fetchrow_hashref;
    my $rows=$res->{rowcount};
    $userresult->finish();
    
    return ($rows <= 0)?0:1;    
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("insert into user values (NULL,'',?,?,'','','','',0,'','','','','','','','','','','',?,'','','','')") or $logger->error($DBI::errstr);
    $userresult->execute($loginname,$password,$email) or $logger->error($DBI::errstr);

    $userresult->finish();
    
    return;
}

sub get_username {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $userresult=$dbh->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);

    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    my $username="";
  
    while (my $res=$userresult->fetchrow_hashref()){
        $username = decode_utf8($res->{loginname});
    }

    $userresult->finish();

    return $username;
}

sub get_username_for_userid {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $userresult=$dbh->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);

    $userresult->execute($userid) or $logger->error($DBI::errstr);
  
    my $username="";
  
    while (my $res=$userresult->fetchrow_hashref()){
        $username = decode_utf8($res->{loginname});
    }

    $userresult->finish();

    return $username;
}

sub get_userid_for_username {
    my ($self,$username)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $userresult=$dbh->prepare("select userid from user where loginname = ?") or $logger->error($DBI::errstr);

    $userresult->execute($username) or $logger->error($DBI::errstr);
  
    my $userid="";
  
    while (my $res=$userresult->fetchrow_hashref()){
        $userid = decode_utf8($res->{userid});
    }

    $userresult->finish();

    return $userid;
}

sub get_userid_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$dbh->prepare("select userid from usersession where sessionid = ?") or $logger->error($DBI::errstr);

    $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
    my $userid=undef;
  
    while(my $res=$userresult->fetchrow_hashref()){
        $userid = decode_utf8($res->{'userid'});
    }

    return $userid;
}

sub clear_cached_userdata {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $request=$dbh->prepare("update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?") or die "$DBI::errstr";
    $request->execute($self->{ID}) or die "$DBI::errstr";
  
    $request->finish();

    return;
}

sub get_targetdb_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$dbh->prepare("select db from usersession,logintarget where usersession.sessionid = ? and usersession.targetid = logintarget.targetid") or $logger->error($DBI::errstr);

    $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
    my $targetdb="";
  
    while(my $res=$userresult->fetchrow_hashref()){
        $targetdb = decode_utf8($res->{'db'});
    }

    return $targetdb;
}

sub get_targettype_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$dbh->prepare("select type from usersession,logintarget where usersession.sessionid = ? and usersession.targetid = logintarget.targetid") or $logger->error($DBI::errstr);

    $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
    my $targettype="";
  
    while(my $res=$userresult->fetchrow_hashref()){
        $targettype = decode_utf8($res->{'type'});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(distinct(titid)) as rowcount from tittag") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numoftitles = $res->{rowcount};

    $idnresult->finish();

    return ($numoftitles)?$numoftitles:0;
}

sub get_number_of_tagging_users {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(distinct(loginname)) as rowcount from tittag") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofusers = $res->{rowcount};

    $idnresult->finish();

    return ($numofusers)?$numofusers:0;
}

sub get_number_of_tags {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(distinct(tagid)) as rowcount from tittag") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numoftags = $res->{rowcount};

    $idnresult->finish();

    return ($numoftags)?$numoftags:0;
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

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $sqlrequest="select count(distinct titid,titdb) as conncount from tittag where tagid=?";
    my @sqlargs = ();
    push @sqlargs, $tagid;
    
    if ($loginname) {
        $sqlrequest.=" and loginname=?";
        push @sqlargs, $loginname;
    }

    if ($database) {
        $sqlrequest.=" and titdb=?";
        push @sqlargs, $database;
    }
    
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute(@sqlargs);
    
    my $res=$request->fetchrow_hashref;
    my $hits = $res->{conncount};
    
    my $limits="";
    if ($hitrange > 0){
        $limits="limit $offset,$hitrange";
    }

    my $recordlist = new OpenBib::RecordList::Title();

    # Bestimmung der Titel
    $sqlrequest="select distinct titid,titdb from tittag where tagid=?";
    @sqlargs = ();
    push @sqlargs, $tagid;
    
    if ($loginname) {
        $sqlrequest.=" and loginname=?";
        push @sqlargs, $loginname;
    }

    if ($database) {
        $sqlrequest.=" and titdb=?";
        push @sqlargs, $database;
    }

    $sqlrequest.=" $limits";

    $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute(@sqlargs);
    
    while (my $res=$request->fetchrow_hashref){
        $recordlist->add(new OpenBib::Record::Title({database => $res->{titdb} , id => $res->{titid}}));
    }

    $recordlist->load_brief_records;
    
    $request->finish();
    
    return ($recordlist,$hits);
}

sub get_number_of_users {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(userid) as rowcount from user") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofusers = $res->{rowcount};

    $idnresult->finish();

    return ($numofusers)?$numofusers:0;
}

sub get_number_of_dbprofiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(profilid) as rowcount from userdbprofile") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofprofiles = $res->{rowcount};

    $idnresult->finish();

    return ($numofprofiles)?$numofprofiles:0;
}

sub get_number_of_collections {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(distinct(userid)) as rowcount from treffer") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofcollections = $res->{rowcount};

    $idnresult->finish();

    return ($numofcollections)?$numofcollections:0;
}

sub get_number_of_collection_entries {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(userid) as rowcount from treffer") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofentries = $res->{rowcount};

    $idnresult->finish();

    return ($numofentries)?$numofentries:0;
}

sub get_all_profiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return () if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select profilid, profilename from userdbprofile where userid = ? order by profilename") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    my @userdbprofiles=();
    while (my $result=$idnresult->fetchrow_hashref()){
        push @userdbprofiles, {
            profilid    => decode_utf8($result->{'profilid'}),
            profilename => decode_utf8($result->{'profilename'}),
        };
    }
    
    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $userresult=$dbh->prepare("select userid from user where loginname = ? and pin = ?") or $logger->error($DBI::errstr);
  
    $userresult->execute($username,$pin) or $logger->error($DBI::errstr);

    my $res=$userresult->fetchrow_hashref();

    my $userid = decode_utf8($res->{'userid'});

    $userresult->finish();

    return (defined $userid)?$userid:-1;
}

sub get_logintargets {
    my ($self) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);
    
    my $request=$dbh->prepare("select * from logintarget order by type DESC,description") or $logger->error($DBI::errstr);
    $request->execute() or $logger->error($DBI::errstr);
    
    my $logintargets_ref = [];
    while (my $result=$request->fetchrow_hashref()) {
        push @$logintargets_ref, {
            id          => decode_utf8($result->{'targetid'}),
            hostname    => decode_utf8($result->{'hostname'}),
            port        => decode_utf8($result->{'port'}),
            username    => decode_utf8($result->{'user'}),
            dbname      => decode_utf8($result->{'db'}),
            description => decode_utf8($result->{'description'}),
            type        => decode_utf8($result->{'type'}),
        };
    }
    $request->finish();

    return $logintargets_ref;
}

sub get_logintarget_by_id {
    my ($self,$targetid) = @_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);
    
    my $request=$dbh->prepare("select * from logintarget where targetid = ?") or $logger->error($DBI::errstr);
    $request->execute($targetid) or $logger->error($DBI::errstr);
    
    my $result=$request->fetchrow_hashref();
    
    my $logintarget_ref = {};

    $logintarget_ref = {
			   id          => decode_utf8($result->{'targetid'}),
			   hostname    => decode_utf8($result->{'hostname'}),
			   port        => decode_utf8($result->{'port'}),
			   username    => decode_utf8($result->{'user'}),
			   dbname      => decode_utf8($result->{'db'}),
			   description => decode_utf8($result->{'description'}),
			   type        => decode_utf8($result->{'type'}),
			  } if ($result->{'targetid'});

    $request->finish();

    $logger->debug("Getting Info for Targetid: $targetid -> Got: ".YAML::Dump($logintarget_ref));
    return $logintarget_ref;
}

sub get_number_of_logintargets {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);
    
    my $idnresult=$dbh->prepare("select count(targetid) as rowcount from logintarget") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numoftargets = $res->{rowcount};

    $idnresult->finish();

    return ($numoftargets)?$numoftargets:0;
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Splitten der Tags
    my @taglist = split("\\s+",$tags);

    # Zuerst alle Verknuepfungen loeschen
    my $request=$dbh->prepare("delete from tittag where loginname = ? and titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($loginname, $titid, $titdb) or $logger->error($DBI::errstr);

    my $tags_ref = [];
    foreach my $tag (@taglist){

        # Normierung
        $tag = OpenBib::Common::Util::grundform({
            content  => $tag,
            tagging  => 1,
        });

        push @$tags_ref, $tag;
        
        $request=$dbh->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
        $request->execute($tag) or $logger->error($DBI::errstr);

        my $result=$request->fetchrow_hashref;

        my $tagid=$result->{id};

        # Wenn Tag nicht existiert, dann kann alles eintragen werden (tags/tittag)
        
        if (!$tagid){
            $logger->debug("Tag $tag noch nicht verhanden");
            $request=$dbh->prepare("insert into tags (tag) values (?)") or $logger->error($DBI::errstr);
            $request->execute(encode_utf8($tag)) or $logger->error($DBI::errstr);

            $request=$dbh->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
            $request->execute(encode_utf8($tag)) or $logger->error($DBI::errstr);
            my $result=$request->fetchrow_hashref;
            my $tagid=$result->{id};

            $request=$dbh->prepare("insert into tittag (tagid,titid,titisbn,titdb,loginname,type) values (?,?,?,?,?,?)") or $logger->error($DBI::errstr);
            $request->execute($tagid,$titid,$titisbn,$titdb,$loginname,$type) or $logger->error($DBI::errstr);
        }
        
        # Jetzt Verknuepfung mit Titel herstellen
        else {
            $logger->debug("Tag verhanden");

            # Neue Verknuepfungen eintragen
            $logger->debug("Verknuepfung zu Titel noch nicht vorhanden");
            $request=$dbh->prepare("insert into tittag (tagid,titid,titisbn,titdb,loginname,type) values (?,?,?,?,?,?)") or $logger->error($DBI::errstr);
            $request->execute($tagid,$titid,$titisbn,$titdb,$loginname,$type) or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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

    my $request=$dbh->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
    $request->execute($oldtag) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $oldtagid = $result->{id};

    
    $request=$dbh->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
    $request->execute($newtag) or $logger->error($DBI::errstr);

    $result=$request->fetchrow_hashref;

    my $newtagid=$result->{id};

    # Wenn NewTag nicht existiert
        
    if (!$newtagid){
        $logger->debug("Tag $newtag noch nicht verhanden");
        $request=$dbh->prepare("insert into tags (tag) values (?)") or $logger->error($DBI::errstr);
        $request->execute(encode_utf8($newtag)) or $logger->error($DBI::errstr);

        $request=$dbh->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
        $request->execute(encode_utf8($newtag)) or $logger->error($DBI::errstr);
        my $result=$request->fetchrow_hashref;
        $newtagid=$result->{id};
    }

    if ($oldtagid && $newtagid){
        $request=$dbh->prepare("update tittag set tagid = ? where tagid = ? and loginname = ?") or $logger->error($DBI::errstr);
        $request->execute($newtagid,$oldtagid,$loginname) or $logger->error($DBI::errstr);
    }
    else {
        return 1;
    }

    return;
}

sub del_tags {
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("delete from tittag where titid=? and titdb=? and loginname=?") or $logger->error($DBI::errstr);
    $request->execute($titid,$titdb,$loginname) or $logger->error($DBI::errstr);

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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where tt.titdb=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.tag") or $logger->error($DBI::errstr);

    $request->execute($dbname) or $logger->error($DBI::errstr);

    my $taglist_ref = [];
    my $maxcount = 0;
    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{tag});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where tt.titid=? and tt.titdb=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.tag") or $logger->error($DBI::errstr);

    $request->execute($titid,$titdb) or $logger->error($DBI::errstr);

    my $taglist_ref = [];
    my $maxcount = 0;
    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{tag});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.id,t.tag,tt.type from tags as t,tittag as tt where tt.loginname=? and tt.titid=? and tt.titdb=? and tt.tagid = t.id") or $logger->error($DBI::errstr);
    $request->execute($loginname,$titid,$titdb) or $logger->error($DBI::errstr);

    my $taglist_ref = [];

    while (my $result=$request->fetchrow_hashref){
        my $tag  = decode_utf8($result->{tag});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where t.id=tt.tagid and tt.loginname=? group by tt.tagid order by t.tag") or $logger->error($DBI::errstr);
    $request->execute($loginname) or $logger->error($DBI::errstr);

    my $taglist_ref = [];
    my $maxcount = 0;
    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{tag});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select t.tag, tt.titid, tt.titdb, tt.type from tags as t, tittag as tt where t.id=tt.tagid and tt.loginname=? group by tt.tagid order by t.tag") or $logger->error($DBI::errstr);
    $request->execute($loginname) or $logger->error($DBI::errstr);

    my $taglist_ref = {};

    while (my $result=$request->fetchrow_hashref){
        my $tag       = decode_utf8($result->{tag});
        my $id        = $result->{titid};
        my $database  = $result->{titdb};
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen
    $rating   =~s/[^0-9]//g;
    
    # Zuerst alle Verknuepfungen loeschen
    my $request=$dbh->prepare("select reviewid from reviewratings where loginname = ? and reviewid=?") or $logger->error($DBI::errstr);
    $request->execute($loginname, $reviewid) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $thisreviewid = $result->{reviewid};

    # Review schon vorhanden?
    if ($thisreviewid){
        return 1; # Review schon vorhanden! Es darf aber pro Nutzer nur einer abgegeben werden;
    }
    else {
        $request=$dbh->prepare("insert into reviewratings (reviewid,loginname,rating) values (?,?,?)") or $logger->error($DBI::errstr);
        $request->execute($reviewid,$loginname,$rating) or $logger->error($DBI::errstr);
    }

    return;
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $rating   =~s/[^0-9]//g;
    $review   =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $nickname =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    
    # Zuerst alle Verknuepfungen loeschen
    my $request=$dbh->prepare("select id from reviews where loginname = ? and titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($loginname, $titid, $titdb) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $reviewid = $result->{id};

    # Review schon vorhanden?
    if ($reviewid){
        $request=$dbh->prepare("update reviews set titid=?, titisbn=?, titdb=?, loginname=?, nickname=?, title=?, review=?, rating=? where id=?") or $logger->error($DBI::errstr);
        $request->execute($titid,$titisbn,$titdb,$loginname,encode_utf8($nickname),encode_utf8($title),encode_utf8($review),$rating,$reviewid) or $logger->error($DBI::errstr);
    }
    else {
        $request=$dbh->prepare("insert into reviews (titid,titisbn,titdb,loginname,nickname,title,review,rating) values (?,?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
        $request->execute($titid,$titisbn,$titdb,$loginname,encode_utf8($nickname),encode_utf8($title),encode_utf8($review),$rating) or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id,nickname,loginname,title,review,rating from reviews where titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($titid,$titdb) or $logger->error($DBI::errstr);

    my $request2=$dbh->prepare("select count(id) as votecount from reviewratings where reviewid=?  group by id") or $logger->error($DBI::errstr);
    my $request3=$dbh->prepare("select count(id) as posvotecount from reviewratings where reviewid=? and rating > 0 group by id") or $logger->error($DBI::errstr);

    my $reviewlist_ref = [];

    while (my $result=$request->fetchrow_hashref){
        my $loginname = decode_utf8($result->{loginname});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id from reviews where titid=? and titdb=? and loginname=?") or $logger->error($DBI::errstr);
    $request->execute($titid,$titdb,$loginname) or $logger->error($DBI::errstr);

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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id,titid,titdb,nickname,loginname,title,review,rating from reviews where id=? and loginname=?") or $logger->error($DBI::errstr);
    $request->execute($id,$loginname) or $logger->error($DBI::errstr);

    my $review_ref = {};

    while (my $result=$request->fetchrow_hashref){
        my $loginname = decode_utf8($result->{loginname});
        my $nickname  = decode_utf8($result->{nickname});
        my $title     = decode_utf8($result->{title});
        my $review    = decode_utf8($result->{review});
        my $id        = $result->{id};
        my $titid     = $result->{titid};
        my $titdb     = $result->{titdb};
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("delete from reviews where id=? and loginname=?") or $logger->error($DBI::errstr);
    $request->execute($id,$loginname) or $logger->error($DBI::errstr);

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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$dbh->prepare("select id,titid,titdb,nickname,loginname,title,review,rating from reviews where loginname=?") or $logger->error($DBI::errstr);
    $request->execute($loginname) or $logger->error($DBI::errstr);

    my $reviewlist_ref = [];

    while (my $result=$request->fetchrow_hashref){
        my $loginname = decode_utf8($result->{loginname});
        my $nickname  = decode_utf8($result->{nickname});
        my $title     = decode_utf8($result->{title});
        my $review    = decode_utf8($result->{review});
        my $id        = $result->{id};
        my $titid     = $result->{titid};
        my $titdb     = $result->{titdb};
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

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    

    # Schon vorhanden
    my $request=$dbh->prepare("select id from litlists where userid = ? and title = ? and type = ?");
    $request->execute($self->{ID},$title,$type);

    my $result=$request->fetchrow_hashref;
    my $litlistid = $result->{id};

    return $litlistid if ($litlistid);

    $request=$dbh->prepare("insert into litlists (userid,title,type) values (?,?,?)") or $logger->error($DBI::errstr);
    $request->execute($self->{ID},$title,$type) or $logger->error($DBI::errstr);

    # Litlist-ID bestimmen und zurueckgeben

    $request=$dbh->prepare("select id from litlists where userid = ? and title = ? and type = ?");
    $request->execute($self->{ID},$title,$type);

    $result=$request->fetchrow_hashref;
    $litlistid = $result->{id};

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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$litlistid);

    my $litlist_properties_ref = $self->get_litlist_properties({litlistid => $litlistid});

    return unless ($litlist_properties_ref->{userid} eq $self->{ID});
    
    my $request=$dbh->prepare("delete from litlistitems where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("delete from litlists where id=?") or $logger->error($DBI::errstr);
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

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$litlistid || !$title || !$type);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    
    my $request=$dbh->prepare("update litlists set title=?, type=? where id=?") or $logger->error($DBI::errstr);
    $request->execute($title,$type,$litlistid) or $logger->error($DBI::errstr);

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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titid || !$titdb || !$litlitid );

    my $request=$dbh->prepare("delete from litlistitems where litlistid=? and titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid,$titid,$titdb) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("insert into litlistitems (litlistid,titid,titdb) values (?,?,?)") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$litlistid || !$titid || !$titdb);

    my $request=$dbh->prepare("delete from litlistitems where litlistid=? and titid=? and titdb=?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    return [] if (!$self->{ID});

    my $sql_stmnt = "select id from litlists where userid=?";

    my $request=$dbh->prepare($sql_stmnt) or $logger->error($DBI::errstr);
    $request->execute($self->{ID}) or $logger->error($DBI::errstr);

    my $litlists_ref = [];

    while (my $result=$request->fetchrow_hashref){
      my $litlistid        = $result->{id};
      
      push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlistid});
    }
    
    return $litlists_ref;
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    return [] if (!$litlistid);

    my $sql_stmnt = "select id,title from litlists where type == 1 and id != ? and userid in (select userid from litlists where id = ?) order by title";

    my $request=$dbh->prepare($sql_stmnt) or $logger->error($DBI::errstr);
    $request->execute($litlistid,$litlistid) or $logger->error($DBI::errstr);

    my $litlists_ref = [];

    while (my $result=$request->fetchrow_hashref){
      my $litlistid        = $result->{id};
      
      push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlistid});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    #return if (!$litlistid);

    my $request=$dbh->prepare("select titid,titdb,tstamp from litlistitems where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    my $recordlist = new OpenBib::RecordList::Title();

    while (my $result=$request->fetchrow_hashref){
      my $titelidn  = decode_utf8($result->{titid});
      my $database  = decode_utf8($result->{titdb});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    #return if (!$litlistid);

    my $request=$dbh->prepare("select count(litlistid) as numofentries from litlistitems where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    return $result->{numofentries};
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);

    return {} if (!$litlistid);

    my $request=$dbh->prepare("select * from litlists where id = ?") or $logger->error($DBI::errstr);
    $request->execute($litlistid) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    my $title     = decode_utf8($result->{title});
    my $type      = $result->{type};
    my $tstamp    = $result->{tstamp};
    my $userid    = $result->{userid};
    my $itemcount = $self->get_number_of_litlistentries({litlistid => $litlistid});

    my $litlist_ref = {
			id        => $litlistid,
			userid    => $userid,
			title     => $title,
			type      => $type,
		        itemcount => $itemcount,
			tstamp    => $tstamp,
		       };

    return $litlist_ref;
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return [] if (!defined $dbh);

    return [] if (!$titid || !$titdb);

    my $request=$dbh->prepare("select ll.* from litlistitems as lli, litlists as ll where ll.id=lli.litlistid and lli.titid=? and lli.titdb=?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $recordlist = new OpenBib::RecordList::Title();

    return $recordlist if (!defined $dbh);

    my $idnresult=$dbh->prepare("select * from treffer where userid = ? order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    while(my $result = $idnresult->fetchrow_hashref){
        my $database  = decode_utf8($result->{'dbname'});
        my $singleidn = decode_utf8($result->{'singleidn'});
        
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
    my $userresult=$dbh->prepare("select count(userid) as rowcount from treffer where userid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
    $userresult->execute($thisuserid,$item_ref->{dbname},$item_ref->{singleidn}) or $logger->error($DBI::errstr);
    my $res  = $userresult->fetchrow_hashref;
    my $rows = $res->{rowcount};
    if ($rows <= 0) {
        $userresult=$dbh->prepare("insert into treffer values (?,?,?)") or $logger->error($DBI::errstr);
        $userresult->execute($thisuserid,$item_ref->{dbname},$item_ref->{singleidn}) or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    my $idnresult=$dbh->prepare("delete from treffer where userid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $idnresult=$dbh->prepare("delete from logintarget where targetid = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $idnresult=$dbh->prepare("update logintarget set hostname = ?, port = ?, user =?, db = ?, description = ?, type = ? where targetid = ?") or $logger->error($DBI::errstr); # 
    $idnresult->execute($hostname,$port,$username,$dbname,$description,$type,$targetid) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub dbprofile_exists {
    my ($self,$profilename)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult=$dbh->prepare("select profilid,count(profilid) as rowcount from userdbprofile where userid = ? and profilename = ? group by profilid") or $logger->error($DBI::errstr);
    $profilresult->execute($self->{ID},$profilename) or $logger->error($DBI::errstr);
    my $res=$profilresult->fetchrow_hashref();
    
    my $numrows=$res->{rowcount};
    
    my $profilid="";
    
    if ($numrows > 0){
        return decode_utf8($res->{'profilid'});
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult2=$dbh->prepare("insert into userdbprofile values (NULL,?,?)") or $logger->error($DBI::errstr);
    
    $profilresult2->execute($profilename,$self->{ID}) or $logger->error($DBI::errstr);
    $profilresult2=$dbh->prepare("select profilid from userdbprofile where userid = ? and profilename = ?") or $logger->error($DBI::errstr);
    
    $profilresult2->execute($self->{ID},$profilename) or $logger->error($DBI::errstr);
    my $res=$profilresult2->fetchrow_hashref();
    my $profilid = decode_utf8($res->{'profilid'});
    
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $profilresult=$dbh->prepare("delete from userdbprofile where userid = ? and profilid = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    # Zuerst werden die Datenbankprofile geloescht
    my $userresult;
    $userresult=$dbh->prepare("delete from profildb using profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid=profildb.profilid") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    $userresult=$dbh->prepare("delete from userdbprofile where userdbprofile.userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    # .. dann die Suchfeldeinstellungen
    $userresult=$dbh->prepare("delete from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    # .. dann die Merkliste
    $userresult=$dbh->prepare("delete from treffer where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    # .. dann die Verknuepfung zur Session
    $userresult=$dbh->prepare("delete from usersession where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    # und schliesslich der eigentliche Benutzereintrag
    $userresult=$dbh->prepare("delete from user where userid = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("delete from usersession where userid = ?") or $logger->error($DBI::errstr);
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

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);
    
    # Es darf keine Session assoziiert sein. Daher stumpf loeschen
    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$dbh->prepare("delete from usersession where sessionid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
    
    $userresult=$dbh->prepare("insert into usersession values (?,?,?)") or $logger->error($DBI::errstr);
    $userresult->execute($globalsessionID,$userid,$targetid) or $logger->error($DBI::errstr);
    
    $userresult->finish();
   
    return;
}

sub delete_private_info {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("update user set nachname = ?, vorname = ?, strasse = ?, ort = ?, plz = ?, soll = ?, gut = ?, avanz = ?, branz = ?, bsanz = ?, vmanz = ?, maanz = ?, vlanz = ?, sperre = ?, sperrdatum = ?, gebdatum = ? where loginname = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);
    
    return {} if (!defined $dbh);

    my $userresult=$dbh->prepare("select * from user where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    my $res=$userresult->fetchrow_hashref();
    
    my $userinfo_ref={};

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

    return $userinfo_ref;
}

sub fieldchoice_exists {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);
    
    # Ueberpruefen, ob der Benutzer schon ein Suchprofil hat
    my $userresult=$dbh->prepare("select count(userid) as rowcount from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return 0 if (!defined $dbh);

    my $userresult=$dbh->prepare("insert into fieldchoice values (?,1,1,1,1,1,1,1,1,1,0,1,1,1,1)") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);
    
    return;
}

sub get_fieldchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    my $result=$targetresult->fetchrow_hashref();

    my $fieldchoice_ref = {
        fs        => decode_utf8($result->{'fs'}),
        hst       => decode_utf8($result->{'hst'}),
        verf      => decode_utf8($result->{'verf'}),
        kor       => decode_utf8($result->{'kor'}),
        swt       => decode_utf8($result->{'swt'}),
        notation  => decode_utf8($result->{'notation'}),
        isbn      => decode_utf8($result->{'isbn'}),
        issn      => decode_utf8($result->{'issn'}),
        sign      => decode_utf8($result->{'sign'}),
        mart      => decode_utf8($result->{'mart'}),
        hststring => decode_utf8($result->{'hststring'}),
        inhalt    => decode_utf8($result->{'inhalt'}),
        gtquelle  => decode_utf8($result->{'gtquelle'}),
        ejahr     => decode_utf8($result->{'ejahr'}),
    };
    
    $targetresult->finish();
    
    return $fieldchoice_ref;
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    $logger->debug("update fieldchoice set fs = ?, hst = ?, hststring = ?, verf = ?, kor = ?, swt = ?, notation = ?, isbn = ?, issn = ?, sign = ?, mart = ?, ejahr = ?, inhalt=?, gtquelle=? where userid = ? - $fs,$hst,$hststring,$verf,$kor,$swt,$notation,$isbn,$issn,$sign,$mart,$ejahr,$inhalt,$gtquelle,$self->{ID}");
    my $targetresult=$dbh->prepare("update fieldchoice set fs = ?, hst = ?, hststring = ?, verf = ?, kor = ?, swt = ?, notation = ?, isbn = ?, issn = ?, sign = ?, mart = ?, ejahr = ?, inhalt=?, gtquelle=? where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($fs,$hst,$hststring,$verf,$kor,$swt,$notation,$isbn,$issn,$sign,$mart,$ejahr,$inhalt,$gtquelle,$self->{ID}) or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("select bibsonomy_sync,bibsonomy_user,bibsonomy_key from user where userid = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $targetresult=$dbh->prepare("update user set bibsonomy_sync = ?, bibsonomy_user = ?, bibsonomy_key = ? where userid = ?") or $logger->error($DBI::errstr);
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    return undef if (!defined $dbh);

    my $userresult=$dbh->prepare("select targetid from logintarget where type = 'self'") or $logger->error($DBI::errstr);
    $userresult->execute() or $logger->error($DBI::errstr);
    
    my $res=$userresult->fetchrow_hashref();
    
    my $targetid = $res->{'targetid'};

    return $targetid;
}

sub get_mask {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    my $thisuserid=($userid)?$userid:$self->{ID};
    
    # Bestimmen des Recherchemasken-Typs
    my $userresult=$dbh->prepare("select masktype from user where userid = ?") or $logger->error($DBI::errstr);

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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    # Update des Recherchemasken-Typs
    my $targetresult=$dbh->prepare("update user set masktype = ? where userid = ?") or $logger->error($DBI::errstr);
    $targetresult->execute($masktype,$self->{ID}) or $logger->error($DBI::errstr);
    $targetresult->finish();

    return;
}

1;
