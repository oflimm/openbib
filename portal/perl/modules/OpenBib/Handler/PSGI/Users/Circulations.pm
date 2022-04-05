#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations
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

package OpenBib::Handler::PSGI::Users::Circulations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Email::Valid;
use DBI;
use Digest::MD5;
use Email::Valid;
use Encode qw/decode_utf8 encode_utf8/;
use HTML::Entities;
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

use base 'OpenBib::Handler::PSGI::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_record'           => 'show_record',
        'renew_loans'           => 'renew_loans',
        'renew_single_loan'     => 'renew_single_loan',
        'show_collection'       => 'show_collection',
        'update_ilsaccount'     => 'update_ilsaccount',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();



    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
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
    my $input_data_ref = $self->parse_valid_input('get_input_definition_ilsaccount');

    my $field          = $input_data_ref->{field};
    
    my $oldpassword    = $input_data_ref->{oldpassword};
    my $password1      = $input_data_ref->{password1};
    my $password2      = $input_data_ref->{password2};
    my $email1         = $input_data_ref->{email1};
    my $email2         = $input_data_ref->{email2};
    my $phone1         = $input_data_ref->{phone1};
    my $phone2         = $input_data_ref->{phone2};

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
        if ($self->param('representation') eq "html"){
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
	elsif ($password1 ne $password2){
	    my $code   = -1;
	    my $reason = $msg->maketext("Die beiden neuen Passwörter, die Sie eingegeben haben, stimmen nicht überein.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	elsif (length(decode_utf8($oldpassword)) != 6 ){
	    my $code   = -1;
	    my $reason = $msg->maketext("Ihr neues Passwort muss 6-stellig sein.");
	    
	    return $self->print_warning($msg->maketext($reason),$code,"$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}");
	}
	elsif ($password1 !~ /^[a-zA-Z0-9]+$/ or $password1 !~ /[0-9]/ or $password1 !~ /[a-zA-Z]/){
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
    
    
    if ($self->param('representation') eq "html"){
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
    my $msg            = $self->param('msg');

    $logger->errog("Handler is obsolete");

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
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');

    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful){
        if ($self->param('representation') eq "html"){
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
	$logger->debug("Trying to renew loans for user $loginname in ils for $database");
    }
    
    my $response_renew_loans_ref = $ils->renew_loans($loginname);

    if ($logger->is_debug){
	$logger->debug("Result renew loans: ".YAML::Dump($response_renew_loans_ref));
    }
    
    if ($response_renew_loans_ref->{error}){
	if ($response_renew_loans_ref->{error_description}){
	    return $self->print_warning(encode_entities($response_renew_loans_ref->{error_description}));
	}
	else {
	    return $self->print_warning($msg->maketext("Eine Gesamtkontoverlängerung durch Sie ist leider nicht möglich"));
	}
    }
    elsif ($response_renew_loans_ref->{successful}){
	# TT-Data erzeugen
	my $ttdata={
	    userid        => $userid,
	    database      => $database,
	    renew_loans   => $response_renew_loans_ref,
	};
	
	return $self->print_page($config->{tt_users_circulations_renew_loans_tname},$ttdata);
	
    }
    else {
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
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');

    # CGI Args
    my $holdingid       = ($query->param('holdingid'      ))?$query->param('holdingid'):undef; # Mediennummer
    my $unit            = ($query->param('unit'           ) >= 0)?$query->param('unit'):0; # Zweigstelle

    $holdingid = uri_unescape($holdingid);
    
    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }

    unless ($holdingid && $unit >= 0){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (holdingid:$holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful){
        if ($self->param('representation') eq "html"){
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
	$logger->debug("Trying to renew single loan for user $loginname via ils for $database with holdingid $holdingid in unit $unit");
    }
    
    my $response_renew_single_loan_ref = $ils->renew_single_loan($loginname,$holdingid,$unit);

    if ($logger->is_debug){
	$logger->debug("Result renew loans: ".YAML::Dump($response_renew_single_loan_ref));
    }
    
    if ($response_renew_single_loan_ref->{error}){
	if ($response_renew_single_loan_ref->{error_description}){
	    return $self->print_warning(encode_entities($response_renew_single_loan_ref->{error_description}));
	}
	else {
	    return $msg->maketext("Eine Verlängerung durch Sie ist leider nicht möglich");
	}
    }
    elsif ($response_renew_single_loan_ref->{successful}){
	# TT-Data erzeugen
	my $ttdata={
	    userid        => $userid,
	    database      => $database,
	    renew_single_loan   => $response_renew_single_loan_ref,
	};
	
	return $self->print_page($config->{tt_users_circulations_renew_single_loan_tname},$ttdata);
	
    }
    else {
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
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

#    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{databases_loc}/id/$database/$config->{circulations_loc}.html";
    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{circulations_loc}.html";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
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
    };
}


1;
__END__

=head1 NAME

OpenBib::Handler::PSGI::Users::Circulation - Benutzerkontofunktionen

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
