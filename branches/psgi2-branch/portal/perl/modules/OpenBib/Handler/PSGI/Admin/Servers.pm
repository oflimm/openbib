#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Servers
#
#  Dieses File ist (C) 2004-2014 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Admin::Servers;

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
use OpenBib::Config::DatabaseInfoTable;
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
        'show_record'               => 'show_record',
        'show_record_form'          => 'show_record_form',
        'create_record'             => 'create_record',
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
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $serverinfos_ref = $config->get_serverinfo_overview;
    
    my $ttdata = {
        serverinfos => $serverinfos_ref,
    };
    
    $self->print_page($config->{tt_admin_servers_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view             = $self->param('view');
    my $serverid         = $self->param('serverid');

    # Shared Args
    my $config           = $self->param('config');
    my $queryoptions     = $self->param('qopts');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    
    my $serverinfo_ref = $config->get_serverinfo->search_rs({ id => $serverid })->single;

    my $updatelog_ref;

    if ($serverinfo_ref) {
        $updatelog_ref = $serverinfo_ref->updatelogs->search_rs(
            undef,
            {                
                rows => $queryoptions->get_option('num'),
                order_by => ['id DESC']
            }
        );
    }
    
    my $ttdata = {
        serverid     => $serverid,
        serverinfo   => $serverinfo_ref,
        updatelog    => $updatelog_ref,
    };
    
    $self->print_page($config->{tt_admin_servers_record_edit_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view             = $self->param('view');
    my $serverid         = $self->strip_suffix($self->param('serverid'));

    # Shared Args
    my $config           = $self->param('config');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $serverinfo_ref = $config->get_serverinfo->search_rs({ id => $serverid })->single;
    
    my $ttdata = {
        serverid     => $serverid,
        serverinfo   => $serverinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_servers_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input($self->get_input_definition);

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    if ($input_data_ref->{hostip} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen einen Servernamen eingeben."));
    }
    
    my $new_serverid = $config->new_server($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{servers_loc}/id/$new_serverid/edit.html?l=$lang");
        return ;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_serverid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $new_serverid");
            $self->param('status',201); # created
            $self->param('serverid',$new_serverid);
            $self->param('location',"$location/$new_serverid");
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
    my $serverid         = $self->param('serverid');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input($self->get_input_definition);

    $input_data_ref->{id} = $serverid;
    
    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $config->update_server($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{servers_loc}");
        return ;
    }
    else {
        $logger->debug("Weiter zum Record $serverid");
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
    my $serverid       = $self->strip_suffix($self->param('serverid'));
    my $config         = $self->param('config');

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
    
    my $r                = $self->param('r');

    # Dispatched Args
    my $view           = $self->param('view')                 || '';
    my $serverid       = $self->param('serverid')             || '';

    # Shared Args
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $config->del_server({id => $serverid});

    #TODO GET?
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
