#####################################################################
#
#  OpenBib::Handler::PSGI::Users::CartItems
#
#  Dieses File ist (C) 2001-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::CartItems;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::CartItems';

# Authentifizierung wird spezialisiert

sub authorization_successful {
    my $self   = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $basic_auth_failure = $self->param('basic_auth_failure') || 0;
    my $userid             = $self->param('userid')             || '';

    $logger->debug("Basic http auth failure: $basic_auth_failure / Userid: $userid ");

    if ($basic_auth_failure || ($userid && !$self->is_authenticated('user',$userid))){
        return 0;
    }

    return 1;
}

sub update_item_in_collection {
    my $self = shift;
    my $input_data_ref = shift;

    my $userid  = $self->param('userid')                      || '';
    my $user    = $self->param('user');

    if ($userid && $userid == $user->{ID}) {
        return $user->update_item_in_collection($input_data_ref);
    }

    return;
}

sub add_item_to_collection {
    my $self = shift;
    my $input_data_ref = shift;

    my $userid  = $self->param('userid')                      || '';

    my $user = $self->param('user');

    if ($userid && $userid == $user->{ID}) {
        return $user->add_item_to_collection($input_data_ref);
    }
    
    return;
}

sub delete_item_from_collection {
    my $self = shift;
    my $id   = shift;

    my $userid  = $self->param('userid')                      || '';

    my $user = $self->param('user');

    if ($userid && $userid == $user->{ID}) {
        return $user->delete_item_from_collection({
            id       => $id,
        });
    }
    
    return;
}

sub get_number_of_items_in_collection {
    my $self = shift;

    my $user = $self->param('user');
    my $view = $self->param('view');
    
    return $user->get_number_of_items_in_collection({view => $view});
}

sub get_single_item_in_collection {
    my $self = shift;
    my $listid = shift;

    my $user = $self->param('user');

    return $user->get_single_item_in_collection($listid);
}

sub get_items_in_collection {
    my $self = shift;

    my $user         = $self->param('user');
    my $view         = $self->param('view');
    my $queryoptions = $self->param('qopts');
    
    return $user->get_items_in_collection({view => $view, queryoptions => $queryoptions });
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $user           = $self->param('user')           || '';
    my $path_prefix    = $self->param('path_prefix');
    my $lang           = $self->param('lang');
    my $config         = $self->param('config');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{cartitems_loc}.html?l=$lang";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

    return;
}

1;
