####################################################################
#
#  OpenBib::Handler::PSGI::Extensions::FidPhil::Users
#
#  Dieses File ist (C) 2004-2020 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Extensions::FidPhil::Users;

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
use OpenBib::Extensions::FidPhil::User;

# Doi we really need to inherit from Admin Users - Base PSGI should be enough???
use base 'OpenBib::Handler::PSGI::Admin::Users';

# Run at startup
sub setup {
	my $self = shift;
	$self->start_mode('show_collection');
	$self->run_modes(
		'show_collection'            => 'show_collection',
		'dispatch_to_representation' => 'dispatch_to_representation',
		);
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    my $view           = $self->param('view');
    my $user           = $self->param('user');
    my $session        = $self->param('session');
    # Shared Args
    my $config         = $self->param('config');
    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }
    $user         = OpenBib::Extensions::FidPhil::User->new({sessionID => $session->{ID}, config => $config});
    my $args_ref = {};
    #benoetigt wird eine ID
    $args_ref->{view} = 2;
    my $userlist_ref = $user->showUsersForView($args_ref);
    # TT-Data erzeugen
    my $ttdata={
        userlist   => $userlist_ref,
    };
    # return $self->print_page("$config->{tt_manager_users_tname}",$ttdata);
    return $self->print_page("manager_users",$ttdata);
}

#    return $self->print_page($config->{tt_admin_users_search_tname},$ttdata);

1;
