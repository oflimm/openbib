
#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Passwords
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

package OpenBib::Mojo::Controller::Users::Passwords;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use Email::Stuffer;
use File::Slurper 'read_binary';
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    my $authenticatorid  = $input_data_ref->{authenticatorid};    
    
    my $authenticators_ref = $config->get_authenticators($view);

    # TT-Data erzeugen
   
    my $ttdata={
        authenticatorid => $authenticatorid,
        authenticators  => $authenticators_ref,	
    };
    
    return $self->print_page($config->{tt_users_passwords_tname},$ttdata);
}

sub create_token {
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

    # CGI / JSON input
    my $input_data_ref    = $self->parse_valid_input();
    my $username          = $input_data_ref->{username};
    my $birthdate         = $input_data_ref->{birthdate};
    my $authenticatorid   = $input_data_ref->{authenticatorid};
    my $mixedbag_ref      = $input_data_ref->{mixed_bag} || {};

    # Aktive Aenderungen des Nutzerkontos
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, Passwort-Reset usw.) sind aktuell systemweit deaktiviert."),1,"$path_prefix/$config->{home_loc}");	
    }

    if ($logger->is_debug){
	$logger->debug("Input: ".YAML::Dump($input_data_ref));
    }

    # Authenticatorid im authtoken sichern
    
    $mixedbag_ref->{authenticatorid} = $authenticatorid;
    
    my @viewauthenticators = $config->get_viewauthenticators($view);

    if ($birthdate !~ /^\d{2}\.\d{2}\.\d{4}$/) {
        my $code   = -1;
	my $reason = $msg->maketext("Bitte geben Sie Ihr Geburtsdatum in der Form TT.MM.JJJJ an (z.B. 27.01.1980).");
	
	return $self->print_warning($reason,$code);
    }
    elsif (!$username) {
        my $code   = -1;
	my $reason = $msg->maketext("Bitte geben Sie die Benutzernummer von Ihrem Bibliotheksausweis ein.");
	
	return $self->print_warning($reason,$code);
    }
    elsif ($username !~ /^[A-Z|9]\d{8}\#[A-Z\d]$/) {
        my $code   = -1;
	my $reason = $msg->maketext("Die eingegebene Benutzernummer ist nicht korrekt.");
	
	return $self->print_warning($reason,$code);
    }
    elsif (!$authenticatorid) {
        my $code   = -1;
	my $reason = $msg->maketext("Es fehlen Informationen über die Authentifizierungsmethode");
	
	return $self->print_warning($reason,$code);
    }
    
    if (!any { $_ eq $authenticatorid } @viewauthenticators) {
        my $code   = -1;
	my $reason = $msg->maketext("Diese Authentifizierungsmethode existiert nicht");
	
	return $self->print_warning($reason,$code);
    }

    my $authenticator_ref = $config->get_authenticator_by_id($authenticatorid);

    my $database = $authenticator_ref->{name};
    
    if (!$config->db_exists($database)){
        my $code   = -1;
	my $reason = $msg->maketext("Für diese Authentifizierungsmethode ist kein Katalog definiert");
	
	return $self->print_warning($reason,$code);
    }

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $response_ref = $ils->get_userdata($username);

    if ($logger->is_debug){
	$logger->debug("ILS userdata: ".YAML::Dump($response_ref));
    }
    
    if ($response_ref->{error}) {
	my $code   = -1;
	my $reason = $response_ref->{error_description};
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }
    elsif ($response_ref->{birthdate} ne $birthdate){
	my $code   = -1;
	my $reason = $msg->maketext("Das eingegebene Geburtsdatum stimmt nicht mit dem von uns gespeicherten Geburtsdatum überein.");
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }
    elsif (!$response_ref->{email}){
	my $code   = -1;
	my $reason = $msg->maketext("In Ihrem Bibliothekskonto ist keine E-Mail-Adresse hinterlegt..");
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }

    my $email = $response_ref->{email};

    my $authtoken = $config->new_authtoken({ authkey => $username, viewname => $view, mixed_bag => $mixedbag_ref });
    
    my $anschreiben="";
    my $afile = "an." . $$;
    
    my $mainttdata = {
	authtoken => $authtoken,
        username  => $username,
        user      => $user,
        msg       => $msg,
    };
    
    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #         ABSOLUTE      => 1,
        #         INCLUDE_PATH  => $config->{tt_include_path},
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
        templatename => $config->{tt_users_passwords_tokenmail_body_tname},
									});
    
    $logger->debug("Using base Template $templatename");
    
    $maintemplate->process($templatename, $mainttdata ) || do {
        $logger->error($maintemplate->error());
        $self->res->code(400); # Server Error
        return;
    };
        
    my $anschfile="/tmp/" . $afile;

    Email::Stuffer->to($email)
	->from($config->{contact_email})
	->subject($msg->maketext("Neues Passwort"))
	->text_body(read_binary($anschfile))
	->send;
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $mainttdata->{view},
        profile      => $mainttdata->{sysprofile},
        templatename => $config->{tt_users_passwords_tokenmail_success_tname},
								     });	
    my $ttdata={
    };
    
    if ($self->stash('representation') eq "html"){
	# TODO GET?
	$self->res->headers->content_type('text/html');
	return $self->print_page($templatename,$ttdata);
    }
    else {
	return $self->print_json({ success => 1 });
    }    
}								     

sub verify_token {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $authtoken      = $self->strip_suffix($self->param('tokenid'));

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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    my $authkey        = $input_data_ref->{authkey};    

    # Aktive Aenderungen des Nutzerkontos
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, Passwort-Reset usw.) sind aktuell systemweit deaktiviert."),1,"$path_prefix/$config->{home_loc}");	
    }

    if ($logger->is_debug){
	$logger->debug("Input: ".YAML::Dump($input_data_ref));
    }

    my $authtokeninfo_ref = $config->get_authtoken({ id => $authtoken, authkey => $authkey, viewname => $view });

    if ($logger->is_debug){
	$logger->debug("Authtokeninfo: ".YAML::Dump($authtokeninfo_ref));
    }
    
    unless (defined $authtokeninfo_ref->{authkey} || $authtokeninfo_ref->{authkey} eq $authkey || defined $authtokeninfo_ref->{mixed_bag}{authenticatorid}){
	return $self->print_warning($msg->maketext("Die Informationen zum Aufruf dieser Webseite sind nicht plausibel."),1,"$path_prefix/$config->{home_loc}");			
    }
    
    my $authenticator_ref = $config->get_authenticator_by_id($authtokeninfo_ref->{mixed_bag}{authenticatorid});

    my $database = $authenticator_ref->{name};

    if (!$config->db_exists($database)){
        my $code   = -1;
	my $reason = $msg->maketext("Für diese Authentifizierungsmethode ist kein Katalog definiert");
	
	return $self->print_warning($reason,$code);
    }
    
    my $authenticators_ref = $config->get_authenticators($view);

    # TT-Data erzeugen
   
    my $ttdata={
        authtoken => $authtoken,
	authkey  => $authkey,
    };
    
    return $self->print_page($config->{tt_users_passwords_verifytoken_tname},$ttdata);
}

sub create_record {
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

    # CGI / JSON input
    my $input_data_ref    = $self->parse_valid_input();
    my $authtoken         = $input_data_ref->{authtoken};
    my $authkey           = $input_data_ref->{authkey};

    if ($authtoken && $authkey){
	return $self->reset_password_by_authtoken;
    }
    
    return $self->reset_password_default;    
}

sub reset_password_by_authtoken {
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    my $authkey        = $input_data_ref->{authkey};
    my $authtoken      = $input_data_ref->{authtoken};
    my $password1      = $input_data_ref->{password1};
    my $password2      = $input_data_ref->{password2};
    
    # Aktive Aenderungen des Nutzerkontos
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, Passwort-Reset usw.) sind aktuell systemweit deaktiviert."),1,"$path_prefix/$config->{home_loc}");	
    }

    if ($logger->is_debug){
	$logger->debug("Input: ".YAML::Dump($input_data_ref));
    }

    my $authtokeninfo_ref = $config->get_authtoken({ id => $authtoken, authkey => $authkey, viewname => $view });

    if ($logger->is_debug){
	$logger->debug("Authtokeninfo: ".YAML::Dump($authtokeninfo_ref));
    }
    
    unless (defined $authtokeninfo_ref->{authkey} || $authtokeninfo_ref->{authkey} eq $authkey || defined $authtokeninfo_ref->{mixed_bag}{authenticatorid}){
	return $self->print_warning($msg->maketext("Die Informationen zum Aufruf dieser Webseite sind nicht plausibel."),1,"$path_prefix/$config->{home_loc}");			
    }
    
    my $authenticator_ref = $config->get_authenticator_by_id($authtokeninfo_ref->{mixed_bag}{authenticatorid});

    my $database = $authenticator_ref->{name};

    if (!$config->db_exists($database)){
        my $code   = -1;
	my $reason = $msg->maketext("Für diese Authentifizierungsmethode ist kein Katalog definiert");
	
	return $self->print_warning($reason,$code);
    }

    if (!$password1 || !$password2) {
	my $code   = -1;
	my $reason = $msg->maketext("Bitte füllen Sie alle beiden Passwort-Felder aus.");
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }
    elsif ($password1 ne $password2){
	my $code   = -1;
	my $reason = $msg->maketext("Die beiden neuen Passwörter, die Sie eingegeben haben, stimmen nicht überein.");
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }
    elsif (length(decode_utf8($password1)) != 6 ){
	my $code   = -1;
	my $reason = $msg->maketext("Ihr neues Passwort muss 6-stellig sein.");
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }
    elsif ($password1 !~ /^[a-zA-Z0-9]+$/ or $password1 !~ /[0-9]/ or $password1 !~ /[a-zA-Z]/){
	my $code   = -1;
	my $reason = $msg->maketext("Bitte geben Sie ein Passwort ein, welches den Vorgaben entspricht.");
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });
    
    my $response_ref = $ils->reset_password($authkey,$password1);
    
    if ($response_ref->{error}) {
	my $code   = -1;
	my $reason = $response_ref->{error_description};
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/$config->{passwords_loc}");
    }        

    # Reset ok, dann authtoken entfernen

    $config->del_authtoken({ id => $authtoken, authkey => $authkey, viewname => $view });
    
    # TT-Data erzeugen
   
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_users_passwords_token_success_tname},$ttdata);
}

sub reset_password_default {
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

    # CGI / JSON input
    my $input_data_ref    = $self->parse_valid_input();
    my $username          = $input_data_ref->{username};
    my $authtoken         = $input_data_ref->{authtoken};
    my $authkey           = $input_data_ref->{authkey};


    my $result_ref = {
        success => 0,
    };
    
    my $loginfailed=0;
    
    if (!$username) {
        my $code   = -1;
	my $reason = $msg->maketext("Sie haben keine E-Mail Adresse eingegeben.");
	
	return $self->print_warning($reason,$code);
    }

    if (!$user->user_exists($username)) {
        my $code   = -2;
	my $reason = $msg->maketext("Dieser Nutzer ist nicht registriert.");
	
	return $self->print_warning($reason,$code);
    }

    # Zufaelliges 12-stelliges Passwort
    my $password = join '', map { ("a".."z", "A".."Z", 0..9)[rand 62] } 1..12;
    
    # Set new password

    my $userid = $user->get_userid_for_username($username, $view);

    if ($userid > 0){
	$user->set_password({ userid => $userid, password => $password });
	$user->reset_login_failure({ userid => $userid});
    }
    else {
      my $code   = -3;
      my $reason = $msg->maketext("Dieser Nutzer ist in diesem Portal nicht registriert.");
      
      return $self->print_warning($reason,$code);
    }

    my $anschreiben="";
    my $afile = "an." . $$;
    
    my $mainttdata = {
        username  => $username,
        password  => $password,
        user      => $user,
        msg       => $msg,
    };
    
    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #         ABSOLUTE      => 1,
        #         INCLUDE_PATH  => $config->{tt_include_path},
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
        templatename => $config->{tt_users_passwords_mail_body_tname},
									});
    
    $logger->debug("Using base Template $templatename");
    
    $maintemplate->process($templatename, $mainttdata ) || do {
        $logger->error($maintemplate->error());
        $self->res->code(400); # Server Error
        return;
    };
        
    my $anschfile="/tmp/" . $afile;

    Email::Stuffer->to($username)
	->from($config->{contact_email})
	->subject($msg->maketext("Passwort vergessen"))
	->text_body(read_binary($anschfile))
	->send;
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $mainttdata->{view},
        profile      => $mainttdata->{sysprofile},
        templatename => $config->{tt_users_passwords_success_tname},
								     });	
    
    my $confirmationid = $user->add_confirmation_request({username => $username, viewname => $view});

    my $ttdata={
    };
    
    if ($self->stash('representation') eq "html"){
	# TODO GET?
	$self->res->headers->content_type('text/html');
	return $self->print_page($templatename,$ttdata);
    }
    else {
	return $self->print_json({success => 1});
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
        birthdate => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        authkey => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        authtoken => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        password1 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        password2 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        mixed_bag => {
            default  => '',
            encoding => 'none',
            type     => 'mixed_bag',
        },
    };
}

1;
