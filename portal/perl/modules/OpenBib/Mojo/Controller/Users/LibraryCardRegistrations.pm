#####################################################################
#
#  OpenBib::Mojo::Controller::Users::LibraryCardRegistrations
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::LibraryCardRegistrations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Email::Valid;               # EMail-Adressen testen
use Email::Stuffer;
use File::Slurper 'read_binary';
use Encode 'decode_utf8';
use HTML::Entities;
use Log::Log4perl qw(get_logger :levels);
use Captcha::reCAPTCHA;
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::ILS::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
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
    
    my $recaptcha = Captcha::reCAPTCHA->new;

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    my $client_ip="";
    
    if ($r->header('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    # TT-Data erzeugen
    my $ttdata={
	use_captcha => 0,
        recaptcha   => $recaptcha,
        
        lang        => $queryoptions->get_option('l'),
    };
    
    return $self->print_page($config->{tt_users_librarycard_registrations_tname},$ttdata);
}

sub register {
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
    my $input_data_ref      = $self->parse_valid_input();

    my $dbname              = $input_data_ref->{dbname}       || '';    
    my $salutation          = $input_data_ref->{salutation}   || '';
    my $forename            = $input_data_ref->{forename}     || '';
    my $surname             = $input_data_ref->{surname}      || '';
    my $birthdate           = $input_data_ref->{birthdate}    || '';
    my $street              = $input_data_ref->{street}       || '';
    my $zip                 = $input_data_ref->{zip}          || '';
    my $city                = $input_data_ref->{city}         || '';
    my $email               = $input_data_ref->{email}        || '';
    my $password1           = $input_data_ref->{password1}    || '';
    my $password2           = $input_data_ref->{password2}    || '';
    my $confirmation        = $input_data_ref->{confirmation} || '';

    my $recaptcha_challenge = $input_data_ref->{'recaptcha_challenge_field'};
    my $recaptcha_response  = $input_data_ref->{'g-recaptcha-response'};

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, Online-Anmeldung, UCCard Freischaltung usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    my $use_captcha = 0;
    
    # Admin darf auch ohne Captcha, z.B. per JSON API, Nutzer registrieren
    if ($use_captcha && !$user->is_admin){
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
		my $code   = -13;
		my $reason = $self->get_error_message($code);
		$logger->error("Library Card registration failed for user $forename $surname: $reason");	
		return $self->print_warning($reason,$code);
	    }
	}
    }

    # Salutation

    my $salutation_codemap_ref = {
	 'Frau'           => 2,   
	 'Frau Dr.'       => 4,   
	 'Frau Prof. Dr.' => 6,   
	 'Herr'           => 1,   
	 'Herr Dr.'       => 3,   
	 'Herr Prof. Dr.' => 5,   
    };

    if (defined $salutation_codemap_ref->{$salutation}){
	$salutation = $salutation_codemap_ref->{$salutation};
    }
    else {
        my $code   = -1;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if (!$forename){
        my $code   = -2;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if (!$surname){
        my $code   = -3;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if ($birthdate !~ /^\d{2}\.\d{2}\.\d{4}$/){
        my $code   = -4;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if (! ($street  && $zip && $city)){
        my $code   = -5;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if ($email && ! Email::Valid->address($email)){
        my $code   = -6;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if (length(decode_utf8($password1)) != 6){
        my $code   = -7;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if ($password1 !~ /^[a-zA-Z0-9]+$/ or $password1 !~ /[0-9]/ or $password1 !~ /[a-zA-Z]/){
        my $code   = -8;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if (!$password2){
        my $code   = -9;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if ($password1 ne $password2){
        my $code   = -10;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if (!$confirmation){
        my $code   = -11;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }

    if (!$dbname || !$config->db_exists($dbname)){
        my $code   = -12;
	my $reason = $self->get_error_message($code);
	$logger->error("Library Card registration failed for user $forename $surname: $reason");	
        return $self->print_warning($reason,$code);
    }
    
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $dbname });

    if ($logger->is_debug){
	$logger->debug("Trying to register user in ils for $dbname");
    }
    
    my $register_ref = $ils->register_librarycard($input_data_ref);

    if ($logger->is_debug){
	$logger->debug("Register librarycard: ".YAML::Dump($input_data_ref));
    }

    if ($register_ref->{error}){
	if ($register_ref->{error_description}){
	    my $reason = encode_entities($register_ref->{error_description});
	    $logger->error("Library Card registration failed for user $forename $surname: $reason");	

	    return $self->print_warning($reason);
	}
	else {
	    $logger->error("Library Card registration failed for user $forename $surname: unknown reason");	

	    return $self->print_warning($msg->maketext("Eine Neuanmeldung durch Sie ist leider nicht möglich"));
	}
    }
    elsif ($register_ref->{successful}){
	$logger->info("Library Card registration successful for user $forename $surname. New username: ".$register_ref->{username});	
	
	# TT-Data erzeugen
	my $ttdata={
	    registration   => $register_ref,
	    userdata       => $input_data_ref,
	};
	
	$ttdata = $self->add_default_ttdata($ttdata);
	
	my $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
	    database     => $dbname,
	    view         => $ttdata->{view},
	    profile      => $ttdata->{sysprofile},
	    templatename => $config->{tt_users_librarycard_registrations_success_tname},
									    });
    
	return $self->print_page($templatename,$ttdata);
    }
    else {
	return $self->print_warning($msg->maketext("Bei der Neuanmeldung ist ein unerwarteter Fehler aufgetreten"));
    }
}

sub get_error_message {
    my $self=shift;
    my $errorcode=shift;

    my $msg            = $self->stash('msg');
    my $config         = $self->stash('config');    
    my $path_prefix    = $self->stash('path_prefix');    

    my %messages = (
         -1 => $msg->maketext("Bitte wählen Sie eine Anrede aus."),
         -2 => $msg->maketext("Bitte geben Sie Ihren Vornamen an."),
         -3 => $msg->maketext("Bitte geben Sie Ihren Nachnamen an."),
         -4 => $msg->maketext("Bitte geben Sie Ihr Geburtsdatum in der Form TT.MM.JJJJ an (z.B. 27.01.1980)."),
         -5 => $msg->maketext("Bitte geben Sie Ihre Postanschrift vollständig an."),
         -6 => $msg->maketext("Die Syntax der eingegebenen E-Mail-Adresse ist ungültig."),
         -7 => $msg->maketext("Bitte geben Sie ein 6-stelliges Passwort an."),
         -8 => $msg->maketext("Bitte geben Sie ein Passwort ein, welches den Vorgaben entspricht."),
         -9 => $msg->maketext("Bitte bestätigen Sie Ihr Passwort."),
        -10 => $msg->maketext("Die beiden Passwörter, die Sie eingegeben haben, stimmen nicht überein."),
        -11 => $msg->maketext("Bitte erkennen Sie die Gebühren- und Nutzungsordnungen an."),
        -12 => $msg->maketext("Der Katalogname fehlt."),
	-13 => $msg->maketext("Sie haben ein falsches Captcha eingegeben! Gehen Sie bitte [_1]zurück[_2] und versuchen Sie es erneut.","<a href=\"$path_prefix/$config->{users_loc}/$config->{librarycard_registrations_loc}.html\">","</a>"),
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
        dbname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        salutation => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        forename => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        surname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        birthdate => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        street => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        zip => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        city => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        email => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        confirmation => {
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
