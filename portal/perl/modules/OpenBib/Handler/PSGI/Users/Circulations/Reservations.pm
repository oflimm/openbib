#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::Reservations
#
#  Dieses File ist (C) 2004-2021 Oliver Flimm <flimm@openbib.org>
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
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape;
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
    my $database       = $self->param('database');

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

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
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
    my $database       = $self->param('database');

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

    my $type            = ($query->param('type'           ))?$query->param('type'):'';
    
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
    unless ($validtarget && $holdingid && $unit >= 0){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (validtarget: $validtarget, holdingid:$holdingid, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    my $userid = $user->get_userid_of_session($session->{ID});
    
    $self->param('userid',$userid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Db: $database - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        $logger->debug("Database: $database - Authenticator: $sessionauthenticator");

        if ($self->param('representation') eq "html"){
#            return $self->tunnel_through_authenticator('POST',$authenticatorid);
            return $self->tunnel_through_authenticator('POST');
	}
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($username,$password,$access_token) = $user->get_credentials();

    $database              = $sessionauthenticator;

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;
    
    if (!defined $pickup_location){
	$logger->debug("Checking reservation for pickup locations");
	
	my $response_check_reservation_ref = $ils->check_reservation({ username => $username, holdingid => $holdingid, unit => $unit });

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
		holdingid     => $holdingid,
		titleid       => $titleid,
		validtarget   => $validtarget,
		pickup_locations => $response_check_reservation_ref->{pickup_locations},
		num_holdings_in_unit => $num_holdings_in_unit, 
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_check_reservation_tname},$ttdata);
	    
	}		
    }
    else {
	$logger->debug("Making reservation");
	
	my $response_make_reservation_ref = $ils->make_reservation({ username => $username, holdingid => $holdingid, titleid => $titleid, unit => $unit, pickup_location => $pickup_location, type => $type});

	if ($logger->is_debug){
	    $logger->debug("Result make_reservation:".YAML::Dump($response_make_reservation_ref));	
	}
	
	if ($response_make_reservation_ref->{error}){
            return $self->print_warning($response_make_reservation_ref->{error_description});
	}
	elsif ($response_make_reservation_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database        => $database,
		unit            => $unit,
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
    my $database       = $self->param('database');
    my $branchid       = $self->param('branchid');
    my $mediaid        = $self->strip_suffix($self->param('dispatch_url_remainder'));

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
    
    # Aktive Aenderungen des Nutzerkontos

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->new;

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my $circexlist=undef;
    
    $logger->info("Zweigstelle: $branchid");
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->get($database)->{circcheckurl});
        my $result = $soap->cancel_reservation(
            SOAP::Data->name(parameter  =>\SOAP::Data->value(
                SOAP::Data->name(username     => $loginname)->type('string'),
                SOAP::Data->name(password     => $password)->type('string'),
                SOAP::Data->name(mediennummer => $mediaid)->type('string'),
                SOAP::Data->name(zweigstelle  => $branchid)->type('string'),
                SOAP::Data->name(database     => $circinfotable->get($database)->{circdb})->type('string'))));
        
        unless ($result->fault) {
            $circexlist=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    };
    
    if ($@){
        $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
    }

    return unless ($self->param('representation') eq "html");

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{databases_loc}/id/$database/$config->{circulations_loc}/id/reservations.html";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

    return;
}

1;
__END__

=head1 NAME

OpenBib::Handler::PSGI::Users::Circulations::Reservations - Vormerkungen

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
