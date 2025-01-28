#####################################################################
#
#  OpenBib::Handler::PSGI::Login
#
#  Dieses File ist (C) 2004-2022 Oliver Flimm <flimm@openbib.org>
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
use HTML::Entities qw/decode_entities/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Socket;
use Template;
use URI::Escape;

use OpenBib::Authenticator::Factory;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
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

        my $redirecturl = "$path_prefix/$config->{users_loc}/id/$user->{ID}/preferences.html?l=$lang";

	my $session_authenticatortype = $user->get_targettype_of_session($session->{ID});

	# Got authorized by ils, then show circulation overview
	if ($session_authenticatortype eq "ils"){
	    $redirecturl = "$path_prefix/$config->{users_loc}/id/$user->{ID}/circulations.html?l=$lang";
	}

        if ($scheme eq "https"){
            $redirecturl ="https://$servername$redirecturl";
        }

        # TODO GET?
        $self->redirect($redirecturl);

        return;
    }

    my $authenticators_ref = $config->get_authenticators($view);
    
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
    my $expire           = $input_data_ref->{expire};    

    # CGI-only Parameters for html-representation
    my $code        = ($query->param('code'))?$query->param('code'):'1';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type        = ($query->param('type'))?$query->param('type'):'';
    my $redirect_to = uri_unescape($query->param('redirect_to'));

    my $redirecturl = "";

    my $result_ref = {
        success => 0,
    };


    # Authentifizierung nur dann valide, wenn dem View das Anmeldeziel
    # authenticatorid zugeordnet ist.
    my @valid_authenticators = $config->get_viewauthenticators($view);

    my $authenticator_is_valid = 0;

    #check if the passed authentification type is valid for this view
    foreach my $valid_authenticator (@valid_authenticators){
	if ($valid_authenticator == $authenticatorid){
	    $authenticator_is_valid = 1;
	    last;
	}
    }

    if (!$authenticator_is_valid){
	my $code   = -6;
	my $reason = $self->get_error_message($code);
	$logger->error("Authentication Error for user $username: $reason ");
	return $self->print_warning($reason,$code);
    }
    
    # Wenn die Session schon authentifiziert ist, dann
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

	# Ablehnung, wenn Nutzer nicht zu den Berechtigten fuer den View gehoeren, dann Meldung

	if (!$user->can_access_view($view)){
	    my $code   = -5;
	    my $reason = $self->get_error_message($code);
	    $logger->error("Authentication Error for user $username: $reason ");
	    
	    return $self->print_warning($reason,$code);
	}
	
        my $redirecturl = "$path_prefix/$config->{users_loc}/id/$user->{ID}/preferences.html?l=$lang";

	my $session_authenticatortype = $user->get_targettype_of_session($session->{ID});
	
	# Got authorized by ils, then show circulation overview
	if ($session_authenticatortype eq "ils"){
	    $redirecturl = "$path_prefix/$config->{users_loc}/id/$user->{ID}/circulations.html?l=$lang";
	}

        if ($scheme eq "https"){
            $redirecturl ="https://$servername$redirecturl";
        }

        # TODO GET?
        $self->redirect($redirecturl);

        return;
    }

    my $userid = 0; # Nicht erfolgreich authentifiziert

    # Failure codes
    #
    #  0: unspecified
    # -1: no username and/or password
    # -2: max_login_failure reached selfref
    # -3: wrong password
    # -4: user does not exist
    # -5: view denied
    # -6: wrong authenticator
    # -7: username is no email
    # -8: max_login_failure reached other
    
    if ($username eq "" || $password eq "") {
        $redirecturl="$path_prefix/$config->{login_loc}/failure?code=-1";
	
	my $code   = -1;
	my $reason = $self->get_error_message($code);

	$logger->error("Authentication Error for user $username: $reason ");
	
	if ($self->param('representation') eq "html"){
	    $logger->debug("Redirecting to $redirecturl");
	    
	    # TODO GET?
	    $self->header_add('Content-Type' => 'text/html');
	    return $self->redirect($redirecturl);
	}
	else {
	    return $self->print_warning($reason,$code);
	}
    }

    eval {
	$password    = decode_entities($password);
	
	# if ($logger->is_debug){
	#     $logger->debug("Using password $password");
	# }
    };    
    
    my $authenticator = OpenBib::Authenticator::Factory->create_authenticator({ id => $authenticatorid, config => $config, session => $session});

    # Konsistenzchecks
    { 
	if ($authenticator->get('type') eq "self" && $username ne "admin" && $username !~/\@/){

	    my $code   = -7;
	    my $reason = $self->get_error_message($code);
	    $logger->error("Authentication Error for user $username: $reason ");
    
	    return $self->print_warning($reason,$code);	    
	}

	my $ils_barcode_regexp = $config->get('ils_barcode_regexp');

	if ($authenticator->get('type') eq "ils" && $ils_barcode_regexp && $username !~/$ils_barcode_regexp/){
	    
	    my $code   = -9;
	    my $reason = $self->get_error_message($code);
	    $logger->error("Authentication Error for user $username: $reason ");
	    
	    return $self->print_warning($reason,$code);	    
	}

    }

    $userid = $authenticator->authenticate({
	username  => $username,
	password  => $password,
	viewname  => $view,
					   });
    
    if ($userid > 0) { 
        $logger->debug("Authentication successful");
	
	$user->update_lastlogin({ userid => $userid });

        $result_ref->{success} = 1;
	$result_ref->{authenticatorid} = $authenticatorid;
        $result_ref->{userid}  = $userid;
        

	my $authorized_user = new OpenBib::User({ ID => $userid, config => $config});
	if (!$authorized_user->can_access_view($view)){
	    
	    my $code   = -5;
	    my $reason = $self->get_error_message($code);
	    $logger->error("Authentication Error for user $username: $reason ");
	    
	    return $self->print_warning($reason,$code);
	}
	
	# Jetzt wird die Session mit der Benutzerid assoziiert

	$logger->info("Authentication successful for user $username");

	$user->connect_session({
	    sessionID        => $session->{ID},
	    userid           => $userid,
	    authenticatorid  => $authenticatorid,
			       });

	# Expiration setzen

	$expire = $config->get('default_session_expiration') unless ($expire);

	my $new_expiration = $session->set_expiration($expire);
	
	$result_ref->{sessionID} = $session->{ID};
	$result_ref->{expire}    = $new_expiration;
	
	# Falls noch keins da ist, eintragen
	if (!$user->searchfields_exist($userid)) {
	    $user->set_default_searchfields($userid);
	}
	
	if (!$user->livesearch_exists($userid)) {
	    $user->set_default_livesearch($userid);
	}
	
	# Jetzt wird die bestehende Trefferliste uebernommen.
	# Gehe ueber alle Eintraege der Trefferliste

	if ($self->param('representation') eq "html"){

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
	}
	
	$redirecturl
	    = "$path_prefix/$config->{users_loc}/id/$userid/preferences.html?l=$lang";

	my $authenticatorinfo_ref = $config->get_authenticator_by_id($authenticatorid);

	# Got authorized by ils, then show circulation overview
	if ($authenticatorinfo_ref->{type} eq "ils"){
	    $redirecturl = "$path_prefix/$config->{users_loc}/id/$userid/circulations.html?l=$lang";
	}

	
	if ($scheme eq "https"){
	    $redirecturl ="https://$servername$redirecturl";
	    
        }
    }
    
    # Wenn Return_url existiert, dann wird dorthin gesprungen
    if ($redirect_to){
	# Resource finger URL -> replace me with userid
	if ($redirect_to=~m{/users/id/me}){
	    $redirect_to=~s{/users/id/me}{/users/id/$userid};
	}
	# Hashed escapen
	$redirect_to=~s{#}{%23}g;
        $redirecturl=$redirect_to;
    }
    
    # Fehlerbehandlung
    if ($userid <= 0) {
        $redirecturl="$path_prefix/$config->{login_loc}/failure?code=$userid";

	my $code   = $userid;
	my $reason = $self->get_error_message($code);

	if ($self->param('representation') ne "html"){
	    return $self->print_warning($reason,$code);	    
	}
    }

    # Success!
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

    return $self->print_warning($self->get_error_message($code),$code);
}

sub get_error_message {
    my $self=shift;
    my $errorcode=shift;

    my $msg            = $self->param('msg');

    my %messages = (

        -1 => $msg->maketext("Sie haben entweder kein Passwort oder keinen Benutzerkennung eingegeben"),

        -2 => $msg->maketext("Die Anmeldung mit Ihrer angegebenen Benutzerkennung und Passwort ist zu oft fehlgeschlagen. Die Kennung ist gesperrt. Bitte fordern Sie ein neues Passwort über 'Passwort vergessen' ."),

	# wrong password
        -3 => $msg->maketext("Sie konnten mit Ihrer angegebenen Benutzerkennung und Passwort nicht erfolgreich authentifiziert werden"),

	# user does not exist
        -4 => $msg->maketext("Sie konnten mit Ihrer angegebenen Benutzerkennung und Passwort nicht erfolgreich authentifiziert werden"),

	-5 => $msg->maketext("Ihre Kennung ist nicht zur Nutzung dieses Portals zugelassen."),

	-6 => $msg->maketext("Ihre Kennung ist nicht zur Nutzung dieses Portals zugelassen. Wrong authenticator"),

	-7 => $msg->maketext("Bitte melden Sie sich mit Ihrer registrierten E-Mail-Adresse an"),

        -8 => $msg->maketext("Die Anmeldung mit Ihrer angegebenen Benutzerkennung und Passwort ist zu oft fehlgeschlagen. Die Kennung ist gesperrt. Bitte wenden Sie sich an an den Schalter \"Bibliotheksausweise und Fernleihrückgabe\" in der USB, um sie zu entsperren. Danach können Sie sich im Ausweisportal (https://ausweis.ub.uni-koeln.de/) ein neues Passwort setzen."),

        -9 => $msg->maketext("Die eingegebene Benutzernummer ist ungültig. Benutzernummern bestehen aus Großbuchstaben, Zahlen und #, z.B. A123456789#B."),
	
	);

    my $unspecified = $msg->maketext("Unspezifischer Fehler-Code");

    if (defined $messages{$errorcode} && $messages{$errorcode}){
	return $messages{$errorcode}
    }
    else {
	return $unspecified;
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
	# See Date::Manip
        expire => { 
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
