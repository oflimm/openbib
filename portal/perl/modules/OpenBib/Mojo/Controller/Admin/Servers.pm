#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Servers
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

package OpenBib::Mojo::Controller::Admin::Servers;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
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
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->stash('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $serverinfos_ref = $config->get_serverinfo_overview;
    
    my $ttdata = {
        serverinfos => $serverinfos_ref,
    };
    
    return $self->print_page($config->{tt_admin_servers_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view             = $self->param('view');
    my $serverid         = $self->param('serverid');

    # Shared Args
    my $config           = $self->stash('config');
    my $queryoptions     = $self->stash('qopts');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    
    my $serverinfo_ref = $config->get_serverinfo->search_rs({ id => $serverid })->single;
    
    my $ttdata = {
        serverid     => $serverid,
        serverinfo   => $serverinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_servers_record_edit_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view             = $self->param('view');
    my $serverid         = $self->strip_suffix($self->param('serverid'));

    # Shared Args
    my $config           = $self->stash('config');
    my $queryoptions     = $self->stash('qopts');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $serverinfo_ref = $config->get_serverinfo->search_rs({ id => $serverid })->single;
    
    my $ttdata = {
        serverid     => $serverid,
        serverinfo   => $serverinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_servers_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $user           = $self->stash('user');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');
    my $representation = $self->stash('representation');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CSRF-Checking
    if ($representation ne "json" && $self->validation->csrf_protect->has_error('csrf_token')){
	
	$logger->debug("CSRF-Check: ".$self->validation->csrf_protect->has_error);
    
	my $code   = -1;
	my $reason = $msg->maketext("Fehler mit CSRF-Token");
	return $self->print_warning($reason,$code);
    }
    
    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    if ($input_data_ref->{hostip} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen einen Servernamen eingeben."));
    }

    if ($config->servername_exists($input_data_ref->{description})){
	return $self->print_warning($msg->maketext("Ein Server mit diesem Namen existiert bereits"));
    }
    
    my $new_serverid = $config->new_server($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{servers_loc}/id/$new_serverid/edit.html?l=$lang");
        return ;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_serverid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $new_serverid");
            $self->stash('status',201); # created
            $self->param('serverid',$new_serverid);
            $self->stash('location',"$location/$new_serverid");
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
    my $serverid       = $self->param('serverid');

    # Shared Args
    my $config         = $self->stash('config');
    my $path_prefix    = $self->stash('path_prefix');
    my $msg            = $self->stash('msg');
    my $representation = $self->stash('representation');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    $input_data_ref->{id} = $serverid;

    # CSRF-Checking
    if ($representation ne "json" && $self->validation->csrf_protect->has_error('csrf_token')){
	
	$logger->debug("CSRF-Check: ".$self->validation->csrf_protect->has_error);
    
	my $code   = -1;
	my $reason = $msg->maketext("Fehler mit CSRF-Token");
	return $self->print_warning($reason,$code);
    }
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    if ($config->servername_exists($input_data_ref->{description})){
	return $self->print_warning($msg->maketext("Ein Server mit diesem Namen existiert bereits"));
    }
    
    $config->update_server($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{servers_loc}");
    }
    else {
        $logger->debug("Weiter zum Record $serverid");
        return $self->show_record;
    }
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $serverid       = $self->strip_suffix($self->stash('serverid'));
    my $config         = $self->stash('config');

    my $serverinfo_ref = $config->get_serverinfo->search({ id => $serverid})->single;

    my $ttdata={
        serverinfo => $serverinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_servers_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')                 || '';
    my $serverid       = $self->param('serverid')             || '';

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $path_prefix    = $self->stash('path_prefix');
    my $msg            = $self->stash('msg');
    my $representation = $self->stash('representation');

    # CSRF-Checking
    if ($representation ne "json" && $self->validation->csrf_protect->has_error('csrf_token')){
	
	$logger->debug("CSRF-Check: ".$self->validation->csrf_protect->has_error);
    
	my $code   = -1;
	my $reason = $msg->maketext("Fehler mit CSRF-Token");
	return $self->print_warning($reason,$code);
    }
    
    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    if ($self->param('confirm')){
	return $self->confirm_delete_record;
    }
    
    $config->del_server({id => $serverid});

    return $self->render( json => { success => 1, id => $serverid }) unless ($self->stash('representation') eq "html");

    $self->res->headers->content_type('text/html');    
    $self->redirect("$path_prefix/$config->{servers_loc}");

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        hostip => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        status => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        clusterid => {
            default  => undef,
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
