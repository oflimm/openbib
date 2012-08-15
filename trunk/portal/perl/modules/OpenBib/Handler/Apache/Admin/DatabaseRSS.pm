#####################################################################
#
#  OpenBib::Handler::Apache::Admin::DatabaseRSS
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

package OpenBib::Handler::Apache::Admin::DatabaseRSS;

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
    my $dbname         = $self->param('databaseid');

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
        $self->print_authorization_error();
        return;
    }

    if (!$config->db_exists($dbname)) {
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        return Apache2::Const::OK;
    }

    my $rssfeed_ref= $config->get_rssfeeds_of_db($dbname);;
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $katalog={
        dbname      => $dbname,
        rssfeeds    => $rssfeed_ref,
    };
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
        katalog      => $katalog,
    };
    
    $self->print_page($config->{tt_admin_database_rss_tname},$ttdata);

    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');
    my $rssid          = $self->strip_suffix($self->param('rssid'));

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
        $self->print_authorization_error();
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }

    my $rssinfo_ref = $config->get_rssfeed_by_id($rssid);
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
        rssinfo      => $rssinfo_ref,
        dbname       => $dbname,
    };
    
    $self->print_page($config->{tt_admin_database_rss_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');

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
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }
    
    $logger->debug("Server: ".$r->get_server_name);

    
    if ($input_data_ref->{type} eq "") {
        $self->print_warning($msg->maketext("Sie müssen einen RSS-Typ eingeben."));
        return Apache2::Const::OK;
    }
    
    if (!$config->db_exists($dbname)) {
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        return Apache2::Const::OK;
    }

    my $dbid = $config->get_databaseinfo->search_rs({ dbname => $dbname })->single()->id;

    $input_data_ref->{dbid} = $dbid;

    my $new_rssid = $config->new_databaseinfo_rss($input_data_ref);

    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}/$dbname/rss");
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_rssid){
            $logger->debug("Weiter zum Record $new_rssid");
            $self->param('status',Apache2::Const::HTTP_CREATED);
            $self->param('rssid',$new_rssid);
            $self->param('location',"$location/$new_rssid");
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
    my $dbname         = $self->param('databaseid');
    my $rssid          = $self->strip_suffix($self->param('rssid'));

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
        $self->print_authorization_error();
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }

    my $rssinfo_ref = $config->get_rssfeed_by_id($rssid);
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
        rssinfo      => $rssinfo_ref,
        dbname       => $dbname,
    };
    
    $self->print_page($config->{tt_admin_database_rss_record_edit_tname},$ttdata);
        
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');
    my $rssid          = $self->param('rssid');

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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    
    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if ($method eq "DELETE"){
        $logger->debug("About to delete $dbname");
        
        if ($confirm){
            my $rssinfo_ref = $config->get_rssfeed_by_id($rssid);

            my $ttdata={
                rssinfo      => $rssinfo_ref,
                dbname       => $dbname,
            };

            $logger->debug("Asking for confirmation");
            $self->print_page($config->{tt_admin_database_rss_record_delete_confirm_tname},$ttdata);

            return Apache2::Const::OK;
        }
        else {
            $self->delete_record;
            return;
        }
    }

    my $dbid = $config->get_databaseinfo->search_rs({ dbname => $dbname })->single()->id;

    $input_data_ref->{dbid} = $dbid;
    $input_data_ref->{id}   = $rssid;
    
    # Ansonsten POST oder PUT => Aktualisieren
    $config->update_databaseinfo_rss($input_data_ref);

    return unless ($self->param('representation') eq "html");

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}/$dbname/rss");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');
    my $rssid          = $self->param('rssid');

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
        $self->print_authorization_error();
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }

    $config->del_databaseinfo_rss($rssid);

    return unless ($self->param('representation') eq "html");

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}/$dbname/rss");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        type => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        active => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
