#####################################################################
#
#  OpenBib::Handler::PSGI::Login
#
#  Dieses File ist (C) 2004-2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Login;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Socket;
use Template;
use URI::Escape;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Login::Util;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_form'    => 'show_form',
        'authenticate' => 'authenticate',
        'failure'      => 'failure',
        'dispatch_to_representation'           => 'dispatch_to_representation',
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
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    my $authenticatorid  = $input_data_ref->{authenticatorid};
    my $username         = $input_data_ref->{username};
    my $password         = $input_data_ref->{password};

    # CGI-only Parameters for html-representation
    my $action      = ($query->param('action'))?$query->param('action'):'none';
    my $code        = ($query->param('code'))?$query->param('code'):'1';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type        = ($query->param('type'))?$query->param('type'):'';
    my $redirect_to = $query->param('redirect_to'); # || "$path_prefix/$config->{searchform_loc}?l=$lang";

    
    # Wenn die Session schon authentifiziert ist, dann wird
    # in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        my $redirecturl = "$path_prefix/$config->{users_loc}/id/[% user.ID %]/preferences.html?l=$lang";
        
        if ($scheme eq "https"){
            $redirecturl ="https://$servername$redirecturl";
        }

        # TODO GET?
        $self->redirect($redirecturl);

        return;
    }

    my $authenticators_ref = $config->get_authenticators();
    
    # TT-Data erzeugen
    my $ttdata={
        authenticatorid => $authenticatorid,
        authenticators  => $authenticators_ref,
        validtarget     => $validtarget,
        username        => $username,
        redirect_to     => $redirect_to,
    };
    
    my $templatename = ($type)?"tt_login_".$type."_tname":"tt_login_tname";
    
    return $self->print_page($config->{$templatename},$ttdata);
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
    my $lang           = $self->param('lang');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');
    
    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    my $authenticatorid  = $input_data_ref->{authenticatorid};
    my $username         = $input_data_ref->{username};
    my $password         = $input_data_ref->{password};

    # CGI-only Parameters for html-representation
    my $code        = ($query->param('code'))?$query->param('code'):'1';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type        = ($query->param('type'))?$query->param('type'):'';
    my $redirect_to = uri_unescape($query->param('redirect_to'));

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        my $redirecturl = "$path_prefix/$config->{users_loc}/id/[% user.ID %]/preferences.html?l=$lang";
        
        if ($scheme eq "https"){
            $redirecturl ="https://$servername$redirecturl";
        }

        # TODO GET?
        $self->redirect($redirecturl);

        return;
    }

    my $loginfailed=0;
    
    if ($username eq "" || $password eq "") {
        $loginfailed=1;
    }
    
    my $authenticator_ref = $config->get_authenticator_by_id($authenticatorid);

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($authenticator_ref));
    }
    
    ## Ausleihkonfiguration fuer den Katalog einlesen
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    
    if ($authenticator_ref->{type} eq "olws") {
        if ($logger->is_debug){
            $logger->debug("Trying to authenticate via OLWS: ".YAML::Dump($circinfotable));
        }
        
        my $userinfo_ref=OpenBib::Login::Util::authenticate_olws_user({
            username      => $username,
            password      => $password,
            circcheckurl  => $circinfotable->{$authenticator_ref->{dbname}}{circcheckurl},
            circdb        => $circinfotable->{$authenticator_ref->{dbname}}{circdb},
        });
        
        my %userinfo=%$userinfo_ref;
        
        $logger->debug("Authentication via OLWS done");
        
        if ($userinfo{'erfolgreich'} ne "1") {
            $loginfailed=2;
        }
        
        # Gegebenenfalls Benutzer lokal eintragen
        else {
            if ($self->param('representation') eq "html"){
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
    }
    elsif ($authenticator_ref->{type} eq "self") {
        # Selbstregistrierung nur fuer email-Adresse und admin

        if ($username ne "admin" && $username !~/\@/){
            return $self->print_warning($msg->maketext("Bitte melden Sie sich mit Ihrer registrierten E-Mail-Adresse an"));
        }
        
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

    my $result_ref = {
        success => 0,
    };

    if (!$loginfailed) {

        $logger->debug("Authentication successful");
        $result_ref->{success} = 1;

        my $userid = $user->get_userid_for_username($username);

        $result_ref->{userid} = $userid;
        
        if ($self->param('representation') eq "html"){
            # Jetzt wird die Session mit der Benutzerid assoziiert
            
            $user->connect_session({
                sessionID => $session->{ID},
                userid    => $userid,
                authenticatorid  => $authenticatorid,
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
            
            if ($logger->is_debug){
                $logger->debug("Items in Session: ".YAML::Dump($recordlist_existing_collection));
            }
            
            foreach my $record (@{$recordlist_existing_collection->to_list}){
                if ($logger->is_debug){
                    $logger->debug("Adding item to personal collection of user $userid: ".YAML::Dump($record));
                }
                
                $user->move_cartitem_to_user({
                    userid => $userid,
                    itemid => $record->{listid},
                });
            }
            
            $logger->debug("Added recently collected title");
            
            # Bestimmen des Recherchemasken-Typs
            my $masktype = $user->get_mask($userid);
            
            $session->set_mask($masktype);
            
            $redirecturl
                = "$path_prefix/$config->{users_loc}/id/$userid/preferences.html?l=$lang";
            
            if ($scheme eq "https"){
                $redirecturl ="https://$servername$redirecturl";
            }
        }
    }
    
    # Wenn Return_url existiert, dann wird dorthin gesprungen
    if ($redirect_to){
        $redirecturl=$redirect_to;
    }
    
    # Fehlerbehandlung
    if ($loginfailed) {
        $redirecturl="$path_prefix/$config->{login_loc}/failure?code=$loginfailed";
    }
    

    if ($self->param('representation') eq "html"){
        $logger->debug("Redirecting to $redirecturl");

        # TODO GET?
        $self->header_add('Content-Type' => 'text/html');
        return $self->redirect($redirecturl);
    }
    else {
        return $self->print_json($result_ref);        
    }
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
    my $authenticatorid  = ($query->param('authenticatorid'))?$query->param('authenticatorid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'';
    my $username = ($query->param('username'))?$query->param('username'):'';
    my $password  = decode_utf8($query->param('password')) || $query->param('password') || '';

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        # TODO GET?
        $self->redirect("$path_prefix/$config->{users_loc}/id/[% user.ID %]/preferences");

        return;
    }

    if    ($code eq "1") {
        return $self->print_warning($msg->maketext("Sie haben entweder kein Passwort oder keinen Usernamen eingegeben"));
    }
    elsif ($code eq "2") {
        return $self->print_warning($msg->maketext("Sie konnten mit Ihrem angegebenen Benutzernamen und Passwort nicht erfolgreich authentifiziert werden"));
    }
    else {
        return $self->print_warning($msg->maketext("Falscher Fehler-Code"));
    }
}

sub get_input_definition {
    my $self=shift;
    
    return {
        authenticatorid => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        username => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        password => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
