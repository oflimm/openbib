#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Views::RSS
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

package OpenBib::Mojo::Controller::Admin::Views::RSS;

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
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Admin';

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $viewname       = $self->param('viewid');

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

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    if (!$config->view_exists($viewname)) {
        return $self->print_warning($msg->maketext("Es existiert kein View unter diesem Namen"));
    }

    my $viewinfo    = $config->get_viewinfo->search({ viewname => $viewname })->single();

    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    my $viewrssfeed_ref  = $config->get_rssfeeds_of_view($viewname);

    my $ttdata={
        viewinfo     => $viewinfo,

        allrssfeeds  => $all_rssfeeds_ref,
        viewrssfeed  => $viewrssfeed_ref,

    };
    
    return $self->print_page($config->{tt_admin_views_rss_record_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $viewname       = $self->param('viewid');

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

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    if (!$config->view_exists($viewname)) {
        return $self->print_warning($msg->maketext("Es existiert kein View unter diesem Namen"));
    }

    my $viewinfo    = $config->get_viewinfo->search({ viewname => $viewname })->single();

    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    my $viewrssfeed_ref  = $config->get_rssfeeds_of_view($viewname);

    my $ttdata={
        viewinfo     => $viewinfo,

        allrssfeeds  => $all_rssfeeds_ref,
        viewrssfeed  => $viewrssfeed_ref,

    };

    return $self->print_page($config->{tt_admin_views_rss_record_edit_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $viewid      = $self->param('viewid');

    # Shared
    my $config      = $self->stash('config');
    my $location    = $self->stash('location');
    my $user        = $self->stash('user');
    my $path_prefix = $self->stash('path_prefix');
    
    $self->update_record;
 
    if ($self->stash('representation') eq "html"){
        # TODO Get
        $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{views_loc}");

        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($viewid){
            $logger->debug("Weiter zum Record $viewid");
            $self->stash('status',201); # created
            $self->stash('location',"$location/$viewid");
            $self->show_record;
        }
    }

    return;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $viewname       = $self->param('viewid');

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
    my $method          = decode_utf8($query->stash('_method')) || '';
    my $confirm         = $query->stash('confirm') || 0;

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    if (!$config->view_exists($viewname)) {
        return $self->print_warning($msg->maketext("Es existiert kein View unter diesem Namen"));
    }

    # Ansonsten POST oder PUT => Aktualisieren
    $config->update_view_rss($viewname,$input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{views_loc}");
        return;
    }
    else {
        $logger->debug("Weiter zum Record $viewname");
        $self->show_record;
    }

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        primrssfeed => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        rssfeeds => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        
    };
}

1;
