#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Clusters
#
#  Dieses File ist (C) 2004-2026 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Admin::Clusters;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Date::Manip qw/ParseDate UnixDate/;
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS qw/encode_json decode_json/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::MQ;
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
        'show_collection'            => 'show_collection',
        'show_record_form'           => 'show_record_form',
        'show_record_consistency'    => 'show_record_consistency',
        'show_record'                => 'show_record',
        'create_record'              => 'create_record',
        'update_record'              => 'update_record',
        'confirm_delete_record'      => 'confirm_delete_record',
        'delete_record'              => 'delete_record',
        'dispatch_to_representation' => 'dispatch_to_representation',
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
    my $config           = $self->param('config');

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
    my $refresh          = $self->param('refresh') || 0; # != 0: Correlation ID
    
    # Shared Args
    my $config           = $self->param('config');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $clusterinfo_ref = $config->get_clusterinfo->search_rs({ id => $clusterid })->single();
    
    my $cluster_differences_ref = [];    

    my $mq = new OpenBib::MQ({ config => $config });

    if ($refresh){
	if ($mq->job_processed({ queue => 'task_clusters', job_id => "cluster_consistency_$clusterid"})){
	    my $result_ref = $mq->get_result({ queue => 'task_clusters', job_id => "cluster_consistency_$clusterid"});
	    $cluster_differences_ref = $result_ref->{payload};
	    $refresh = 0;
	}
    }
    else {
	# Send Message to task queue referencing a callback queue and correlation id
	my $result_ref = $mq->submit_job({ queue => 'task_clusters', job_id => "cluster_consistency_$clusterid" , payload => { id => $clusterid }});

	unless ($result_ref->{submitted}){
	    $logger->fatal("Unable to submitt task");
	}

	if ($mq->job_processed({ queue => 'task_clusters', job_id => "cluster_consistency_$clusterid"})){
	    $cluster_differences_ref = $mq->get_result({ queue => 'task_clusters', job_id => "cluster_consistency_$clusterid"});
	    $refresh = 0;
	}
	else {
	    $refresh = 1;
	}	
    }
    
    my $ttdata = {
	refresh       => $refresh,
        clusterid     => $clusterid,
        clusterinfo   => $clusterinfo_ref,
	differences   => $cluster_differences_ref,
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
    my $config           = $self->param('config');

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
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');
    my $user           = $self->param('user');
    my $lang           = $self->param('lang');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    my $new_clusterid = $config->new_cluster($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{clusters_loc}/id/$new_clusterid/edit.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_clusterid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $new_clusterid");
            $self->param('status',201); # created
            $self->param('clusterid',$new_clusterid);
            $self->param('location',"$location/$new_clusterid");
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
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');
    my $lang           = $self->param('lang');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    $input_data_ref->{id} = $clusterid;
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    # POST oder PUT => Aktualisieren

    $config->update_cluster($input_data_ref);

    if ($self->param('representation') eq "html"){
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
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $clusterid      = $self->strip_suffix($self->param('clusterid'));
    my $config         = $self->param('config');

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
    
    my $r                = $self->param('r');

    # Dispatched Args
    my $view            = $self->param('view')                  || '';
    my $clusterid       = $self->param('clusterid')             || '';

    # Shared Args
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    $config->del_cluster({id => $clusterid});

    # TODO GET?
    return $self->redirect("$path_prefix/$config->{clusters_loc}");
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
