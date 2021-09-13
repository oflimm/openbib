#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::Orders
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

package OpenBib::Handler::PSGI::Users::Circulations::Orders;

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

use base 'OpenBib::Handler::PSGI::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
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
	$logger->debug("Trying to get orders for user $loginname in ils for $database");
    }
    
    my $orders_ref = $ils->get_orders($loginname);

    if ($logger->is_debug){
	$logger->debug("Got orders: ".YAML::Dump($orders_ref));
    }
    
    my $authenticator = $session->get_authenticator;

    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        loginname  => $loginname,
        password   => $password,
        
        orders     => $orders_ref,

	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_orders_tname},$ttdata);
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
    
    # Aktive Aenderungen des Nutzerkontos
    my $validtarget     = ($query->param('validtarget'    ))?$query->param('validtarget'):undef;
    my $holdingid       = ($query->param('holdingid'      ))?$query->param('holdingid'):undef; # Mediennummer
    my $pickup_location = ($query->param('pickup_location') >= 0)?$query->param('pickup_location'):undef;
    my $unit            = ($query->param('unit'           ) >= 0)?$query->param('unit'):0;

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
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($username,$password,$access_token) = $user->get_credentials();
    
    $database              = $user->get_targetdb_of_session($session->{ID});

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;
    
    if (!defined $pickup_location){
	$logger->debug("Checking order for pickup locations");
	
	my $response_check_order_ref = $ils->check_order({ username => $username, holdingid => $holdingid, unit => $unit});

	if ($logger->is_debug){
	    $logger->debug("Result check_order:".YAML::Dump($response_check_order_ref));
	}
	
	if ($response_check_order_ref->{error}){
            return $self->print_warning($response_check_order_ref->{error_description});
	}
	elsif ($response_check_order_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database      => $database,
		unit          => $unit,
		holdingid     => $holdingid,
		validtarget   => $validtarget,
		pickup_locations => $response_check_order_ref->{pickup_locations},
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_check_order_tname},$ttdata);
	    
	}		
    }
    else {
	$logger->debug("Making order");
	
	my $response_make_order_ref = $ils->make_order({ username => $username, holdingid => $holdingid, unit => $unit, pickup_location => $pickup_location});

	if ($logger->is_debug){
	    $logger->debug("Result make_order:".YAML::Dump($response_make_order_ref));	
	}
	
	if ($response_make_order_ref->{error}){
            return $self->print_warning($response_make_order_ref->{error_description});
	}
	elsif ($response_make_order_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database      => $database,
		unit          => $unit,
		holdingid     => $holdingid,
		pickup_location => $pickup_location,
		validtarget   => $validtarget,
		order         => $response_make_order_ref,
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_make_order_tname},$ttdata);
	    
	}		
    }
}


1;
__END__

=head1 NAME

OpenBib::Circulation - Benutzerkonto

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
