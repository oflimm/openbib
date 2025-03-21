#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Locations
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

package OpenBib::Mojo::Controller::Admin::Locations;

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

    # Shared Args
    my $config         = $self->stash('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $locationinfo_ref = $config->get_locationinfo_overview();
    
    my $ttdata={
        locations  => $locationinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_locations_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $locationid     = $self->strip_suffix($self->param('locationid'));

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

    my $locationinfo = $config->get_locationinfo->single({identifier => $locationid});

    my $locationinfo_ref = {};
        
    if ($locationinfo){
        $locationinfo_ref = {
            id          => $locationinfo->id,
            identifier  => $locationinfo->identifier,
            description => $locationinfo->description,
            shortdesc   => $locationinfo->shortdesc,
            type        => $locationinfo->type,
            fields      => $config->get_locationinfo_fields($locationid),
        };
    }

    my $ttdata={
        locationid   => $locationid,
        locationinfo => $locationinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_locations_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')                   || '';

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

    if ($input_data_ref->{identifier} eq "" && $input_data_ref->{description} eq "" && $input_data_ref->{type}) {
        
        return $self->print_warning($msg->maketext("Sie müssen mindestens einen Identifier, dessen Typ und eine Beschreibung eingeben."));
    }
    
    if ($config->location_exists($input_data_ref->{identifier})) {
        
        return $self->print_warning($msg->maketext("Es existiert bereits ein Standort mit diesem Identifier"));
    }
    
    $config->new_locationinfo($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{locations_loc}/id/$input_data_ref->{identifier}/edit.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record $input_data_ref->{identifier}");
        $self->stash('status',201); # created
        $self->show_record;
    }
    
    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $locationid     = $self->param('locationid');

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

    my $locationinfo = $config->get_locationinfo->single({identifier => $locationid});

    my $locationinfo_ref = {};
    
    if ($locationinfo){
        $locationinfo_ref = {
            id          => $locationinfo->id,
            identifier  => $locationinfo->identifier,
            description => $locationinfo->description,
            shortdesc   => $locationinfo->shortdesc,
            type        => $locationinfo->type,
            fields      => $config->get_locationinfo_fields($locationid),
        };
    }
    
    my $ttdata={
        locationid   => $locationid,
        locationinfo => $locationinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_locations_record_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')                   || '';
    my $locationid     = $self->param('locationid')             || '';

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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{identifier} = $locationid;
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    $config->update_locationinfo($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{locations_loc}");
        return;
    }
    else {
        $logger->debug("Weiter zum Record $locationid");
        $self->show_record;
    }
    
    return;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $locationid     = $self->strip_suffix($self->stash('locationid'));
    my $config         = $self->stash('config');

    my $ttdata={
        locationid => $locationid,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_locations_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Ards
    my $view           = $self->param('view');
    my $locationid     = $self->param('locationid');

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

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    if ($self->param('confirm')){
	return $self->confirm_delete_record;
    }
    
    $config->delete_locationinfo($locationid);

    return $self->render( json => { success => 1, id => $locationid }) unless ($self->stash('representation') eq "html");

    $self->res->headers->content_type('text/html');    
    $self->redirect("$path_prefix/$config->{locations_loc}.html");
    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        identifier => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        shortdesc => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        type => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        # Muster: field_FIELD_SUBFIELD_MULT
        fields => {
            default   => {},
            encoding  => 'none',
            type      => 'fields',
	    no_escape => 1,
        },
        
    };
}

1;
