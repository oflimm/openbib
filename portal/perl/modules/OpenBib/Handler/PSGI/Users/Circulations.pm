#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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
use URI::Escape;

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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
    };
    
    return $self->print_page($config->{tt_users_collections_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $circulationid  = $self->strip_suffix($self->param('circulationid')) || 'borrows';
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
    my $validtarget        = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    if    ($circulationid eq "reservations"){
        $self->show_reservations;
    }
    elsif ($circulationid eq "reminders"){
        $self->show_reminders;
    }
    elsif ($circulationid eq "orders"){
        $self->show_orders;
    }
    elsif ($circulationid eq "borrows"){
        $self->show_borrows;
    }

    return;

}

sub show_reservations {
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
    
    # CGI Args
    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    # Aktive Aenderungen des Nutzerkontos
    my $validtarget   = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $mediennummer  = ($query->param('mnr'        ))?$query->param('mnr'):undef;
    my $ausgabeort    = ($query->param('aort'       ))?$query->param('aort'):0;
    my $zweigstelle   = ($query->param('zst'        ))?$query->param('zst'):0;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
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

    my $authenticator=$session->get_authenticator;

    # TT-Data erzeugen
    
    my $ttdata={
        authenticator => $authenticator,
        loginname    => $loginname,
        password     => $password,
        
        reservations => $circexlist,
        
        database     => $database,
        
        show_corporate_banner => 0,
        show_foot_banner      => 1,
    };
    
    return $self->print_page($config->{tt_users_circulations_reservations_tname},$ttdata);
}

sub show_reminders {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $circulationid  = $self->strip_suffix($self->param('circulationid'))           || 'borrows';

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
    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    # Aktive Aenderungen des Nutzerkontos
    my $validtarget   = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $mediennummer  = ($query->param('mnr'        ))?$query->param('mnr'):undef;
    my $ausgabeort    = ($query->param('aort'       ))?$query->param('aort'):0;
    my $zweigstelle   = ($query->param('zst'        ))?$query->param('zst'):0;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    my $circexlist=undef;
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->get_reminders(
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

    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    
    my $ttdata={
        authenticator => $authenticator,
        loginname  => $loginname,
        password   => $password,
        
        reminders  => $circexlist,
        
        show_corporate_banner => 0,
        show_foot_banner      => 1,
    };
      
    return $self->print_page($config->{tt_users_circulations_reminders_tname},$ttdata);
}

sub show_orders {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $circulationid  = $self->strip_suffix($self->param('circulationid'))           || 'borrows';

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
    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    # Aktive Aenderungen des Nutzerkontos
    my $validtarget   = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $mediennummer  = ($query->param('mnr'        ))?$query->param('mnr'):undef;
    my $ausgabeort    = ($query->param('aort'       ))?$query->param('aort'):0;
    my $zweigstelle   = ($query->param('zst'        ))?$query->param('zst'):0;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    my $circexlist=undef;
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->get_orders(
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

    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        loginname  => $loginname,
        password   => $password,
        
        orders     => $circexlist,
        
        show_corporate_banner => 0,
        show_foot_banner      => 1,
    };
    
    return $self->print_page($config->{tt_users_circulations_orders_tname},$ttdata);
}

sub show_borrows {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $circulationid  = $self->strip_suffix($self->param('circulationid'))           || 'borrows';

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
    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    # Aktive Aenderungen des Nutzerkontos
    my $validtarget   = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $mediennummer  = ($query->param('mnr'        ))?$query->param('mnr'):undef;
    my $ausgabeort    = ($query->param('aort'       ))?$query->param('aort'):0;
    my $zweigstelle   = ($query->param('zst'        ))?$query->param('zst'):0;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    my $circexlist=undef;
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->get_borrows(
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

    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        loginname  => $loginname,
        password   => $password,
        
        borrows    => $circexlist,
        
        database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_borrows_tname},$ttdata);
}

sub make_reservation {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $circulationid  = $self->strip_suffix($self->param('circulationid'))           || 'borrows';

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
    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    # Aktive Aenderungen des Nutzerkontos
    my $validtarget   = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $mediennummer  = ($query->param('mnr'        ))?$query->param('mnr'):undef;
    my $ausgabeort    = ($query->param('aort'       ))?$query->param('aort'):0;
    my $zweigstelle   = ($query->param('zst'        ))?$query->param('zst'):0;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    if (! $user->{ID}){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else {
            return $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
        }   
    }
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
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

    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        result     => $circexlist,
    };
    
    return $self->print_page($config->{tt_users_circulations_make_reservation_tname},$ttdata);
}


sub cancel_reservation {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $branchid       = $self->param('branchid');
    my $mediaid        = $self->strip_suffix($self->param('mediaid'));

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
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
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

    my $new_location = "$config->{base_loc}/$view/$config->{circulation_loc}?action=showcirc;circaction=reservations";

    # TODO internal redirect
    $self->redirect($new_location);
    
    return;
}

sub make_order {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $circulationid  = $self->strip_suffix($self->param('circulationid'))           || 'borrows';
    
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
    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    # Aktive Aenderungen des Nutzerkontos
    my $validtarget   = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $mediennummer  = ($query->param('mnr'        ))?$query->param('mnr'):undef;
    my $ausgabeort    = ($query->param('aort'       ))?$query->param('aort'):0;
    my $zweigstelle   = ($query->param('zst'        ))?$query->param('zst'):0;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    unless($sessionauthenticator eq $validtarget){
        # Aufruf-URL
        my $return_uri = uri_escape($r->request_uri);

        # TODO internal redirect
        $self->redirect($return_uri);

        return;
    }
    
    my $circexlist=undef;
    
    $logger->info("Zweigstelle: $zweigstelle");
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->make_order(
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

    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        result     => $circexlist,
    };
    
    return $self->print_page($config->{tt_users_circulations_make_order_tname},$ttdata);
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
    
    # CGI Args
    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    
    my ($loginname,$password) = $user->get_credentials();
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    my $circexlist=undef;
    
    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Circulation")
                -> proxy($circinfotable->{$database}{circcheckurl});
        my $result = $soap->renew_loans(
            SOAP::Data->name(parameter  =>\SOAP::Data->value(
                SOAP::Data->name(username     => $loginname)->type('string'),
                SOAP::Data->name(password     => $password)->type('string'),
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

    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        result     => $circexlist,
    };
    
    return $self->print_page($config->{tt_users_circulations_renew_loans_tname},$ttdata);
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
