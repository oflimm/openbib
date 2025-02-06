####################################################################
#
#  OpenBib::Mojo::Controller::Viewadmin
#
#  Dieses File ist (C) 2004-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Viewadmin;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Email::Valid;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Admin';

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');    

    if (!$user->is_viewadmin($view)){
        return $self->print_authorization_error();
    }

    my $ttdata={
    };
    
    return $self->print_page($config->{tt_viewadmin_tname},$ttdata);
}

# Authentifizierung wird spezialisiert

sub authorization_successful {
    my $self           = shift;
    my $required_right = shift; # right_create, right_read, right_update, right_delete
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $view               = $self->stash('view')               || '';
    my $scope              = $self->stash('scope')              || '';
    my $basic_auth_failure = $self->stash('basic_auth_failure') || 0;
    my $user               = $self->stash('user');
    my $userid             = $self->stash('userid')             || $user->{ID} || '';

    my $user_has_required_right = 0;

    # Wird ein zum Zugriff erforderliches Recht uebergeben, dann muessen die Berechtigungen in den Rollen des Nutzers ueberprueft
    # werden. Hierbei werden etwaige Beschraenkungen auf Views beruecksichtigt.
    if (defined $required_right){
        if ($scope && $userid && $self->is_authenticated('user',$userid)){
            if ($user->allowed_for_view($view)){
                $user_has_required_right = $user->has_right({ scope => $scope, right => $required_right });
            }
        }
    }
    $logger->debug("Basic http auth failure: $basic_auth_failure");

    if ($self->is_authenticated('admin') || $user_has_required_right){
        return 1;
    }
    
#     if (($basic_auth_failure && !$user->is_admin) || !$self->is_authenticated('admin')){
#         return 0;
#     }

    return 0;
}

1;
