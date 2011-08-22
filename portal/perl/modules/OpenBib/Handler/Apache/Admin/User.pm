#####################################################################
#
#  OpenBib::Handler::Apache::Admin::User
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin::User;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
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
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use CGI::Application::Plugin::Redirect;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_search'               => 'show_search',
        'show_search_form'          => 'show_search_form',
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

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->is_authenticated('admin')){
        return;
    }

    # TT-Data erzeugen
    my $ttdata={
    };
    
    $self->print_page($config->{tt_admin_user_tname},$ttdata);

}


sub show_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->is_authenticated('admin')){
        return;
    }
    
    # TT-Data erzeugen
    my $ttdata={
    };
    
    $self->print_page($config->{tt_admin_user_search_form_tname},$ttdata);

}

sub show_search {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    # Dispatched Args
    my $view           = $self->param('view')                   || '';


    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $user           = $self->param('user');

    # CGI Args
    my $args_ref = {};
    $args_ref->{roleid}     = $query->param('roleid') if ($query->param('roleid'));
    $args_ref->{username}   = $query->param('username') if ($query->param('username'));
    $args_ref->{surname}    = $query->param('surname') if ($query->param('surname'));
    $args_ref->{commonname} = $query->param('commonname') if ($query->param('commonname'));
    
    if (!$self->is_authenticated('admin')){
        return;
    }

    if (!$args_ref->{roleid} && !$args_ref->{username} && !$args_ref->{surname} && !$args_ref->{commonname}){
        $self->print_warning($msg->maketext("Bitte geben Sie einen Suchbegriff ein."));
        return Apache2::Const::OK;
    }

    my $userlist_ref = $user->search($args_ref);;

    # TT-Data erzeugen
    my $ttdata={
        userlist   => $userlist_ref,
    };
    
    $self->print_page($config->{tt_admin_user_search_tname},$ttdata);
}
    
1;
