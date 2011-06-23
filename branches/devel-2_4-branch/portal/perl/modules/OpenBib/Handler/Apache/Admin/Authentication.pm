#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Authentication
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

package OpenBib::Handler::Apache::Admin::Authentication;

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
        'show_record_form'          => 'show_record_form',
        'create_record'             => 'create_record',
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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');

    if (!$self->is_authenticated('admin')){
        return;
    }

    $logger->debug("Server: ".$r->get_server_name."Representation: $representation");

    # TT-Data erzeugen
    my $ttdata={
    };
    
    $self->print_page($config->{tt_admin_authentication_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    # Dispatched Args
    my $view             = $self->param('view')                   || '';
    my $authenticationid = $self->param('authenticationid')       || '';

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
    
    if (!$self->is_authenticated('admin')){
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    my $logintarget_ref = $user->get_logintarget_by_id($authenticationid);
    
    my $ttdata={
        logintarget => $logintarget_ref,
    };
    
    $self->print_page($config->{tt_admin_authentication_record_edit_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';
    my $representation = $self->param('representation') || '';

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

    # CGI Args
    my $description     = decode_utf8($query->param('description'))     || '';
    my $targetid        = $query->param('targetid')        || '';
    my $hostname        = $query->param('hostname')        || '';
    my $port            = $query->param('port')            || '';
    my $username        = $query->param('username')        || '';
    my $dbname          = $query->param('dbname')          || '';
    my $type            = $query->param('type')            || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    my $thislogintarget_ref = {
        id          => $targetid,
        hostname    => $hostname,
        port        => $port,
        username    => $username,
        dbname      => $dbname,
        description => $description,
        type        => $type,
    };

    if ($description eq "") {
        
        $self->print_warning($msg->maketext("Sie müssen mindestens eine Beschreibung eingeben."));
        
        return Apache2::Const::OK;
    }
    
    if ($user->logintarget_exists({description => $thislogintarget_ref->{description}})) {
        
        $self->print_warning($msg->maketext("Es existiert bereits ein Anmeldeziel unter diesem Namen"));
        
        return Apache2::Const::OK;
    }
    
    $config->new_logintarget($thislogintarget_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_authentication_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view             = $self->param('view')                   || '';
    my $authenticationid = $self->param('authenticationid')       || '';

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

    # CGI Args
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;
    
    my $description     = decode_utf8($query->param('description'))     || '';
    my $hostname        = $query->param('hostname')        || '';
    my $port            = $query->param('port')            || '';
    my $username        = $query->param('username')        || '';
    my $dbname          = $query->param('dbname')          || '';
    my $type            = $query->param('type')            || '';

    if (!$self->is_authenticated('admin')){
        return;
    }
    
    $logger->debug("Server: ".$r->get_server_name);

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if ($method eq "DELETE"){
        $logger->debug("About to delete $authenticationid");
        
        if ($confirm){
            my $logintarget_ref = $user->get_logintarget_by_id($authenticationid);
            
            my $ttdata={
                stylesheet => $stylesheet,
                logintarget  => $logintarget_ref,

                view       => $view,
                
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };

            $logger->debug("Asking for confirmation");
            OpenBib::Common::Util::print_page($config->{tt_admin_authentication_record_delete_confirm_tname},$ttdata,$r);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->delete_record;
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren
    
    my $thislogintarget_ref = {
        id          => $authenticationid,
        hostname    => $hostname,
        port        => $port,
        username    => $username,
        dbname      => $dbname,
        description => $description,
        type        => $type,
    };

    $logger->debug("Info: ".YAML::Dump($thislogintarget_ref));

    $config->update_logintarget($thislogintarget_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_authentication_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view             = $self->param('view')                   || '';
    my $authenticationid = $self->param('authenticationid')             || '';

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->is_authenticated('admin')){
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    $config->del_logintarget($authenticationid);
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_authentication_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

    
1;
