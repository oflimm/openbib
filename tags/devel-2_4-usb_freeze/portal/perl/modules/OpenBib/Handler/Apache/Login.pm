#####################################################################
#
#  OpenBib::Handler::Apache::Login
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Handler::Apache::Login;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest (); # internal_redirect
use DBI;
use Digest::MD5;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Socket;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Login::Util;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_form'    => 'show_form',
        'authenticate' => 'authenticate',
        'failure'      => 'failure',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $code      = ($query->param('code'))?$query->param('code'):'1';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password  = decode_utf8($query->param('password')) || $query->param('password') || '';

    # Main-Actions
    my $do_login       = $query->param('do_login')        || '';
    my $do_auth        = $query->param('do_auth' )        || '';
    my $do_loginfailed = $query->param('do_loginfailed')  || '';

    my $return_url = $session->get_returnurl();

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{user_loc}/[% user.ID %]/preference.html?l=$lang");
        $self->query->status(Apache2::Const::REDIRECT);
        
        return;
    }

    my $logintargets_ref = $user->get_logintargets();
    
    # TT-Data erzeugen
    my $ttdata={
        logintargets => $logintargets_ref,
        validtarget  => $validtarget,
        loginname    => $loginname,
        return_url   => $return_url,
    };
    
    my $templatename = ($type)?"tt_login_".$type."_tname":"tt_login_tname";
    
    $self->print_page($config->{$templatename},$ttdata);

    return Apache2::Const::OK;
}

sub authenticate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $code      = ($query->param('code'))?$query->param('code'):'1';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password  = decode_utf8($query->param('password')) || $query->param('password') || '';

    # Main-Actions
    my $do_login       = $query->param('do_login')        || '';
    my $do_auth        = $query->param('do_auth' )        || '';
    my $do_loginfailed = $query->param('do_loginfailed')  || '';

    my $return_url = $session->get_returnurl();

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{user_loc}/[% user.ID %]/preference");
        $self->query->status(Apache2::Const::REDIRECT);

        return;
    }

    my $loginfailed=0;
    
    if ($loginname eq "" || $password eq "") {
        $loginfailed=1;
    }
    
    my $logintarget_ref = $user->get_logintarget_by_id($targetid);
    
    my $hostname    = $logintarget_ref->{hostname};
    my $port        = $logintarget_ref->{port};
    my $username    = $logintarget_ref->{username};
    my $db          = $logintarget_ref->{dbname};
    my $description = $logintarget_ref->{description};
    my $type        = $logintarget_ref->{type};
    
    $logger->debug("Hostname: $hostname Port: $port Username: $username DB: $db Description: $description Type: $type");
    
    ## Ausleihkonfiguration fuer den Katalog einlesen
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    
    if ($type eq "olws") {
        $logger->debug("Trying to authenticate via OLWS: ".YAML::Dump($circinfotable));
        
        my $userinfo_ref=OpenBib::Login::Util::authenticate_olws_user({
            username      => $loginname,
            pin           => $password,
            circcheckurl  => $circinfotable->{$db}{circcheckurl},
            circdb        => $circinfotable->{$db}{circdb},
        });
        
        my %userinfo=%$userinfo_ref;
        
        $logger->debug("Authentication via OLWS done");
        
        if ($userinfo{'erfolgreich'} ne "1") {
            $loginfailed=2;
        }
        
        # Gegebenenfalls Benutzer lokal eintragen
        else {
            my $userid;
            
            # Eintragen, wenn noch nicht existent
            if (!$user->user_exists($loginname)) {
                # Neuen Satz eintragen
                $user->add({
                    loginname => $loginname,
                    password  => $password,
                });
            }
            else {
                # Satz aktualisieren
                $user->set_credentials({
                    loginname => $loginname,
                    password  => $password,
                });
            }
            
            # Benuzerinformationen eintragen
            $user->set_private_info($loginname,$userinfo_ref);
        }
    }
    elsif ($type eq "self") {
        my $result = $user->authenticate_self_user({
            username  => $loginname,
            pin       => $password,
        });
        
        if ($result <= 0) {
            $loginfailed=2;
        }
    }
    else {
        $loginfailed=2;
    }
    
    my $redirecturl = "";
    
    if (!$loginfailed) {
        # Jetzt wird die Session mit der Benutzerid assoziiert
        my $userid = $user->get_userid_for_username($loginname);
        
        $user->connect_session({
            sessionID => $session->{ID},
            userid    => $userid,
            targetid  => $targetid,
        });
        
        # Falls noch keins da ist, eintragen
        if (!$user->fieldchoice_exists($userid)) {
            $user->set_default_fieldchoice($userid);
        }
        
        if (!$user->spelling_suggestion_exists($userid)) {
            $user->set_default_spelling_suggestion($userid);
        }
        
        if (!$user->livesearch_exists($userid)) {
            $user->set_default_livesearch($userid);
        }
        
        # Jetzt wird die bestehende Trefferliste uebernommen.
        # Gehe ueber alle Eintraege der Trefferliste
        
        my $recordlist_existing_collection = $session->get_items_in_collection();
        
        $logger->debug("Items in Session: ".YAML::Dump($recordlist_existing_collection));
        
        foreach my $record (@{$recordlist_existing_collection->to_list}){
            $logger->debug("Adding item to personal collection of user $userid: ".YAML::Dump($record));
            
            $user->add_item_to_collection({
                userid => $userid,
                item   => {
                    dbname     => $record->{database},
                    singleidn  => $record->{id},
                },
            });
        }
        
        # Bestimmen des Recherchemasken-Typs
        my $masktype = $user->get_mask($userid);
        
        $session->set_mask($masktype);
        
        $redirecturl
            = "$path_prefix/$config->{user_loc}/$userid/preferences.html";
        
    }
    
    # Wenn Return_url existiert, dann wird im Body-Frame dorthin gesprungen
    if ($return_url){
        $redirecturl=$return_url;
        
        $session->set_returnurl('');
    }
    
    # Fehlerbehandlung
    if ($loginfailed) {
        $redirecturl="$path_prefix/$config->{login_loc}/failure?code=$loginfailed";
    }
    
    $logger->debug("Redirecting to $redirecturl");
    
    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $redirecturl);
    $self->query->status(Apache2::Const::REDIRECT);
    
    return;
}

sub failure {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $code      = ($query->param('code'))?$query->param('code'):'1';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password  = decode_utf8($query->param('password')) || $query->param('password') || '';

    # Main-Actions
    my $do_login       = $query->param('do_login')        || '';
    my $do_auth        = $query->param('do_auth' )        || '';
    my $do_loginfailed = $query->param('do_loginfailed')  || '';

    my $return_url = $session->get_returnurl();

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{user_loc}/[% user.ID %]/preference");
        $self->query->status(Apache2::Const::REDIRECT);

        return;
    }

    if    ($code eq "1") {
        $self->print_warning($msg->maketext("Sie haben entweder kein Passwort oder keinen Loginnamen eingegeben"));
    }
    elsif ($code eq "2") {
        $self->print_warning($msg->maketext("Sie konnten mit Ihrem angegebenen Benutzernamen und Passwort nicht erfolgreich authentifiziert werden"));
    }
    else {
        $self->print_warning($msg->maketext("Falscher Fehler-Code"));
    }

    return Apache2::Const::OK;
}

1;
