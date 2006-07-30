#####################################################################
#
#  OpenBib::User
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $self = { };

    bless ($self, $class);

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    $self->{dbh}       = $dbh;

    return $self;
}

sub get_cred_for_userid {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $userresult=$self->{dbh}->prepare("select loginname,pin from user where userid = ?") or $logger->error($DBI::errstr);

    $userresult->execute($userid) or $logger->error($DBI::errstr);
  
    my @cred=();
  
    while(my $res=$userresult->fetchrow_hashref()){
        $cred[0] = decode_utf8($res->{loginname});
        $cred[1] = decode_utf8($res->{pin});
    }

    $userresult->finish();

    return @cred;

}

sub get_username_for_userid {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $userresult=$self->{dbh}->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);

    $userresult->execute($userid) or $logger->error($DBI::errstr);
  
    my $username="";
  
    while (my $res=$userresult->fetchrow_hashref()){
        $username = decode_utf8($res->{loginname});
    }

    $userresult->finish();

    return $username;
}

sub get_userid_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$self->{dbh}->prepare("select userid from usersession where sessionid = ?") or $logger->error($DBI::errstr);

    $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
    my $userid="";
  
    while(my $res=$userresult->fetchrow_hashref()){
        $userid = decode_utf8($res->{'userid'});
    }

    # Userid merken
    $self->{userid} = $userid;

    return $userid;
}

sub get_targetdb_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$self->{dbh}->prepare("select db from usersession,logintarget where usersession.sessionid = ? and usersession.targetid = logintarget.targetid") or $logger->error($DBI::errstr);

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

    my $config = new OpenBib::Config();
    
    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$self->{dbh}->prepare("select type from usersession,logintarget where usersession.sessionid = ? and usersession.targetid = logintarget.targetid") or $logger->error($DBI::errstr);

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

    my $config = new OpenBib::Config();

    my $idnresult=$self->{dbh}->prepare("select profilename from userdbprofile where profilid = ?") or $logger->error($DBI::errstr);
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

    my $config = new OpenBib::Config();

    my $idnresult=$self->{dbh}->prepare("select dbname from profildb where profilid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profileid) or $logger->error($DBI::errstr);

    my @profiledbs=();
    while (my $result=$idnresult->fetchrow_hashref()){
        push @profiledbs, decode_utf8($result->{'dbname'});
    }
    
    $idnresult->finish();

    return @profiledbs;
}

sub get_number_of_items_in_collection {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select count(*) as rowcount from treffer where userid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($userid) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofitems = $res->{rowcount};
    $idnresult->finish();

    return $numofitems;
}

sub get_all_profiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();

    my $idnresult=$self->{dbh}->prepare("select profilid, profilename from userdbprofile where userid = ? order by profilename") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{userid}) or $logger->error($DBI::errstr);

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

    my $userresult=$self->{dbh}->prepare("select userid from user where loginname = ? and pin = ?") or $logger->error($DBI::errstr);
  
    $userresult->execute($username,$pin) or $logger->error($DBI::errstr);

    my $res=$userresult->fetchrow_hashref();

    my $userid = decode_utf8($res->{'userid'});

    $userresult->finish();

    return (defined $userid)?$userid:-1;
}
    
sub DESTROY {
    my $self = shift;
    $self->{dbh}->disconnect();

    return;
}

1;
