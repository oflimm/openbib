#####################################################################
#
#  OpenBib::Handler::PSGI::Users::UCCardActivations
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

package OpenBib::Handler::PSGI::Users::UCCardActivations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Email::Valid;               # EMail-Adressen testen
use Email::Stuffer;
use File::Slurper 'read_binary';
use Encode 'decode_utf8';
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

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'              => 'show',
        'authenticate'      => 'authenticate',
        'activate'          => 'activate',
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
    
    return $self->print_page($config->{tt_users_uccard_activations_tname},$ttdata);
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
    
    # CGI / JSON input
    my $input_data_ref      = $self->parse_valid_input();

    my $username            = $input_data_ref->{ucusername}     || '';    
    my $password            = $input_data_ref->{ucpassword}     || '';
    my $dbname              = $input_data_ref->{dbname}       || '';
    
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, Online-Anmeldung, UCCard Freischaltung usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    if (!$username){
        my $code   = -1;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    if (!$password){
        my $code   = -2;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    if (!$dbname || ! $config->db_exists($dbname)){
        my $code   = -3;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $dbname });

    if ($logger->is_debug){
	$logger->debug("Trying to authenticate user");
    }
    
    my $authentications_ref = $ils->uccard_login($input_data_ref);

    if ($logger->is_debug){
	$logger->debug("Login UCCard: ".YAML::Dump($input_data_ref));
    }

    if ($authentications_ref->{error}){
	if ($authentications_ref->{error_description}){
	    return $self->print_warning(encode_entities($authentications_ref->{error_description}));
	}
	else {
	    return $self->print_warning($msg->maketext("Eine Authentifizierung für die UC-Card durch Sie ist leider nicht möglich"));
	}
    }
    elsif ($authentications_ref->{successful}){
	# TT-Data erzeugen
	my $ttdata={
	    authentications   => $authentications_ref,
	    logindata         => $input_data_ref,
	};
	
	$ttdata = $self->add_default_ttdata($ttdata);
	
	my $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
	    database     => $dbname,
	    view         => $ttdata->{view},
	    profile      => $ttdata->{sysprofile},
	    templatename => $config->{tt_users_uccard_activations_confirmation_tname},
									    });
    
	return $self->print_page($templatename,$ttdata);
    }
    else {
	return $self->print_warning($msg->maketext("Bei der Anmeldung für die UC-Card ist ein unerwarteter Fehler aufgetreten"));
    }
}

sub activate {
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

    my $dbname              = $input_data_ref->{dbname}       || '';    
    my $ucusername          = $input_data_ref->{ucusername}   || '';
    my $ucpassword          = $input_data_ref->{ucpassword}   || '';
    my $password1           = $input_data_ref->{password1}    || '';
    my $password2           = $input_data_ref->{password2}    || '';
    my $confirmation        = $input_data_ref->{confirmation} || '';

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, Online-Anmeldung, UCCard Freischaltung usw.) sind aktuell systemweit deaktiviert."));	
    }

    if ($confirmation != 1){
        my $code   = -4;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }
    
    if (length(decode_utf8($password1)) != 6){
        my $code   = -5;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    if ($password1 !~ /^[a-zA-Z0-9]+$/ or $password1 !~ /[0-9]/ or $password1 !~ /[a-zA-Z]/){
        my $code   = -6;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    if ($password1 ne $password2){
        my $code   = -7;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }
    
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $dbname });

    my $authentications_ref = $ils->uccard_login($input_data_ref);
    
    if ($logger->is_debug){
	$logger->debug("Trying to authenticate user with UCCard");
    }

    if (!defined $authentications_ref->{successful} || !$authentications_ref->{successful}){
        my $code   = -5;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    if (!defined $authentications_ref->{studentid} || !$authentications_ref->{studentid}){
        my $code   = -6;
	my $reason = $self->get_error_message($code);
        return $self->print_warning($reason,$code);
    }

    # Studentid aus Authentifizierunginformationen zur Missbrauchsvermeidung
    $input_data_ref->{studentid} = $authentications_ref->{studentid};
    
    my $activations_ref = $ils->uccard_activate($input_data_ref);

    if ($logger->is_debug){
	$logger->debug("Activate UCCard: ".YAML::Dump($input_data_ref));
    }

    if ($activations_ref->{error}){
	if ($activations_ref->{error_description}){
	    return $self->print_warning(encode_entities($activations_ref->{error_description}));
	}
	else {
	    return $self->print_warning($msg->maketext("Eine Freischaltung der UCCard durch Sie ist leider nicht möglich"));
	}
    }
    elsif ($activations_ref->{successful}){
	# TT-Data erzeugen
	my $ttdata={
	    activations    => $activations_ref,
	    userdata       => $input_data_ref,
	};
	
	$ttdata = $self->add_default_ttdata($ttdata);
	
	my $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
	    database     => $dbname,
	    view         => $ttdata->{view},
	    profile      => $ttdata->{sysprofile},
	    templatename => $config->{tt_users_uccard_activations_success_tname},
									    });
    
	return $self->print_page($templatename,$ttdata);
    }
    else {
	return $self->print_warning($msg->maketext("Bei der Freischaltung der UCCard ist ein unerwarteter Fehler aufgetreten"));
    }
}

sub get_error_message {
    my $self=shift;
    my $errorcode=shift;

    my $msg            = $self->param('msg');
    my $config         = $self->param('config');    
    my $path_prefix    = $self->param('path_prefix');    

    my %messages = (
         -1 => $msg->maketext("Bitte geben Sie den Benutzernamen Ihres Studierenden-Accounts ein."),
         -2 => $msg->maketext("Bitte geben Sie das Passwort Ihres Studierenden-Accounts ein."),
         -3 => $msg->maketext("Der Katalogname fehlt."),
         -4 => $msg->maketext("Bitte erkennen Sie die Gebühren- und Nutzungsordnungen an."),
         -5 => $msg->maketext("Ihr Passwort muss 6-stellig sein."),
         -6 => $msg->maketext("Bitte geben Sie ein Passwort ein, welches den Vorgaben entspricht."),
         -7 => $msg->maketext("Die beiden Passwörter, die Sie eingegeben haben, stimmen nicht überein."),
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
        ucusername => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        ucpassword => {
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
        confirmation => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}


1;
