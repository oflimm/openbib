####################################################################
#
#  OpenBib::Handler::Apache::Users::Templates.pm
#
#  Copyright 2014 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Users::Templates;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Reload;
use Apache2::Request;
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
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'            => 'show_collection',
        'show_record_form'           => 'show_record_form',
        'update_record'              => 'update_record',
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
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $usertemplates = $user->get_templates_of_user($user->{ID});

    my $ttdata={
        usertemplates   => $usertemplates,
        userid          => $user->{ID},
    };
    
    $self->print_page($config->{tt_users_templates_tname},$ttdata);

    return Apache2::Const::OK;
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
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');

    # CGI Args
    my $numrev         = $query->param('numrev');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $templateinfo_ref = $config->get_templateinfo->search_rs(
        {
            'me.id' => $templateid,
            'user_templates.userid' => $user->{ID},
        },
        {
            join => ['user_templates'],
        }
    )->single;

    my $ttdata = {
        numrev       => $numrev,
        templateinfo => $templateinfo_ref,
    };
    
    $self->print_page($config->{tt_users_templates_record_edit_tname},$ttdata);
        
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $query          = $self->query();
    
    my $view           = $self->param('view')           || '';
    my $templateid     = $self->param('templateid')     || '';
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{id} = $templateid; # templateid wird durch Resourcenbestandteil ueberschrieben
    
    if ($logger->is_debug){
        $logger->debug("Info: ".YAML::Dump($input_data_ref));
    }

    if (!$config->{schema}->resultset('Templateinfo')->search_rs({id => $templateid})->count){
        $self->print_warning($msg->maketext("Es existiert kein Template unter dieser ID"));
        
        return Apache2::Const::OK;
    }

    $logger->debug("Admin? ".$user->is_admin);
    $logger->debug("User->ID? ".$user->{ID});
    $logger->debug("Has Template?".$user->has_template($templateid));
    
    if (!$user->is_admin && !$user->has_template($templateid)){
        $self->print_warning($msg->maketext("Sie haben keine Berechtigung dieses Template zu ändern!"));
        return Apache2::Const::OK;
    }
    
    $config->update_template($input_data_ref);

    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        if ($user->is_admin){ 
            $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_loc}/$config->{templates_loc}");
        }
        else {
            $self->query->headers_out->add(Location => "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{templates_loc}");
        }       
        
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        $logger->debug("Weiter zur ID $templateid");
        $self->show_record;
    }
    
    return;
}

sub authorization_successful {
    my $self   = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $user               = $self->param('user');    
    my $basic_auth_failure = $self->param('basic_auth_failure') || 0;
    my $userid             = $self->param('userid')             || $user->{ID} || '';

    $logger->debug("Basic http auth failure: $basic_auth_failure / Userid: $userid ");


    
    if ($basic_auth_failure || !$userid || (!$self->is_authenticated('user',$userid) && !$self->is_authenticated('admin'))){
        return 0;
    }

    return 1;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        templatetext => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
