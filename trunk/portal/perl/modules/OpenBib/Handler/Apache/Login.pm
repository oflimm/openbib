#####################################################################
#
#  OpenBib::Handler::Apache::Login
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
    my $action      = ($query->param('action'))?$query->param('action'):'none';
    my $code        = ($query->param('code'))?$query->param('code'):'1';
    my $targetid    = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type        = ($query->param('type'))?$query->param('type'):'';
    my $username    = ($query->param('username'))?$query->param('username'):'';
    my $password    = decode_utf8($query->param('password')) || $query->param('password') || '';
    my $redirect_to = decode_utf8($query->param('redirect_to')); # || "$path_prefix/$config->{searchform_loc}?l=$lang";

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{users_loc}/id/[% user.ID %]/preferences.html?l=$lang");
        $self->query->status(Apache2::Const::REDIRECT);
        
        return;
    }

    my $authenticationtargets_ref = $config->get_authenticationtargets();
    
    # TT-Data erzeugen
    my $ttdata={
        authenticationtargets => $authenticationtargets_ref,
        validtarget  => $validtarget,
        username     => $username,
        redirect_to  => $redirect_to,
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
    my $view           = $self->param('view');

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
    my $code        = ($query->param('code'))?$query->param('code'):'1';
    my $targetid    = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type        = ($query->param('type'))?$query->param('type'):'';
    my $username    = ($query->param('username'))?$query->param('username'):'';
    my $password    = decode_utf8($query->param('password')) || $query->param('password') || '';
    my $redirect_to = decode_utf8($query->param('redirect_to'));

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{users_loc}/id/[% user.ID %]/preferences");
        $self->query->status(Apache2::Const::REDIRECT);

        return;
    }

    my $loginfailed=0;
    
    if ($username eq "" || $password eq "") {
        $loginfailed=1;
    }
    
    my $authenticationtarget_ref = $config->get_authenticationtarget_by_id($targetid);

    $logger->debug(YAML::Dump($authenticationtarget_ref));
    
    ## Ausleihkonfiguration fuer den Katalog einlesen
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    
    if ($authenticationtarget_ref->{type} eq "olws") {
        $logger->debug("Trying to authenticate via OLWS: ".YAML::Dump($circinfotable));
        
        my $userinfo_ref=OpenBib::Login::Util::authenticate_olws_user({
            username      => $username,
            password      => $password,
            circcheckurl  => $circinfotable->{$authenticationtarget_ref->{db}}{circcheckurl},
            circdb        => $circinfotable->{$authenticationtarget_ref->{db}}{circdb},
        });
        
        my %userinfo=%$userinfo_ref;
        
        $logger->debug("Authentication via OLWS done");
        
        if ($userinfo{'erfolgreich'} ne "1") {
            $loginfailed=2;
        }
        
        # Gegebenenfalls Benutzer lokal eintragen
        else {
            my $userid;

            $logger->debug("Save/update user");
            
            # Eintragen, wenn noch nicht existent
            if (!$user->user_exists($username)) {
                # Neuen Satz eintragen
                $user->add({
                    username => $username,
                    password  => $password,
                });

                $logger->debug("User added");
            }
            else {
                # Satz aktualisieren
                $user->set_credentials({
                    username => $username,
                    password  => $password,
                });

                $logger->debug("User credentials updated");
            }
            
            # Benuzerinformationen eintragen
            $user->set_private_info($username,$userinfo_ref);

            $logger->debug("Updated private user info");
        }
    }
    elsif ($authenticationtarget_ref->{type} eq "self") {
        my $result = $user->authenticate_self_user({
            username  => $username,
            password  => $password,
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

        $logger->debug("Authentication successful");
                
        # Jetzt wird die Session mit der Benutzerid assoziiert
        my $userid = $user->get_userid_for_username($username);
        
        $user->connect_session({
            sessionID => $session->{ID},
            userid    => $userid,
            targetid  => $targetid,
        });
        
        # Falls noch keins da ist, eintragen
        if (!$user->searchfields_exist($userid)) {
            $user->set_default_searchfields($userid);
        }
        
        if (!$user->livesearch_exists($userid)) {
            $user->set_default_livesearch($userid);
        }
        
        # Jetzt wird die bestehende Trefferliste uebernommen.
        # Gehe ueber alle Eintraege der Trefferliste

        $logger->debug("Session connected, defaults for searchfields/livesearch set");
        
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

        $logger->debug("Added recently collected title");
        
        # Bestimmen des Recherchemasken-Typs
        my $masktype = $user->get_mask($userid);
        
        $session->set_mask($masktype);
        
        $redirecturl
            = "$path_prefix/$config->{users_loc}/id/$userid/preferences.html";
        
    }
    
    # Wenn Return_url existiert, dann wird dorthin gesprungen
    if ($redirect_to){
        $redirecturl=$redirect_to;
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
    my $code      = ($query->param('code'))?$query->param('code'):'1';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'';
    my $username = ($query->param('username'))?$query->param('username'):'';
    my $password  = decode_utf8($query->param('password')) || $query->param('password') || '';

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{users_loc}/id/[% user.ID %]/preferences");
        $self->query->status(Apache2::Const::REDIRECT);

        return;
    }

    if    ($code eq "1") {
        $self->print_warning($msg->maketext("Sie haben entweder kein Passwort oder keinen Usernamen eingegeben"));
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
