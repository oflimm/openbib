#####################################################################
#
#  OpenBib::Mojo::Controller::Title::Tag.pm
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

package OpenBib::Mojo::Controller::Title::Tag;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);
use Date::Manip;
use URI::Escape qw(uri_escape uri_escape_utf8);
use Encode 'decode_utf8';

use OpenBib::Catalog;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Util;
use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $path_prefix    = $self->stash('path_prefix');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');

    # CGI Args
    my $method         = $query->stash('_method')     || '';
    
    my $offset         = $query->stash('offset')            || 0;
    my $num            = $query->stash('num')               || 50;
    $titleid          = $query->stash('titleid')             || '';
    my $dbname          = $query->stash('dbname')             || '';
    my $titisbn        = $query->stash('titisbn')           || '';
    my $tags           = decode_utf8($query->stash('tags')) || '';
    my $type           = $query->stash('type')              || 1;

    my $oldtag         = $query->stash('oldtag')            || '';
    my $newtag         = $query->stash('newtag')            || '';
    
    # Actions
    my $format         = $query->stash('format')            || 'cloud';
    my $private_tags   = $query->stash('private_tags')      || 0;
    my $searchtitoftag = $query->stash('searchtitoftag')    || '';
    my $edit_usertags  = $query->stash('edit_usertags')     || '';
    my $show_usertags  = $query->stash('show_usertags')     || '';

    my $queryid        = $query->stash('queryid')           || '';

    my $do_add         = $query->stash('do_add')            || '';
    my $do_edit        = $query->stash('do_edit')           || '';
    my $do_change      = $query->stash('do_change')         || '';
    my $do_del         = $query->stash('do_del')            || '';
    
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
            
            if ($self->stash('representation') eq "html"){
                # Aufruf-URL
                my $return_uri = uri_escape($r->request_uri);
                
                $self->redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");

                return;
            }
            else  {
                return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
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

        # TODO GET?
        $self->header_add('Content-Type' => 'text/html');
        $self->redirect($new_location);

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

    return $self->print_page($config->{'tt_tags_tname'},$ttdata);
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

    # CGI Args
    my $method         = $query->stash('_method')     || '';
    
    if (! $user->{ID}){
        if ($self->stash('representation') eq "html"){
            # Aufruf-URL
            my $return_uri = uri_escape($r->request_uri);
            
            return $self->redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{userid}  = $user->{ID};
    $input_data_ref->{titleid} = $titleid;
    $input_data_ref->{dbname}  = $database;

    $self->stash('userid',$user->{ID});
    
    $logger->debug("Aufnehmen/Aendern der Tags: $input_data_ref->{tags}");
        
    $user->add_tags($input_data_ref);

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{titles_loc}/database/$input_data_ref->{dbname}/id/$input_data_ref->{titleid}.html?l=$lang;no_log=1";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

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
            # Aufruf-URL
            my $return_uri = uri_escape($r->request_uri);
            
            return $self->redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
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

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

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
