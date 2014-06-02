#####################################################################
#
#  OpenBib::Handler::Apache::Users::Tags::Names.pm
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

package OpenBib::Handler::Apache::Users::Tags::Names;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest (); # internal_redirect
use Apache2::URI ();
use APR::URI ();

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
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'show_collection_form'                 => 'show_collection_form',
        'show_record'                          => 'show_record',
        'update_record'                        => 'update_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
        'dispatch_to_user'                     => 'dispatch_to_user',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub dispatch_to_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view           = $self->param('view');

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

    if (! $user->{ID}){
        return $self->tunnel_through_authenticator;            
    }
    else {
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{tags_loc}/names";
        
        return $self->redirect($new_location,'303 See Other');
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

    # CGI Args
    my $format         = $query->param('format')      || 'cloud';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        format     => $format,
        targettype => $targettype,
        username   => $username,
    };

    $self->print_page($config->{tt_users_tags_names_tname},$ttdata,$r);

    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $tagname        = $self->strip_suffix($self->param('tagname'));

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
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $offset         = $query->param('offset') || 0;
    my $num            = $query->param('num')               || 50;
    my $method         = $query->param('_method') || '';
    my $database       = $query->param('db')     || '';
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $format         = $query->param('format') || 'cloud';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $username   = $user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title;
    my $hits       = 0;

    $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));

    my $tagid = $user->get_id_of_tag({tag => $tagname});
    
    my $titles_ref;
    
    ($recordlist,$hits)= $user->get_titles_of_tag({
        tagid     => $tagid,
        offset    => $offset,
        hitrange  => $num,
        username  => $user->get_username,
    });
        
    # Zugriff loggen
    $session->log_event({
        type      => 804,
        content   => $tagname,
    });

    $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));

    $recordlist->load_brief_records;

    $recordlist->sort({order => $queryoptions->get_option('srto'), type => $queryoptions->get_option('srt')});
    
    my $ttdata = {
        sortorder        => $queryoptions->get_option('srto'),
        sorttype         => $queryoptions->get_option('srt'),
        hits             => $hits,
        offset           => $offset,
        num              => $num,

        recordlist       => $recordlist,
        query            => $query,
        tagname          => $tagname,
        tagid            => $tagid,
    };

    $self->print_page($config->{'tt_users_tags_names_record_tname'},$ttdata);

    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $query          = $self->query();
    my $view           = $self->param('view');
    my $path_prefix    = $self->param('path_prefix');
    my $lang           = $self->param('lang');
    my $msg            = $self->param('msg');
    my $user           = $self->param('user');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $queryoptions   = $self->param('queryoptions');
    
    if (! $user->{ID}){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator;            
        }
        else {
            $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
        }   

        return Apache2::Const::OK;
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{userid}  = $user->{ID};
    
    my $status = $user->rename_tag($input_data_ref);
    
    if ($status){
        $self->print_warning("Die Ersetzung des Tags konnte nicht ausgeführt werden.");
        return Apache2::Const::OK;
    }

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
    }

    return;
}

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $targettype=$user->get_targettype_of_session($session->{ID});

    # TT-Data erzeugen
    my $ttdata={
        targettype => $targettype,
    };
    
    $self->print_page($config->{tt_users_tags_record_edit_tname},$ttdata);
    return Apache2::Const::OK;
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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $path_prefix    = $self->param('path_prefix');

    my $method         = $query->param('_method') || '';

    if (! $user->{ID} | $user->{ID} ne $userid){
        if ($self->param('representation') eq "html"){
            # Aufruf-URL
            my $return_uri = uri_escape($r->parsed_uri->unparse);
            
            $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
        }
        else  {
            $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
            return Apache2::Const::OK;
        }
    }

    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{userid}  = $user->{ID};

    $self->param('userid',$user->{ID});
    
    $logger->debug("Aufnehmen/Aendern der Tags: $input_data_ref->{tags}");
        
    $user->add_tags($input_data_ref);
    
    if ($self->param('representation') eq "html"){
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{titles_loc}/database/$input_data_ref->{dbname}/id/$input_data_ref->{titleid}.html?l=$lang;no_log=1";
        
        $self->query->method('GET');
        $self->query->content_type('text/html');
        $self->query->headers_out->add(Location => $new_location);
        $self->query->status(Apache2::Const::REDIRECT);
    }
    
    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');
    my $userid         = $self->param('userid');
    my $tagid          = $self->param('tagid');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $path_prefix    = $self->param('path_prefix');
    
    if (! $user->{ID} || $user->{ID} ne $userid){
        if ($self->param('representation') eq "html"){
            # Aufruf-URL
            my $return_uri = uri_escape($r->parsed_uri->unparse);
            
            $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
        }
        else  {
            $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
            return Apache2::Const::OK;
        }
    }

    my $del_args_ref = {
        titleid   => $titleid,
        dbname    => $database,
        userid    => $userid,
    };

    if ($tagid){
        $del_args_ref->{tagid} = $tagid;
    }
    
    $user->del_tags($del_args_ref);

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{titles_loc}/database/$database/id/$titleid.html?l=$lang;no_log=1";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');
    
    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{tags_loc}/names.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        from => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        to => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
