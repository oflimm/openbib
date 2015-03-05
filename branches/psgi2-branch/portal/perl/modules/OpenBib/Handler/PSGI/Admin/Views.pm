#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Views
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

package OpenBib::Handler::PSGI::Admin::Views;

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

use base 'OpenBib::Handler::PSGI::Admin';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_collection_form'      => 'show_collection_form',
        'create_record'             => 'create_record',
        'show_record'               => 'show_record',
        'show_record_form'          => 'show_record_form',
        'update_record'             => 'update_record',
        'confirm_delete_record'     => 'confirm_delete_record',
        'delete_record'             => 'delete_record',
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

    my $viewinfo_ref = $config->get_viewinfo_overview();
    
    my $ttdata={
        views      => $viewinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_views_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $viewname       = $self->strip_suffix($self->param('viewid'));

    # Shared Args
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # View muss existieren
    unless ($config->view_exists($viewname)) {
        return $self->print_warning($msg->maketext("Ein View dieses Namens existiert nicht."));
    }

    my $viewinfo    = $config->get_viewinfo->search({ viewname => $viewname })->single();

    my $profilename = $viewinfo->profileid->profilename;
    
    my @profiledbs       = $config->get_profiledbs($profilename);
    my @viewdbs          = $config->get_viewdbs($viewname);
    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    my $viewrssfeed_ref  = $config->get_rssfeeds_of_view($viewname);

    my $ttdata={
        dbnames     => \@profiledbs,
        viewdbs     => \@viewdbs,
        viewinfo    => $viewinfo,
        allrssfeeds => $all_rssfeeds_ref,
    };
    
    return $self->print_page($config->{tt_admin_views_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if ($input_data_ref->{viewname} eq "" || $input_data_ref->{description} eq "" || $input_data_ref->{profilename} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen mindestens einen Viewnamen, eine Beschreibung sowie ein Katalog-Profil eingeben."));
    }

    # Profile muss vorhanden sein.
    if (!$config->profile_exists($input_data_ref->{profilename})) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    # View darf noch nicht existieren
    if ($config->view_exists($input_data_ref->{viewname})) {
        return $self->print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"));
    }
    
    my $new_viewid = $config->new_view($input_data_ref);
    
    if (!$new_viewid){
        return $self->print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"));
    }

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{views_loc}/id/$input_data_ref->{viewname}/edit.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_viewid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zum Record $input_data_ref->{viewname}");
            $self->param('status',201); # created
            $self->param('viewid',$input_data_ref->{viewname});
            $self->param('location',"$location/$input_data_ref->{viewname}");
            $self->show_record;
        }
    }

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $viewname       = $self->param('viewid');

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $viewinfo    = $config->get_viewinfo->search({ viewname => $viewname })->single();

    my $viewdbs_ref      = {};
    foreach my $dbname ($config->get_viewdbs($viewname)){
        $viewdbs_ref->{$dbname} = 1;
    }

    my @profiledbs       = sort $config->get_profiledbs($config->get_profilename_of_view($viewname));
    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    my $viewrssfeed_ref  = $config->get_rssfeeds_of_view($viewname);

    my $ttdata={
        viewinfo   => $viewinfo,
        selected_viewdbs    => $viewdbs_ref,

        allrssfeeds  => $all_rssfeeds_ref,
        viewrssfeed  => $viewrssfeed_ref,

        dbnames    => \@profiledbs,
        viewinfo   => $viewinfo,
    };
    
    return $self->print_page($config->{tt_admin_views_record_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $view           = $self->param('view');
    my $viewname       = $self->param('viewid');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{viewname} = $viewname;
        
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->view_exists($viewname)) {
        return $self->print_warning($msg->maketext("Es existiert kein View unter diesem Namen"));
    }

    # Profile muss vorhanden sein.
    if (!$config->profile_exists($input_data_ref->{profilename})) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    $config->update_view($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{views_loc}.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record $viewname");
        $self->show_record;
    }

    return;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $viewname       = $self->strip_suffix($self->param('viewid'));
    my $config         = $self->param('config');

    my $viewinfo_ref = $config->get_viewinfo->search({ viewname => $viewname})->single;
    
    my $ttdata={
        viewinfo   => $viewinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_views_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $viewname       = $self->param('viewid');

    # Shared Args
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');
    my $lang           = $self->param('lang');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $config->del_view($viewname);

    return unless ($self->param('representation') eq "html");

    # TODO GET?
    $self->redirect("$path_prefix/$config->{admin_loc}/$config->{views_loc}.html?l=$lang");

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        viewname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        profilename => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        stripuri => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },
        active => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },
        start_loc => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        servername => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        databases => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        
    };
}

1;
