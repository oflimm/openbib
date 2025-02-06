#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Tags.pm
#
#  Copyright 2007-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::Tags;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Users';

sub dispatch_to_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view           = $self->param('view');

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

    if (! $user->{ID}){
        return $self->tunnel_through_authenticator;            
    }
    else {
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{tags_loc}";
        
        return $self->redirect($new_location,303);
    }

    return;
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    # CGI-Parameter

    $self->set_paging;

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $private_tags_ref = $user->get_private_tags({
        userid    => $user->{ID},
        offset    => $self->stash('offset'),
        sortorder => $queryoptions->get_option('srto'),
        sorttype  => $queryoptions->get_option('srt'),
        num       => $self->stash('num')
    });

    my $total_count = $user->get_number_of_private_tags({ userid => $user->{ID} });
    
    my $nav = Data::Pageset->new({
        'total_entries'    => $total_count,
        'entries_per_page' => $self->stash('num'),
        'current_page'     => $self->stash('page'),
        'mode'             => 'slide',
    });

    my $username   = $user->get_username();
    
    # TT-Data erzeugen
    my $ttdata={
        username      => $username,
        hits          => $total_count,
        nav           => $nav,
        private_tags  => $private_tags_ref,
    };
    
    return $self->print_page($config->{tt_users_tags_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $tagid          = $self->strip_suffix($self->param('tagid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $representation = $self->stash('representation');
    my $content_type   = $self->stash('content_type');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my $database       = $query->stash('db')     || '';
    my $sorttype       = $query->stash('srt')    || "person";
    my $sortorder      = $query->stash('srto')   || "asc";
    my $format         = $query->stash('format') || 'cloud';

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $username   = $user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title;
    my $hits       = 0;

    my $tag        = undef;
    
    if ($tagid =~ /^\d+$/){
        # Zuerst Gesamtzahl bestimmen
        $tag = $user->get_name_of_tag({tagid => $tagid});
    }
    
    my $titles_ref;

    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');

    ($recordlist,$hits)= $user->get_titles_of_tag({
        username  => $username,
        offset    => $offset,
        hitrange  => $queryoptions->get_option('num'),
        sortorder => $queryoptions->get_option('srto'),
        sorttype  => $queryoptions->get_option('srt'),
    });

    my $nav = Data::Pageset->new({
        'total_entries'    => $hits,
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });

    # Zugriff loggen
    $session->log_event({
        type      => 804,
        content   => $tag,
    });
    
    if ($logger->is_debug){
        $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
        $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
    }

    my $ttdata = {
        nav              => $nav,
        sortorder        => $queryoptions->get_option('srto'),
        sorttype         => $queryoptions->get_option('srt'),
        hits             => $hits,
        offset           => $offset,
        num              => $queryoptions->get_option('num'),

        recordlist       => $recordlist,
        query            => $query,
        tagname          => $tag,
        tagid            => $tagid,
    };

    return $self->print_page($config->{'tt_users_tags_record_tname'},$ttdata);
}

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $representation = $self->stash('representation');
    my $content_type   = $self->stash('content_type');
    my $path_prefix    = $self->stash('path_prefix');

    if (! $user->{ID}){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else {
            return $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
        }   
    }

    my $targettype=$user->get_targettype_of_session($session->{ID});

    # TT-Data erzeugen
    my $ttdata={
        targettype => $targettype,
    };
    
    return $self->print_page($config->{tt_users_tags_record_edit_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');
    my $userid         = $self->param('userid');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $path_prefix    = $self->stash('path_prefix');

    if (! $user->{ID}){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else {
            return $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
        }   
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{userid}  = $user->{ID};

    $self->stash('userid',$user->{ID});
    
    $logger->debug("Aufnehmen/Aendern der Tags: $input_data_ref->{tags}");
        
    $user->add_tags($input_data_ref);
    
    if ($self->stash('representation') eq "html"){
        if ($query->stash('redirect_to')){
            my $new_location = uri_unescape($query->stash('redirect_to'));
            return $self->redirect($new_location,303);
        }
        else {
            $self->return_baseurl;
        }
    }
    
    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $tagid          = $self->param('tagid');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $path_prefix    = $self->stash('path_prefix');

    if (! $user->{ID}){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else {
            return $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
        }   
    }

    if ($tagid && $user->{ID}){
        $user->del_tag({ tagid => $tagid, userid => $user->{ID}});
    }

    if ($self->stash('representation') eq "html"){
        if ($query->stash('redirect_to')){
            my $new_location = $query->stash('redirect_to');

            # TODO: Get?
            $self->header_add('Content-Type','text/html');
            $self->redirect($new_location);
        }
        else {
            return $self->return_baseurl;
        }
    }

    return;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->stash('view')           || '';
    my $userid         = $self->stash('userid')         || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    
    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{tags_loc}.html";

    # TODO: Get?
    $self->header_add('Content-Type','text/html');
    return $self->redirect($new_location);
}

sub get_input_definition {
    my $self=shift;
    
    return {
        tags => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        dbname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        titleid => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        type => {
            default  => '1',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
