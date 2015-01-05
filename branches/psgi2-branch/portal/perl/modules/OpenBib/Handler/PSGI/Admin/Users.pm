#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Users
#
#  Dieses File ist (C) 2004-2014 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Admin::Users;

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
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Admin';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_record_form'          => 'show_record_form',
        'show_search'               => 'show_search',
        'show_search_form'          => 'show_search_form',
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

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # TT-Data erzeugen
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_admin_users_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';
    my $userid         = $self->param('userid')                 || '';

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

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;
        
    my $ttdata={
        userinfo   => $userinfo,
    };
    
    return $self->print_page($config->{tt_admin_users_record_edit_tname},$ttdata);
}

sub show_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    # TT-Data erzeugen
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_admin_users_search_form_tname},$ttdata);
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
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$args_ref->{roleid} && !$args_ref->{username} && !$args_ref->{surname} && !$args_ref->{commonname}){
        return $self->print_warning($msg->maketext("Bitte geben Sie einen Suchbegriff ein."));
    }

    my $userlist_ref = $user->search($args_ref);;

    # TT-Data erzeugen
    my $ttdata={
        userlist   => $userlist_ref,
    };
    
    return $self->print_page($config->{tt_admin_users_search_tname},$ttdata);
}
    
1;
