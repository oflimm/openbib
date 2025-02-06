#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Circulations::Requests
#
#  Dieses File ist (C) 2022-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::Circulations::Requests;

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
use URI::Escape;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::ILS::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;
use JSON::XS qw/encode_json decode_json/;
use LWP::UserAgent;

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
    my $scheme         = $self->stash('scheme');
    my $servername     = $self->stash('servername');

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    my $sessionuserid        = $user->get_userid_of_session($session->{ID});

    if (!$self->authorization_successful || $userid ne $sessionuserid){
        if ($self->stash('representation') eq "html"){
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
	$logger->debug("Trying to get requests for user $loginname in ils for $database");
    }
    
    my $requests_ref = $ils->get_requests($loginname);

    if ($logger->is_debug){
	$logger->debug("Got requests: ".YAML::Dump($requests_ref));
    }

    my $authenticator = $session->get_authenticator;

    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        loginname  => $loginname,
        password   => $password,
        
        requests     => $requests_ref,

	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_requests_tname},$ttdata);
}

sub create_record {
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
    
    # Aktive Aenderungen des Nutzerkontos
    my $validtarget     = ($r->param('validtarget'    ))?$r->param('validtarget'):undef;
    my $holdingid       = ($r->param('holdingid'      ))?$r->param('holdingid'):undef; # Mediennummer
    my $pickup_location = ($r->param('pickup_location') || $r->param('pickup_location') >= 0)?$r->param('pickup_location'):undef;
    my $unit            = ($r->param('unit'           ) >= 0)?$r->param('unit'):0;
    my $storage         = ($r->param('storage'        ))?$r->param('storage'):undef;
    my $titleid         = ($r->param('titleid'        ))?$r->param('titleid'):undef;
    my $limitation      = ($r->param('limitation'     ))?$r->param('limitation'):undef;

    $holdingid = uri_unescape($holdingid) if ($holdingid);

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    unless ($validtarget && $holdingid && $unit >= 0){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (validtarget: $validtarget, holdingid:$holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    my $sessionuserid = $user->get_userid_of_session($session->{ID});
    
    $self->stash('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($username,$password,$access_token) = $user->get_credentials();
    
    my $database              = $sessionauthenticator;

    if ($logger->is_debug){
	$logger->debug("database: $database - titleid: $titleid - unit: $unit - storage: $storage - holdingid: $holdingid - validtarget: $validtarget - pickup_location: $pickup_location");
    }
    
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;
    
    if (!defined $pickup_location){
	if ($logger->is_info){
	    $logger->info("Trying to check request for pickup locations for user $username and holdingid $holdingid in unit $unit");
	}
	
	my $response_check_request_ref = $ils->check_request({ username => $username, titleid => $titleid, holdingid => $holdingid, unit => $unit, storage => $storage, limitation => $limitation});

	if ($logger->is_debug){
	    $logger->debug("Result check_request:".YAML::Dump($response_check_request_ref));
	}
	
	if ($response_check_request_ref->{error}){
	    my $reason = encode_entities($response_check_request_ref->{error_description});
	    $logger->error("Request check for pickup location failed for user $username and holdingid $holdingid: $reason");	

            return $self->print_warning($reason);
	}
	elsif ($response_check_request_ref->{successful}){
	    $logger->info("Request check for pickup location successful for user $username and holdingid $holdingid");	
	    
	    # TT-Data erzeugen
	    my $ttdata={
		database      => $database,
		unit          => $unit,
		storage       => $storage,
		titleid       => $titleid,
		holdingid     => $holdingid,
		limitation    => $limitation,
		validtarget   => $validtarget,
		pickup_locations => $response_check_request_ref->{pickup_locations},
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_check_request_tname},$ttdata);
	    
	}		
    }
    else {
	if ($logger->is_info){
	    $logger->info("Trying to make request for user $username and holdingid $holdingid in unit $unit and pickup location $pickup_location");
	}
	
	my $response_make_request_ref = $ils->make_request({ username => $username, titleid => $titleid, holdingid => $holdingid, unit => $unit, storage => $storage, pickup_location => $pickup_location});

	if ($logger->is_debug){
	    $logger->debug("Result make_request:".YAML::Dump($response_make_request_ref));	
	}
	
	if ($response_make_request_ref->{error}){
	    my $reason = encode_entities($response_make_request_ref->{error_description});
	    $logger->error("Making request failed for user $username and holdingid $holdingid: $reason");	

            return $self->print_warning($reason);
	}
	elsif ($response_make_request_ref->{successful}){
	    $logger->info("Make request successful for user $username and holdingid $holdingid in pickup location $pickup_location");	
	    
	    # TT-Data erzeugen
	    my $ttdata={
		database        => $database,
		unit            => $unit,
		storage         => $storage,
		holdingid       => $holdingid,
		pickup_location => $pickup_location,
		validtarget     => $validtarget,
		request           => $response_make_request_ref,
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_make_request_tname},$ttdata);
	    
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
    my $authenticatorid = ($r->param('authenticatorid'))?$r->param('authenticatorid'):undef;
    # Aktive Aenderungen des Nutzerkontos
    my $validtarget     = ($r->param('validtarget'    ))?$r->param('validtarget'):undef;
    my $holdingid       = ($r->param('holdingid'      ))?$r->param('holdingid'):undef; # Mediennummer
    my $requestid       = ($r->param('requestid'      ))?$r->param('requestid'):''; # Requestid (fuer Alma)
    my $unit            = ($r->param('unit'           ) >= 0)?$r->param('unit'):0;
    my $unitname        = ($r->param('unitname'       ))?$r->param('unitname'):undef;
    my $titleid         = ($r->param('titleid'        ))?$r->param('titleid'):undef;
    my $title           = ($r->param('title'          ))?$r->param('title'):undef;
    my $author          = ($r->param('author'         ))?$r->param('author'):undef;
    my $date            = ($r->param('date'           ))?$r->param('date'):undef;
    my $receipt         = ($r->param('receipt'        ))?$r->param('receipt'):undef;
    my $remark          = ($r->param('remark'         ))?$r->param('remark'):undef;

    $unitname  = uri_unescape($unitname) if ($unitname);    
    $title     = uri_unescape($title) if ($title);    
    $holdingid = uri_unescape($holdingid) if ($holdingid);
    
    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    unless ($validtarget && ($holdingid || $requestid ) && $unit >= 0){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (validtarget: $validtarget, requestid: $requestid, holdingid: $holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    my $sessionuserid = $user->get_userid_of_session($session->{ID});
    
    $self->stash('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful){
        $logger->debug("Authenticator: $sessionauthenticator");

        if ($self->stash('representation') eq "html"){
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
    
    my $userinfo_ref = $ils->get_userdata($username);

    my $username_full = $userinfo_ref->{fullname} || 'Kein Name vorhanden';
    my $email         = $userinfo_ref->{email};

    if ($logger->is_info){
	$logger->info("Trying to cancel request for user $username ($sessionuserid) with holdingid $holdingid / requestid $requestid in unit $unit");
    }
    
    if ($receipt && !$email){
	my $reason = $msg->maketext("Es existiert keine E-Mail-Addresse für eine Kopie der Stornierungs-Mail an Sie.");
	$logger->error("Cancel request failed for user $username ($sessionuserid) and holdingid $holdingid / requestid  $requestid: $reason");	
	
	return $self->print_warning($reason);
    }

    # Stornierungsgrund nicht als wichtig erachtet
    # if (!$remark){
    # 	my $reason = $msg->maketext("Bitte geben Sie einen Stornierungsgrund an.");
    # 	$logger->error("Cancel request failed for user $username ($sessionuserid) and holdingid $holdingid / requestid  $requestid: $reason");	
	
    # 	return $self->print_warning($reason);
    # }
    
    my $response_cancel_request_ref = $ils->cancel_request({ title => $title, author => $author, requestid => $requestid, holdingid => $holdingid, unit => $unit, unitname => $unitname, date => $date, username => $username, username_full => $username_full, email => $email, remark => $remark, receipt => $receipt });
    
    if ($logger->is_debug){
	$logger->debug("Result cancel_request:".YAML::Dump($response_cancel_request_ref));
    }
    
    if ($response_cancel_request_ref->{error}){
	if (defined $response_cancel_request_ref->{error_description}){
	    my $reason = encode_entities($response_cancel_request_ref->{error_description});
	    $logger->error("Cancel request failed for user $username ($sessionuserid) and holdingid $holdingid / requestid  $requestid: $reason");	

	    return $self->print_warning($reason);
	}
	else {
	    $logger->error("Cancel request failed for user $username ($sessionuserid) and holdingid $holdingid / requestid  $requestid: unknown reason");	
	    
	    return $self->print_warning($msg->maketext("Eine Stornierung der Bestellung für dieses Medium durch Sie ist leider nicht möglich"));
	}
    }
    elsif ($response_cancel_request_ref->{successful}){

	$logger->info("Cancel request successful for user $username ($sessionuserid) and holdingid $holdingid / requestid  $requestid");	

	# TT-Data erzeugen
	my $ttdata = {
	    userid        => $userid,
	    database      => $database,
	    unit          => $unit,
	    requestid     => $requestid,
	    holdingid     => $holdingid,
	    validtarget   => $validtarget,
	    cancel_request  => $response_cancel_request_ref,
	};
	
	return $self->print_page($config->{tt_users_circulations_cancel_request_tname},$ttdata);
	
    }
    else {
	$logger->error("Cancel request failed for user $username ($sessionuserid) and holdingid $holdingid / requestid  $requestid: unexpected error");		
	return $self->print_warning($msg->maketext("Bei der Stornierung der Vormerkung ist ein unerwarteter Fehler aufgetreten"));
    }
    
    # return unless ($self->stash('representation') eq "html");

    # my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{databases_loc}/id/$database/$config->{circulations_loc}/id/requests.html";

    # # TODO GET?
    # $self->header_add('Content-Type' => 'text/html');
    # $self->redirect($new_location);

    return;
}

sub confirm_delete_record {
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

    # CGI Args
    my $authenticatorid = ($r->param('authenticatorid'))?$r->param('authenticatorid'):undef;
    # Aktive Aenderungen des Nutzerkontos
    my $validtarget     = ($r->param('validtarget'    ))?$r->param('validtarget'):undef;
    my $holdingid       = ($r->param('holdingid'      ))?$r->param('holdingid'):undef; # Mediennummer
    my $requestid       = ($r->param('requestid'      ))?$r->param('requestid'):undef; # Requestid (fuer Alma)
    my $titleid         = ($r->param('titleid'        ))?$r->param('titleid'):undef; # Katkey
    my $date            = ($r->param('date'           ))?$r->param('date'):''; # Bestelldatum
    my $unitname        = ($r->param('unitname'       ))?$r->param('unitname'):''; 
    my $unit            = ($r->param('unit'           ) >= 0)?$r->param('unit'):0;

    $unitname  = uri_unescape($unitname) if ($unitname);    
    $holdingid = uri_unescape($holdingid) if ($holdingid);
    
    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    unless ($validtarget && $titleid && ( $holdingid || $requestid) && $unit >= 0){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (validtarget: $validtarget, holdingid:$holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    my $sessionuserid = $user->get_userid_of_session($session->{ID});
    
    $self->stash('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful || $userid ne $sessionuserid){
        $logger->debug("Authenticator: $sessionauthenticator");

        if ($self->stash('representation') eq "html"){
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
    
    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    
    $record->load_full_record;

    my $userinfo_ref = $ils->get_userdata($username);
    
    my $ttdata={
	database  => $database,
	userinfo  => $userinfo_ref,
	record    => $record,
	unit      => $unit,
	unitname  => $unitname,
	holdingid => $holdingid,
	requestid => $requestid,
	date      => $date,
        userid    => $userid,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_users_circulations_cancel_request_confirm_tname},$ttdata);
}

1;
__END__

=head1 NAME

OpenBib::Mojo::Controller::Users::Circultation::Requests - Benutzerkonto: Auftraege (Bestellungen und Vormerkungen)

=head1 DESCRIPTION

Das Modul implementiert fuer den Benutzer des Suchportals die Anzeige von Auftraegen

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
