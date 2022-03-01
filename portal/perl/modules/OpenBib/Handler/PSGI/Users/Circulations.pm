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

use DBI;
use Digest::MD5;
use Email::Valid;
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



    # Dispatched Ards
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

    $logger->debug("Loginname: $loginname");

    my $account_ref = $ils->get_accountinfo($loginname);
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
#        items      => $items_ref,
#        fees       => $fees_ref,

	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_tname},$ttdata);
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

    # Aktive Aenderungen des Nutzerkontos

    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellunge, Vormerkungen, usw.) sind aktuell systemweit deaktiviert."));	
    }
    
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

    $database              = $sessionauthenticator;
    
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
	return $self->print_warning($msg->maketext("Eine Gesamtkontoverlängerung durch Sie ist leider nicht möglich"));
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

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    $database              = $sessionauthenticator;
    
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
	    return $self->print_warning($response_renew_single_loan_ref->{error_description});
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
