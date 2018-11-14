#####################################################################
#
#  OpenBib::User
#
#  Dieses File ist (C) 2006-2015 Oliver Flimm <flimm@openbib.org>
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

use Benchmark ':hireswallclock';
use Cache::Memcached::Fast;
use DBIx::Class::ResultClass::HashRefInflator;
use Digest::MD5;
use Encode qw(decode_utf8 encode_utf8);
use JSON::XS;
use Data::Pageset;
use Log::Log4perl qw(get_logger :levels);
use YAML::Syck;

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Schema::System;
use OpenBib::Schema::System::Singleton;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    my $id          = exists $arg_ref->{ID}
        ? $arg_ref->{ID}                    : undef;

    my $config     = exists $arg_ref->{config}
        ? $arg_ref->{config}                : OpenBib::Config->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->{_config} = $config;
    
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Reuse des memc-Handles von config
    if ($config->{memc}){
	$self->{memc} = $config->{memc};
    }

    if (defined $sessionID){
        my $userid = $self->get_userid_of_session($sessionID);
        if (defined $userid){
            $self->{ID} = $userid ;
            $logger->debug("Got UserID $userid for session $sessionID");
        }
        else {
            $logger->debug("No UserID for session $sessionID");
        }
    }
    elsif (defined $id){
         $self->{ID} = $id ;
         $logger->debug("Got UserID $id - NO session assoziated");
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for is ".timestr($timeall));
    }

    $self->{_is_admin} = undef;

    return $self;
}

sub get_config {
    my $self = shift;

    return $self->{_config};
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
    my $credentials = $self->get_schema->resultset('Userinfo')->single(
        {
            id => $thisuserid,
        }
    );

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
        my $userinfo = $self->get_schema->resultset('Userinfo')->single(
            {
                username => $username,
            }
        )->update({ password => \"crypt('$password', gen_salt('bf'))" });
    }
    elsif ($self->{ID}) {
        # DBI: "update userinfo set pin = ? where id = ?"
        my $userinfo = $self->get_schema->resultset('Userinfo')->single(
            {
                id => $self->{ID},
            }
        )->update({ password => \"crypt('$password', gen_salt('bf'))" });
    }
    else {
        $logger->error("Neither username nor userid given");
    }

    return;
}

sub update_lastlogin {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username   = exists $arg_ref->{username}
        ? $arg_ref->{username}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($username){
        # DBI: "update userinfo set pin = ? where username = ?"
        my $userinfo = $self->get_schema->resultset('Userinfo')->single(
            {
                username => $username,
            }
        )->update({ lastlogin => \"NOW()" });
    }
    elsif ($self->{ID}) {
        # DBI: "update userinfo set pin = ? where id = ?"
        my $userinfo = $self->get_schema->resultset('Userinfo')->single(
            {
                id => $self->{ID},
            }
        )->update({ lastlogin => \"NOW()" });
    }
    else {
        $logger->error("Neither username nor userid given");
    }

    return;
}

sub load_privileges {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $userid    = exists $arg_ref->{userid}
        ? $arg_ref->{userid}             : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my ($atime,$btime,$timeall);
        
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    my $role_rights_ref = {};
    
    my $user_roles = $self->get_schema->resultset('UserRole')->search(
        {
            'userid.id' => $thisuserid,
        },
        {
            select => ['roleid.id'],
            as     => ['thisroleid'],
            join   => ['roleid','userid'],
        }
    );

    return $role_rights_ref unless ($user_roles);
    
    my $role_rights =  $self->get_schema->resultset('RoleRight')->search(
        {
            'roleid.id'  => { -in => $user_roles->as_query },
        },
        {
            select       => ['me.scope','me.right_create','me.right_read','me.right_update','me.right_delete'],
            as           => ['thisscope','thisright_create','thisright_read','thisright_update','thisright_delete'],
            join         => ['roleid'],
            order_by     => ['me.scope'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    while (my $result_ref = $role_rights->next()){
        my $thisscope        = $result_ref->{thisscope};
        my $thisright_create = $result_ref->{thisright_create};
        my $thisright_read   = $result_ref->{thisright_read};
        my $thisright_update = $result_ref->{thisright_update};
        my $thisright_delete = $result_ref->{thisright_delete};
        
        $role_rights_ref->{$thisscope}{right_create} = $thisright_create;
        $role_rights_ref->{$thisscope}{right_read}   = $thisright_read;
        $role_rights_ref->{$thisscope}{right_update} = $thisright_update;
        $role_rights_ref->{$thisscope}{right_delete} = $thisright_delete;
    }

    my $views_ref = {};

    my $role_views = $self->get_schema->resultset('RoleView')->search(
        {
            'roleid.id' => { -in => $user_roles->as_query },
        },
        {
            select       => ['viewid.viewname'],
            as           => ['thisviewname'],
            join         => ['roleid','viewid'],
            order_by     => ['viewid.viewname'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    while (my $result_ref = $role_views->next()){
        if ($logger->is_debug){
            $logger->debug("View: ".YAML::Dump($result_ref));
        }
        my $thisviewname = $result_ref->{thisviewname};
        $views_ref->{$thisviewname} = 1;
    }

    if ($logger->is_debug){
        $logger->debug("Restricted Views: ".YAML::Dump($views_ref));
        $logger->debug("Rights: ".YAML::Dump($role_rights_ref));
    }

    $self->{restricted_views} = $views_ref;
    $self->{rights}           = $role_rights_ref;

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Laden der Berechtigungen ".timestr($timeall));
    }
    
    return $self;
}

sub has_right {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $scope     = exists $arg_ref->{scope}
        ? $arg_ref->{scope}             : undef;

    my $right     = exists $arg_ref->{right}
        ? $arg_ref->{right}             : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Allgemeiner Admin darf alles!!!
    if ($self->is_admin){
        return 1;
    }
    
    unless (defined $self->{restricted_views} && defined $self->{rights}){
        $self->load_privileges;
    }

    if (defined $self->{rights}{$scope}{$right} && $self->{rights}{$scope}{$right} == 1){
        return 1;
    }

    return 0;
}

sub allowed_for_view {
    my ($self,$viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    unless (defined $self->{restricted_views} && defined $self->{rights}){
        $self->load_privileges;
    }

    my $user_allowed_for_view = 0;
    
    if (!keys %{$self->{restricted_views}}){
        $user_allowed_for_view = 1;
    }
    elsif (defined $self->{restricted_views}{$viewname} && $self->{restricted_views}{$viewname}){
        $user_allowed_for_view = 1;
    }

    return $user_allowed_for_view;
}

sub user_exists {
    my ($self,$username)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from user where username = ?"
    my $count = $self->get_schema->resultset('Userinfo')->search({ username => $username})->count;
    
    return $count;    
}

sub can_access_view {
    my ($self,$viewname)=@_;

    my $config = $self->get_config;

    my $viewinfo = $config->get_viewinfo->single({ viewname => $viewname });

    # Standardmaessig darf jeder Nutzer jeden View verwenden
    my $user_shall_access = 1;
    
    if ($viewinfo && $viewinfo->force_login){
	$user_shall_access = 0;

	if ($self->{ID}){
	    my $viewroles_ref      = {};
	    foreach my $rolename ($config->get_viewroles($viewname)){
		$viewroles_ref->{$rolename} = 1;
	    }
	    
	    foreach my $userrole (keys %{$self->get_roles_of_user($self->{ID})}){
		if ($viewroles_ref->{$userrole}){
		    $user_shall_access = 1;
		}
	    }
	}
    }

    return $user_shall_access;
}

sub add {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username   = exists $arg_ref->{username}
        ? $arg_ref->{username}             : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}              : undef;

    my $hashed_password    = exists $arg_ref->{hashed_password}
        ? $arg_ref->{hashed_password}              : undef;

    my $email       = exists $arg_ref->{email}
        ? $arg_ref->{email}                 : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "insert into user values (NULL,'',?,?,'','','','',0,'','','','','','','','','','','',?,'','','','','')"
    my $new_user = $self->get_schema->resultset('Userinfo')->create({
        username  => $username,
        password  => $hashed_password,
        email     => $email,
    });

    if ($password){
        $new_user->update({ password => \"crypt('$password', gen_salt('bf'))" });
    }
    elsif ($hashed_password){
        $new_user->update({ password => $hashed_password });
    }
    
    return;
}

sub set_password {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username   = exists $arg_ref->{username}
        ? $arg_ref->{username}             : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}              : undef;

    my $hashed_password    = exists $arg_ref->{hashed_password}
        ? $arg_ref->{hashed_password}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "insert into user values (NULL,'',?,?,'','','','',0,'','','','','','','','','','','',?,'','','','','')"
    my $update_user = $self->get_schema->resultset('Userinfo')->search_rs(
        {
            username  => $username,
        }
    );

    if ($password){
        $update_user->update({ password => \"crypt('$password', gen_salt('bf'))" });
    }
    elsif ($hashed_password){
        $update_user->update({ password => $hashed_password });
    }
    
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

    # Ggf. schon existierendes Request loeschen
    $self->get_schema->resultset('Registration')->search({ username => $username})->delete;
    
    # DBI: "insert into userregistration values (?,NULL,?,?)"
    $self->get_schema->resultset('Registration')->create({
        id        => $registrationid,
        username  => $username,
        password  => \"crypt('$password', gen_salt('bf'))",
    });
    
    return $registrationid;
}

sub get_confirmation_request {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $registrationid = exists $arg_ref->{registrationid}
        ? $arg_ref->{registrationid}             : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from userregistration where registrationid = ?"
    my $confirmationinfo = $self->get_schema->resultset('Registration')->single(
        {
            id => $registrationid,
        }
    );

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
    my $confirmationinfo = $self->get_schema->resultset('Registration')->search_rs(
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
    my $userinfo = $self->get_schema->resultset('Userinfo')->single(
        {
            id => $self->{ID},
        }
    );

    my $username;
    
    if ($userinfo){
        $username=$userinfo->username;
    }
    
    return $username;
}

sub get_username_for_userid {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select username from user where userid = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single(
        {
            id => $userid,
        }
    );

    my $username;

    if ($userinfo){
        $username = $userinfo->username;
    }
    
    return $username;
}

sub get_userid_for_username {
    my ($self,$username)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select userid from user where username = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single(
        {
            username => $username,
        }
    );

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
    my $usersession = $self->get_schema->resultset('UserSession')->search_rs(
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
        $logger->debug("Got UserID $userid for SessionID $sessionID");
    }
    else {
        $logger->debug("No UserID found for SessionID $sessionID");
    }
    
    return $userid;
}

sub clear_cached_userdata {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?"
    $self->get_schema->resultset('Userinfo')->single(
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

    # DBI: select db from user_session,authenticator where user_session.sessionid = ? and user_session.targetid = authenticator.targetid"
    my $authenticator = $self->get_schema->resultset('UserSession')->search_rs(
        {
            'sid.sessionid' => $sessionID,
        },
        {
            join   => ['sid','authenticatorid'],
            select => ['authenticatorid.dbname'],
            as     => ['thisdbname'],
        }
            
    )->single;
    
    my $targetdb;

    if ($authenticator){
        $targetdb = $authenticator->get_column('thisdbname');
    }
    
    return $targetdb;
}

sub get_targettype_of_session {
    my ($self,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: select type from user_session,authenticator where user_session.sessionid = ? and user_session.targetid = authenticator.targetid"
    my $authenticator = $self->get_schema->resultset('UserSession')->search_rs(
        {
            'sid.sessionid' => $sessionID,
        },
        {
            join   => ['sid','authenticatorid'],
            select => ['authenticatorid.type'],
            as     => ['thistype'],
        }
            
    )->single;
    
    my $targettype;

    if ($authenticator){
        $targettype = $authenticator->get_column('thistype');
    }

    return $targettype;
}

sub get_usersearchprofile {
    my ($self,$profileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $userprofile = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            'me.id'        => $profileid,
            'me.userid'    => $self->{ID},
        },
        {
            join   => ['searchprofileid'],
            select => ['me.profilename','searchprofileid.databases_as_json'],
            as     => ['thisprofilename','thisdatabases_as_json'],
        }

    )->single();

    my $usersearchprofileinfo = {};
        
    if ($userprofile){
        my $dbs_as_json = $userprofile->get_column('thisdatabases_as_json');
        my $profilename = $userprofile->get_column('thisprofilename');
        
        my $dbs_ref = decode_json $dbs_as_json;
        
        $usersearchprofileinfo = {
            profilename => $profilename,
            databases   => $dbs_ref,
        };
        
    }
    
    return $usersearchprofileinfo;
}

sub get_profilename_of_usersearchprofileid {
    my ($self,$usersearchprofileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $usersearchprofile = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            id     => $usersearchprofileid,
            userid => $self->{ID},
        },
        {
            columns => ['profilename'],
        }
    )->single();

    if ($usersearchprofile){
       return $usersearchprofile->profilename;
    }

    return;
}

sub get_profiledbs_of_usersearchprofileid {
    my ($self,$usersearchprofileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select profildb.dbname as dbname from profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid = ? and userdbprofile.profilid=profildb.profilid order by dbname"
    my $usersearchprofile = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            'me.id'        => $usersearchprofileid,
            'me.userid'    => $self->{ID},
        },
        {
            join   => ['searchprofileid'],
            select => ['searchprofileid.databases_as_json'],
            as     => ['thisdatabases_as_json'],
        }

    )->single();

    my @profiledbs;
    
    if ($usersearchprofile){
        my $dbs_as_json = $usersearchprofile->get_column('thisdatabases_as_json');

        $logger->debug("Found Databases as JSON: $dbs_as_json");
        
        my $dbs_ref = decode_json $dbs_as_json;
        
        @profiledbs = @{$dbs_ref};
    }
    else {
        $logger->debug("Couldn't find databases/searchprofile for userprofile $usersearchprofileid and user $self->{ID}");
    }
    
    return @profiledbs;
}

sub get_number_of_items_in_collection {
    my ($self,$arg_ref)=@_;

    my $view                = exists $arg_ref->{view}
        ? $arg_ref->{view}                : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $numofitems;
    
    if ($view){
        my $databases =  $self->get_schema->resultset('ViewDb')->search(
            {
                -or => [
                    {
                        'dbid.active'           => 1,
                        'viewid.viewname'       => $view,
                    },
                    {
                        'dbid.active'           => 1,
                        'dbid.system'           => { '~' => '^Backend' },
                    },
                ],
            }, 
            {
                join     => ['dbid','viewid'],
                select   => [ 'dbid.dbname' ],
                as       => ['dbname'],
                group_by => ['dbid.dbname'],
            }
        );

        $numofitems = $self->get_schema->resultset('UserCartitem')->search_rs(
            {
                'userid.id'       => $self->{ID},
                'cartitemid.dbname' => { -in => $databases->as_query },
            },
            {
                join => ['userid','cartitemid'],
            }
        )->count;
    }
    else {
        $numofitems = $self->get_schema->resultset('UserCartitem')->search_rs(
            {
                'userid.id' => $self->{ID},
            },
            {
                join => ['userid'],
            }
        )->count;
    }
    
    return $numofitems;
}

sub get_number_of_tagged_titles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(titleid)) as rowcount from tittag"
    my $numoftitles = $self->get_schema->resultset('TitTag')->search(
        {
            id => { '>' => 0 }, # force Index-Scan
        },
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
    my $numofusers = $self->get_schema->resultset('TitTag')->search(
        {
            id => { '>' => 0 }, # force Index-Scan
        },
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
    my $numoftags = $self->get_schema->resultset('TitTag')->search(
        {
            id => { '>' => 0 }, # force Index-Scan
        },
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
    my $tag = $self->get_schema->resultset('Tag')->search_rs(
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
    my $id = $self->get_schema->resultset('Tag')->single(
        {
            name => $tag
        }
    )->id;
    
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

    my $sortorder   = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}              : '';
    
    my $sorttype    = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}               : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
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

    # DBI: "select count(distinct titleid,dbname) as conncount from tittag where tagid=?"
#    my $hits = $self->get_schema->resultset('TitTag')->search_rs(
#        $where_ref,
#        $attribute_ref
#    )->count;


    # Dann jeweilige Titelmenge bestimmen
    
    my $recordlist = new OpenBib::RecordList::Title();

    $where_ref     = {
        tagid => $tagid,
    };
    
    $attribute_ref = {
        select   => ['me.titleid','me.dbname'],
        as       => ['thistitleid','thisdbname'],
        group_by => ['me.titleid','me.dbname','me.id','me.srt_title','me.srt_person','me.srt_year'],
    };
    
    if ($username) {
        $where_ref->{'userid.username'}  = $username;
        $attribute_ref->{'join'}         = [ 'userid' ];
    }

    if ($database) {
        $where_ref->{'me.dbname'} = $database;
    }

    # DBI: "select count(distinct titleid,dbname) as conncount from tittag where tagid=?"
    my $hits = $self->get_schema->resultset('TitTag')->search_rs(
        $where_ref,
        $attribute_ref
    )->count;
    
    if ($hitrange){
        $attribute_ref->{rows}   = $hitrange;
        $attribute_ref->{offset} = $offset;
    }

    if ($sorttype eq "person"){
        if ($sortorder eq "asc"){
            $attribute_ref->{order_by}   = "me.srt_person ASC";
        }
        else {
            $attribute_ref->{order_by}   = "me.srt_person DESC";
        }
    }
    elsif ($sorttype eq "title"){
        if ($sortorder eq "asc"){
            $attribute_ref->{order_by}   = "me.srt_title ASC";
        }
        else {
            $attribute_ref->{order_by}   = "me.srt_title DESC";
        }
    }
    elsif ($sorttype eq "year"){
        if ($sortorder eq "asc"){
            $attribute_ref->{order_by}   = "me.srt_year ASC";
        }
        else {
            $attribute_ref->{order_by}   = "me.srt_year DESC";
        }
    }
    # Sonst nach ID
    else {
        $attribute_ref->{order_by}   = "me.id DESC";
    }
    
    # DBI: "select distinct titleid,dbname from tittag where tagid=?";
    my $tagged_titles = $self->get_schema->resultset('TitTag')->search_rs(
        $where_ref,
        $attribute_ref
    );

    foreach my $title ($tagged_titles->all){
        $recordlist->add(new OpenBib::Record::Title({database => $title->get_column('thisdbname'), id => $title->get_column('thistitleid'), config => $config }));
    }

    $recordlist->load_brief_records;
    
    return ($recordlist,$hits);
}

sub get_number_of_users {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from userinfo"
    my $numofusers = $self->get_schema->resultset('Userinfo')->search_rs(
        {
            id => { '>' => 0 }, # force Index-Scan
        }
    )->count;

    return $numofusers;
}

sub get_number_of_selfreg_users {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from userinfo"
    my $numofusers = $self->get_schema->resultset('Userinfo')->search_rs(
        {
            username => { '~' => '^.+?\@.+?\..+?$' }, # Match email
        }
    )->count;

    return $numofusers;
}

sub get_number_of_dbprofiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI "select count(profilid) as rowcount from user_profile"
    my $numofprofiles = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            id => { '>' => 0 }, # force Index-Scan
        }
    )->count;

    return $numofprofiles;
}

sub get_number_of_collections {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(userid)) as rowcount from collection"
    my $numofcollections = $self->get_schema->resultset('UserCartitem')->search_rs(
        {
            id => { '>' => 0 }, # force Index-Scan
        },
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
    my $numofentries = $self->get_schema->resultset('UserCartitem')->search_rs(
        {
            id => { '>' => 0 }, # force Index-Scan
        },
    )->count;

    return $numofentries;
}

sub get_all_profiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select profilid, profilename from userdbprofile where userid = ? order by profilename"
    my $userprofiles = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            userid => $self->{ID},
        },
        {
            order_by => ['profilename'],
        }
    );
            
    my @userdbprofiles=();
        
    while (my $userprofile = $userprofiles->next){
        push @userdbprofiles, {
            profileid        => $userprofile->id,
            searchprofileid  => $userprofile->searchprofileid->id,
            profilename      => $userprofile->profilename,
        };
    }
    
    return @userdbprofiles;
}

sub get_all_searchprofiles {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select profilid, profilename from userdbprofile where userid = ? order by profilename"
    my $userprofiles = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            userid => $self->{ID},
        },
        {
            order_by => ['profilename'],
        }
    );
            
    my $searchprofiles_ref = [];
        
    while (my $userprofile = $userprofiles->next){
        push @{$searchprofiles_ref}, {
            profileid        => $userprofile->id,
            searchprofileid  => $userprofile->searchprofileid->id,
            profilename      => $userprofile->profilename,
        };
    }
    
    return $searchprofiles_ref;
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
    my $authentication = $self->get_schema->resultset('Userinfo')->search_rs(
        {
            username  => $username,
        },
        {
            select => ['id', \"me.password  = crypt('$password',me.password)"],
            as     => ['thisid','is_authenticated'],
        }
            
    )->first;
    
    my $userid = -1;

    if ($authentication && $authentication->get_column('is_authenticated')){
        $userid = $authentication->get_column('thisid');
    }

    $logger->debug("Got Userid $userid");

    return $userid;
}

sub add_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tags                = exists $arg_ref->{tags}
        ? $arg_ref->{tags    }            : undef;
    my $titleid             = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}             : undef;
    my $titleisbn           = exists $arg_ref->{titleisbn}
        ? $arg_ref->{titleisbn}           : '';
    my $dbname              = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}              : undef;
    my $userid              = exists $arg_ref->{userid}
        ? $arg_ref->{userid}              : undef;
    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # Splitten der Tags
    my @taglist = split('\s+',$tags);

    foreach my $tagname (@taglist){

        # Normierung
        $tagname = OpenBib::Common::Util::normalize({
            content  => $tagname,
            tagging  => 1,
        });

        # DBI: "select id from tags where tag = ?"
        my $tag = $self->get_schema->resultset('Tag')->search_rs(
            {
                name => $tagname,
            }
        )->single();

        # Sortierungsinformationen bestimmen

        my $record;
        
        eval {
            $record = OpenBib::Record::Title->new({database => $dbname, id => $titleid})->load_brief_record;
        };
        
        if ($@){
            $logger->error($@);
            next;
        }
        
        my $sortfields_ref = $record->get_sortfields;
        my $cached_title   = $record->to_json;

        # Wenn Tag nicht existiert, dann kann alles eintragen werden (tags/tittag)
        
        if (!$tag){
            $logger->debug("Tag $tagname noch nicht verhanden");

            # DBI: "insert into tags (tag) values (?)"
            my $new_tag = $self->get_schema->resultset('Tag')->create({ name => encode_utf8($tagname) });

            # DBI: "select id from tags where tag = ?"
            #      "insert into tittag (tagid,titleid,titisbn,dbname,username,type) values (?,?,?,?,?,?)"

            $new_tag->create_related(
                'tit_tags',
                {
                    titleid    => $titleid,
                    titleisbn  => $titleisbn,
                    dbname     => $dbname,
                    userid     => $userid,
                    type       => $type,
                    titlecache => $cached_title,
                    srt_person => $sortfields_ref->{person},
                    srt_title  => $sortfields_ref->{title},
                    srt_year   => $sortfields_ref->{year},
                }
            );
        }
        
        # Jetzt Verknuepfung mit Titel herstellen
        else {
            $logger->debug("Tag $tagname verhanden");

            my $tittag_exists = $tag->tit_tags->search_rs(
                {
                    titleid   => $titleid,
                    dbname    => $dbname,
                    userid    => $userid,
                }
            )->count;

            $logger->debug("Tit-Tag exists? $tittag_exists");

            if (! $tittag_exists){
                # Neue Verknuepfungen eintragen
                $logger->debug("Verknuepfung zu Titel noch nicht vorhanden");
 
                # DBI: "insert into tittag (tagid,titleid,titisbn,dbname,username,type) values (?,?,?,?,?,?)"
                $tag->create_related(
                    'tit_tags',
                    {
                        titleid    => $titleid,
                        titleisbn  => $titleisbn,
                        dbname     => $dbname,
                        userid     => $userid,
                        type       => $type,                    
                        titlecache => $cached_title,
                        srt_person => $sortfields_ref->{person},
                        srt_title  => $sortfields_ref->{title},
                        srt_year   => $sortfields_ref->{year},
                    }
                );
            }
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
    
    my $record    = new OpenBib::Record::Title({ database => $dbname , id => $titleid})->load_full_record;
    my $bibkey    = $record->to_bibkey;
    
    my $recordlist = $bibsonomy->get_posts({ user => 'self', bibkey => $bibkey});

    my $tags_ref = [];

    foreach my $tag_ref (@{$self->get_private_tags_of_tit(
        {
            titleid   => $titleid,
            dbname    => $dbname,
            username  => $self->get_username_for_userid($userid),            
        }
    )}){
        push @$tags_ref, $tag_ref->{tagname};
    }
    
    $logger->debug("Bibkey: $bibkey");
    # 2) ja, dann Tags und Sichtbarkeit anpassen
    if ($recordlist->get_size > 0){
        $logger->debug("Syncing Tags and Visibility $dbname:$titleid");
        $bibsonomy->change_post({ tags => $tags_ref, bibkey => $bibkey, visibility => $visibility });
    }
    # 3) nein, dann mit Tags neu anlegen
    else {
        if (@$tags_ref){
            if ($logger->is_debug){            
                $logger->debug("Syncing Record $dbname:$titleid");
                $logger->debug("Tags".YAML::Dump($tags_ref));
            }
            
            $bibsonomy->new_post({ tags => $tags_ref, record => $record, visibility => $visibility });
        }
    }

    return;
}

sub rename_tag {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $from              = exists $arg_ref->{from}
        ? $arg_ref->{from  }            : undef;
    my $to              = exists $arg_ref->{to}
        ? $arg_ref->{to  }            : undef;
    my $userid           = exists $arg_ref->{userid}
        ? $arg_ref->{userid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # Normierung
    $from = OpenBib::Common::Util::normalize({
        content  => $from,
        tagging  => 1,
    });

    $to = OpenBib::Common::Util::normalize({
        content  => $to,
        tagging  => 1,
    });

    # Vorgehensweise
    # 1.) oldid von from bestimmen
    # 2.) Uebepruefen, ob to schon existiert. Wenn nicht, dann anlegen
    #     und newid merken
    # 3.) In tittag alle Vorkommen von oldid durch newid fuer userid
    #     ersetzen

    # DBI: "select id from tag where name = ?"
    my $tag_old = $self->get_schema->resultset('Tag')->single(
        {
            name => $from,
        }
    );

    my $fromid;
    my $toid;
        
    if ($tag_old){
        $fromid = $tag_old->id;
    }
    else {
        $logger->error("Old Tag $from does not exist to be renamed!");
        return 1;
    }

    # DBI: "select id from tag where name = ?"
    my $tag_new = $self->get_schema->resultset('Tag')->single(
        {
            name => $to,
        }
    );

    if ($tag_new){
        $toid = $tag_new->id;
    }
    else {
        $logger->debug("Tag $to noch nicht verhanden");
        # DBI: "insert into tag (name) values (?)"
        #      "select id from tag where name = ?"
        my $created_tag = $self->get_schema->resultset('Tag')->create(
            {
                name => $to,
            }
        );

        $toid = $created_tag->id;
    }
    # Wenn To nicht existiert
        
    if ($fromid && $toid){
        # DBI: "update tit_tag set tagid = ? where tagid = ? and userid = ?"
        $self->get_schema->resultset('TitTag')->search_rs(
            {
                tagid  => $fromid,
                userid => $userid,
            }
        )->update(
            {
                tagid => $toid,
            }
        );
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
    my $tagid                = exists $arg_ref->{tagid}
        ? $arg_ref->{tagid}               : undef;
    my $titleid             = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}             : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $dbname              = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}              : undef;
    my $userid              = exists $arg_ref->{userid}
        ? $arg_ref->{userid}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    if ($tags){
        foreach my $tag (split("\\s+",$tags)){
            # DBI: "delete from tit_tag where titleid=? and dbname=? and userid=? and tagid=?"
            $self->get_schema->resultset('TitTag')->search_rs(
                {
                    'me.titleid'      => $titleid,
                    'me.dbname'       => $dbname,
                    'userid.id'       => $userid,
                    'tagid.name'      => $tag,
                        
                },
                {
                    join => ['tagid','userid'],
                }
            )->delete;
        }
    }
    elsif ($tagid){
        # DBI: "delete from tit_tag where titleid=? and dbname=? and userid=? and tagid=?"
        $self->get_schema->resultset('TitTag')->search_rs(
            {
                'me.titleid'      => $titleid,
                'me.dbname'       => $dbname,
                'userid.id'       => $userid,
                'tagid.name'      => $tagid,
                
            },
            {
                join => ['tagid','userid'],
            }
        )->delete;
    }
    else {
        # DBI: "delete from tittag where titleid=? and dbname=? and userid=?"
        $self->get_schema->resultset('TitTag')->search_rs(
            {
                'me.titleid'      => $titleid,
                'me.dbname'       => $dbname,
                'userid.id'       => $userid,
            },
            {
                join => ['userid'],
            }
        )->delete;
    }
    
    return;
}

sub del_tag {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tagid                = exists $arg_ref->{tagid}
        ? $arg_ref->{tagid}               : undef;

    my $userid               = exists $arg_ref->{userid}
        ? $arg_ref->{userid}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    if ($tagid && $userid){
        # DBI: "delete from tit_tag where titleid=? and dbname=? and userid=? and tagid=?"
        eval {
            $self->get_schema->resultset('TitTag')->single(
                {
                    id     => $tagid,
                    userid => $userid,
                },
            )->delete;
        };

        if ($@){
            $logger->error($@);
        }
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

    # DBI: "select t.name, t.id, count(tt.tagid) as tagcount from tag as t, tit_tag as tt where tt.dbname=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.name"
    my $tittags = $self->get_schema->resultset('TitTag')->search_rs(
        {
            'me.dbname' => $dbname,
            'me.type'   => 1,
        },
        {
            group_by => ['me.tagid'],
            order_by => ['tagid.name'],
            join     => ['tagid'],
            select   => ['tagid.name','tagid.id',{ count => 'me.tagid' }],
            as       => ['thistagname','thistagid','thistagcount'],
        }
    );
    
    my $taglist_ref = [];
    my $maxcount    = 0;
    foreach my $tittag ($tittags->all){
        my $tag       = $tittag->get_column('thistagname');
        my $id        = $tittag->get_column('thistagid');
        my $count     = $tittag->get_column('thistagcount');

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
    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $dbname               = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    # DBI: "select t.name, t.id, count(tt.tagid) as tagcount from tag as t, tit_tag as tt where tt.titleid=? and tt.dbname=? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by t.name") or $logger->error($DBI::errstr);
    my $tittags = $self->get_schema->resultset('TitTag')->search_rs(
        {
            'me.titleid' => $titleid,
            'me.dbname'  => $dbname,
            'me.type'    => 1,
        },
        {
            group_by => ['tagid.id','tagid.name'],
            order_by => ['tagid.name'],
            join => ['tagid'],
            select => ['tagid.name','tagid.id',{ count => 'me.tagid' }],
            as     => ['thistagname','thistagid','thistagcount'],
        }
    );

    my $taglist_ref = [];
    my $maxcount    = 0;
    foreach my $tittag ($tittags->all){
        my $tag       = $tittag->get_column('thistagname');
        my $id        = $tittag->get_column('thistagid');
        my $count     = $tittag->get_column('thistagcount');

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

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time is ".timestr($timeall));
    }

    return $taglist_ref;
}

sub get_private_tags_of_tit {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $dbname               = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select t.id,t.name,tt.type from tag as t,tit_tag as tt where tt.userid=? and tt.titleid=? and tt.dbname=? and tt.tagid = t.id"
    my $tittags = $self->get_schema->resultset('TitTag')->search_rs(
        {
            'me.titleid'  => $titleid,
            'me.dbname'   => $dbname,
            'userid.username' => $username,
        },
        {
            group_by => ['me.id','tagid.id','tagid.name','me.type'],
            order_by => ['tagid.name'],
            join => ['tagid','userid'],
            select => ['me.id','tagid.name','tagid.id','me.type'],
            as     => ['thisid','thistagname','thistagid','thistagtype'],
        }
    );

    my $taglist_ref = [];

    foreach my $tittag ($tittags->all){
        my $id        = $tittag->get_column('thisid');
        my $tagname   = $tittag->get_column('thistagname');
        my $tagid     = $tittag->get_column('thistagid');
        my $type      = $tittag->get_column('thistagtype');

        push @$taglist_ref, {
            id      => $id,
            tagid   => $tagid,
            tagname => $tagname,
            type    => $type,
        };
    }
    
    return $taglist_ref;
}

sub get_private_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $offset       = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : undef;
    my $num          = exists $arg_ref->{num}
        ? $arg_ref->{num}           : undef;
    my $userid       = exists $arg_ref->{userid}
        ? $arg_ref->{userid}        : undef;
    my $sortorder   = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}              : '';
    my $sorttype    = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}               : '';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $tags_ref = [];

    my $attribute_ref =         {
        group_by => ['id','titleid','dbname'],
        rows     => $num,
        offset   => $offset,
        select   => ['id','tagid','titleid','dbname'],
        as       => ['thisid','thistagid','thistitleid','thisdbname','srt_person','srt_title','srt_year'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',            
    };

    if ($sorttype eq "person"){
        if ($sortorder eq "asc"){
            $attribute_ref->{order_by}   = "srt_person ASC";
        }
        else {
            $attribute_ref->{order_by}   = "srt_person DESC";
        }
    }
    elsif ($sorttype eq "title"){
        if ($sortorder eq "asc"){
            $attribute_ref->{order_by}   = "srt_title ASC";
        }
        else {
            $attribute_ref->{order_by}   = "srt_title DESC";
        }
    }
    elsif ($sorttype eq "year"){
        if ($sortorder eq "asc"){
            $attribute_ref->{order_by}   = "srt_year ASC";
        }
        else {
            $attribute_ref->{order_by}   = "srt_year DESC";
        }
    }
    # Sonst nach ID
    else {
        $attribute_ref->{order_by}   = "id DESC";
    }

    # DBI: "select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where t.id=tt.tagid and tt.type=1 group by tt.tagid order by tt.ttid DESC limit $count";
    my $tags = $self->get_schema->resultset('TitTag')->search(
        {
            'userid'   => $userid,
        },
        $attribute_ref
    );
    
    while (my $singletag = $tags->next){
        my $id        = $singletag->{thisid};
        my $tagid     = $singletag->{thistagid};
        my $titleid   = $singletag->{thistitleid};
        my $dbname    = $singletag->{thisdbname};

        my $tagname   = $self->get_name_of_tag({ tagid => $tagid});
        
        $logger->debug("Got tagname $tagname, tagid $tagid, titleid $titleid and dbname $dbname");
        
        my $record = new OpenBib::Record::Title({ id => $titleid, database => $dbname, config => $config })->load_brief_record;
        
        push @$tags_ref, {
            id        => $id,
            tagid     => $tagid,
            tagname   => $tagname,
            titleid   => $titleid,
            dbname    => $dbname,
            record    => $record,
        };
    }        
    
    return $tags_ref;
}

sub get_private_tags_by_name {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $userid       = exists $arg_ref->{userid}
        ? $arg_ref->{userid}        : undef;
    my $offset       = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : undef;
    my $num          = exists $arg_ref->{num}
        ? $arg_ref->{num}           : undef;
    my $sortorder    = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}     : 'title';
    my $sorttype     = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}      : 'asc';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("userid: $userid");

    my $attribute_ref = { 
        group_by => ['tagid.id','tagid.name'],
        order_by => ['tagid.name'],
        join     => ['tagid','userid'],
        select   => ['tagid.name','tagid.id',{ count => 'me.tagid' }],
        as       => ['thistagname','thistagid','thistagcount'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',            
    };
    
    # DBI: "select t.name, t.id, count(tt.tagid) as tagcount from tag as t, tit_tag as tt where t.id=tt.tagid and tt.userid=? group by tt.tagid order by t.name"
    my $numoftags = $self->get_schema->resultset('TitTag')->search_rs(
        {
            'userid.id' => $userid,
        },
        $attribute_ref
    )->count;

    if (defined $num && defined $offset){
        $attribute_ref->{rows}   = $num;
        $attribute_ref->{offset} = $offset;
    }

    if ($sorttype eq "title"){
        if ($sortorder eq "asc"){
            $attribute_ref->{order_by}   = "tagid.name ASC";
        }
        else {
            $attribute_ref->{order_by}   = "tagid.name DESC";
        }
    }
    else {
        $attribute_ref->{order_by}   = "tagid.name ASC";
    }

    my $tittags = $self->get_schema->resultset('TitTag')->search_rs(
        {
            'userid.id' => $userid,
        },
        $attribute_ref
    );

    my $taglist_ref = [];
    my $maxcount = 0;
    while (my $tittag = $tittags->next){
        my $tag       = $tittag->{thistagname};
        my $id        = $tittag->{thistagid};
        my $count     = $tittag->{thistagcount};

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

    if ($logger->is_debug){
        $logger->debug("Private Tags: ".YAML::Dump($taglist_ref));
    }
    
    return ($taglist_ref,$numoftags);
}

sub get_private_tagged_titles {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("username: $username");

    # DBI: "select t.name, tt.titleid, tt.dbname, tt.type from tag as t, tit_tag as tt where t.id=tt.tagid and tt.userid=? group by tt.tagid order by t.name"
    my $tittags = $self->get_schema->resultset('TitTag')->search_rs(
        {
            'userid.username' => $username,
        },
        {
            group_by => ['me.tagid','me.titleid','me.dbname','me.type','tagid.name'],
            order_by => ['tagid.name'],
            join     => ['tagid','userid'],
            select   => ['tagid.name','me.titleid','me.dbname','me.type'],
            as       => ['thistagname','thistitleid','thisdbname','thistagtype'],
        }
    );

    my $taglist_ref = {};

    foreach my $tittag ($tittags->all){
        my $tag       = $tittag->get_column('thistagname');
        my $id        = $tittag->get_column('thistitleid');
        my $database  = $tittag->get_column('thisdbname');
        my $type      = $tittag->get_column('thistagtype');

        $taglist_ref->{$database}{$id}{visibility} = $type;
        
        unless (exists $taglist_ref->{$database}{$id}{tags}){
            $taglist_ref->{$database}{$id}{tags} = [];
        }
        
        push @{$taglist_ref->{$database}{$id}{tags}}, $tag;
    }

    if ($logger->is_debug){
        $logger->debug("Private Tags: ".YAML::Dump($taglist_ref));
    }
    
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
        # DBI: "select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where tt.dbname= ? and t.id=tt.tagid and tt.type=1 group by tt.tagid order by tt.ttid DESC limit $count"
        my $tags = $self->get_schema->resultset('TitTag')->search(
            {
                'me.type'   => 1,
                'me.dbname' => $database,
            },
            {
                group_by => ['me.tagid','tagid.id','tagid.name'],
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
        my $tags = $self->get_schema->resultset('TitTag')->search(
            {
                'me.type'   => 1,
            },
            {
                group_by => ['tagid.id','tagid.name'],
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

sub get_recent_tags_by_name {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $offset       = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : 0;
    my $num          = exists $arg_ref->{num}
        ? $arg_ref->{num}           : 20;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $tags_ref = [];
    
    # DBI: "select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where t.id=tt.tagid and tt.type=1 group by tt.tagid order by tt.ttid DESC limit $count";
    my $tags = $self->get_schema->resultset('Tag')->search(
        {
            'tit_tags.type'   => 1,
        },
        {
            group_by => ['me.name','me.id'],
            order_by => ['me.id DESC'],
            join     => ['tit_tags'],
            rows     => $num,
            offset   => $offset,
            select   => ['me.name','me.id'],
            as       => ['thisname','thisid'],
        }
    );

    my $numoftags = $self->get_schema->resultset('Tag')->search(
        {
            'tit_tags.type'   => 1,
        },
        {
            group_by => ['me.name'],
            order_by => ['me.id DESC'],
            join     => ['tit_tags'],
            select   => ['me.name'],
            as       => ['thisname'],
        }
    )->count;
    
    foreach my $singletag ($tags->all){
        my $tagname    = $singletag->get_column('thisname');
        my $tagid      = $singletag->get_column('thisid');
        my $itemcount  = $self->get_number_of_public_tags_by_name($tagname);        
        
        $logger->debug("Got tagname $tagname");
        
        push @$tags_ref, {
            itemcount => $itemcount,
            tagname   => $tagname,
            id        => $tagid,
        };
    }        
    
    return {
        count => $numoftags,
        tags  => $tags_ref
    };
}

sub obsolete_get_recent_tags_by_name {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $num          = exists $arg_ref->{num}
        ? $arg_ref->{num}             : 5;

    my $offset       = exists $arg_ref->{offset}
        ? $arg_ref->{offset}          : 0;

    my $database     = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $tags_ref = [];

    my $tittag = $self->get_schema->resultset('TitTag');

    my $tags_rs = $tittag->search_rs(
        {
            'type'   => 1,
        },
        {
            group_by => ['id','tagid'],
            order_by => ['id DESC'],
            select   => ['tagid'],
            as       => ['thistagid'],
        }
    );

    my $numoftags = $self->get_schema->resultset('Tag')->search(
        {
            'tit_tags.type'   => 1,
        },
        {
            group_by => ['me.name'],
            order_by => ['me.id DESC'],
            join     => ['tit_tags'],
            select   => ['me.name'],
            as       => ['thisname'],
        }
    )->count;

    my $tags = $tittag->search_rs(
        {
            'tagid' => { '-in' => $tags_rs->get_column('thistagid')->as_query },
        },
        {
            select => [{ distinct => 'tagid'}],
            order_by => ['tagid'],
            rows     => $num,
            offset   => $offset,
            as       => ['thistagid'],
            order_by => ['tagid'],
        }
    );

    
    foreach my $singletag ($tags->all){
        my $tagid     = $singletag->get_column('thistagid');
        my $tagname   = $self->get_name_of_tag({ tagid => $tagid});
        my $itemcount = $self->get_number_of_public_tags_by_name($tagname);        

        $logger->debug("Got tagname $tagname");
        
        push @$tags_ref, {
            itemcount => $itemcount,
            tagname   => $tagname,
            id        => $tagid,
        };
    }        

    
    return {
        count => $numoftags,
        tags  => $tags_ref,
    }
}

sub get_public_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $offset       = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : undef;
    my $num          = exists $arg_ref->{num}
        ? $arg_ref->{num}           : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $tags_ref = [];
    
    # DBI: "select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where t.id=tt.tagid and tt.type=1 group by tt.tagid order by tt.ttid DESC limit $count";
    my $tags = $self->get_schema->resultset('TitTag')->search(
        {
            'type'   => 1,
        },
        {
            group_by => ['id','titleid','dbname'],
            order_by => ['id ASC'],
            rows     => $num,
            offset   => $offset,
            select   => ['id','tagid','titleid','dbname'],
            as       => ['thisid','thistagid','thistitleid','thisdbname'],
        }
    );
    
    foreach my $singletag ($tags->all){
        my $id        = $singletag->get_column('thisid');
        my $tagid     = $singletag->get_column('thistagid');
        my $titleid   = $singletag->get_column('thistitleid');
        my $dbname    = $singletag->get_column('thisdbname');

        my $tagname   = $self->get_name_of_tag({ tagid => $tagid});
        
        $logger->debug("Got tagname $tagname, tagid $tagid, titleid $titleid and dbname $dbname");
        
        my $record = new OpenBib::Record::Title({ id => $titleid, database => $dbname, config => $config })->load_brief_record;
        
        push @$tags_ref, {
            id        => $id,
            tagid     => $tagid,
            tagname   => $tagname,
            titleid   => $titleid,
            dbname    => $dbname,
            record    => $record,
        };
    }        
    
    return $tags_ref;
}

sub get_public_tags_by_name {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $offset       = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : 0;
    my $num          = exists $arg_ref->{num}
        ? $arg_ref->{num}           : 20;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $tags_ref = [];
    
    # DBI: "select t.tag, t.id, count(tt.tagid) as tagcount from tags as t, tittag as tt where t.id=tt.tagid and tt.type=1 group by tt.tagid order by tt.ttid DESC limit $count";
    my $tags = $self->get_schema->resultset('Tag')->search(
        {
            'tit_tags.type'   => 1,
        },
        {
            group_by => ['me.name','me.id'],
            order_by => ['me.name ASC'],
            join     => ['tit_tags'],
            rows     => $num,
            offset   => $offset,
            select   => ['me.name','me.id'],
            as       => ['thisname','thisid'],
        }
    );

    my $numoftags = $self->get_schema->resultset('Tag')->search(
        {
            'tit_tags.type'   => 1,
        },
        {
            group_by => ['me.name'],
            order_by => ['me.name ASC'],
            join     => ['tit_tags'],
            select   => ['me.name'],
            as       => ['thisname'],
        }
    )->count;
    
    foreach my $singletag ($tags->all){
        my $tagname    = $singletag->get_column('thisname');
        my $tagid      = $singletag->get_column('thisid');
        my $itemcount  = $self->get_number_of_public_tags_by_name($tagname);        
        
        $logger->debug("Got tagname $tagname");
        
        push @$tags_ref, {
            itemcount => $itemcount,
            tagname   => $tagname,
            id        => $tagid,
        };
    }        
    
    return {
        count => $numoftags,
        tags  => $tags_ref
    };
}

sub get_number_of_public_tags {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(titleid)) as rowcount from tittag"
    my $numoftitles = $self->get_schema->resultset('TitTag')->search(
        {
            type => 1,
        },
        {
            group_by => ['titleid'],
        }
    )->count;

    return $numoftitles;
}

sub get_number_of_private_tags {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $userid            = exists $arg_ref->{userid}
        ? $arg_ref->{userid}            : undef;
        
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(titleid)) as rowcount from tittag"
    my $numoftitles = $self->get_schema->resultset('TitTag')->search(
        {
            userid => $userid,
        },
    )->count;

    return $numoftitles;
}

sub get_number_of_public_tags_by_name {
    my ($self,$tagname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(distinct(titleid)) as rowcount from tittag"
    my $numoftitles = $self->get_schema->resultset('TitTag')->search(
        {
            'me.type' => 1,
            'tagid.name' => $tagname,
            
        },
        {
            group_by => ['titleid'],
            join => ['tagid'],
        }
    )->count;

    return $numoftitles;
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
    my $reviewrating = $self->get_schema->resultset('Reviewrating')->search_rs(
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
        $self->get_schema->resultset('Reviewrating')->create(
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

    return {} if (!$reviewid);

    # DBI: "select * from review where id = ?"
    my $review = $self->get_schema->resultset('Review')->single({
        id => $reviewid,
    });
    
    if ($review){
        my $title      = $review->title;
        my $titleid    = $review->titleid;
        my $dbname     = $review->dbname;
        my $titisbn    = $review->titleisbn;
        my $tstamp     = $review->tstamp;
        my $nickname   = $review->nickname;
        my $reviewtext = $review->reviewtext;
        my $rating     = $review->rating;
        my $userid     = $review->userid;
        
        my $review_ref = {
            id               => $reviewid,
            userid           => $userid,
            title            => $title,
            dbname           => $dbname,
            titleid          => $titleid,
            tstamp           => $tstamp,
            reviewtext       => $reviewtext,
            rating           => $rating,
        };

        if ($logger->is_debug){
            $logger->debug("Review Properties: ".YAML::Dump($review_ref));
        }
        
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
    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $dbname               = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
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
    my $review = $self->get_schema->resultset('Review')->search_rs(
        {
            userid => $self->get_userid_for_username($username),
            titleid => $titleid,
            dbname => $dbname,
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
        $self->get_schema->create(
            {
                titleid    => $titleid,
                dbname     => $dbname,
                userid     => $self->get_userid_for_username($username),
                titleisbn  => $titisbn,
                nickname   => encode_utf8($nickname),
                title      => encode_utf8($title),
                reviewtext => encode_utf8($reviewtext),
                rating     => $rating,
            }            
        );
    }

    return;
}

sub get_reviews_of_tit {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $dbname               = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select id,nickname,userid,title,review,rating from review where titleid=? and dbname=?"
    my $reviews = $self->get_schema->resultset('Review')->search_rs(
        {
            titleid => $titleid,
            dbname  => $dbname,
        }
    );

    my $reviewlist_ref = [];

    foreach my $review ($reviews->all){
        my $userid    = $review->userid;
        my $username = $self->get_username_for_userid($userid);
        my $nickname  = $review->nickname;
        my $title     = $review->title;
        my $review    = $review->reviewtext;
        my $id        = $review->id;
        my $rating    = $review->rating;

        # DBI: "select count(id) as votecount from reviewrating where reviewid=?  group by id"
        my $votecount = $self->get_schema->resultset('Reviewrating')->search_rs(
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
            $posvotecount = $self->get_schema->resultset('Reviewrating')->search_rs(
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
    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}               : undef;
    my $titisbn             = exists $arg_ref->{titisbn}
        ? $arg_ref->{titisbn}             : '';
    my $dbname               = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
    my $username           = exists $arg_ref->{username}
        ? $arg_ref->{username}           : undef;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select id from review where titleid=? and dbname=? and userid=?"
    my $review = $self->get_schema->resultset('Review')->search_rs(
        {
            titleid => $titleid,
            dbname  => $dbname,
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
    my $review = $self->get_schema->resultset('Review')->search_rs(
        {
            id => $id,
            userid => $self->get_userid_for_username($username),
        }
    )->first;

    my $review_ref = {};
    
    if ($review){
        $logger->debug("Found Review $id for User $username");

        my $userid     = $review->userid;
        my $username   = $self->get_username_for_userid($userid);
        my $nickname   = $review->nickname;
        my $title      = $review->title;
        my $reviewtext = $review->reviewtext;
        my $id         = $review->id;
        my $titleid      = $review->titleid;
        my $dbname      = $review->dbname;
        my $rating     = $review->rating;

        $review_ref = {
            id        => $id,
            titleid     => $titleid,
            dbname     => $dbname,
            username  => $username,
            nickname  => $nickname,
            title     => $title,
            review    => $reviewtext,
            rating    => $rating,
        };
    }

    if ($logger->is_debug){
        $logger->debug("Got Review: ".YAML::Dump($review_ref));
    }

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
    $self->get_schema->resultset('Review')->search_rs(
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

    # DBI: "select id,titleid,dbname,nickname,userid,title,review,rating from review where userid=?"
    my $reviews = $self->get_schema->resultset('Review')->search_rs(
        {
            userid => $self->get_userid_for_username($username),
        }
    );

    my $reviewlist_ref = [];
    
    foreach my $review ($reviews->all){
        my $userid     = $review->userid;
        my $username   = $self->get_username_for_userid($userid);
        my $nickname   = $review->nickname;
        my $title      = $review->title;
        my $reviewtext = $review->reviewtext;
        my $id         = $review->id;
        my $titleid      = $review->titleid;
        my $dbname      = $review->dbname;
        my $rating     = $review->rating;

        push @$reviewlist_ref, {
            id        => $id,
            titleid     => $titleid,
            dbname     => $dbname,
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
    my $topics_ref        = exists $arg_ref->{topics}
        ? $arg_ref->{topics}              : [];
 
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;

    # Schon vorhanden
    # DBI: "select id from litlist where userid = ? and title = ? and type = ?"
    my $litlist = $self->get_schema->resultset('Litlist')->search_rs(
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
    my $new_litlist = $self->get_schema->resultset('Litlist')->create(
        {
            userid => $self->{ID},
            tstamp => \'NOW()',
            title  => $title,
            type   => $type,
        }
    );

    my $litlistid;
    
    if ($new_litlist){
        $litlistid = $new_litlist->id;
    }
    
    # Litlist-ID bestimmen und zurueckgeben

    if (defined $topics_ref){
        unless (ref($topics_ref) eq 'ARRAY') {
            $topics_ref = [ $topics_ref ];
        }
        
        if (@{$topics_ref}){
            foreach my $topicid (@{$topics_ref}){
                # DBI "insert into litlist_topic (litlistid,topicid) values (?,?)") or $logger->error($DBI::errstr);
                $new_litlist->create_related('litlist_topics',
                                             {
                                                 topicid => $topicid,
                                             }
                                         );
            }
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

    my $litlist = $self->get_schema->resultset('Litlist')->search_rs(
        {
            id     => $litlistid,
            userid => $self->{ID},
        }
    )->single;

    return unless ($litlist);

    eval {
        $litlist->litlist_topics->delete;
        $litlist->litlistitems->delete;
        $litlist->delete;
    };

    if ($@){
        $logger->error($@);
    }
        
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
        ? $arg_ref->{lecture}             : 0;
    my $topics_ref        = exists $arg_ref->{topics}
        ? $arg_ref->{topics}            : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return if (!$litlistid || !$title || !$type);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;

    my $litlist = $self->get_schema->resultset('Litlist')->single(
        {
            id     => $litlistid,
        }
    );
    
    return unless ($litlist);

    # DBI: "update litlist set title=?, type=?, lecture=? where id=?"
    $litlist->update(
        {
            title   => $title,
            type    => $type,
            lecture => $lecture,
        }
    );
    
    unless (ref($topics_ref) eq 'ARRAY') {
        $topics_ref = [ $topics_ref ];
    }
    
    if (@{$topics_ref}){
        # DBI: "delete from litlist_topic where litlistid = ?"

        $litlist->delete_related('litlist_topics');

        foreach my $topicid (@{$topics_ref}){
            # DBI: "insert into litlist_topic (litlistid,topicid) values (?,?)"
            $litlist->create_related('litlist_topics',
                                     {
                                         topicid => $topicid,
                                     }      
                                 );
        }
    }

    return;
}

sub add_litlistentry {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid             = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;
    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}             : undef;
    my $dbname                = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}              : undef;
    my $comment               = exists $arg_ref->{comment}
        ? $arg_ref->{comment}             : undef;
    my $record                = exists $arg_ref->{record}
        ? $arg_ref->{record}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $new_litlistitem;
    
    if ($titleid && $dbname){
        # DBI: "delete from litlistitem where litlistid=? and titleid=? and dbname=?"
        my $litlistitem = $self->get_schema->resultset('Litlistitem')->search_rs(
            {        
                litlistid => $litlistid,
                dbname    => $dbname,
                titleid   => $titleid,
            }
        )->single;
        
        return if ($litlistitem);
        
        my $cached_title = OpenBib::Record::Title->new({ id => $titleid, database => $dbname, config => $config })->load_brief_record->to_json;
        
        $logger->debug("Caching Bibliographic Data: $cached_title");

        # DBI: "insert into litlistitem (litlistid,titleid,dbname) values (?,?,?)"
        $new_litlistitem = $self->get_schema->resultset('Litlistitem')->create(
            {
                litlistid  => $litlistid,
                dbname     => $dbname,
                titleid    => $titleid,
                titlecache => $cached_title,
                comment    => $comment,
                tstamp     => \'NOW()',
            }
        );
    }
    elsif ($record){
        # DBI: "delete from litlistitem where litlistid=? and titleid=? and dbname=?"

        my $record_json = encode_json $record;
        
        my $litlistitem = $self->get_schema->resultset('Litlistitem')->search_rs(
            {        
                litlistid  => $litlistid,
                titlecache => $record_json,
            }
        )->single;
        
        return if ($litlistitem);
    
        $logger->debug("Caching Bibliographic Data: $record_json");
        
        # DBI: "insert into litlistitem (litlistid,titleid,dbname) values (?,?,?)"
        $new_litlistitem = $self->get_schema->resultset('Litlistitem')->create(
            {
                litlistid  => $litlistid,
                titleid    => 0,
                dbname     => '',
                titlecache => $record_json,
                comment    => $comment,
                tstamp     => \'NOW()',                
            }
        );
    }

    if ($new_litlistitem){
        return $new_litlistitem->id;
    }

    return;
}

sub update_litlistentry {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid             = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;
    my $itemid                = exists $arg_ref->{itemid}
        ? $arg_ref->{itemid}              : undef;
    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}             : undef;
    my $dbname                = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}              : undef;
    my $comment               = exists $arg_ref->{comment}
        ? $arg_ref->{comment}             : undef;
    my $record                = exists $arg_ref->{record}
        ? $arg_ref->{record}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # DBI: "delete from litlistitem where litlistid=? and titleid=? and dbname=?"
    my $litlistitem = $self->get_schema->resultset('Litlistitem')->search_rs(
        {        
            litlistid => $litlistid,
            id        => $itemid,
        }
    )->single;
    
    return 1 if (!$litlistitem);

    if ($titleid && $dbname){
        
        my $cached_title = OpenBib::Record::Title->new({ id => $titleid, database => $dbname, config => $config })->load_brief_record->to_json;
        
        $logger->debug("Caching Bibliographic Data: $cached_title Comment: $comment");

        # DBI: "insert into litlistitem (litlistid,titleid,dbname) values (?,?,?)"
        $litlistitem->update(
            {
                dbname     => $dbname,
                titleid    => $titleid,
                titlecache => $cached_title,
                tstamp     => \'NOW()',
                comment    => $comment,
            }
        );
    }
    elsif ($record){
        my $record_json = encode_json $record;

        $logger->debug("Caching Bibliographic Data: $record_json");
        
        # DBI: "insert into litlistitem (litlistid,titleid,dbname) values (?,?,?)"
        $litlistitem->update(
            {
                titlecache => $record_json,
                tstamp     => \'NOW()',                
                comment    => $comment,
            }
        );
    }

    return;
}

sub del_litlistentry {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;
    my $entryid             = exists $arg_ref->{entryid}
        ? $arg_ref->{entryid}             : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return if (!$litlistid && !$entryid );

    # DBI: "delete from litlistitem where litlistid=? and titleid=? and dbname=?"
    my $litlistitem = $self->get_schema->resultset('Litlistitem')->search_rs({        
        litlistid => $litlistid,
        id        => $entryid,
    });

    if ($litlistitem){
        $litlistitem->delete;
    }

    return;
}

sub get_litlists {
    my ($self,$arg_ref)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $view                = exists $arg_ref->{view}
        ? $arg_ref->{view}                : '';
    
    return [] if (!$self->{ID});

    my $litlists_ref = [];

    # DBI: "select id from litlist where userid=?"
    my $litlists = $self->get_schema->resultset('Litlist')->search_rs(
        {
            userid => $self->{ID},
        }
    );

    foreach my $litlist ($litlists->all){
      push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->id, view => $view});
    }
    
    return $litlists_ref;
}

sub get_recent_litlists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $count        = exists $arg_ref->{count}
        ? $arg_ref->{count}           : 5;

    my $topicid      = exists $arg_ref->{topicid}
        ? $arg_ref->{topicid}           : undef;

    my $database     = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;

    my $view         = exists $arg_ref->{view}
        ? $arg_ref->{view}              : '';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $litlists;
    
    if ($topicid){
#        $litlists = $self->get_schema->resultset('Litlist')->search(
#             {
#                 'topicid.id'  => $topicid,
#                 'me.type'       => 1,
#             },
#             {
#                 select   => [ 'me.id' ],
#                 as       => ['thislitlistid'],
#                 order_by => [ 'me.id DESC' ],
#                 rows     => $count,
#                 prefetch => [{ 'litlist_topics' => 'topicid' }],
#                 join     => [ 'litlist_topics' ],
#             }
#         );
        $litlists = $self->get_schema->resultset('LitlistTopic')->search(
            {
                'topicid.id'   => $topicid,
                'litlistid.type' => 1,
            },
            {
                select   => [ 'litlistid.id' ],
                as       => ['thislitlistid'],
                order_by => [ 'litlistid.id DESC' ],
                rows     => $count,
                join     => [ 'litlistid', 'topicid' ],
            }
        );
    }
    elsif ($database){
        $litlists = $self->get_schema->resultset('Litlist')->search(
            {
                'type' => 1,
                'litlistitems.dbname' => $database,
            },
            {
                select   => [ 'me.id' ],
                as       => ['thislitlistid'],
                group_by => ['me.id'],
                order_by => [ 'me.id DESC' ],
                rows     => $count,
                join     => [ 'litlistitems'],
            }
        );
    }
    else {
        $litlists = $self->get_schema->resultset('Litlist')->search(
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
        push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->get_column('thislitlistid'), view => $view});
    }
    
    return $litlists_ref;
}

sub get_number_of_public_litlists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $topicid      = exists $arg_ref->{topicid}
        ? $arg_ref->{topicid}        : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $count;
    
    if ($topicid){
        $count = $self->get_schema->resultset('Litlist')->search(
            {
                'topicid.id'  => $topicid,
                'me.type'     => 1,
            },
            {
                select   => [ 'me.id' ],
                as       => ['thislitlistid'],
#                prefetch => [{ 'litlist_topics' => 'topicid' }],
                join     => [ 'litlist_topics', { 'litlist_topics' => 'topicid' } ],
            }
        )->count;

#        $sql_stmnt = "select distinct(ls.litlistid) as id from litlist_topic as ls, litlist as l where ls.topicid = ? and ls.litlistid = l.id and l.type = 1";
#        push @sql_args, $topicid;
    }
    else {
        $count = $self->get_schema->resultset('Litlist')->search(
            {
                'type' => 1,
            },
        )->count;
    }

    $logger->debug("Got $count public litlists for topic $topicid");
    
    return $count;
}

sub get_public_litlists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $topicid      = exists $arg_ref->{topicid}
        ? $arg_ref->{topicid}        : undef;
    my $offset       = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : undef;
    my $num          = exists $arg_ref->{num}
        ? $arg_ref->{num}        : undef;
    my $view         = exists $arg_ref->{view}
        ? $arg_ref->{view}       : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("Getting public litlists with offset $offset, num $num for topic $topicid");
    my $litlists;
    
    if ($topicid){
        $litlists = $self->get_schema->resultset('Litlist')->search(
            {
                'topicid.id'  => $topicid,
                'me.type'     => 1,
            },
            {
#                select   => [ {distinct => 'me.id'} ],
                order_by => ['title ASC'],
                group_by => ['me.id'],
                rows     => $num,
                offset   => $offset,
                select   => [ 'me.id' ],
                as       => ['thislitlistid'],
#                prefetch => [{ 'litlist_topics' => 'topicid' }],
                join     => [ 'litlist_topics', { 'litlist_topics' => 'topicid' } ],
            }
        );

#        $sql_stmnt = "select distinct(ls.litlistid) as id from litlist_topic as ls, litlist as l where ls.topicid = ? and ls.litlistid = l.id and l.type = 1";
#        push @sql_args, $topicid;
    }
    else {
        $litlists = $self->get_schema->resultset('Litlist')->search(
            {
                'type' => 1,
            },
            {
                order_by => ['title ASC'],
                rows     => $num,
                offset   => $offset,
                select   => ['id'],
                as       => ['thislitlistid'],
            }
        );

        # $sql_stmnt = "select id from litlist where type = 1";
    }

    my $litlists_ref = [];

    foreach my $litlist ($litlists->all){
      my $litlistid        = $litlist->get_column('thislitlistid');

      my $properties_ref = $self->get_litlist_properties({litlistid => $litlistid, view => $view});
      push @$litlists_ref, $properties_ref;
    }

    return $litlists_ref;
}

sub get_other_litlists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;
    my $view                = exists $arg_ref->{view}
        ? $arg_ref->{view}                : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $litlists_ref = {
        same_user     => [],
        same_title    => [],
    };

    return $litlists_ref if (!$litlistid);

    # Gleicher Nutzer
    # DBI: "select id,title from litlist where type = 1 and id != ? and userid in () order by title";

    my $inside_same_user = $self->get_schema->resultset('Litlist')->search_rs({ id => $litlistid});
    
    my $same_user = $self->get_schema->resultset('Litlist')->search_rs(
        {
            id   => { '!=' => $litlistid },
            type => 1,
            userid => { -in => $inside_same_user->get_column('userid')->as_query },
        }
    );
    
    foreach my $litlist ($same_user->all){
      my $litlistid        = $litlist->id;
      
      push @{$litlists_ref->{same_user}}, $self->get_litlist_properties({litlistid => $litlistid}, view => $view);
    }

    # Gleicher Titel
    # DBI: "select distinct b.litlistid from litlistitems as a left join litlistitems as b on a.dbname=b.dbname where a.titleid=b.titleid and a.litlistid=? and b.litlistid!=?";

    my $inside_same_title = $self->get_schema->resultset('Litlistitem')->search_rs({ litlistid => $litlistid});
    my $same_title = $self->get_schema->resultset('Litlistitem')->search_rs(
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

	if ($logger->is_debug && defined $litlistid){
	    $logger->debug("Found litlist $litlistid with same title");
	}

        my $litlist_props    = $self->get_litlist_properties({litlistid => $litlistid, view => $view});
        push @{$litlists_ref->{same_title}}, $litlist_props if ($litlist_props->{type} == 1);
    }

    $logger->debug($litlists_ref);
    
    return $litlists_ref;
}

sub get_litlistentries {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    my $view                = exists $arg_ref->{view}
        ? $arg_ref->{view}            : undef;
    
    my $sorttype            = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}            : undef;

    my $sortorder           = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;

    my $litlistitems;

    if ($view){
        my $databases =  $self->get_schema->resultset('ViewDb')->search(
            {
                -or => [
                    {
                        'dbid.active'           => 1,
                        'viewid.viewname'       => $view,
                    },
                    {
                        'dbid.active'           => 1,
                        'dbid.system'           => { '~' => '^Backend' },
                    },
                ],
            }, 
            {
                join => ['dbid','viewid'],
                select   => [ 'dbid.dbname' ],
                as       => ['dbname'],
                group_by => ['dbid.dbname'],
            }
        );

        $litlistitems = $self->get_schema->resultset('Litlistitem')->search_rs(
            {
                litlistid => $litlistid,
                dbname    => { -in => $databases->as_query },
            }
        );

    }
    else {
        # DBI: "select titleid,dbname,tstamp from litlistitem where litlistid=?"
        $litlistitems = $self->get_schema->resultset('Litlistitem')->search_rs(
            {
                litlistid => $litlistid,
            }
        );
    }
    
    my $recordlist = new OpenBib::RecordList::Title();

    foreach my $litlistitem ($litlistitems->all){
        my $listid     = $litlistitem->id;
        my $titleid    = $litlistitem->titleid;
        my $database   = $litlistitem->dbname;
        my $tstamp     = $litlistitem->tstamp;
        my $comment    = $litlistitem->comment;
        my $titlecache = $litlistitem->titlecache;
        
        my $record = ($titleid && $database)?OpenBib::Record::Title->new({id =>$titleid, database => $database, date => $tstamp, listid => $listid, comment => $comment, config => $config })->load_brief_record:OpenBib::Record::Title->new({ date => $tstamp, listid => $listid, comment => $comment, config => $config })->set_fields_from_json($titlecache);
        
        $recordlist->add($record);
    }
    
    $recordlist->sort({order=>$sortorder,type=>$sorttype});
        
    return $recordlist;
}

sub get_single_litlistentry {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    my $itemid              = exists $arg_ref->{itemid}
        ? $arg_ref->{itemid}              : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # DBI: "select titleid,dbname,tstamp from litlistitem where litlistid=?"
    my $litlistitem = $self->get_schema->resultset('Litlistitem')->search_rs(
        {
            litlistid => $litlistid,
            id => $itemid,
        }
    )->single;

    if ($litlistitem){
        my $listid     = $litlistitem->id;
        my $titleid    = $litlistitem->titleid;
        my $database   = $litlistitem->dbname;
        my $tstamp     = $litlistitem->tstamp;
        my $comment    = $litlistitem->comment;
        my $titlecache = $litlistitem->titlecache;
        
        my $record = ($titleid && $database)?OpenBib::Record::Title->new({id =>$titleid, database => $database, date => $tstamp, listid => $listid, comment => $comment, config => $config })->load_brief_record:OpenBib::Record::Title->new({ date => $tstamp, listid => $listid, comment => $comment, config => $config })->set_fields_from_json($titlecache);

        return $record;
    }

    return OpenBib::Record::Title->new({config => $config});
}

sub get_number_of_litlistentries {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    my $view                = exists $arg_ref->{view}
        ? $arg_ref->{view}                : '';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $numofentries;
    
    if ($view){
        my $databases =  $self->get_schema->resultset('ViewDb')->search(
            {
                -or => [
                    {
                        'dbid.active'           => 1,
                        'viewid.viewname'       => $view,
                    },
                    {
                        'dbid.active'           => 1,
                        'dbid.system'           => { '~' => '^Backend' },
                    },
                ],
            }, 
            {
                join => ['dbid','viewid'],
                select   => [ 'dbid.dbname' ],
                as       => ['dbname'],
                group_by => ['dbid.dbname'],
            }
        );
        
        $numofentries = $self->get_schema->resultset('Litlistitem')->search(
            {
                litlistid => $litlistid,
                dbname    => { -in => $databases->as_query },
            }
        )->count;

    }
    else {
        # DBI: "select count(litlistid) as numofentries from litlistitem where litlistid=?"
        $numofentries = $self->get_schema->resultset('Litlistitem')->search(
            {
                litlistid => $litlistid,
            }
        )->count;
    }
    
    return $numofentries;
}

sub get_number_of_litlists {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(id) as numoflitlists from litlist where type = 1"
    my $public_lists = $self->get_schema->resultset('Litlist')->search(
        {
            type => 1,
        }
    )->count;
    
    # DBI: "select count(id) as numoflitlists from litlists where type = 2"
    my $private_lists = $self->get_schema->resultset('Litlist')->search(
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

    my $view                = exists $arg_ref->{view}
        ? $arg_ref->{view}                : '';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return {} if (!$litlistid);

    # DBI: "select * from litlist where id = ?"
    my $litlist = $self->get_schema->resultset('Litlist')->single(
        {
            id => $litlistid,
        }   
    );

    return {} if (!$litlist);

    my $title     = $litlist->title;
    my $type      = $litlist->type;
    my $lecture   = $litlist->lecture;
    my $tstamp    = $litlist->tstamp;
    my $userid    = $litlist->userid->id;
    my $itemcount = $self->get_number_of_litlistentries({litlistid => $litlistid, view => $view});

    # DBI: "select s.* from litlist_topic as ls, topic as s where ls.litlistid=? and ls.topicid=s.id"
    my $topics = $self->get_schema->resultset('LitlistTopic')->search_rs(
        {
            'litlistid.id' => $litlistid,
        },
        {
            select => ['topicid.id','topicid.description','topicid.name'],
            as     => ['thistopicid','thistopicdescription','thistopicname'],
            
            join => ['litlistid','topicid'],
        }
    );
    
    my $topics_ref          = [];
    my $topic_selected_ref  = {};

    foreach my $topic ($topics->all){
        my $topicid   = $topic->get_column('thistopicid');
        my $name        = $topic->get_column('thistopicname');
        my $description = $topic->get_column('thistopicdescription');

        $topic_selected_ref->{$topicid}=1;
        push @{$topics_ref}, {
            id          => $topicid,
            name        => $name,
            description => $description,
            litlistcount => $self->get_number_of_litlists_by_topic({topicid => $topicid}),
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
                        topics         => $topics_ref,
                        topic_selected => $topic_selected_ref,
		       };

    return $litlist_ref;
}

sub get_topics {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from topics order by name"
    my $topics = $self->get_schema->resultset('Topic')->search_rs(
        undef,        
        {
            'order_by' => ['name'],
        }
    );

    my $topics_ref = [];
    
    foreach my $topic ($topics->all){
        push @{$topics_ref}, {
            id           => $topic->id,
            name         => $topic->name,
            description  => $topic->description,
            litlistcount => $self->get_number_of_litlists_by_topic({topicid => $topic->id}),
        };
    }

    return $topics_ref;
}

sub get_topics_of_litlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $topics = $self->get_schema->resultset('LitlistTopic')->search_rs(
        {
            'litlistid.id' => $litlistid,
        },
        {
            select => ['topicid.id','topicid.description','topicid.name'],
            as     => ['thistopicid','thistopicdescription','thistopicname'],
            
            join => ['litlistid','topicid'],
        }
    );
    
    my $topics_ref = [];
    
    foreach my $topic ($topics->all){
        my $topicid   = $topic->get_column('thistopicid');
        my $name        = $topic->get_column('thistopicname');
        my $description = $topic->get_column('thistopicdescription');

        push @{$topics_ref}, {
            id          => $topicid,
            name        => $name,
            description => $description,
            litlistcount => $self->get_number_of_litlists_by_topic({topicid => $topicid}),
        };
    }

    return $topics_ref;
}

sub get_classifications_of_topic {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $topicid           = exists $arg_ref->{topicid}
        ? $arg_ref->{topicid}           : undef;

    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'BK';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return [] if (!defined $topicid);

    # DBI: "select * from topicclassification where topicid = ? and type = ?"
    my $classifications = $self->get_schema->resultset('Topicclassification')->search_rs(
        {
            topicid => $topicid,
            type      => $type,
        }   
    );
    
    my $classifications_ref = [];

    foreach my $classification ($classifications->all){
        push @{$classifications_ref}, $classification->classification;
    }

    if ($logger->is_debug){
        $logger->debug("Got classifications ".YAML::Dump($classifications_ref));
    }

    return $classifications_ref;
}

sub set_classifications_of_topic {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $topicid           = exists $arg_ref->{topicid}
        ? $arg_ref->{topicid}           : undef;

    my $classifications_ref = exists $arg_ref->{classifications}
        ? $arg_ref->{classifications}     : undef;

    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'bk';
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("Classifications4 ".YAML::Dump($classifications_ref));
    }

    unless (ref($classifications_ref) eq 'ARRAY') {
        $classifications_ref = [ $classifications_ref ];
    }

    # DBI: "delete from topicclassification where topicid=? and type = ?"
    my $topicclassifications = $self->get_schema->resultset('Topicclassification')->search_rs(
        {
            topicid   => $topicid,
            type      => $type,
        }
    )->delete;

    foreach my $classification (@{$classifications_ref}){
        $logger->debug("Adding Classification $classification of type $type");
        
        # DBI: "insert into topicclassification values (?,?,?);"
        $self->get_schema->resultset('Topicclassification')->create(
            {
                classification => $classification,
                topicid        => $topicid,
                type           => $type,
            }
        );
    }
    
    return;
}

sub get_number_of_litlists_by_topic {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $topicid           = exists $arg_ref->{topicid}
        ? $arg_ref->{topicid}           : undef;

    my $type               = exists $arg_ref->{type}
        ? $arg_ref->{type}              : 1;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $count_ref={};

    #    $self->get_schema->storage->debug(1);
    # DBI: "select count(distinct l2s.litlistid) as llcount from litlist_topic as l2s, litlist as l where l2s.litlistid=l.id and l2s.topicid=? and l.type=1 and (select count(li.litlistid) > 0 from litlistitem as li where l2s.litlistid=li.litlistid)"
    $count_ref->{public} = $self->get_schema->resultset('Litlist')->search(
        {
            'topicid.id'  => $topicid,
            'me.type' => 1,
        },
        {
            prefetch => [{ 'litlist_topics' => 'topicid' }],
            join     => [ 'litlist_topics', 'litlistitems' ],
        }
    )->count;

    if ($type eq "all"){
        # "select count(distinct litlistid) as llcount from litlist2topic as l2s where topicid=? and (select count(li.litlistid) > 0 from litlistitems as li where l2s.litlistid=li.litlistid)"
        $count_ref->{all}=$self->get_schema->resultset('Litlist')->search(
            {
                'topicid.id'  => $topicid,
            },
            {
                prefetch => [{ 'litlist_topics' => 'topicid' }],
                join     => [ 'litlist_topics', 'litlistitems' ],
            }
        )->count;
        
        $count_ref->{private} = $count_ref->{all} - $count_ref->{public};
    }

 

    return $count_ref;
}

sub set_topics_of_litlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    my $topics_ref        = exists $arg_ref->{topics}
        ? $arg_ref->{topics}            : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "delete from litlist_topic where litlistid=?"
    $self->get_schema->resultset('LitlistTopic')->search_rs(
        {
            litlistid => $litlistid,
        }   
    )->delete_all;
    
    # DBI: "insert into litlist_topic values (?,?);"

    foreach my $topicid (@{$topics_ref}){
        $self->get_schema->resultset('LitlistTopic')->create(
            {
                litlistid => $litlistid,
                topicid => $topicid,
            }
        );
    }

    return;
}

sub get_topic {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id           = exists $arg_ref->{id}
        ? $arg_ref->{id}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from topic where id = ?"
    my $topic = $self->get_schema->resultset('Topic')->search_rs(
        {
            id => $id,
        }
    )->first;

    my $topic_ref = {};
    
    if ($topic){
        $topic_ref = {
            id           => $topic->id,
            name         => $topic->name,
            description  => $topic->description,
        };
    }

    return $topic_ref;
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

    my $ownerid = $self->get_litlist_properties({ litlistid => $litlistid })->{userid};

    $logger->debug("Got Ownerid $ownerid for Litlist $litlistid");
    
    return $ownerid;
}

sub get_litlists_of_tit {
    my ($self,$arg_ref)=@_;

    my $titleid               = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}               : undef;
    my $dbname                = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
    my $view                  = exists $arg_ref->{view}
        ? $arg_ref->{view}                 : '';

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return [] if (!$titleid || !$dbname);

    # DBI: "select ll.* from litlistitem as lli, litlist as ll where ll.id=lli.litlistid and lli.titleid=? and lli.dbname=?") or $logger->error($DBI::errstr);

    my $litlists = $self->get_schema->resultset('Litlistitem')->search_rs(
        {
            'me.titleid'       => $titleid,
            'me.dbname'        => $dbname,
        },
        {
            select => ['me.litlistid','litlistid.userid','litlistid.type'],
            as     => ['thislitlistid','thisuserid','thistype'],
            join   => ['litlistid']
        }
    );

    my $litlists_ref = [];

    foreach my $litlist ($litlists->all){
        if ((defined $self->{ID} && defined $litlist->get_column('thisuserid') && $self->{ID} eq $litlist->get_column('thisuserid')) || (defined $litlist->get_column('thistype') && $litlist->get_column('thistype') eq "1")){
            push @$litlists_ref, $self->get_litlist_properties({litlistid => $litlist->get_column('thislitlistid'), view => $view});
        };
    }

    return $litlists_ref;
}

sub get_single_item_in_collection {
    my ($self,$listid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $cartitem = $self->get_schema->resultset('UserCartitem')->search_rs(
        {
            'cartitemid.id'  => $listid,
            'userid.id'      => $self->{ID},
        },
        {
            select => ['cartitemid.dbname','cartitemid.titleid','cartitemid.id','cartitemid.titlecache','cartitemid.tstamp','cartitemid.comment'],
            as     => ['thisdbname','thistitleid','thisid','thistitlecache','thiststamp','thiscomment'],
            join   => ['userid','cartitemid'],
        }
    )->single;

    if ($cartitem){
        my $database   = $cartitem->get_column('thisdbname');
        my $titleid    = $cartitem->get_column('thistitleid');
        my $listid     = $cartitem->get_column('thisid');
        my $titlecache = $cartitem->get_column('thistitlecache');
        my $tstamp     = $cartitem->get_column('thiststamp');
        my $comment    = $cartitem->get_column('thiscomment');
        
        my $record = ($titleid && $database)?OpenBib::Record::Title->new({id =>$titleid, database => $database, listid => $listid, tstamp => $tstamp, comment => $comment, config => $config })->load_brief_record:OpenBib::Record::Title->new({ listid => $listid, config => $config })->set_fields_from_json($titlecache);

        return $record;
    }
    
    return;
}

sub get_items_in_collection {
    my ($self,$arg_ref)=@_;

    my $view                = exists $arg_ref->{view}
        ? $arg_ref->{view}                : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $recordlist = new OpenBib::RecordList::Title();

    my $cartitems;
    
    if ($view){
        my $databases =  $self->get_schema->resultset('ViewDb')->search(
            {
                -or => [
                    {
                        'dbid.active'           => 1,
                        'viewid.viewname'       => $view,
                    },
                    {
                        'dbid.active'           => 1,
                        'dbid.system'           => { '~' => '^Backend' },
                    },
                ],
            }, 
            {
                join => ['dbid','viewid'],
                select   => [ 'dbid.dbname' ],
                as       => ['dbname'],
                group_by => ['dbid.dbname'],
            }
        );

        $cartitems = $self->get_schema->resultset('UserCartitem')->search_rs(
            {
                'userid.id'          => $self->{ID},
                'cartitemid.dbname'  => { -in => $databases->as_query },
                
            },
            {
                select  => [ 'cartitemid.dbname', 'cartitemid.titleid', 'cartitemid.titlecache', 'cartitemid.id', 'cartitemid.tstamp', 'cartitemid.comment' ],
                as      => [ 'thisdbname', 'thistitleid', 'thistitlecache', 'thislistid', 'thiststamp', 'thiscomment' ],
                join    => ['userid','cartitemid'],
            }
        );
    }
    else {
        # DBI: "select * from collection where userid = ? order by dbname"
        $cartitems = $self->get_schema->resultset('UserCartitem')->search_rs(
            {
                'userid.id' => $self->{ID},
            },
            {
                select  => [ 'cartitemid.dbname', 'cartitemid.titleid', 'cartitemid.titlecache', 'cartitemid.id', 'cartitemid.tstamp', 'cartitemid.comment' ],
                as      => [ 'thisdbname', 'thistitleid', 'thistitlecache', 'thislistid', 'thiststamp', 'thiscomment' ],
                join    => ['userid','cartitemid'],
            }
        );
    }

    foreach my $item ($cartitems->all){
        my $database   = $item->get_column('thisdbname');
        my $titleid    = $item->get_column('thistitleid');
        my $titlecache = $item->get_column('thistitlecache');
        my $listid     = $item->get_column('thislistid');
        my $tstamp     = $item->get_column('thiststamp');
        my $comment    = $item->get_column('thiscomment');

        $logger->debug("Processing Item $listid with DB: $database ID: $titleid / Record: $titlecache");

        if ($database && $titleid){
            $recordlist->add(new OpenBib::Record::Title({ database => $database, id => $titleid, listid => $listid, date => $tstamp, comment => $comment, config => $config })->load_brief_record);
        }
        elsif ($titlecache) {
            my $record = new OpenBib::Record::Title({listid => $listid, date => $tstamp, comment => $comment, config => $config });
            $record->set_fields_from_json($titlecache);
            $recordlist->add($record);
        }
    }
    
    return $recordlist;
}

sub add_item_to_collection {
    my ($self,$arg_ref)=@_;

    my $userid       = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;

    my $dbname       = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
    
    my $titleid      = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}              : undef;
    
    my $comment      = exists $arg_ref->{comment}
        ? $arg_ref->{comment}              : '';
    
    my $record       = exists $arg_ref->{record}
        ? $arg_ref->{record}               : undef;
    
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    my $new_title ;

    if ($dbname && $titleid){
        # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
        
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        my $have_title = $self->get_schema->resultset('UserCartitem')->search_rs(
            {
                'userid.id'                => $thisuserid,
                'cartitemid.dbname'  => $dbname,
                'cartitemid.titleid' => $titleid,
            },
            {
                join => ['userid','cartitemid'],
            }
        )->count;
        
        if (!$have_title) {
            my $cached_title = new OpenBib::Record::Title({ database => $dbname , id => $titleid, config => $config });
            my $record_json = $cached_title->load_brief_record->to_json;
            
            $logger->debug("Adding Title to Usercollection: $record_json");
            
            # DBI "insert into treffer values (?,?,?,?)"
            $new_title = $self->get_schema->resultset('Cartitem')->create(
                {
                    dbname     => $dbname,
                    titleid    => $titleid,
                    titlecache => $record_json,
                    comment    => $comment,
                    tstamp     => \'NOW()',
                }
            );

            $self->get_schema->resultset('UserCartitem')->create(
                {
                    userid           => $thisuserid,
                    cartitemid => $new_title->id,
                }
            );
        }
    }
    elsif ($record){
        # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
        
        my $record_json = encode_json $record;
        
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        my $have_title = $self->get_schema->resultset('UserCartitem')->search_rs(
            {
                'userid.id'                   => $thisuserid,
                'cartitemid.titlecache' => $record_json,
            },
            {
                join => ['userid','cartitemid'],
            }
        )->count;
        
        if (!$have_title) {
            $logger->debug("Adding Title to Usercollection: $record_json");
            
            # DBI "insert into treffer values (?,?,?,?)"
            $new_title = $self->get_schema->resultset('Cartitem')->create(
                {
                    titleid    => '',
                    dbname     => '',
                    titlecache => $record_json,
                    comment    => $comment,
                    tstamp     => \'NOW()',
                }
            );

            $self->get_schema->resultset('UserCartitem')->create(
                {
                    userid           => $thisuserid,
                    cartitemid => $new_title->id,
                }
            );
        }
    }

    if ($new_title){
        my $new_titleid = $new_title->id;
        $logger->debug("Created new collection entry with id $new_titleid");
        return $new_titleid;
    }
    
    return ;
}

sub move_cartitem_to_user {
    my ($self,$arg_ref)=@_;

    my $itemid       = exists $arg_ref->{itemid}
        ? $arg_ref->{itemid}               : undef;

    my $userid       = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    my $new_title ;

    if ($itemid){
        eval {
            $self->get_schema->resultset('UserCartitem')->create(
                {
                    userid           => $thisuserid,
                    cartitemid => $itemid,
                }
            );
            $self->get_schema->resultset('SessionCartitem')->single(
                {
                    cartitemid => $itemid,
                }
            )->delete;
        };

        if ($@){
            $logger->error($@);
        }

    }       
    $logger->debug("Connected existing collection entry $itemid with userid $thisuserid");
    
    return ;
}

# Aktualisiert werden kann nur der Kommentar!
sub update_item_in_collection {
    my ($self,$arg_ref)=@_;

    my $userid       = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;

    my $itemid       = exists $arg_ref->{itemid}
        ? $arg_ref->{itemid}               : undef;

    my $comment      = exists $arg_ref->{comment}
        ? $arg_ref->{comment}              : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    if ($itemid){
        # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
        
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        my $title = $self->get_schema->resultset('Cartitem')->search_rs(
            {
                'user_cartitemids.userid'  => $thisuserid,
                'me.id'                          => $itemid,
            },
            {
                join => ['user_cartitemids'],
            }
        );

        if ($title) {
            $title->update(
                {
                    comment    => $comment,
                    tstamp     => \'NOW()',
                }
            );
        }

    }

    return ;
}

sub delete_item_from_collection {
    my ($self,$arg_ref)=@_;

    my $userid         = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;

    my $itemid         = exists $arg_ref->{id}
        ? $arg_ref->{id}                   : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thisuserid = (defined $userid)?$userid:$self->{ID};

    $logger->debug("Trying to delete Item $itemid for user $thisuserid");
    
    eval {
        # DBI: "delete from treffer where sessionid = ? and dbname = ? and singleidn = ?"
        my $item = $self->get_schema->resultset('Cartitem')->search_rs(
            {
                'user_cartitems.userid' => $thisuserid,
                'me.id'                 => $itemid
            },
            {
                join => ['user_cartitems']
            }
        )->single;

        if ($item){
            $item->user_cartitems->delete;
            $item->delete;
        }
        else {
            $logger->debug("Can't delete Item $itemid: ".$@);
        }
    };

    if ($@){
        $logger->error($@);
    }
    
    return ;
}

sub update_user_rights_role {
    my ($self,$userinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "delete from user_role where userid=?"
    $self->get_schema->resultset('UserRole')->search_rs(
        {
            userid => $userinfo_ref->{id},
        }
    )->delete_all;
    
    foreach my $roleid (@{$userinfo_ref->{roles}}){
        $logger->debug("Adding Role $roleid to user $userinfo_ref->{id}");

        # DBI: "insert into user_role values (?,?)"
        $self->get_schema->resultset('UserRole')->search_rs(
            {
                userid => $userinfo_ref->{id},
            }
        )->create(
            {
                userid => $userinfo_ref->{id},
                roleid => $roleid,
            }
        );
    }

    return;
}

sub update_user_rights_template {
    my ($self,$userinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->get_schema->resultset('UserTemplate')->search_rs(
        {
            userid => $userinfo_ref->{id},
        }
    )->delete_all;
    
    foreach my $templateid (@{$userinfo_ref->{templates}}){
        $logger->debug("Adding Template $templateid to user $userinfo_ref->{id}");

        $self->get_schema->resultset('UserTemplate')->search_rs(
            {
                userid => $userinfo_ref->{id},
            }
        )->create(
            {
                userid     => $userinfo_ref->{id},
                templateid => $templateid,
            }
        );
    }

    return;
}

sub update_user_rights_view {
    my ($self,$userinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->get_schema->resultset('UserView')->search_rs(
        {
            userid => $userinfo_ref->{id},
        }
    )->delete_all;
    
    foreach my $viewname (@{$userinfo_ref->{views}}){
        $logger->debug("Adding View $viewname to user $userinfo_ref->{id}");

        my $viewid = $self->get_viewinfo->single({ viewname => $viewname })->id;

        next unless ($viewid);
        
        $self->get_schema->resultset('UserView')->search_rs(
            {
                userid => $userinfo_ref->{id},
            }
        )->create(
            {
                userid => $userinfo_ref->{id},
                viewid => $viewid,
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
    my $profile = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            profilename => $profilename,
            userid      => $self->{ID},
        }   

    )->first;

    if ($profile){
        return $profile->id,
    }
    else {
        return 0;
    }
    
}

sub new_dbprofile {
    my ($self,$profilename,$databases_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $searchprofileid = $config->get_searchprofile_or_create($databases_ref);
    
    # DBI: "insert into user_profile values (NULL,?,?)"
    my $new_profile = $self->get_schema->resultset('UserSearchprofile')->create(
        {
            profilename     => $profilename,
            userid          => $self->{ID},
            searchprofileid => $searchprofileid,
        }
    );
    
    return $new_profile->id;
}

sub update_dbprofile {
    my ($self,$profileid,$profilename,$databases_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $searchprofileid = $config->get_searchprofile_or_create($databases_ref);

    # DBI: "insert into user_profile values (NULL,?,?)"
    my $profile = $self->get_schema->resultset('UserSearchprofile')->search_rs(
        {
            userid           => $self->{ID},
            id               => $profileid,

        }
    )->single();

    if ($profile){
        $profile->update(
            {
                profilename     => $profilename,
                userid          => $self->{ID},
                searchprofileid => $searchprofileid,
            }
        );
    }
    
    return;
}

sub delete_dbprofile {
    my ($self,$profileid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "delete from user_profile where userid = ? and profileid = ?"
    $self->get_schema->resultset('UserSearchprofile')->search_rs(
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

    my $userinfo = $self->get_schema->resultset('Userinfo')->single({
        id => $self->{ID}
    });

    if ($userinfo){
        # Zuerst werden die Datenbankprofile geloescht
        # DBI: "delete from profildb using profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid=profildb.profilid"
        $userinfo->user_searchprofiles->delete;
    
        # .. dann die Suchfeldeinstellungen
        # DBI: "delete from searchfield where userid = ?"
        $userinfo->searchfields->delete;

        # .. dann die Livesearcheinstellungen
        # DBI: "delete from livesearch where userid = ?"
        $userinfo->livesearches->delete;

        # .. dann die Tags
        $userinfo->tit_tags->delete;

        # .. dann die Literaturlisten
#        $userinfo->litlists->litlist_topics->delete;
#        $userinfo->litlists->litlistitems->delete;
        $userinfo->litlists->delete;

        # .. dann die Reviewratings
        $userinfo->reviewratings->delete;

        # .. dann die Reviews
        $userinfo->reviews->delete;
        
        # .. dann die Rollen
        # DBI: "delete from livesearch where userid = ?"
        $userinfo->user_roles->delete;

        # .. dann die Merkliste
        # DBI: "delete from collection where userid = ?"
#        $userinfo->user_cartitems->cartitems->delete;
        $userinfo->user_cartitems->delete;

        # .. dann die Verknuepfung zur Session
        # DBI: "delete from user_session where userid = ?"
        $userinfo->user_sessions->delete;
    
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

    my $userinfo = $self->get_schema->resultset('Userinfo')->search_rs(
        {
            id => $self->{ID}
        }
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

    my $authenticatorid         = exists $arg_ref->{authenticatorid}
        ? $arg_ref->{authenticatorid}               : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    if (!$sessionID){
        $logger->debug("No SessionID given. Can't connect session to userid $userid");
        return;        
    }
    
    # Es darf keine Session assoziiert sein. Daher stumpf loeschen

    # DBI: "delete from user_session where sessionid = ?"
    $self->get_schema->resultset('UserSession')->search_rs(
        {
            'sid.sessionid' => $sessionID,
        },
        {
            join => ['sid'],
        }
    )->delete;
    
    my $sid = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $sessionID })->id;

    # DBI: "insert into user_session values (?,?,?)"
    $self->get_schema->resultset('UserSession')->create(
        {
            sid      => $sid,
            userid   => $userid,
            authenticatorid => $authenticatorid,
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
    $self->get_schema->resultset('Userinfo')->single(
        {
            id => $self->{ID},
        }
    )->update(
        {
            nachname   => '',
            vorname    => '',
            strasse    => '',
            ort        => '',
            plz        => 0,
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
    $self->get_schema->resultset('Userinfo')->single(
        {
            id => $self->get_userid_for_username($username),
        }
    )->update(
        {
            nachname   => $userinfo_ref->{'Nachname'},
            vorname    => $userinfo_ref->{'Vorname'},
            strasse    => '',
            ort        => '',
            plz        => '',
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
            gebdatum   => '',
        }
    );

    return;
}

sub get_info {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from userinfo where id = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single({ id => $self->{ID} });
    
    my $userinfo_ref={};

    if ($userinfo){
        $userinfo_ref->{'id'}         = $self->{'ID'};
        $userinfo_ref->{'nachname'}   = $userinfo->nachname;
        $userinfo_ref->{'vorname'}    = $userinfo->vorname;
        $userinfo_ref->{'strasse'}    = $userinfo->strasse;
        $userinfo_ref->{'ort'}        = $userinfo->ort;
        $userinfo_ref->{'plz'}        = $userinfo->plz;
        $userinfo_ref->{'soll'}       = $userinfo->soll;
        $userinfo_ref->{'gut'}        = $userinfo->gut;
        $userinfo_ref->{'avanz'}      = $userinfo->avanz; # Ausgeliehene Medien
        $userinfo_ref->{'branz'}      = $userinfo->branz; # Buchrueckforderungen
        $userinfo_ref->{'bsanz'}      = $userinfo->bsanz; # Bestellte Medien
        $userinfo_ref->{'vmanz'}      = $userinfo->vmanz; # Vormerkungen
        $userinfo_ref->{'maanz'}      = $userinfo->maanz; # ueberzogene Medien
        $userinfo_ref->{'vlanz'}      = $userinfo->vlanz; # Verlaengerte Medien
        $userinfo_ref->{'sperre'}     = $userinfo->sperre;
        $userinfo_ref->{'sperrdatum'} = $userinfo->sperrdatum;
        $userinfo_ref->{'email'}      = $userinfo->email;
        $userinfo_ref->{'gebdatum'}   = $userinfo->gebdatum;
        $userinfo_ref->{'username'}   = $userinfo->username;
        $userinfo_ref->{'password'}   = $userinfo->password;
        $userinfo_ref->{'masktype'}   = $userinfo->masktype;
        $userinfo_ref->{'autocompletiontype'} = $userinfo->autocompletiontype;
        $userinfo_ref->{'spelling_as_you_type'}   = $userinfo->spelling_as_you_type;
        $userinfo_ref->{'spelling_resultlist'}    = $userinfo->spelling_resultlist;
    }
    
    # Rollen

    # DBI: "select * from role,user_role where user_role.userid = ? and user_role.roleid=role.id"
    my $userroles = $self->get_schema->resultset('UserRole')->search_rs(
        {
            'me.userid' => $self->{ID},
        },
        {
            join   => ['roleid'],
            select => ['roleid.rolename'],
            as     => ['thisrolename'],
        }
    );

    foreach my $userrole ($userroles->all){
        $userinfo_ref->{role}{$userrole->get_column('thisrolename')}=1;
    }

    # Templates

    my $usertemplates = $self->get_schema->resultset('UserTemplate')->search_rs(
        {
            'me.userid' => $self->{ID},
        },
        {
            join   => ['templateid'],
            select => ['templateid.id'],
            as     => ['thistemplateid'],
        }
    );

    foreach my $usertemplate ($usertemplates->all){
        $userinfo_ref->{template}{$usertemplate->get_column('thistemplateid')}=1;
    }

    return $userinfo_ref;
}

sub get_all_roles {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("Getting roles");

    # DBI: "select * from role"
    my $roles = $self->get_schema->resultset('Roleinfo')->search_rs(undef);

    my $roles_ref = [];
    foreach my $role ($roles->all){
        push @$roles_ref, {
            id          => $role->id,
            rolename    => $role->rolename,
            description => $role->description,
        };
    }

    if ($logger->is_debug){
        $logger->debug("Available roles ".YAML::Dump($roles_ref));
    }
    
    return $roles_ref;
}

sub get_roles_of_user {
    my ($self,$userid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("Getting roles");

    # DBI: "select role.name from role,user_role where user_role.userid=? and user_role.roleid=role.id"
    my $userroles = $self->get_schema->resultset('UserRole')->search_rs(
        {
            'me.userid' => $self->{ID},
        },
        {
            join   => ['roleid'],
            select => ['roleid.rolename','roleid.description'],
            as     => ['thisrolename','thisroledescription'],
        }
    );

    my $role_ref = {};
    foreach my $userrole ($userroles->all){
        $role_ref->{$userrole->get_column('thisrolename')} = $userrole->get_column('thisroledescription');
    }

    if ($logger->is_debug){
        $logger->debug("Available roles ".YAML::Dump($role_ref));
    }
    
    return $role_ref;
}

sub get_all_templates {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("Getting templates");

    # DBI: "select * from templateinfo"
    my $templates = $self->get_schema->resultset('Templateinfo')->search_rs(undef, {join => 'viewid', order_by => ['viewid.viewname ASC','templatename ASC','templatelang ASC']});

    my $templates_ref = [];
    foreach my $template ($templates->all){
        push @$templates_ref, {
            id           => $template->id,
            templatename => $template->templatename,
            viewname     => $template->viewid->viewname,
            templatelang => $template->templatelang,
        };
    }

    if ($logger->is_debug){
        $logger->debug("Available templates ".YAML::Dump($templates_ref));
    }
    
    return $templates_ref;
}

sub get_templates_of_user {
    my ($self,$userid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("Getting templates");

    my $thisuserid = ($userid)?$userid:$self->{ID};
    
    my $usertemplates = $self->get_schema->resultset('UserTemplate')->search_rs(
        {
            'me.userid' => $thisuserid,
        },
    );

    return $usertemplates ;
}

sub has_template {
    my ($self,$templateid,$userid)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $logger->debug("Getting templates");

    my $thisuserid = ($userid)?$userid:$self->{ID};
    
    my $has_template = $self->get_schema->resultset('UserTemplate')->search_rs(
        {
            'userid'     => $thisuserid,
            'templateid' => $templateid,
        },
    )->count;

    return $has_template ;
}

sub searchfields_exist {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from searchfield where userid = ?"
    my $have_searchfields = $self->get_schema->resultset('Searchfield')->search_rs(
        {
            userid => $userid,
        }
    )->count;

    return $have_searchfields;
}

sub set_default_searchfields {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $self->get_schema->resultset('Searchfield')->search_rs(
        {
            userid => $userid,
        }
    )->delete;

    # DBI: "insert into searchfield values (?,?,?)"
    $self->get_schema->resultset('Searchfield')->populate(
        [
            {
                userid      => $userid,
                searchfield => 'freesearch',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'title',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'titlestring',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'classification',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'corporatebody',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'subject',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'source',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'person',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'year',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'isbn',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'issn',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'content',
                active      => 1,
            },
            {
                userid      => $userid,
                searchfield => 'mediatype',
                active      => 0,
            },
            {
                userid      => $userid,
                searchfield => 'mark',
                active      => 1,
            },
        ]);
    
    return;
}

sub get_searchfields {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from searchfield where userid = ?") or $logger->error($DBI::errstr);
    my $searchfields=$self->get_schema->resultset('Searchfield')->search_rs(
        {
            userid => $self->{ID},
        }
    );
    
    my $searchfield_ref = {};

    foreach my $searchfield ($searchfields->all){
        my $field  = $searchfield->searchfield;
        my $active = $searchfield->active;

        $searchfield_ref->{$field}{active}=$active;
    };
    
    return $searchfield_ref;
}

sub set_searchfields {
    my ($self,$arg_ref)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $self->get_schema->resultset('Searchfield')->search_rs(
        {
            userid => $self->{ID},
        }
    )->delete;

    my $searchfields_ref = [];

    foreach my $searchfield (keys %$arg_ref){
        push @$searchfields_ref, {
            userid      => $self->{ID},
            searchfield => $searchfield,
            active      => $arg_ref->{$searchfield},
        };
    }
    
    # DBI: "insert into searchfield values (?,?,?)"
    $self->get_schema->resultset('Searchfield')->populate($searchfields_ref);
    
    return;
}

sub get_spelling_suggestion {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select * from userinfo where userid = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single(
        {
            id => $self->{ID},
        }
    );

    my $spelling_suggestion_ref = {};
    
    if ($userinfo){
        $spelling_suggestion_ref->{as_you_type} = $userinfo->spelling_as_you_type;
        $spelling_suggestion_ref->{resultlist}  = $userinfo->spelling_resultlist;
    };
    
    return $spelling_suggestion_ref;
}

sub set_default_spelling_suggestion {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $userinfo = $self->get_schema->resultset('Userinfo')->single(
        {
            id => $self->{ID},
        }
    );

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

    my $userinfo = $self->get_schema->resultset('Userinfo')->single(
        {
            id => $self->{ID},
        }
    );

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

    # DBI: "select * from livesearch where userid = ?"
    my $livesearches=$self->get_schema->resultset('Livesearch')->search_rs(
        {
            userid => $self->{ID},
        }
    );
    
    my $livesearch_ref = {};
    
    foreach my $livesearch ($livesearches->all){
        my $field  = $livesearch->searchfield;
        my $active = $livesearch->active;
        my $exact  = $livesearch->exact;

        $livesearch_ref->{$field} = {
            active => $active,
            exact  => $exact,
        };
    }
    
    return $livesearch_ref;
}

sub livesearch_exists {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select count(userid) as rowcount from livesearch where userid = ?"
    my $have_livesearch = $self->get_schema->resultset('Livesearch')->search_rs(
        {
            userid => $userid,
        }
    )->count;
    
    return $have_livesearch;
}

sub set_default_livesearch {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $self->get_schema->resultset('Livesearch')->search_rs(
        {
            userid => $userid,
        }
    )->delete;

    # DBI: "insert into livesearch values (?,?,?)"
    $self->get_schema->resultset('Livesearch')->populate(
        [
            {
                userid      => $userid,
                searchfield => 'freesearch',
                active      => 0,
                exact       => 1,
            },
            {
                userid      => $userid,
                searchfield => 'person',
                active      => 0,
                exact       => 1,
            },
            {
                userid      => $userid,
                searchfield => 'subject',
                active      => 0,
                exact       => 1,
            },
        ]
    );
    
    return;
}

sub set_livesearch {
    my ($self,$arg_ref)=@_;

    my $freesearch       = exists $arg_ref->{freesearch}
        ? $arg_ref->{freesearch}       : undef;
    my $freesearch_exact = exists $arg_ref->{freesearch_exact}
        ? $arg_ref->{freesearch_exact} : undef;
    my $person           = exists $arg_ref->{person}
        ? $arg_ref->{person}           : undef;
    my $person_exact     = exists $arg_ref->{person_exact}
        ? $arg_ref->{person_exact}     : undef;
    my $subject          = exists $arg_ref->{subject}
        ? $arg_ref->{subject}          : undef;
    my $subject_exact    = exists $arg_ref->{subject_exact}
        ? $arg_ref->{subject_exact}    : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    $self->get_schema->resultset('Livesearch')->search_rs(
        {
            userid => $self->{ID},
        }
    )->delete;

    # DBI: "insert into livesearch values (?,?,?)"
    $self->get_schema->resultset('Livesearch')->populate(
        [
            {
                userid      => $self->{ID},
                searchfield => 'freesearch',
                active      => $freesearch,
                exact       => $freesearch_exact,
            },
            {
                userid      => $self->{ID},
                searchfield => 'person',
                active      => $person,
                exact       => $person_exact,
            },
            {
                userid      => $self->{ID},
                searchfield => 'subject',
                active      => $subject,
                exact       => $subject_exact,
            },
        ]
    );

    return;
}

sub get_bibsonomy {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    # DBI: "select bibsonomy_sync,bibsonomy_user,bibsonomy_key from userinfo where userid = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->search_rs(
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
        $bibsonomy_ref->{sync} = $userinfo->bibsonomy_sync;
        $bibsonomy_ref->{user} = $userinfo->bibsonomy_user;
        $bibsonomy_ref->{key}  = $userinfo->bibsonomy_key;
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
    my $userinfo = $self->get_schema->resultset('Userinfo')->single(
        {
            id => $self->{ID},
        }
    )->update(
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

    my $config = $self->get_config;
    
    my $bibsonomy_ref = $self->get_bibsonomy;

    return unless ($bibsonomy_ref->{user} || $bibsonomy_ref->{key});
        
    my $bibsonomy = new OpenBib::BibSonomy({api_user => $bibsonomy_ref->{user}, api_key => $bibsonomy_ref->{key}});

    $logger->debug("Syncing all to BibSonomy");

    my $username  = $self->get_username;
    my $titles_ref = $self->get_private_tagged_titles({username => $username});

    foreach my $database (keys %$titles_ref){
        foreach my $id (keys %{$titles_ref->{$database}}){
            my $tags_ref   = $titles_ref->{$database}{$id}{tags};
            my $visibility =
                ($titles_ref->{$database}{$id}{visibility} == 1)?'public':
                    ($titles_ref->{$database}{$id}{visibility} == 2)?'private':'private';

            # 1) Ueberpruefen, ob Titel bereits existiert

            my $record    = new OpenBib::Record::Title({ database => $database , id => $id, config => $config })->load_full_record;
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
                    if ($logger->is_debug){
                        $logger->debug("Syncing Record $database:$id");
                        $logger->debug("Tags".YAML::Dump($tags_ref));
                    }
                    
                    $bibsonomy->new_post({ tags => $tags_ref, record => $record, visibility => $visibility });
                }
            }
        }
    }
    
    return;
}

sub get_mask {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thisuserid=($userid)?$userid:$self->{ID};
    
    # Bestimmen des Recherchemasken-Typs
    # DBI: "select masktype from userinfo where id = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single({ id => $thisuserid });

    my $masktype = "simple";
    
    if ($userinfo && $userinfo->masktype){
        $masktype = $userinfo->masktype;
    }

    return $masktype
}

sub set_mask {
    my ($self,$masktype)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update userinfo set masktype = ? where id = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single({ id => $self->{ID} })->update(
        {
            masktype => $masktype,
        }
    );

    return;
}

sub get_autocompletion {
    my ($self,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thisuserid=($userid)?$userid:$self->{ID};
    
    # Bestimmen des Recherchemasken-Typs
    # DBI: "select autocompletiontype from userinfo where id = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single({ id => $thisuserid });

    my $autocompletiontype = "livesearch";
    
    if ($userinfo && $userinfo->autocompletiontype){
        $autocompletiontype = $userinfo->autocompletiontype;
    }

    return $autocompletiontype;
}

sub set_autocompletion {
    my ($self,$autocompletiontype)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Setting autocompletion type to $autocompletiontype");
    
    # Update des Autovervollstaendigung-Typs
    # DBI: "update userinfo set autocompletiontype = ? where id = ?"
    my $userinfo = $self->get_schema->resultset('Userinfo')->single({ id => $self->{ID} })->update(
        {
            autocompletiontype => $autocompletiontype,
        }
    );

    return;
}

sub is_admin {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (defined $self->{_is_admin}){
	return 	$self->{_is_admin};
    }
    
    my $config = $self->get_config;

    # Statischer Admin-User aus portal.yml
    if (defined $self->{ID} && $self->{ID} eq $config->{adminuser}){
	$self->{_is_admin} = 1;
	
	return 1;
    } 

    # Sonst: Normale Nutzer mit der der Admin-Role
    
    # DBI: "select count(ur.userid) as rowcount from userrole as ur, role as r where ur.userid = ? and r.role = 'admin' and r.id=ur.roleid"
    my $count = $self->get_schema->resultset('UserRole')->search(
        {
            'roleid.rolename' => 'admin',
            'userid.id'   => $self->{ID},
        },
        {
            join => ['roleid','userid'],
        }
    )->count;

    
    $self->{_is_admin} = $count;
    
    return $self->{_is_admin};
}

sub has_role {
    my ($self,$role,$userid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $thisuserid = ($userid)?$userid:$self->{ID};

    # DBI: "select count(ur.userid) as rowcount from userrole as ur, role as r where ur.userid = ? and r.role = 'admin' and r.id=ur.roleid"
    my $count = $self->get_schema->resultset('UserRole')->search(
        {
            'roleid.rolename' => $role,
            'userid.id'       => $thisuserid,
        },
        {
            join => ['roleid','userid'],
        }
    )->count;
    
    return $count;
}

sub del_topic {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        # DBI: "delete from topic where id = ?"
        $self->get_schema->resultset('Topic')->single({id => $id})->delete;
    };

    return;
}

sub update_topic {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $name                     = exists $arg_ref->{name}
        ? $arg_ref->{name}                : undef;
    my $description              = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update topic set name = ?, description = ? where id = ?"
    $self->get_schema->resultset('Topic')->single({id => $id})->update(
        {
            name        => $name,
            description => $description,
        }
    );

    return;
}

sub update_topic_mapping {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                            = exists $arg_ref->{id}
        ? $arg_ref->{id}                       : undef;
    my $classifications_ref           = exists $arg_ref->{classifications}
        ? $arg_ref->{classifications}          : [];
    my $type                          = exists $arg_ref->{type}
        ? $arg_ref->{type}                     : 'bk';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Angabe von type bedingt update der entsprechenden Klassifikationen
    if ($type){       
        if ($logger->is_debug){
            $logger->debug("Classifications5 ".YAML::Dump($classifications_ref));
        }
        
        $self->set_classifications_of_topic({
            topicid         => $id,
            classifications => $classifications_ref,
            type            => $type,
        });
    }

    return;
}

sub new_topic {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $name                   = exists $arg_ref->{name}
        ? $arg_ref->{name}                : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $have_topic = $self->get_schema->resultset('Topic')->search_rs(
        {
            name        => $name,
        }   
    )->count;

    if ($have_topic) {
      return -1;
    }

    $self->get_schema->resultset('Topic')->create(
        {
            name        => $name,
            description => $description,
        }   
    );
    
    return 1;
}

sub topic_exists {
    my ($self,$name) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(*) as rowcount from topics where name = ?"
    my $have_topic = $self->get_schema->resultset('Topic')->search_rs(
        {
            name        => $name,
        }   
    )->count;

    return $have_topic;
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

    my @found_userids = ();
    if ($roleid) {
        # DBI: "select userid from user_role where roleid=?"
        my $userroles = $self->get_schema->resultset('UserRole')->search(
            {
                roleid => $roleid,
            }
        );
        foreach my $userrole ($userroles->all){
            my $userid = $userrole->get_column('userid');
              push @found_userids, $userid;
        }
    }
    else {
        my $where_ref = {};
        if ($username) {
            $where_ref->{username} = { '~' => $username };
        }
        
        if ($commonname) {
            $where_ref->{nachname} = { '~' => $commonname };
        }
        
        if ($surname) {
            $where_ref->{vorname} = { '~' => $surname };
        }

        my $users = $self->get_schema->resultset('Userinfo')->search($where_ref);
        foreach my $user ($users->all){
            my $userid = $user->get_column('id');
            push @found_userids, $userid;
        }
    }
    
    $logger->debug("Looking up user $username/$surname/$commonname roleid $roleid");

    my $userlist_ref = [];
    
    foreach my $userid (@found_userids){
        $logger->debug("Found ID $userid");
        my $single_user = new OpenBib::User({ID => $userid});
        push @$userlist_ref, $single_user->get_info;
    }

    return $userlist_ref;
}

sub migrate_ugc {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $olduserid             = exists $arg_ref->{olduserid}
        ? $arg_ref->{olduserid}              : undef;
    my $newuserid             = exists $arg_ref->{newuserid}
        ? $arg_ref->{newuserid}              : undef;
    my $migrate_collections    = exists $arg_ref->{migrate_collections}
        ? $arg_ref->{migrate_collections}  : undef;
    my $migrate_litlists       = exists $arg_ref->{migrate_litlists}
        ? $arg_ref->{migrate_litlists}     : undef;
    my $migrate_tags           = exists $arg_ref->{migrate_tags}
        ? $arg_ref->{migrate_tags}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($migrate_collections){
        my $collectionentries = $self->get_schema->resultset('UserCartitem')->search(
            {
                userid => $olduserid,
            }
        );
        
        while (my $collectionentry = $collectionentries->next()){
            $logger->debug("Migrating user collections id ".$collectionentry->get_column('id'));
            
            $collectionentry->update({ userid => $newuserid });
        }
    }

    
    if ($migrate_litlists){
        my $litlists = $self->get_schema->resultset('Litlist')->search(
            {
                userid => $olduserid,
            }
        );

        while (my $litlist = $litlists->next()){
            $logger->debug("Migrating litlist id ".$litlist->get_column('id'));
            $litlist->update({ userid => $newuserid });
        }

    }

    if ($migrate_tags){
        my $tags = $self->get_schema->resultset('TitTag')->search(
            {
                userid => $olduserid,
            }
        );

        while (my $tag = $tags->next()){
            $logger->debug("Migrating tag id ".$tag->get_column('id'));
            $tag->update({ userid => $newuserid });
        }
    }
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($arg_ref));
    }
    
    return;
}

sub get_schema {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Schema $self");
    
    if (defined $self->{schema}){
        $logger->debug("Reusing Schema $self");
        return $self->{schema};
    }

    if (defined $self->{_config}){
        $logger->debug("Reusing Config-Schema ".$self->get_config);
        return $self->get_config->get_schema;        
    }
    
    $logger->debug("Creating new Schema $self");    
    
    $self->connectDB;
    
    return $self->{schema};
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # UTF8: {'pg_enable_utf8'    => 1}
    if ($config->{'systemdbsingleton'}){
        eval {        
            my $schema = OpenBib::Schema::System::Singleton->instance;
            $self->{schema} = $schema->get_schema;
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
    else {
        eval {        
            $self->{schema} = OpenBib::Schema::System->connect("DBI:Pg:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},$config->{systemdboptions}) or $logger->error_die($DBI::errstr);
            
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
        
    
    return;
}

sub disconnectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Try disconnecting from System-DB $self");
    
    if (defined $self->{schema}){
        eval {
            $logger->debug("Disconnect from System-DB now $self");
            $self->{schema}->storage->dbh->disconnect;
            delete $self->{schema};
        };

        if ($@){
            $logger->error($@);
        }
    }
    
    return;
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Destroying User-Object $self");

    if (defined $self->{schema}){
        $self->disconnectDB;
    }

    return;
}

1;
