#####################################################################
#
#  OpenBib::Handler::Apache::Title::Tag.pm
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

package OpenBib::Handler::Apache::Title::Tag;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common REDIRECT);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use CGI::Application::Plugin::Redirect;
use Log::Log4perl qw(get_logger :levels);
use Date::Manip;
use URI::Escape qw(uri_escape uri_escape_utf8);
use Encode 'decode_utf8';

use OpenBib::Catalog;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Util;
use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'create_record'           => 'create_record',
        'update_record'           => 'update_record',
        'delete_record'           => 'delete_record',
        'show_record'             => 'show_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');
    my $userid         = $self->param('userid');
    my $tagid          = $self->strip_suffix($self->param('tagid'));

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
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');

    # CGI Args
    my $method         = $query->param('_method')     || '';
    
    my $offset         = $query->param('offset')            || 0;
    my $num            = $query->param('num')               || 50;
    $titleid          = $query->param('titleid')             || '';
    my $dbname          = $query->param('dbname')             || '';
    my $titisbn        = $query->param('titisbn')           || '';
    my $tags           = decode_utf8($query->param('tags')) || '';
    my $type           = $query->param('type')              || 1;

    my $oldtag         = $query->param('oldtag')            || '';
    my $newtag         = $query->param('newtag')            || '';
    
    # Actions
    my $format         = $query->param('format')            || 'cloud';
    my $private_tags   = $query->param('private_tags')      || 0;
    my $searchtitoftag = $query->param('searchtitoftag')    || '';
    my $edit_usertags  = $query->param('edit_usertags')     || '';
    my $show_usertags  = $query->param('show_usertags')     || '';

    my $queryid        = $query->param('queryid')           || '';

    my $do_add         = $query->param('do_add')            || '';
    my $do_edit        = $query->param('do_edit')           || '';
    my $do_change      = $query->param('do_change')         || '';
    my $do_del         = $query->param('do_del')            || '';
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    if ($method){

        $logger->debug("userID: ".$user->{ID}." userid:$userid");
        
        if (! $user->{ID} || ($userid &&  $user->{ID} ne $userid)){

            $logger->debug("Redirecting to login page");
            
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
                
        if ($method eq "POST"){
            $self->create_record;
        }

        if ($method eq "PUT"){
            $self->update_record;
        }
        
        if ($method eq "DELETE"){
            $self->delete_record;

        }

        
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{titles_loc}/database/$database/id/$titleid.html?l=$lang;no_log=1";

        $logger->debug("Redirecting to $new_location");

        $self->query->method('GET');
        $self->query->content_type('text/html');
        $self->query->headers_out->add(Location => $new_location);
        $self->query->status(Apache2::Const::REDIRECT);

        return;
    }
    
    my $recordlist = new OpenBib::RecordList::Title;
    my $hits       = 0;

    # Mit Suffix, dann keine Aushandlung des Typs

    my $tag        = undef;

    # Tags per id
    if ($tagid =~ /^\d+$/){
        # Zuerst Gesamtzahl bestimmen
        $tag = $user->get_name_of_tag({tagid => $tagid});
    }
    # Tags per name
    else {
        $tag = $tagid;

        $tagid = $user->get_id_of_tag({tag => $tag});
    }
    
    my $titles_ref;
    
    ($recordlist,$hits)= $user->get_titles_of_tag({
        tagid     => $tagid,
        offset    => $offset,
        hitrange  => $num,
    });
        
    # Zugriff loggen
    $session->log_event({
        type      => 804,
        content   => $tag,
    });

    if ($logger->is_debug){
        $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
    }

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
        tag              => $tag,
        tagid            => $tagid,
    };

    $self->print_page($config->{'tt_tags_tname'},$ttdata);
    
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

    # CGI Args
    my $method         = $query->param('_method')     || '';
    
    if (! $user->{ID}){
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{userid}  = $user->{ID};
    $input_data_ref->{titleid} = $titleid;
    $input_data_ref->{dbname}  = $database;

    $self->param('userid',$user->{ID});
    
    $logger->debug("Aufnehmen/Aendern der Tags: $input_data_ref->{tags}");
        
    $user->add_tags($input_data_ref);

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{titles_loc}/database/$input_data_ref->{dbname}/id/$input_data_ref->{titleid}.html?l=$lang;no_log=1";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

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
    
    if (! $user->{ID}){
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
        userid    => $user->{ID},
    };

    if ($tagid){
        $del_args_ref->{tagid} = $tagid;
    }
    
    $user->del_tags($del_args_ref);

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{titles_loc}/database/$database/id/$titleid.html?l=$lang;no_log=1";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        tags => {
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
