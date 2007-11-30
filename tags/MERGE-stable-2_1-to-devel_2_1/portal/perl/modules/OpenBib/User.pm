#####################################################################
#
#  OpenBib::User
#
#  Dieses File ist (C) 2006-2007 Oliver Flimm <flimm@openbib.org>
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

use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Common::Util;
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
            or $logger->error($DBI::errstr);

    $self->{dbh}       = $dbh;

    return $self;
}

sub userdb_accessible{
    my ($self)=@_;

    if (defined $self->{dbh}){
        return 1;
    }
    
    return 0;
}
    
sub get_cred_for_userid {
    my ($self,$userid)=@_;
                  
    # Log4perl logger erzeugen
    my $logger = get_logger();

    return if (!defined $self->{dbh});
    
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

    return undef if (!defined $self->{dbh});
    
    my $userresult=$self->{dbh}->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);

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

    return undef if (!defined $self->{dbh});
    
    my $userresult=$self->{dbh}->prepare("select userid from user where loginname = ?") or $logger->error($DBI::errstr);

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

    return undef if (!defined $self->{dbh});
    
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

sub clear_cached_userdata {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});

    my $request=$self->{dbh}->prepare("update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?") or die "$DBI::errstr";
    $request->execute($userid) or die "$DBI::errstr";
  
    $request->finish();

    return;
}

sub get_targetdb_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
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

    return undef if (!defined $self->{dbh});
    
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

    return undef if (!defined $self->{dbh});
    
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

    return if (!defined $self->{dbh});
    
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

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(*) as rowcount from treffer where userid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($userid) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofitems = $res->{rowcount};
    $idnresult->finish();

    return $numofitems;
}

sub get_number_of_tagged_titles {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(distinct(titid)) as rowcount from tittag") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numoftitles = $res->{rowcount};

    $idnresult->finish();

    return ($numoftitles)?$numoftitles:0;
}

sub get_number_of_tagging_users {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(distinct(loginname)) as rowcount from tittag") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofusers = $res->{rowcount};

    $idnresult->finish();

    return ($numofusers)?$numofusers:0;
}

sub get_number_of_tags {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(distinct(tagid)) as rowcount from tittag") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numoftags = $res->{rowcount};

    $idnresult->finish();

    return ($numoftags)?$numoftags:0;
}

sub get_number_of_users {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(userid) as rowcount from user") or $logger->error($DBI::errstr);
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

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(profilid) as rowcount from userdbprofile") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofprofiles = $res->{rowcount};

    $idnresult->finish();

    return ($numofprofiles)?$numofprofiles:0;
}

sub get_number_of_collections {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(distinct(userid)) as rowcount from treffer") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofcollections = $res->{rowcount};

    $idnresult->finish();

    return ($numofcollections)?$numofcollections:0;
}

sub get_number_of_collection_entries {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(userid) as rowcount from treffer") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});
    
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

    return undef if (!defined $self->{dbh});
    
    my $userresult=$self->{dbh}->prepare("select userid from user where loginname = ? and pin = ?") or $logger->error($DBI::errstr);
  
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

    return if (!defined $self->{dbh});
    
    my $request=$self->{dbh}->prepare("select * from logintarget order by type DESC,description") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});
    
    my $request=$self->{dbh}->prepare("select * from logintarget where targetid = ?") or $logger->error($DBI::errstr);
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
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef if (!defined $self->{dbh});
    
    my $idnresult=$self->{dbh}->prepare("select count(targetid) as rowcount from logintarget") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Splitten der Tags
    my @taglist = split("\\s+",$tags);

    # Zuerst alle Verknuepfungen loeschen
    my $request=$self->{dbh}->prepare("delete from tittag where loginname = ? and titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($loginname, $titid, $titdb) or $logger->error($DBI::errstr);

    foreach my $tag (@taglist){

        # Normierung
        $tag = OpenBib::Common::Util::grundform({
            content  => $tag,
            tagging  => 1,
        });

        $request=$self->{dbh}->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
        $request->execute($tag) or $logger->error($DBI::errstr);

        my $result=$request->fetchrow_hashref;

        my $tagid=$result->{id};

        # Wenn Tag nicht existiert, dann kann alles eintragen werden (tags/tittag)
        
        if (!$tagid){
            $logger->debug("Tag $tag noch nicht verhanden");
            $request=$self->{dbh}->prepare("insert into tags (tag) values (?)") or $logger->error($DBI::errstr);
            $request->execute(encode_utf8($tag)) or $logger->error($DBI::errstr);

            $request=$self->{dbh}->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
            $request->execute(encode_utf8($tag)) or $logger->error($DBI::errstr);
            my $result=$request->fetchrow_hashref;
            my $tagid=$result->{id};

            $request=$self->{dbh}->prepare("insert into tittag (tagid,titid,titisbn,titdb,loginname,type) values (?,?,?,?,?,?)") or $logger->error($DBI::errstr);
            $request->execute($tagid,$titid,$titisbn,$titdb,$loginname,$type) or $logger->error($DBI::errstr);
        }
        
        # Jetzt Verknuepfung mit Titel herstellen
        else {
            $logger->debug("Tag verhanden");

            # Neue Verknuepfungen eintragen
            $logger->debug("Verknuepfung zu Titel noch nicht vorhanden");
            $request=$self->{dbh}->prepare("insert into tittag (tagid,titid,titisbn,titdb,loginname,type) values (?,?,?,?,?,?)") or $logger->error($DBI::errstr);
            $request->execute($tagid,$titid,$titisbn,$titdb,$loginname,$type) or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

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

    my $request=$self->{dbh}->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
    $request->execute($oldtag) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $oldtagid = $result->{id};

    
    $request=$self->{dbh}->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
    $request->execute($newtag) or $logger->error($DBI::errstr);

    $result=$request->fetchrow_hashref;

    my $newtagid=$result->{id};

    # Wenn NewTag nicht existiert
        
    if (!$newtagid){
        $logger->debug("Tag $newtag noch nicht verhanden");
        $request=$self->{dbh}->prepare("insert into tags (tag) values (?)") or $logger->error($DBI::errstr);
        $request->execute(encode_utf8($newtag)) or $logger->error($DBI::errstr);

        $request=$self->{dbh}->prepare("select id from tags where tag = ?") or $logger->error($DBI::errstr);
        $request->execute(encode_utf8($newtag)) or $logger->error($DBI::errstr);
        my $result=$request->fetchrow_hashref;
        $newtagid=$result->{id};
    }

    if ($oldtagid && $newtagid){
        $request=$self->{dbh}->prepare("update tittag set tagid = ? where tagid = ? and loginname = ?") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("delete from tittag where titid=? and titdb=? and loginname=?") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where tt.titdb=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.tag") or $logger->error($DBI::errstr);

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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where tt.titid=? and tt.titdb=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.tag") or $logger->error($DBI::errstr);

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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select t.id,t.tag,tt.type from tags as t,tittag as tt where tt.loginname=? and tt.titid=? and tt.titdb=? and tt.tagid = t.id") or $logger->error($DBI::errstr);
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
    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where t.id=tt.tagid and tt.loginname=? group by tt.tagid order by t.tag") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen
    $rating   =~s/[^0-9]//g;
    
    # Zuerst alle Verknuepfungen loeschen
    my $request=$self->{dbh}->prepare("select reviewid from reviewratings where loginname = ? and reviewid=?") or $logger->error($DBI::errstr);
    $request->execute($loginname, $reviewid) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $thisreviewid = $result->{reviewid};

    # Review schon vorhanden?
    if ($thisreviewid){
        return 1; # Review schon vorhanden! Es darf aber pro Nutzer nur einer abgegeben werden;
    }
    else {
        $request=$self->{dbh}->prepare("insert into reviewratings (reviewid,loginname,rating) values (?,?,?)") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $rating   =~s/[^0-9]//g;
    $review   =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    $nickname =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    
    # Zuerst alle Verknuepfungen loeschen
    my $request=$self->{dbh}->prepare("select id from reviews where loginname = ? and titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($loginname, $titid, $titdb) or $logger->error($DBI::errstr);

    my $result   = $request->fetchrow_hashref;
    my $reviewid = $result->{id};

    # Review schon vorhanden?
    if ($reviewid){
        $request=$self->{dbh}->prepare("update reviews set titid=?, titisbn=?, titdb=?, loginname=?, nickname=?, title=?, review=?, rating=? where id=?") or $logger->error($DBI::errstr);
        $request->execute($titid,$titisbn,$titdb,$loginname,encode_utf8($nickname),encode_utf8($title),encode_utf8($review),$rating,$reviewid) or $logger->error($DBI::errstr);
    }
    else {
        $request=$self->{dbh}->prepare("insert into reviews (titid,titisbn,titdb,loginname,nickname,title,review,rating) values (?,?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select id,nickname,loginname,title,review,rating from reviews where titid=? and titdb=?") or $logger->error($DBI::errstr);
    $request->execute($titid,$titdb) or $logger->error($DBI::errstr);

    my $request2=$self->{dbh}->prepare("select count(id) as votecount from reviewratings where reviewid=?  group by id") or $logger->error($DBI::errstr);
    my $request3=$self->{dbh}->prepare("select count(id) as posvotecount from reviewratings where reviewid=? and rating > 0 group by id") or $logger->error($DBI::errstr);

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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select id from reviews where titid=? and titdb=? and loginname=?") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select id,titid,titdb,nickname,loginname,title,review,rating from reviews where id=? and loginname=?") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("delete from reviews where id=? and loginname=?") or $logger->error($DBI::errstr);
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

    return if (!defined $self->{dbh});

    #return if (!$titid || !$titdb || !$loginname || !$tags);

    my $request=$self->{dbh}->prepare("select id,titid,titdb,nickname,loginname,title,review,rating from reviews where loginname=?") or $logger->error($DBI::errstr);
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

sub DESTROY {
    my $self = shift;

    return if (!defined $self->{dbh});

    $self->{dbh}->disconnect();

    return;
}

1;
