#####################################################################
#
#  OpenBib::Handler::Apache::Users::Circulations::Reservations
#
#  Dieses File ist (C) 2004-2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Users::Circulations::Reservations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest ();
use Apache2::URI ();
use APR::URI ();
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
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache::Users';

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

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
            return Apache2::Const::OK;
        }
    }
    
    my ($loginname,$password) = $user->get_credentials();
    #my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    my $circexlist=undef;
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->get_reservations(
            SOAP::Data->name(parameter  =>\SOAP::Data->value(
                SOAP::Data->name(username => $loginname)->type('string'),
                SOAP::Data->name(password => $password)->type('string'),
                SOAP::Data->name(database => $circinfotable->{$database}{circdb})->type('string'))));
        
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

    # TT-Data erzeugen
    
    my $ttdata={
        loginname    => $loginname,
        password     => $password,
        
        reservations => $circexlist,
        
        database     => $database,
        
        show_corporate_banner => 0,
        show_foot_banner      => 1,
    };
    
    $self->print_page($config->{tt_users_circulations_reservations_tname},$ttdata);

    return Apache2::Const::OK;    
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
    my $mediennummer    = ($query->param('mediaid'        ))?$query->param('mediaid'):undef;
    my $ausgabeort      = ($query->param('pickup'       ))?$query->param('pickup'):0;
    my $zweigstelle     = ($query->param('branchid'        ))?$query->param('branchid'):0;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        $logger->debug("Database: $database - Authenticator: $sessionauthenticator");

        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST',$authenticatorid);            
        }
        else  {
            $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
            return Apache2::Const::OK;
        }
    }
    
    my $circexlist=undef;
    
    $logger->info("Zweigstelle: $zweigstelle");
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->make_reservation(
            SOAP::Data->name(parameter  =>\SOAP::Data->value(
                SOAP::Data->name(username     => $loginname)->type('string'),
                SOAP::Data->name(password     => $password)->type('string'),
                SOAP::Data->name(mediennummer => $mediennummer)->type('string'),
                SOAP::Data->name(ausgabeort   => $ausgabeort)->type('string'),
                SOAP::Data->name(zweigstelle  => $zweigstelle)->type('string'),
                SOAP::Data->name(database     => $circinfotable->{$database}{circdb})->type('string'))));
        
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
    
    # TT-Data erzeugen
    my $ttdata={
        result     => $circexlist,
    };
    
    $self->print_page($config->{tt_users_circulations_make_reservation_tname},$ttdata);

    return Apache2::Const::OK;        
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

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
            return Apache2::Const::OK;
        }
    }

    my $circexlist=undef;
    
    $logger->info("Zweigstelle: $branchid");
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->cancel_reservation(
            SOAP::Data->name(parameter  =>\SOAP::Data->value(
                SOAP::Data->name(username     => $loginname)->type('string'),
                SOAP::Data->name(password     => $password)->type('string'),
                SOAP::Data->name(mediennummer => $mediaid)->type('string'),
                SOAP::Data->name(zweigstelle  => $branchid)->type('string'),
                SOAP::Data->name(database     => $circinfotable->{$database}{circdb})->type('string'))));
        
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
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{databases_loc}/id/$database/$config->{circulations_loc}/id/reservations.html");
    $self->query->status(Apache2::Const::REDIRECT);

    return Apache2::Const::OK;
}

1;
__END__

=head1 NAME

OpenBib::Handler::Apache::Users::Circulations::Reservations - Vormerkungen

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
