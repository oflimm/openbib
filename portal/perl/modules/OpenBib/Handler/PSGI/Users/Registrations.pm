#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Registrations
#
#  Dieses File ist (C) 2004-2019 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::Registrations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Email::Valid;               # EMail-Adressen testen
use Email::MIME;
use Email::Stuffer;
use Email::Sender::Simple;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Captcha::reCAPTCHA;
use POSIX;


use OpenBib::Common::Util;
use OpenBib::Config;
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
        'show'              => 'show',
        'register'          => 'register',
        'mail_confirmation' => 'mail_confirmation',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
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
    my $action              = ($query->param('action'))?$query->param('action'):'none';
    my $targetid            = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $username            = ($query->param('username'))?$query->param('username'):'';
    my $password1           = ($query->param('password1'))?$query->param('password1'):'';
    my $password2           = ($query->param('password2'))?$query->param('password2'):'';
    my $recaptcha_challenge = $query->param('recaptcha_challenge_field');
    my $recaptcha_response  = $query->param('recaptcha_response_field');

    
    my $recaptcha = Captcha::reCAPTCHA->new;

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    my $client_ip="";
    
    if ($r->header('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    # TT-Data erzeugen
    my $ttdata={
        recaptcha  => $recaptcha,
        
        lang       => $queryoptions->get_option('l'),
    };
    
    return $self->print_page($config->{tt_users_registrations_tname},$ttdata);
}

sub mail_confirmation {
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

    # CGI / JSON input
    my $input_data_ref      = $self->parse_valid_input();

    my $username            = $input_data_ref->{username}  || '';
    my $password1           = $input_data_ref->{password1} || '';
    my $password2           = $input_data_ref->{password2} || '';
    my $recaptcha_challenge = $input_data_ref->{'recaptcha_challenge_field'};
    #my $recaptcha_response = $input_data_ref->{'recaptcha_response_field'};
    my $recaptcha_response  = $input_data_ref->{'g-recaptcha-response'};

    if ($logger->is_debug){
	foreach my $qparam (keys %$input_data_ref){
	    $logger->debug("$qparam -> ".$input_data_ref->{$qparam});
	}
    }

    my $result_ref = {
        success => 0,
    };
    
    # Cleanup Username
    $username=~s/^\s+//g;
    $username=~s/\s+$//g;
    
    if ($username eq "" || $password1 eq "" || $password2 eq "") {
        my $code   = -1;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }
    
    if ($password1 ne $password2) {
        my $code   = -2;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }
    
    # Ueberpruefen, ob es eine gueltige Mailadresse angegeben wurde.
    unless (Email::Valid->address($username)){
        my $code   = -3;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    my $authenticator_self_ref = $config->get_authenticator_self;
    
    if ($user->user_exists_in_view({ username => $username, viewname => $view, authenticatorid => $authenticator_self_ref->{id}})) {
        my $code   = -4;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    
    # Viewadmin darf ueber das ohne Captcha Nutzer registrieren

    if (!$user->is_admin && !$user->is_viewadmin($view)){
	my $recaptcha = Captcha::reCAPTCHA->new;
	
	# Wenn der Request ueber einen Proxy kommt, dann urspruengliche
	# Client-IP setzen
	my $client_ip="";
	
	if ($r->header('X-Forwarded-For') =~ /([^,\s]+)$/) {
	    $client_ip=$1;
	}
		
	# Recaptcha nur verwenden, wenn Zugriffsinformationen vorhanden sind
	if ($config->{recaptcha_private_key}){
	    # Recaptcha pruefen
	    my $recaptcha_result = $recaptcha->check_answer_v2(
		$config->{recaptcha_private_key}, $recaptcha_response, $client_ip
		);
	    
	    unless ( $recaptcha_result->{is_valid} ) {
		my $code   = -6;
		my $reason = $self->get_error_message($code);
		return $self->print_warning($reason,$code);
	    }
	}
    }
    
    my $registrationid = $user->add_confirmation_request({username => $username, password => $password1, viewname => $view});

    # Bestaetigungsmail versenden

    my $afile = "an." . $$ . ".txt";

    my $subject  = $msg->maketext("Bestaetigen Sie Ihre Registrierung");
    my $viewinfo = $config->get_viewinfo->search({ viewname => $view })->single();

    my $mainttdata = {        
	registrationid => $registrationid,

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
        templatename => $config->{tt_users_registrations_mail_message_tname},
    });

    $logger->debug("Using base Template $templatename");
    
    $maintemplate->process($templatename, $mainttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->header_add('Status','400'); # Server Error
        return;
    };

    #  my $mailmsg = MIME::Lite->new(
    #     From            => $config->{contact_email},
    #     To              => $username,
    #     Subject         => $subject,
    #     Type            => 'multipart/mixed'
    # );

    my $anschfile="/tmp/" . $afile;

    # $mailmsg->attach(
    #     Type            => 'text/plain',
    #     Encoding        => '8bit',
	# Path            => $anschfile,
    # );
    
    # #$mailmsg->send('sendmail', "/usr/bin/mail -s -f$config->{contact_email}");
    # $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config->{contact_email}");
    
    Email::Stuffer->to($user)
              ->from($config->{contact_email})
              ->subject($subject)
              ->attach_file($anschfile)
              ->send;
    
    # my @parts = (
    # Email::MIME->create(
    #     attributes=> {
    #         content_type => "text/plain",
    #         disposition  => "attachment",
    #         charset      => "US-ASCII",
    #     }
    # ));
    
    # my $email = Email::MIME->create(
    # header => [
    #     From => $config->{contact_email},
    #     To => $username,
    # ],
    # parts      => [ @parts ],
    # );

    # Email::Sender::Simple->try_to_send($email);

   

    # TT-Data erzeugen
    my $ttdata={
	registrationid => $registrationid,
        username       => $username,
    };

    $ttdata = $self->add_default_ttdata($ttdata);
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $config->{tt_users_registrations_confirmation_tname},
    });
    
    return $self->print_page($templatename,$ttdata);
}

sub register {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $registrationid = $self->strip_suffix($self->param('registrationid')) || '';

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
    

    my $client_ip = "";
    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    if ($r->header('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip = $1; # $r->connection->remote_ip($1);
    }

    # ab jetzt ist klar, dass es den Benutzer noch nicht gibt.
    # Jetzt eintragen und session mit dem Benutzer assoziieren;

    my $confirmation_info_ref = $user->get_confirmation_request({registrationid => $registrationid});

    my $username         = $confirmation_info_ref->{username};
    my $hashed_password  = $confirmation_info_ref->{password};
    my $viewid           = $confirmation_info_ref->{viewid};
    
    if ($username && $viewid && $hashed_password){

	my $authenticator_self_ref = $config->get_authenticator_self;
	
	
	# Wurde dieser Nutzername inzwischen bereits registriert?
	if ($user->user_exists_in_view({ username => $username, viewid => $viewid, authenticatorid => $authenticator_self_ref->{id} })) {
	    my $code   = -4;
	    my $reason = $self->get_error_message($code);
	    return $self->print_warning($reason,$code);
	}
	
	# OK, neuer Nutzer -> eintragen
	$user->add({
	    username         => $username,
	    hashed_password  => $hashed_password,
	    viewid           => $viewid,
	    email            => $username,
	    authenticatorid  => $authenticator_self_ref->{id},
		   });
	
	# An dieser Stelle darf zur Bequemlichkeit der Nutzer die Session 
	# nicht automatisch mit dem Nutzer verknuepft werden (=automatische
	# Anmeldung), dann dann ueber das Ausprobieren von Registrierungs-IDs 
	# Nutzer-Identitaeten angenommen werden koennten.
	
	$user->clear_confirmation_request({ registrationid => $registrationid });
    }
    else {
	my $code   = -5;
	my $reason = $self->get_error_message($code);
	return $self->print_warning($reason,$code);
    }

    # TT-Data erzeugen
    my $ttdata={
        username   => $username,
    };

    $ttdata = $self->add_default_ttdata($ttdata);
    
    my $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $config->{tt_users_registrations_success_tname},
    });
    
    return $self->print_page($templatename,$ttdata);
}

sub get_error_message {
    my $self=shift;
    my $errorcode=shift;

    my $msg            = $self->param('msg');
    my $config         = $self->param('config');    
    my $path_prefix    = $self->param('path_prefix');    

    my %messages = (
        -1 => $msg->maketext("Es wurde entweder kein Benutzername oder keine zwei Passworte eingegeben"),
        -2 => $msg->maketext("Die beiden eingegebenen Passworte stimmen nicht überein."),
        -3 => $msg->maketext("Sie haben keine gültige Mailadresse eingegeben. Gehen Sie bitte [_1]zurück[_2] und korrigieren Sie Ihre Eingabe","<a href=\"$path_prefix/$config->{users_loc}/$config->{registrations_loc}\">","</a>"),
        -4 => $msg->maketext("Ein Benutzer mit dem Namen existiert bereits. Haben Sie vielleicht Ihr Passwort vergessen? Dann gehen Sie bitte [_1]zurück[_2] und lassen es sich zumailen.","<a href=\"$path_prefix/$config->{users_loc}/$config->{passwords_loc}.html\">","</a>"),
        -5 => $msg->maketext("Diese Registrierungs-ID existiert nicht für dieses Portal."),
	-6 => $msg->maketext("Sie haben ein falsches Captcha eingegeben! Gehen Sie bitte [_1]zurück[_2] und versuchen Sie es erneut.","<a href=\"$path_prefix/$config->{users_loc}/$config->{registrations_loc}.html\">","</a>"),
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
        username => {
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
        'recaptcha_challenge_field' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        'g-recaptcha-response' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}


1;
