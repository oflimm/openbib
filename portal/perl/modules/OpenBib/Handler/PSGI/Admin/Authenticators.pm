#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Authenticators
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

package OpenBib::Handler::PSGI::Admin::Authenticators;

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
        'show_record_form'          => 'show_record_form',
        'show_record'               => 'show_record',
        'create_record'             => 'create_record',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
        'confirm_delete_record'     => 'confirm_delete_record',
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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    # TT-Data erzeugen
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_admin_authenticators_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view            = $self->param('view');
    my $authenticatorid = $self->strip_suffix($self->param('authenticatorid'));

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
    
    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    $logger->debug("Server: ".$r->get_server_name);
    $logger->debug("Authenticatorid: ".$authenticatorid);

    my $authenticator_ref = $config->get_authenticator_by_id($authenticatorid);

    if ($logger->is_debug){
        $logger->debug("Authenticator-Info: ".YAML::Dump($authenticator_ref));
    }
    
    my $ttdata={
        authenticatorid   => $authenticatorid,
        authenticatorinfo => $authenticator_ref,
    };
    
    return $self->print_page($config->{tt_admin_authenticators_record_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view')                   || '';
    my $authenticatorid   = $self->param('authenticatorid')       || '';

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
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    $logger->debug("Server: ".$r->get_server_name);

    my $authenticator_ref = $config->get_authenticator_by_id($authenticatorid);
    
    my $ttdata={
        authenticatorinfo => $authenticator_ref,
    };
    
    return $self->print_page($config->{tt_admin_authenticators_record_edit_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    $logger->debug("Server: ".$r->get_server_name);

    if ($input_data_ref->{description} eq "") {        
        return $self->print_warning($msg->maketext("Sie müssen mindestens eine Beschreibung eingeben."));
    }
    
    if ($config->authenticator_exists({description => $input_data_ref->{description}})) {
        return $self->print_warning($msg->maketext("Es existiert bereits ein Anmeldeziel unter diesem Namen"));
    }
    
    my $new_authenticatorid = $config->new_authenticator($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{authenticators_loc}/id/$new_authenticatorid/edit.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_authenticatorid){
            $logger->debug("Weiter zum Record $new_authenticatorid");
            $self->param('status',201); # created
            $self->param('authenticatorid',$new_authenticatorid);
            $self->param('location',"$location/$new_authenticatorid");
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
    my $view             = $self->param('view')                   || '';
    my $authenticatorid = $self->param('authenticatorid')       || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{id} = $authenticatorid;
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }
    
    $logger->debug("Server: ".$r->get_server_name);

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if ($method eq "DELETE"){
        $logger->debug("About to delete $authenticatorid");
        
        if ($confirm){
            my $authenticator_ref = $config->get_authenticator_by_id($authenticatorid);
            
            my $ttdata={
                stylesheet => $stylesheet,
                authenticator  => $authenticator_ref,

                view       => $view,
                
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };

            $logger->debug("Asking for confirmation");

            return $self->print_page($config->{tt_admin_authenticators_record_delete_confirm_tname},$ttdata);
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->delete_record;
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren
    
    $config->update_authenticator($input_data_ref);

    return unless ($self->param('representation') eq "html");

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{authenticators_loc}.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record $authenticatorid");
        $self->show_record;
    }

    return;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view            = $self->param('view');
    my $authenticatorid = $self->strip_suffix($self->param('authenticatorid'));
    my $config          = $self->param('config');

    my $authenticator_ref = $config->get_authenticator_by_id($authenticatorid);

    if ($logger->is_debug){
	$logger->debug("Confirming deletion of authenticator $authenticatorid");
	$logger->debug("Authenticator is: ".YAML::Dump($authenticator_ref));
    }
    
    my $ttdata={
       authenticatorinfo  => $authenticator_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_authenticators_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view             = $self->param('view')                   || '';
    my $authenticatorid = $self->param('authenticatorid')             || '';

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    $logger->debug("Server: ".$r->get_server_name);

    $config->delete_authenticator($authenticatorid);

    return unless ($self->param('representation') eq "html");

    # TODO GET?
    return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{authenticators_loc}.html?l=$lang");
}

sub get_input_definition {
    my $self=shift;
    
    return {
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        name => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        mfa => {
            default  => 'none',
            encoding => 'none',
            type     => 'scalar',
        },
        type => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        views => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        
    };
}
    
1;
