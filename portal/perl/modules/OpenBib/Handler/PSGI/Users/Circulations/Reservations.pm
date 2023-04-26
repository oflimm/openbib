#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::Reservations
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

package OpenBib::Handler::PSGI::Users::Circulations::Reservations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Email::Valid;
use HTML::Entities;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape qw(uri_unescape);
use JSON::XS qw/encode_json decode_json/;
use LWP::UserAgent;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::ILS::Factory;
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
        'delete_record'         => 'delete_record',
        'create_record'         => 'create_record',
        'show_collection'       => 'show_collection',
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
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    my $sessionuserid        = $user->get_userid_of_session($session->{ID});

    if (!$self->authorization_successful || $userid ne $sessionuserid){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('GET');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my $database = $sessionauthenticator;
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    if ($logger->is_debug){
	$logger->debug("Trying to get reservations for user $loginname in ils for $database");
    }
    
    my $reservations_ref = $ils->get_reservations($loginname);

    if ($logger->is_debug){
	$logger->debug("Got reservations: ".YAML::Dump($reservations_ref));
    }
    
    my $authenticator = $session->get_authenticator;

    # TT-Data erzeugen
    
    my $ttdata={
        authenticator => $authenticator,
        loginname    => $loginname,
        password     => $password,
	
        reservations => $reservations_ref,
        
        database     => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_reservations_tname},$ttdata);
}

sub create_record {
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
    
    # CGI Args
    my $authenticatorid = ($query->param('authenticatorid'))?$query->param('authenticatorid'):undef;
    # Aktive Aenderungen des Nutzerkontos
    my $validtarget     = ($query->param('validtarget'    ))?$query->param('validtarget'):undef;
    my $holdingid       = ($query->param('holdingid'      ))?$query->param('holdingid'):undef; # Mediennummer
    my $titleid         = ($query->param('titleid'        ))?$query->param('titleid'):undef; # Katkey
    my $num_holdings_in_unit = ($query->param('num_holdings_in_unit'))?$query->param('num_holdings_in_unit'):undef; # Anzahl Exemplare in dieser Zweigstelle
    
    my $pickup_location = ($query->param('pickup_location') >= 0)?$query->param('pickup_location'):undef;
    my $unit            = ($query->param('unit'           ) >= 0)?$query->param('unit'):0;
    my $storage         = ($query->param('storage'        ))?$query->param('storage'):undef;
    my $limitation      = ($query->param('limitation'     ))?$query->param('limitation'):undef;

    my $type            = ($query->param('type'           ))?$query->param('type'):'';

    $holdingid = uri_unescape($holdingid);
    
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    unless ($validtarget && $holdingid && ( $unit || $unit >= 0)){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (validtarget: $validtarget, holdingid:$holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    my $sessionuserid = $user->get_userid_of_session($session->{ID});
    
    $self->param('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful){
        $logger->debug("Authenticator: $sessionauthenticator");

        if ($self->param('representation') eq "html"){
#            return $self->tunnel_through_authenticator('POST',$authenticatorid);
            return $self->tunnel_through_authenticator('POST');
	}
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($username,$password,$access_token) = $user->get_credentials();

    my $database              = $sessionauthenticator;

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;
    
    if (!defined $pickup_location){
	$logger->debug("Checking reservation for pickup locations");
	
	my $response_check_reservation_ref = $ils->check_reservation({ username => $username, titleid => $titleid, holdingid => $holdingid, unit => $unit, storage => $storage, limitation => $limitation });

	if ($logger->is_debug){
	    $logger->debug("Result check_reservation:".YAML::Dump($response_check_reservation_ref));
	}
	
	if ($response_check_reservation_ref->{error}){
#            return $self->print_warning($response_check_reservation_ref->{error_description});
            return $self->print_warning($msg->maketext("Eine Vormerkung dieses Mediums durch Sie ist leider nicht möglich"));
	}
	elsif ($response_check_reservation_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database      => $database,
		unit          => $unit,
		storage       => $storage,
		holdingid     => $holdingid,
		titleid       => $titleid,
		limitation    => $limitation,
		validtarget   => $validtarget,
		pickup_locations => $response_check_reservation_ref->{pickup_locations},
		num_holdings_in_unit => $num_holdings_in_unit, 
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_check_reservation_tname},$ttdata);
	    
	}		
    }
    else {
	$logger->debug("Making reservation");
	
	my $response_make_reservation_ref = $ils->make_reservation({ username => $username, holdingid => $holdingid, titleid => $titleid, unit => $unit, storage => $storage, pickup_location => $pickup_location, type => $type});

	if ($logger->is_debug){
	    $logger->debug("Result make_reservation:".YAML::Dump($response_make_reservation_ref));	
	}
	
	if ($response_make_reservation_ref->{error}){
            return $self->print_warning(encode_entities($response_make_reservation_ref->{error_description}));
	}
	elsif ($response_make_reservation_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database        => $database,
		unit            => $unit,
		storage         => $storage,
		holdingid       => $holdingid,
		pickup_location => $pickup_location,
		validtarget     => $validtarget,
		reservation     => $response_make_reservation_ref,
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_make_reservation_tname},$ttdata);
	    
	}		
    }
}

sub delete_record {
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

    # CGI Args
    my $authenticatorid = ($query->param('authenticatorid'))?$query->param('authenticatorid'):undef;
    # Aktive Aenderungen des Nutzerkontos
    my $validtarget     = ($query->param('validtarget'    ))?$query->param('validtarget'):undef;
    my $requestid       = ($query->param('requestid'      ))?$query->param('requestid'):undef; # Requestid (fuer Alma)
    my $holdingid       = ($query->param('holdingid'      ))?$query->param('holdingid'):undef; # Mediennummer
    my $unit            = ($query->param('unit'           ) >= 0)?$query->param('unit'):0;

    $holdingid = uri_unescape($holdingid);
    
    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    unless ($validtarget && ( $holdingid || $requestid ) && ( $unit || $unit >= 0) ){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (validtarget: $validtarget, holdingid:$holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    my $sessionuserid        = $user->get_userid_of_session($session->{ID});
    
    $self->param('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful || $userid ne $sessionuserid){
        $logger->debug("Authenticator: $sessionauthenticator");

        if ($self->param('representation') eq "html"){
#            return $self->tunnel_through_authenticator('POST',$authenticatorid);
            return $self->tunnel_through_authenticator('POST');
	}
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($username,$password,$access_token) = $user->get_credentials();

    my $database              = $sessionauthenticator;

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;

    $logger->debug("Canceling reservation for $holdingid in unit $unit for $username");
	
    my $response_cancel_reservation_ref = $ils->cancel_reservation({ username => $username, requestid => $requestid, holdingid => $holdingid, unit => $unit });
    
    if ($logger->is_debug){
	$logger->debug("Result cancel_reservation:".YAML::Dump($response_cancel_reservation_ref));
    }
    
    if ($response_cancel_reservation_ref->{error}){
	#            return $self->print_warning($response_cancel_reservation_ref->{error_description});
	return $self->print_warning($msg->maketext("Eine Stornierung der Vormerkung für dieses Mediums durch Sie ist leider nicht möglich"));
    }
    elsif ($response_cancel_reservation_ref->{successful}){
	# TT-Data erzeugen
	my $ttdata={
	    userid        => $userid,
	    database      => $database,
	    unit          => $unit,
	    holdingid     => $holdingid,
	    requestid     => $requestid,
	    validtarget   => $validtarget,
	    cancel_reservation  => $response_cancel_reservation_ref,
	};
	
	return $self->print_page($config->{tt_users_circulations_cancel_reservation_tname},$ttdata);
	
    }
    else {
	return $self->print_warning($msg->maketext("Bei der Stornierung der Vormerkung ist ein unerwarteter Fehler aufgetreten"));
    }
    
    # return unless ($self->param('representation') eq "html");

    # my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{databases_loc}/id/$database/$config->{circulations_loc}/id/reservations.html";

    # # TODO GET?
    # $self->header_add('Content-Type' => 'text/html');
    # $self->redirect($new_location);

    return;
}

1;
__END__

=head1 NAME

OpenBib::Handler::PSGI::Users::Circulations::Reservations - Benutzerkonto: Vormerkungen

=head1 DESCRIPTION

Das Modul implementiert fuer den Benutzer des Suchportals die
Vormerkfunktionen

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
