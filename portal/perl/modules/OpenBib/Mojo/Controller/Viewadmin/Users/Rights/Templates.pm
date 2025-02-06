#####################################################################
#
#  OpenBib::Mojo::Controller::Viewadmin::Users::Rights::Templates
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Viewadmin::Users::Rights::Templates;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Schema::System;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Admin';

sub update_record {
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
    my @templates      = ($r->param('templates'))?$r->param('templates'):();

    # Acting user in View?
    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }

    # User to change in View?
    if (!$user->user_exists_in_view({ viewname => $view, userid => $userid})){
        return $self->print_authorization_error();
    }

    # Templates in View?
    @templates = $user->filter_templates_by_view({ viewname => $view, templates => \@templates});

    if (!@templates){
        return $self->print_authorization_error();
    }
    
    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $thisuserinfo_ref = {
        id        => $userid,
        templates => \@templates,
    };

    $user->update_user_rights_template($thisuserinfo_ref);

    $self->redirect("$path_prefix/$config->{viewadmin_loc}/$config->{users_loc}");
}

1;
