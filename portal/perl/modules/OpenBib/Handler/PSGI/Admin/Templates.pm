####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Templates.pm
#
#  Copyright 2014-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Admin::Templates;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use JSON::XS;
use Data::Pageset;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape;
use XML::RSS;

use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Admin';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_record'                => 'show_record',
        'show_collection'            => 'show_collection',
        'show_record_form'           => 'show_record_form',
        'create_record'              => 'create_record',
        'delete_record'              => 'delete_record',
        'confirm_delete_record'      => 'confirm_delete_record',
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

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $templateinfo_ref = $config->get_templateinfo_overview();

    my $all_templates_ref = {};

    foreach my $config_key (keys %$config){
        if ($config_key =~m/^tt_.+_tname/){
            $all_templates_ref->{$config->{$config_key}} = 1;
        }
    }

    my $ttdata={                # 
        templateinfos   => $templateinfo_ref,
        all_templates   => $all_templates_ref,
    };
    
    return $self->print_page($config->{tt_admin_templates_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $user           = $self->param('user');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    if ($input_data_ref->{templatename} eq "" || $input_data_ref->{viewname} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen mindestens einen Templatename und einen View eingeben."),2);
    }
    
    my $other_template_exists = $config->template_exists($input_data_ref->{templatename},$input_data_ref->{viewname},$input_data_ref->{templatelang});
    
    if ($other_template_exists) {
        return $self->print_warning($msg->maketext("Es existiert bereits ein Template in diesem View"),3);
    }

    my $new_templateid = $config->new_template($input_data_ref);

    if ($self->param('representation') eq "html"){
        $self->header_add('Content-Type' => 'text/html');
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{templates_loc}/id/$new_templateid/edit.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_templateid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $input_data_ref->{dbname}");
            $self->param('status',201); # created
            $self->param('templateid',$new_templateid);
            $self->show_record;
        }
    }

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args

    # Shared Args
    my $r              = $self->param('r');
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $templateid     = $self->strip_suffix($self->param('templateid'));

    # CGI Args
    my $numrev         = $query->param('numrev') || 3;
    
    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }
    
    $logger->debug("Show Record $templateid");

    my $templateinfo_ref = $config->get_templateinfo->search_rs({ id => $templateid})->single;

    if (!$templateinfo_ref){
        $logger->error("Template $templateid couldn't be found.");
    }
    
    my $ttdata={
        numrev       => $numrev,
        templateinfo => $templateinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_templates_record_tname},$ttdata);
}


sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $query          = $self->query();

    my $view           = $self->param('view')           || '';
    my $templateid     = $self->param('templateid')             || '';

    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    # CGI Args
    my $numrev         = $query->param('numrev');
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $templateinfo_ref = $config->get_templateinfo->search_rs({ id => $templateid})->single;

    my $all_templates_ref = {};

    foreach my $config_key (keys %$config){
        if ($config_key =~m/^tt_.+_tname/){
            $all_templates_ref->{$config->{$config_key}} = 1;
        }
    }

    my $ttdata={                # 
        numrev          => $numrev,
        templateinfo    => $templateinfo_ref,
        all_templates   => $all_templates_ref,
    };
    
    return $self->print_page($config->{tt_admin_templates_record_edit_tname},$ttdata);
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $templateid     = $self->strip_suffix($self->param('templateid'));
    my $config         = $self->param('config');

    my $templateinfo_ref = $config->get_templateinfo->search_rs({ id => $templateid})->single;
    
    my $ttdata={
        templateinfo => $templateinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_templates_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $templateid     = $self->param('templateid');
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }
    
    if (!$config->get_schema->resultset('Templateinfo')->search_rs({id => $templateid})->count){
        return $self->print_warning($msg->maketext("Es existiert kein Template unter dieser ID"));
    }

    $logger->debug("Deleting template record $templateid");
    
    $config->del_template({ id => $templateid });

    return unless ($self->param('representation') eq "html");

    $self->header_add('Content-Type' => 'text/html');
    return $self->redirect("$path_prefix/$config->{templates_loc}");
}

sub get_input_definition {
    my $self=shift;
    
    return {
        viewname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        templatename => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        templatepart => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        templatedesc => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        templatetext => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	    no_escape => 1,
        },
        templatelang => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
