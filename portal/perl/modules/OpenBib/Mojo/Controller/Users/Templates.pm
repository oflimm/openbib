####################################################################
#
#  OpenBib::Mojo::Controller::Users::Templates.pm
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

package OpenBib::Mojo::Controller::Users::Templates;

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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $usertemplates = $user->get_templates_of_user($user->{ID});

    my $ttdata={
        usertemplates   => $usertemplates,
        userid          => $user->{ID},
    };
    
    return $self->print_page($config->{tt_users_templates_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $templateid     = $self->param('templateid')     || '';

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');

    # CGI Args
    my $numrev         = $r->param('numrev');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
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
    
    return $self->print_page($config->{tt_users_templates_record_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    
    my $view           = $self->stash('view')           || '';
    my $templateid     = $self->stash('templateid')     || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');
    my $user           = $self->stash('user');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{id} = $templateid; # templateid wird durch Resourcenbestandteil ueberschrieben
    
    if ($logger->is_debug){
        $logger->debug("Info: ".YAML::Dump($input_data_ref));
    }

    if (!$config->get_schema->resultset('Templateinfo')->search_rs({id => $templateid})->count){
        return $self->print_warning($msg->maketext("Es existiert kein Template unter dieser ID"));
    }

    $logger->debug("Admin? ".$user->is_admin);
    $logger->debug("User->ID? ".$user->{ID});
    $logger->debug("Has Template?".$user->has_template($templateid));
    
    if (!$user->is_admin && !$user->has_template($templateid)){
        return $self->print_warning($msg->maketext("Sie haben keine Berechtigung dieses Template zu ändern!"));
    }
    
    $config->update_template($input_data_ref);

    if ($self->stash('representation') eq "html"){
        $self->header_add('Content-Type','text/html');

        if ($user->is_admin){ 
            return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{templates_loc}");
        }
        else {
            return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{templates_loc}");
        }       
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

    my $user               = $self->stash('user');    
    my $basic_auth_failure = $self->stash('basic_auth_failure') || 0;
    my $userid             = $self->stash('userid')             || $user->{ID} || '';

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
            default   => '',
            encoding  => 'none',
            type      => 'scalar',
	    no_escape => 1,
        },
    };
}

1;
