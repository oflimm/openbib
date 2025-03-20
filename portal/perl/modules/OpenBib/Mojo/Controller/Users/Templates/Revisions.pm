####################################################################
#
#  OpenBib::Mojo::Controller::Users::Templates::Revisions.pm
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

package OpenBib::Mojo::Controller::Users::Templates::Revisions;

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

use base 'OpenBib::Mojo::Controller::Users';

sub revert_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $templateid     = $self->param('templateid');
    my $revisionid     = $self->param('revisionid');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');
    my $user           = $self->stash('user');
    my $lang           = $self->stash('lang');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $revision = $config->get_templateinforevision->search(
        {
            id => $revisionid,
        }
    )->single;

    if (!$user->is_admin && !$user->has_template($templateid)){
        return $self->print_warning($msg->maketext("Sie haben keine Berechtigung dieses Template zu ändern!"));
    }
    
    my $input_data_ref = {};

    $input_data_ref->{id} = $templateid; # templateid wird durch Resourcenbestandteil ueberschrieben
    
    if ($revision){
        $input_data_ref->{templatetext} = $revision->templatetext;
    }
    else {
        return $self->print_warning($msg->maketext("Es existiert keine Revision mit dieser ID"));
    }   
    
    $config->update_template($input_data_ref);

    if ($self->stash('representation') eq "html"){
        $self->res->headers->content_type('text/html');
        
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
        $self->res->headers->content_type('text/html');

        return $self->redirect("$path_prefix/$config->{templates_loc}/id/$templateid");
    }
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $templateid     = $self->stash('templateid');
    my $revisionid     = $self->stash('revisionid');
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    if (!$config->get_templateinforevision->search_rs({id => $revisionid})->count){
        return $self->print_warning($msg->maketext("Es existiert keine Template-Revision mit dieser ID"));
    }

    $logger->debug("Deleting revision record $revisionid");
    
    $config->del_templaterevision({ id => $revisionid });

    return unless ($self->stash('representation') eq "html");
    
    $self->res->headers->content_type('text/html');
    
    if ($user->is_admin){
        
        return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{templates_loc}/id/${templateid}/edit");
    }
    else {
        return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{templates_loc}/id/${templateid}/edit");
    }       
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $templateid     = $self->stash('templateid');
    my $revisionid     = $self->strip_suffix($self->stash('revisionid'));
    my $config         = $self->stash('config');

    my $revision_ref   = $config->get_templateinforevision->search_rs({ id => $revisionid})->single;
    
    my $ttdata={
        templateid => $templateid,
        revisionid => $revisionid,
        revision   => $revision_ref,
    };
    
    $logger->debug("Asking for confirmation");
    return $self->print_page($config->{tt_templates_revisions_record_delete_confirm_tname},$ttdata);
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

1;
