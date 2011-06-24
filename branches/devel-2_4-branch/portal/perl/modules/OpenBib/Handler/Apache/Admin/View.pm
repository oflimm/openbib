#####################################################################
#
#  OpenBib::Handler::Apache::Admin::View
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

package OpenBib::Handler::Apache::Admin::View;

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
        'show_collection_form'      => 'show_collection_form',
        'create_record'             => 'create_record',
        'show_record'               => 'show_record',
        'show_record_form'          => 'show_record_form',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
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

    my $viewinfo_ref = $config->get_viewinfo_overview();
    
    my $ttdata={
        views      => $viewinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_view_tname},$ttdata);
    
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

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $viewinfo_obj  = $config->get_viewinfo->search({ viewname => $viewname })->single();

    my $description = $viewinfo_obj->description;
    my $primrssfeed = $viewinfo_obj->rssfeed;
    my $start_loc   = $viewinfo_obj->start_loc;
    my $start_stid  = $viewinfo_obj->start_stid;
    my $profilename = $viewinfo_obj->profilename;
    my $stripuri    = $viewinfo_obj->stripuri;
    my $joinindex   = $viewinfo_obj->joinindex;
    my $active      = $viewinfo_obj->active;
             
    my @profiledbs       = $config->get_profiledbs($profilename);
    my @viewdbs          = $config->get_viewdbs($viewname);
    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    my $viewrssfeed_ref  = $config->get_rssfeeds_of_view($viewname);

    my $viewinfo={
        viewname     => $viewname,
        description  => $description,
        stripuri     => $stripuri,
        joinindex    => $joinindex,
        active       => $active,
        start_loc    => $start_loc,
        start_stid   => $start_stid,
        profilename  => $profilename,
        viewdbs      => \@viewdbs,
        allrssfeeds  => $all_rssfeeds_ref,
        viewrssfeed  => $viewrssfeed_ref,
        primrssfeed  => $primrssfeed,
    };

    
    my $ttdata={
        dbnames    => \@profiledbs,
        viewinfo   => $viewinfo,
        dbinfo     => $dbinfotable,
    };
    
    $self->print_page($config->{tt_admin_view_record_tname},$ttdata);
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
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $description     = decode_utf8($query->param('description'))     || '';
    my $viewname        = $query->param('viewname')                     || '';
    my $profilename     = $query->param('profilename')                  || '';
    my $stripuri        = $query->param('stripuri')       || 0;
    my $joinindex       = $query->param('joinindex')       || 0;
    my $active          = $query->param('active')          || 0;
    my $viewstart_loc   = $query->param('viewstart_loc')             || '';
    my $viewstart_stid  = $query->param('viewstart_stid')            || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    if ($viewname eq "" || $description eq "" || $profilename eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Viewnamen, eine Beschreibung sowie ein Katalog-Profil eingeben."));
        return Apache2::Const::OK;
    }

    # Profile muss vorhanden sein.
    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    # View darf noch nicht existieren
    if ($config->view_exists($viewname)) {
        $self->print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"));
        return Apache2::Const::OK;
    }
    
    my $ret = $config->new_view({
        viewname    => $viewname,
        description => $description,
        profilename => $profilename,
        stripuri    => $stripuri,
        joinindex   => $joinindex,
        active      => $active,
        start_loc   => $viewstart_loc,
        start_stid  => $viewstart_stid,
    });
    
    if ($ret == -1){
        $self->print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"));
        return Apache2::Const::OK;
    }

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_view_loc}/$viewname/edit");
    $self->query->status(Apache2::Const::REDIRECT);
    
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

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $viewinfo_obj  = $config->get_viewinfo->search({ viewname => $viewname })->single();

    my $description = $viewinfo_obj->description;
    my $primrssfeed = $viewinfo_obj->rssfeed;
    my $start_loc   = $viewinfo_obj->start_loc;
    my $start_stid  = $viewinfo_obj->start_stid;
    my $profilename = $viewinfo_obj->profilename;
    my $stripuri    = $viewinfo_obj->stripuri;
    my $joinindex   = $viewinfo_obj->joinindex;
    my $active      = $viewinfo_obj->active;
             
    my @profiledbs       = $config->get_profiledbs($profilename);
    my @viewdbs          = $config->get_viewdbs($viewname);
    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    my $viewrssfeed_ref=$config->get_rssfeeds_of_view($viewname);

    my $viewinfo={
        viewname     => $viewname,
        description  => $description,
        active       => $active,
        stripuri     => $stripuri,
        joinindex    => $joinindex,
        start_loc    => $start_loc,
        start_stid   => $start_stid,
        profilename  => $profilename,
        viewdbs      => \@viewdbs,
        allrssfeeds  => $all_rssfeeds_ref,
        viewrssfeed  => $viewrssfeed_ref,
        primrssfeed  => $primrssfeed,
    };

    
    my $ttdata={
        dbnames    => \@profiledbs,
        viewinfo   => $viewinfo,
        dbinfo     => $dbinfotable,
    };
    
    $self->print_page($config->{tt_admin_view_record_edit_tname},$ttdata);

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
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;
    my $description     = decode_utf8($query->param('description'))     || '';
    my $joinindex       = $query->param('joinindex')       || 0;
    my $stripuri        = $query->param('stripuri')        || 0;
    my $active          = $query->param('active')          || 0;
    my $primrssfeed     = $query->param('primrssfeed')     || '';
    my $viewstart_loc   = $query->param('viewstart_loc')             || '';
    my $viewstart_stid  = $query->param('viewstart_stid')            || '';
    my $profilename     = $query->param('profilename')     || '';
    my @viewdb          = ($query->param('viewdb'))?$query->param('viewdb'):();
    my @rssfeeds        = ($query->param('rssfeeds'))?$query->param('rssfeeds'):();
    
    if (!$self->is_authenticated('admin')){
        return;
    }

    if (!$config->view_exists($viewname)) {
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        return Apache2::Const::OK;
    }

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if ($method eq "DELETE"){
        $logger->debug("About to delete $viewname");
        
        if ($confirm){
            my $viewinfo_ref = $config->get_viewinfo->search({ viewname => $viewname})->single;
            
            my $ttdata={
                viewinfo   => $viewinfo_ref,
            };

            $logger->debug("Asking for confirmation");
            $self->print_page($config->{tt_admin_view_record_delete_confirm_tname},$ttdata);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->delete_record;
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren

    # Profile muss vorhanden sein.
    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    my $thisviewinfo_ref = {
        viewname    => $viewname,
        description => $description,
        stripuri    => $stripuri,
        joinindex   => $joinindex,
        active      => $active,
        primrssfeed => $primrssfeed,
        start_loc   => $viewstart_loc,
        start_stid  => $viewstart_stid,
        profilename => $profilename,
        viewdb      => \@viewdb,
        rssfeeds    => \@rssfeeds,
    };

    $logger->debug("Info: ".YAML::Dump($thisviewinfo_ref));
    
    $config->update_view($thisviewinfo_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_view_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
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

    if (!$self->is_authenticated('admin')){
        return;
    }

    $config->del_view($viewname);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_view_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
