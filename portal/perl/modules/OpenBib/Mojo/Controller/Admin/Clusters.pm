#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Clusters
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

package OpenBib::Mojo::Controller::Admin::Clusters;

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

    my $clusterinfos_ref = $config->get_clusterinfo_overview;
    
    my $ttdata = {
        clusterinfos => $clusterinfos_ref,
    };
    
    return $self->print_page($config->{tt_admin_clusters_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view             = $self->param('view');
    my $clusterid        = $self->param('clusterid');

    # Shared Args
    my $config           = $self->stash('config');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $clusterinfo_ref = $config->get_clusterinfo->search_rs({ id => $clusterid })->single();
    
    my $ttdata = {
        clusterid     => $clusterid,
        clusterinfo   => $clusterinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_clusters_record_edit_tname},$ttdata);
}

sub show_record_consistency {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view             = $self->param('view');
    my $clusterid        = $self->param('clusterid');

    # Shared Args
    my $config           = $self->stash('config');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $clusterinfo_ref = $config->get_clusterinfo->search_rs({ id => $clusterid })->single();
    
    my $ttdata = {
        clusterid     => $clusterid,
        clusterinfo   => $clusterinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_clusters_record_consistency_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view             = $self->param('view');
    my $clusterid        = $self->strip_suffix($self->param('clusterid'));

    # Shared Args
    my $config           = $self->stash('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    $logger->debug("Clusterid: $clusterid");
    
    my $clusterinfo_ref = $config->get_clusterinfo->search_rs({ id => $clusterid })->single();;
    
    my $ttdata = {
        clusterid     => $clusterid,
        clusterinfo   => $clusterinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_clusters_record_tname},$ttdata);
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
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');
    my $user           = $self->stash('user');
    my $lang           = $self->stash('lang');
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

    if ($config->clustername_exists($input_data_ref->{description})){
	return $self->print_warning($msg->maketext("Ein Cluster mit diesem Namen existiert bereits"));
    }
    
    my $new_clusterid = $config->new_cluster($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{clusters_loc}/id/$new_clusterid/edit.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_clusterid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $new_clusterid");
            $self->stash('status',201); # created
            $self->param('clusterid',$new_clusterid);
            $self->stash('location',"$location/id/$new_clusterid");
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
    my $view             = $self->param('view');
    my $clusterid        = $self->param('clusterid');

    # Shared Args
    my $config         = $self->stash('config');
    my $path_prefix    = $self->stash('path_prefix');
    my $lang           = $self->stash('lang');
    my $msg            = $self->stash('msg');
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
    
    $input_data_ref->{id} = $clusterid;
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    # POST oder PUT => Aktualisieren

    if ($config->clustername_exists($input_data_ref->{description})){
	return $self->print_warning($msg->maketext("Ein Cluster mit diesem Namen existiert bereits"));
    }
        
    $config->update_cluster($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{clusters_loc}");
    }
    else {
        $logger->debug("Weiter zum Record $clusterid");
        return $self->show_record;
    }
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $clusterid      = $self->strip_suffix($self->stash('clusterid'));
    my $config         = $self->stash('config');

    my $clusterinfo_ref = $config->get_clusterinfo->search({ id => $clusterid})->single;

    my $ttdata={
        clusterid   => $clusterid,
        clusterinfo => $clusterinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_clusters_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r                = $self->stash('r');

    # Dispatched Args
    my $view            = $self->param('view')                  || '';
    my $clusterid       = $self->param('clusterid')             || '';

    # Shared Args
    my $config         = $self->stash('config');
    my $path_prefix    = $self->stash('path_prefix');
    my $lang           = $self->stash('lang');
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
    
    $config->del_cluster({id => $clusterid});

    return $self->render( json => { success => 1, id => $clusterid }) unless ($self->stash('representation') eq "html");

    $self->res->headers->content_type('text/html');    
    return  $self->redirect("$path_prefix/$config->{clusters_loc}.html?l=$lang");
}

sub get_input_definition {
    my $self=shift;
    
    return {
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
        active => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
