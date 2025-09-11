#####################################################################
#
#  OpenBib::Mojo::Controller::Login
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

package OpenBib::Mojo::Controller::Login;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Email::Stuffer;
use Encode 'decode_utf8';
use File::Slurper 'read_binary';
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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $scheme         = $self->stash('scheme');
    my $servername     = $self->stash('servername');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    my $authenticatorid  = $input_data_ref->{authenticatorid};
    my $username         = $input_data_ref->{username};
    my $password         = $input_data_ref->{password};

    # CGI-only Parameters for html-representation
    my $action      = ($r->param('action'))?$r->param('action'):'none';
    my $code        = ($r->param('code'))?$r->param('code'):'1';
    my $validtarget = ($r->param('validtarget'))?$r->param('validtarget'):'none';
    my $type        = ($r->param('type'))?$r->param('type'):'';
    my $redirect_to = $r->param('redirect_to') || '';  # || "$path_prefix/$config->{searchform_loc}?l=$lang";

    $logger->debug("Redirecting to: $redirect_to");

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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');    
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $lang           = $self->stash('lang');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');    
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $scheme         = $self->stash('scheme');
    my $servername     = $self->stash('servername');
    my $representation = $self->stash('representation');
    
    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    my $authenticatorid  = $input_data_ref->{authenticatorid};
    my $username         = $input_data_ref->{username};
    my $password         = $input_data_ref->{password};
    my $mfa_token        = $input_data_ref->{mfa_token};
    my $expire           = $input_data_ref->{expire};    

    # CGI-only Parameters for html-representation
    my $code        = ($r->param('code'))?$r->param('code'):'1';
    my $validtarget = ($r->param('validtarget'))?$r->param('validtarget'):'none';
    my $type        = ($r->param('type'))?$r->param('type'):'';
    my $redirect_to = uri_unescape($r->param('redirect_to'));

    my $redirecturl = "";

    my $result_ref = {
        success => 0,
    };
    
    $logger->debug("CSRF-Check: ".$self->validation->csrf_protect->has_error);
    
    # CSRF-Checking
    if ($representation ne "json" && $self->validation->csrf_protect->has_error('csrf_token')){
	my $code   = -10;
	my $reason = $self->get_error_message($code);
	return $self->print_warning($reason,$code);
    }
        
    my $mfa_done = 0;
    
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

    my $authenticator = OpenBib::Authenticator::Factory->create_authenticator({ id => $authenticatorid, config => $config, session => $session});

    my $userid = 0; # Nicht erfolgreich authentifiziert
    
    # Uebergabe MFA-Token, dann dieses Ueberpruefen
    if ($username && $mfa_token){
	$userid = $authenticator->authenticate({
	    username  => $username,
	    mfa_token => $mfa_token,
	    viewname  => $view,
					       });
	$mfa_done = 1;

	$logger->debug("MFA Check => Userid: $userid");
    }
    else {
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
	# -10: invalid mfa_token
	
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
	
    }

    if ($userid == -11){
	my $reason = $self->get_error_message($userid);
	$logger->error("Authentication Error for user $username: $reason ");
	
	return $self->print_warning($reason,$code);
    }

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

	# Bevor die Session mit der Benutzerid assoziiert wird, muss bei MFA
	# der zweite Faktor generiert, ggf. verschickt und ueberprueft werden

	my $authenticator_mfa = $config->get_authenticator_mfa($authenticatorid);
	if ($authenticator_mfa eq "email" && !$mfa_done){
	    my $mfa_token = $user->gen_mfa_token;
	    my $email = $user->get_info($userid)->{email};

	    my $code = -11;
	    my $reason = $self->get_error_message($code);
	    
	    return $self->print_warning($reason,$code) unless ($email);
	    
	    return $self->send_mfa_mail({ authenticatorid => $authenticatorid, username => $username, userid => $userid, email => $email, mfa_token => $mfa_token, redirect_to => $redirect_to });
	}
	elsif ($authenticator_mfa eq "email_admin" && !$mfa_done){
	    my $userdata_ref = $user->get_info($userid);
	    
	    my $mfa_admin_ref = $config->{mfa_admin};

	    my $mfa_required = 0;

	    if (defined $mfa_admin_ref->{users}{$username}){
		$mfa_required = 1;
	    }
	    elsif (defined $userdata_ref->{role}) {
		foreach my $thisrole (keys %{$userdata_ref->{role}}){
		    if (defined $mfa_admin_ref->{roles}{$thisrole}){
			$mfa_required = 1;
		    }
		}
	    }

	    if ($logger->is_debug){
		$logger->debug("Userinfo: ".YAML::Dump($userdata_ref));
		$logger->debug("MFA email_admin: Roles: ".YAML::Dump($userdata_ref->{role})." - Configured: ".YAML::Dump($mfa_admin_ref)." -> required: $mfa_required");
	    }
	    
	    if ($mfa_required){
		my $mfa_token = $user->gen_mfa_token;
		
		my $email = $userdata_ref->{email};

		my $code = -11;
		my $reason = $self->get_error_message($code);
		
		return $self->print_warning($reason,$code) unless ($email);
		
		return $self->send_mfa_mail({ authenticatorid => $authenticatorid, username => $username, userid => $userid, email => $email, mfa_token => $mfa_token, redirect_to => $redirect_to });
	    }
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

	if ($self->stash('representation') eq "html"){

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
	$logger->debug("Redirect to: $redirect_to");
	# Resource finger URL -> replace me with userid
	if ($redirect_to=~m{/users/id/me}){
	    $redirect_to=~s{/users/id/me}{/users/id/$userid};
	}
	# Hashed escapen
	$redirect_to=~s{#}{%23}g;
        $redirecturl=$redirect_to;
	$logger->debug("Processed redirect to: $redirect_to");
    }
    
    # Fehlerbehandlung
    if ($userid <= 0) {
        $redirecturl="$path_prefix/$config->{login_loc}/failure?code=$userid";

	my $code   = $userid;
	my $reason = $self->get_error_message($code);

	if ($self->stash('representation') ne "html"){
	    return $self->print_warning($reason,$code);	    
	}
    }

    # Success!
    if ($self->stash('representation') eq "html"){
        $logger->debug("Authentication success: Redirecting to $redirecturl");

        # TODO GET?
        $self->res->headers->content_type('text/html');
        return $self->redirect($redirecturl);
    }
    else {
        $logger->debug("Authentication success: Returning JSON");	
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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');    
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');    
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my $code      = ($r->param('code'))?$r->param('code'):'1';
    my $authenticatorid  = ($r->param('authenticatorid'))?$r->param('authenticatorid'):'none';
    my $validtarget = ($r->param('validtarget'))?$r->param('validtarget'):'none';
    my $type      = ($r->param('type'))?$r->param('type'):'';
    my $username = ($r->param('username'))?$r->param('username'):'';
    my $password  = decode_utf8($r->param('password')) || $r->param('password') || '';

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

    my $msg            = $self->stash('msg');

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

        -10 => $msg->maketext("Die Anmeldung ist wegen eines inkorrekten CSRF-Tokens gescheitert."),

	-11 => $msg->maketext("Das eingegebene MFA Token ist ungültig. Bitte versuchen Sie sich nochmals neu anzumelden."),

	-12 => $msg->maketext("Es konnte keine E-Mailadresse zum Verschicken des MFA Tokens gefunden werden."),
	
	);

    my $unspecified = $msg->maketext("Unspezifischer Fehler-Code");

    if (defined $messages{$errorcode} && $messages{$errorcode}){
	return $messages{$errorcode}
    }
    else {
	return $unspecified;
    }
}

sub send_mfa_mail {
    my ($self, $arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    
    # Set defaults
    my $authenticatorid = exists $arg_ref->{authenticatorid}
        ? $arg_ref->{authenticatorid}       : undef;

    my $username     = exists $arg_ref->{username}
        ? $arg_ref->{username}              : undef;

    my $userid       = exists $arg_ref->{userid}
        ? $arg_ref->{userid}                : undef;
    
    my $email        = exists $arg_ref->{email}
        ? $arg_ref->{email}                 : undef;

    my $mfa_token    = exists $arg_ref->{mfa_token}
        ? $arg_ref->{mfa_token}             : undef;

    my $redirect_to  = exists $arg_ref->{redirect_to}
        ? $arg_ref->{redirect_to}           : undef;
    
    # Bestaetigungsmail versenden

    my $afile = "an." . $$ . ".txt";

    my $subject  = $msg->maketext("MFA-Token zur Anmeldung am Portal");
    my $viewinfo = $config->get_viewinfo->search({ viewname => $view })->single();

    my $mainttdata = {
	username       => $username,
	userid         => $userid,
	email          => $email,
	mfa_token      => $mfa_token,
	mfa_type       => 'email',	
	viewinfo       => $viewinfo,
    };
    
    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        ABSOLUTE      => 1,
        #        INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });

    $mainttdata = $self->add_default_ttdata($mainttdata);
    
    my $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $mainttdata->{view},
        profile      => $mainttdata->{sysprofile},
        templatename => $config->{tt_login_mfa_mail_message_tname},
    });

    $logger->debug("Using base Template $templatename");
    
    $maintemplate->process($templatename, $mainttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->header_add('Status','400'); # Server Error
        return;
    };

    my $anschfile="/tmp/" . $afile;
    
    Email::Stuffer->to($email)
	->from($config->{contact_email})
	->subject($subject)
	->text_body(read_binary($anschfile))
	->send;

    # TT-Data erzeugen
    my $ttdata={
	mfa_authenticatorid => $authenticatorid,
	mfa_username    => $username,
	mfa_userid      => $userid,
	mfa_email       => $email,
	mfa_token       => $mfa_token,
	mfa_type        => 'email',
	mfa_redirect_to => $redirect_to,
    };
    
    $ttdata = $self->add_default_ttdata($ttdata);

    if ($logger->is_debug){
	$logger->debug("TTdata: ".YAML::Dump($ttdata));
    }
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $config->{tt_login_mfa_form_tname},
    });

    $user->set_mfa_token({ userid => $userid, mfa_token => $mfa_token });
    
    return $self->print_page($templatename,$ttdata);
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
	    required => 1,
        },
        mfa_token => {
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
