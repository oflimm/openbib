#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Circulations::Fees
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

package OpenBib::Mojo::Controller::Users::Circulations::Fees;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use URI;

use DBI;
use Digest::MD5;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use JSON::XS qw/encode_json decode_json/;
use URI::Escape;
use LWP::UserAgent;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::ILS::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;
use OpenBib::Record::Title;

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
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $database = $sessionauthenticator;

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    if ($logger->is_debug){
	$logger->debug("Trying to get fees for user $loginname in ils for $database");
    }
    
    my $fees_ref = $ils->get_fees($loginname);

    if ($logger->is_debug){
	$logger->debug("Got fees: ".YAML::Dump($fees_ref));
    }
    
    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    
    my $ttdata={
        authenticator => $authenticator,
        loginname     => $loginname,
        password      => $password,
	
        fees          => $fees_ref,

        database      => $database,        
    };
      
    return $self->print_page($config->{tt_users_circulations_fees_tname},$ttdata);
}


1;
__END__

=head1 NAME

OpenBib::Mojo::Controller::Users::Circulations::Reminders - Ueberfaellige Medie/Gebuehren(Fernleihe)

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
