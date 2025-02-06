#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Databases::RSS
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

package OpenBib::Mojo::Controller::Admin::Databases::RSS;

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

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');

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

    if (!$config->db_exists($dbname)) {
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
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
    
    return $self->print_page($config->{tt_admin_databases_rss_tname},$ttdata);
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

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    my $rssinfo_ref = $config->get_rssfeed_by_id($rssid);
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
        rssinfo      => $rssinfo_ref,
        dbname       => $dbname,
    };
    
    return $self->print_page($config->{tt_admin_databases_rss_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }
    
    $logger->debug("Server: ".$r->get_server_name);

    
    if ($input_data_ref->{type} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen einen RSS-Typ eingeben."));
    }
    
    if (!$config->db_exists($dbname)) {
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    my $dbid = $config->get_databaseinfo->search_rs({ dbname => $dbname })->single()->id;

    $input_data_ref->{dbid} = $dbid;

    my $new_rssid = $config->new_databaseinfo_rss($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{databases_loc}/id/$dbname/rss.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_rssid){
            $logger->debug("Weiter zum Record $new_rssid");
            $self->stash('status',201); # created
            $self->stash('rssid',$new_rssid);
            $self->stash('location',"$location/$new_rssid");
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

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    my $rssinfo_ref = $config->get_rssfeed_by_id($rssid);
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
        rssinfo      => $rssinfo_ref,
        dbname       => $dbname,
    };
    
    return $self->print_page($config->{tt_admin_databases_rss_record_edit_tname},$ttdata);
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
    my $method          = decode_utf8($r->param('_method')) || '';
    my $confirm         = $r->param('confirm') || 0;

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    my $dbid = $config->get_databaseinfo->search_rs({ dbname => $dbname })->single()->id;

    my $update_args = {
        dbid => $dbid,
        id   => $rssid,
    };

    if ($input_data_ref->{active}){
        $update_args->{active} = $input_data_ref->{active};
    }
    
    
    # Ansonsten POST oder PUT => Aktualisieren
    $config->update_databaseinfo_rss($update_args);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{databases_loc}/id/$dbname/rss");
        return;
    }
    else {
        $logger->debug("Weiter zum Record $rssid");
        $self->show_record;
    }

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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    $config->del_databaseinfo_rss($rssid);

    return unless ($self->stash('representation') eq "html");

    # TODO GET?
    return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{databases_loc}/id/$dbname/rss.html?l=$lang");
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
