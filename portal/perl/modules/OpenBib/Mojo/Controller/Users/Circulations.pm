#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Circulations
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

package OpenBib::Mojo::Controller::Users::Circulations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Crypt::JWT qw(decode_jwt encode_jwt);
use Email::Valid;
use DBI;
use Digest::MD5;
use Email::Valid;
use Encode qw/decode_utf8 encode_utf8/;
use HTML::Entities qw/decode_entities encode_entities/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape qw/uri_unescape/;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Users';

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    # CGI Args for payment status
    my $jwt            = $r->param('bibpay_jwt');

    my $payment_ref    = $config->get('payment');

    my $payment_decoding_error = 0;
    
    my $payment_result_ref = {};

    if ($jwt){
	eval {
	    $payment_result_ref = decode_jwt(token => $jwt, key => $payment_ref->{secret}, accepted_alg => 'HS256');
	};
	
	if ($@){
	    $payment_decoding_error = 1;
	}
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator();            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $database              = $sessionauthenticator;
    
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    $logger->debug("Loginname: $loginname");

    my $account_ref  = $ils->get_accountinfo($loginname);
    my $userdata_ref = $ils->get_userdata($loginname);

#    my $items_ref = $ils->get_items($loginname);
#    my $fees_ref  = $ils->get_fees($loginname);

    if ($logger->is_debug){
	$logger->debug("Got account: ".YAML::Dump($account_ref));
#	$logger->debug("Got fees: ".YAML::Dump($fees_ref));
#	$logger->debug("Got fees: ".YAML::Dump($fees_ref));
    }
    
    my $authenticator = $session->get_authenticator;

    if ($logger->is_debug){
	$logger->debug("Trying to renew loans for user $loginname in ils for $database");
    }
    
    # TT-Data erzeugen
    my $ttdata={
	jwt                    => $jwt,
	payment_decoding_error => $payment_decoding_error,
	payment_result         => $payment_result_ref,
	
        authenticator => $authenticator,
        loginname  => $loginname,
        password   => $password,

	account    => $account_ref,
	userdata   => $userdata_ref,
#        items      => $items_ref,
#        fees       => $fees_ref,

	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_tname},$ttdata);
}

sub update_ilsaccount {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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
    my $input_data_ref = $self->parse_valid_input('get_input_definition_ilsaccount');

    my $field          = $input_data_ref->{field};
    
    my $oldpassword    = $input_data_ref->{oldpassword};
    my $password1      = $input_data_ref->{password1};
    my $password2      = $input_data_ref->{password2};
    my $email1         = $input_data_ref->{email1};
    my $email2         = $input_data_ref->{email2};
    my $phone1         = $input_data_ref->{phone1};
    my $phone2         = $input_data_ref->{phone2};
    my $pin1           = $input_data_ref->{pin1};
    my $pin2           = $input_data_ref->{pin2};

    # Aktive Aenderungen des Nutzerkontos
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."),1,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");	
    }

    if (!$field){
        my $code   = -1;
	my $reason = $msg->maketext("Es wurde keine Information uebergeben welches Feld aktualisiert werden soll");
	
	return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $database              = $sessionauthenticator;
    
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;

    if ($logger->is_debug){
	$logger->debug("Trying to update field $field for user $loginname in ils for $database");
    }

    my $response_ref;
    
    if ($field eq "password"){
    
	if (!$oldpassword || !$password1 || !$password2) {
	    my $code   = -1;
	    my $reason = $msg->maketext("Bitte füllen Sie alle drei Passwort-Felder aus.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}

	eval {
	    $oldpassword    = decode_entities($oldpassword);
	    $password1      = decode_entities($password1);
	    $password2      = decode_entities($password2);

	    # if ($logger->is_debug){
	    # 	$logger->debug("Change Password $oldpassword to $password1 / $password2");
	    # }
	};

	if ($@){
	    my $code   = -1;
	    my $reason = $msg->maketext("Es ist ein Dekodierungsfehler des Passworts aufgetreten.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");	    
	}
        
	if ($password1 ne $password2){
	    my $code   = -1;
	    my $reason = $msg->maketext("Die beiden neuen Passwörter, die Sie eingegeben haben, stimmen nicht überein.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	elsif (length(decode_utf8($password1)) < 6 ){
	    my $code   = -1;
	    my $reason = $msg->maketext("Ihr neues Passwort muss mindestens 6-stellig sein.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	elsif ($password1 !~ /^[a-zA-Z0-9[:punct:]]+$/ or $password1 !~ /[0-9]/ or $password1 !~ /[a-zA-Z]/){
	    my $code   = -1;
	    my $reason = $msg->maketext("Bitte geben Sie ein Passwort ein, welches den Vorgaben entspricht.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}

	$response_ref = $ils->update_password($loginname,$oldpassword,$password1);

	if ($response_ref->{error}) {
	    my $code   = -1;
	    my $reason = $response_ref->{error_description};
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	
    }
    elsif ($field eq "email"){
    
	if ($email1 eq "" || $email1 ne $email2) {
	    my $code   = -1;
	    my $reason = $msg->maketext("Sie haben entweder kein Mail-Adresse eingegeben oder die beiden Mail-Adressen stimmen nicht überein");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}

	if (! Email::Valid->address($email1)) {
	    my $code   = -1;
	    my $reason = $msg->maketext("Die Syntax der eingegebenen E-Mail-Adresse ist ungültig.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}		
	
	$response_ref = $ils->update_email($loginname,$email1);

	if ($response_ref->{error}) {
	    my $code   = -1;
	    my $reason = $response_ref->{error_description};
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}

    }
    elsif ($field eq "phone"){
    
	if ($phone1 ne $phone2) {
	    my $code   = -1;
	    my $reason = $msg->maketext("Sie haben entweder keine Telefon-Nummer eingegeben oder die beiden Telefon-Nummern stimmen nicht überein");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}

	$response_ref = $ils->update_phone($loginname,$phone1);

	if ($response_ref->{error}) {
	    my $code   = -1;
	    my $reason = $response_ref->{error_description};
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	
    }

    elsif ($field eq "pin"){
    
	if ($pin1 ne $pin2) {
	    my $code   = -1;
	    my $reason = $msg->maketext("Sie haben entweder keine Ausleih-PIN eingegeben oder die beiden PINs stimmen nicht überein");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	elsif ($pin1 !~ m/^\d\d\d\d/) {
	    my $code   = -1;
	    my $reason = $msg->maketext("Sie haben keine 4 Ziffern für die Ausleih-PIN eingegeben");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}

	$response_ref = $ils->update_pin($loginname,$pin1);

	if ($response_ref->{error}) {
	    my $code   = -1;
	    my $reason = $response_ref->{error_description};
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	
    }

    if ($self->stash('representation') eq "html"){
	my $reason = $response_ref->{message} || "Aktion erfolgreich.";
	
	return $self->print_info($msg->maketext($reason),1,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
#        $self->return_baseurl;
#        return;
    }
    else {
	return $self->print_json($response_ref);
    }

    return;
}


sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared args
    my $msg            = $self->stash('msg');

    $logger->error("Handler is obsolete");

    return $self->print_warning($msg->maketext("Diese Funktion wird nicht mehr unterstützt"));	
}

sub renew_loans {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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
    my $scheme         = $self->stash('scheme');
    my $servername     = $self->stash('servername');

    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $database              = $sessionauthenticator;
    
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;

    if ($logger->is_info){
	$logger->info("Trying to renew loans for user $loginname ($userid) in ils for $database");
    }
    
    my $response_renew_loans_ref = $ils->renew_loans($loginname);

    if ($logger->is_debug){
	$logger->debug("Result renew loans: ".YAML::Dump($response_renew_loans_ref));
    }
    
    if ($response_renew_loans_ref->{error}){
	if ($response_renew_loans_ref->{error_description}){
	    my $reason = encode_entities($response_renew_loans_ref->{error_description});
	    $logger->error("Renew loans for user $loginname ($userid) failed: $reason");
	    return $self->print_warning($reason);
	}
	else {
	    $logger->error("Renew loans for user $loginname ($userid) failed: unknown reason");
	    return $self->print_warning($msg->maketext("Eine Gesamtkontoverlängerung durch Sie ist leider nicht möglich"));
	}
    }
    elsif ($response_renew_loans_ref->{successful}){
	$logger->info("Renew loans for user $loginname ($userid) successful");
	# TT-Data erzeugen
	my $ttdata={
	    userid        => $userid,
	    database      => $database,
	    renew_loans   => $response_renew_loans_ref,
	};
	
	return $self->print_page($config->{tt_users_circulations_renew_loans_tname},$ttdata);
	
    }
    else {
	$logger->error("Renew loans for user $userid failed: unexpected error");
	return $self->print_warning($msg->maketext("Bei der Gesamtkontoverlängerung ist ein unerwarteter Fehler aufgetreten"));
    }
}

sub renew_single_loan {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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
    my $scheme         = $self->stash('scheme');
    my $servername     = $self->stash('servername');

    # CGI Args
    my $holdingid       = ($r->param('holdingid'      ))?$r->param('holdingid'):undef; # Mediennummer
    my $loanid          = ($r->param('loanid'         ))?$r->param('loanid'):undef; # Loanid (fuer Alma)
    my $unit            = ($r->param('unit'           ) >= 0)?$r->param('unit'):0; # Zweigstelle

    $holdingid = uri_unescape($holdingid) if ($holdingid);
    
    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }

    unless (( $loanid || $holdingid ) && ($unit || $unit >= 0)){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (holdingid:$holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $database              = $sessionauthenticator;
    
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;

    if ($logger->is_info){
	$logger->info("Trying to renew single loan for user $loginname ($userid) via ils for $database with holdingid $holdingid in unit $unit");
    }
    
    my $response_renew_single_loan_ref = $ils->renew_single_loan($loginname,$holdingid,$unit,$loanid);

    if ($logger->is_debug){
	$logger->debug("Result renew loans: ".YAML::Dump($response_renew_single_loan_ref));
    }
    
    if ($response_renew_single_loan_ref->{error}){
	if ($response_renew_single_loan_ref->{error_description}){
	    my $reason = encode_entities($response_renew_single_loan_ref->{error_description});
	    $logger->error("Renew single loan for user $loginname ($userid) and holdingid $holdingid failed: $reason");

	    return $self->print_warning($reason);
	}
	else {
	    $logger->error("Renew single loan for user $loginname ($userid) and holdingid $holdingid failed: unknown reason");
	    return $self->print_warning($msg->maketext("Eine Verlängerung durch Sie ist leider nicht möglich"));
	}
    }
    elsif ($response_renew_single_loan_ref->{successful}){
	$logger->info("Renew single loan for user $loginname ($userid) and holdingid $holdingid successful");	
	# TT-Data erzeugen
	my $ttdata={
	    userid        => $userid,
	    loanid        => $loanid,
	    database      => $database,
	    renew_single_loan   => $response_renew_single_loan_ref,
	};
	
	return $self->print_page($config->{tt_users_circulations_renew_single_loan_tname},$ttdata);	
    }
    else {
	if ($logger->is_fatal){
	    $logger->fatal("Unexpected error trying to renew single loan for user $loginname ($userid) via ils for $database with holdingid $holdingid in unit $unit. Response was: ".YAML::Dump($response_renew_single_loan_ref));
	}

	return $self->print_warning($msg->maketext("Bei der Verlängerung des Mediums ist ein unerwarteter Fehler aufgetreten"));
    }
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->param('database')       || '';
    my $userid         = $self->param('userid')         || '';

    # Shared Args
    my $config         = $self->stash('config');
    my $path_prefix    = $self->stash('path_prefix');

#    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{databases_loc}/id/$database/$config->{circulations_loc}.html";
    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{circulations_loc}.html";

    # TODO GET?
    $self->res->headers->content_type('text/html');
    $self->redirect($new_location);

    return;
}

sub get_input_definition_ilsaccount {
    my $self=shift;
    
    return {
	field => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	oldpassword => {
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
	email1 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	email2 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	phone1 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	phone2 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	pin1 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	pin2 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}


1;
__END__

=head1 NAME

OpenBib::Mojo::Controller::Users::Circulation - Benutzerkontofunktionen

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
