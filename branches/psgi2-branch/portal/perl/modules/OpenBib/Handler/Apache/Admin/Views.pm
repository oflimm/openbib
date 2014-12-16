#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Views
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

package OpenBib::Handler::Apache::Admin::Views;

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
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use CGI::Application::Plugin::Redirect;

use base 'OpenBib::Handler::Apache::Admin';

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
        $self->print_authorization_error();
        return;
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
    my $viewinfo_ref = $config->get_viewinfo_overview();
    
    my $ttdata={
        dbinfo     => $dbinfotable,
        views      => $viewinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_views_tname},$ttdata);
    
    return Apache2::Const::OK;
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
        $self->print_authorization_error();
        return;
    }

    # View muss existieren
    unless ($config->view_exists($viewname)) {
        $self->print_warning($msg->maketext("Ein View dieses Namens existiert nicht."));
        return Apache2::Const::OK;
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

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
        dbinfo      => $dbinfotable,
        allrssfeeds => $all_rssfeeds_ref,
    };
    
    $self->print_page($config->{tt_admin_views_record_tname},$ttdata);
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
        $self->print_authorization_error();
        return;
    }

    if ($input_data_ref->{viewname} eq "" || $input_data_ref->{description} eq "" || $input_data_ref->{profilename} eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Viewnamen, eine Beschreibung sowie ein Katalog-Profil eingeben."));
        return Apache2::Const::OK;
    }

    # Profile muss vorhanden sein.
    if (!$config->profile_exists($input_data_ref->{profilename})) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    # View darf noch nicht existieren
    if ($config->view_exists($input_data_ref->{viewname})) {
        $self->print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"));
        return Apache2::Const::OK;
    }
    
    my $new_viewid = $config->new_view($input_data_ref);
    
    if (!$new_viewid){
        $self->print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"));
        return Apache2::Const::OK;
    }

    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_loc}/$config->{views_loc}/id/$input_data_ref->{viewname}/edit.html?l=$lang");
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_viewid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zum Record $input_data_ref->{viewname}");
            $self->param('status',Apache2::Const::HTTP_CREATED);
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
        $self->print_authorization_error();
        return;
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

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
        dbinfo     => $dbinfotable,
    };
    
    $self->print_page($config->{tt_admin_views_record_edit_tname},$ttdata);

    return Apache2::Const::OK;
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
        $self->print_authorization_error();
        return;
    }

    if (!$config->view_exists($viewname)) {
        $self->print_warning($msg->maketext("Es existiert kein View unter diesem Namen"));
        return Apache2::Const::OK;
    }

    # Profile muss vorhanden sein.
    if (!$config->profile_exists($input_data_ref->{profilename})) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    $config->update_view($input_data_ref);

    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_loc}/$config->{views_loc}.html?l=$lang");
        $self->query->status(Apache2::Const::REDIRECT);
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
    $self->print_page($config->{tt_admin_views_record_delete_confirm_tname},$ttdata);
    
    return Apache2::Const::OK;
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
        $self->print_authorization_error();
        return;
    }

    $config->del_view($viewname);

    return unless ($self->param('representation') eq "html");
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_loc}/$config->{views_loc}.html?l=$lang");
    $self->query->status(Apache2::Const::REDIRECT);

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
