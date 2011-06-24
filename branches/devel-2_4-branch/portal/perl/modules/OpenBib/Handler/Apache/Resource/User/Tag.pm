#####################################################################
#
#  OpenBib::Handler::Apache::Resource::User::Tag.pm
#
#  Copyright 2007-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::User::Tag;

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

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'show_collection_form'                 => 'show_collection_form',
        'show_record'                          => 'show_record',
        'create_record'                        => 'create_record',
        'update_record'                        => 'update_record',
        'delete_record'                        => 'delete_record',
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

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    my $loginname  = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        format     => $format,
        targettype => $targettype,
        loginname  => $loginname,
    };

    $self->print_page($config->{tt_resource_user_tag_collection_tname},$ttdata,$r);

    return Apache2::Const::OK;
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
    my $hitrange       = $query->param('num')    || 50;
    my $database       = $query->param('db')     || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
    my $format         = $query->param('format') || 'cloud';

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    my $loginname = $user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title;
    my $hits       = 0;

    my $tag        = undef;
    
    if ($tagid =~ /^\d+$/){
        # Zuerst Gesamtzahl bestimmen
        $tag = $user->get_name_of_tag({tagid => $tagid});
    }
    
    my $titles_ref;
    
    ($recordlist,$hits)= $user->get_titles_of_tag({
        loginname => $loginname,
        tagid     => $tagid,
        offset    => $offset,
        hitrange  => $hitrange,
    });
        
    # Zugriff loggen
    $session->log_event({
        type      => 804,
        content   => $tag,
    });
    
    $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
    
    $recordlist->print_to_handler({
        representation   => $representation,
        content_type     => $content_type,
        database         => $database,
        sortorder        => $sortorder,
        sorttype         => $sorttype,
        apachereq        => $r,
        stylesheet       => $stylesheet,
        view             => $view,
        hits             => $hits,
        offset           => $offset,
        hitrange         => $hitrange,
        query            => $query,
        template         => 'tt_resource_user_tag_tname',
        location         => 'resource_user_loc',
        parameter        => {
            loginname    => $loginname,
            tag          => $tag,
            private_tags => 1,
        },
        
        msg              => $msg,
    });

    return Apache2::Const::OK;
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

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    my $targettype=$user->get_targettype_of_session($session->{ID});

    # TT-Data erzeugen
    my $ttdata={
        targettype => $targettype,
    };
    
    $self->print_page($config->{tt_resource_user_tag_edit_tname},$ttdata);
    return Apache2::Const::OK;
}

sub showyyy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });    

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('num')    || 50;
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $tags           = decode_utf8($query->param('tags'))        || '';
    my $type           = $query->param('type')        || 1;

    my $oldtag         = $query->param('oldtag')      || '';
    my $newtag         = $query->param('newtag')      || '';
    
    # Actions
    my $format         = $query->param('format')      || 'cloud';
    my $private_tags   = $query->param('private_tags')   || 0;
    my $searchtitoftag = $query->param('searchtitoftag') || '';
    my $edit_usertags  = $query->param('edit_usertags')  || '';
    my $show_usertags  = $query->param('show_usertags')  || '';

    my $queryid        = $query->param('queryid')     || '';

    my $do_add         = $query->param('do_add')      || '';
    my $do_edit        = $query->param('do_edit')     || '';
    my $do_change      = $query->param('do_change')   || '';
    my $do_del         = $query->param('do_del')      || '';
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    unless($user->{ID} || $searchtitoftag){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}");

        return Apache2::Const::OK;
    }

    my $loginname = $user->get_username();
    
    if ($do_add && $user->{ID}){

        $logger->debug("Aufnehmen/Aendern der Tags: $tags");
        
        $user->add_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
            type      => $type,
        });

        $r->internal_redirect("$config->{base_loc}/$view/$config->{search_loc}?db=$titdb;fs=id:$titid;no_log=1");
        return Apache2::Const::OK;
    }
    elsif ($do_del && $user->{ID}){

        $logger->debug("Loeschen der Tags $tags von $titdb:$titid");
        
        $user->del_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
        });

        if ($tags =~/^\w+$/){
            my $tagid = $user->get_id_of_tag({tag => $tags});
            $r->internal_redirect("$config->{base_loc}/$view/$config->{tags_loc}?searchtitoftag=$tagid;private_tags=1");
        }
        else {
            $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{search_loc}?db=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        }
        return Apache2::Const::OK;

    }
    elsif ($do_change && $user->{ID}){
        
        $logger->debug("Aendern des Tags $oldtag in $newtag");
        
        my $status = $user->rename_tag({
            oldtag    => $oldtag,
            newtag    => $newtag,
            loginname => $loginname,
        });

        if ($status){
            OpenBib::Common::Util::print_warning("Die Ersetzung des Tags konnte nicht ausgeführt werden.",$r,$msg);
            return Apache2::Const::OK;
        }
        
        $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{tags_loc}?show_usertags=1");
        return Apache2::Const::OK;

    }
    
    if ($edit_usertags && $user->{ID}){

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            targettype => $targettype,
            loginname  => $loginname,
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_tags_editusertags_tname},$ttdata,$r);
    }

    if ($show_usertags && $user->{ID}){

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            format     => $format,
            targettype => $targettype,
            loginname  => $loginname,
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_tags_showusertags_tname},$ttdata,$r);
    }
    
    if ($searchtitoftag) {
        my $recordlist = new OpenBib::RecordList::Title;
        my $hits       = 0;
        my $tag        = undef;
        
        if ($searchtitoftag =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            $tag = $user->get_name_of_tag({tagid => $searchtitoftag});
            
            if ($private_tags){
                if (!$user->{ID}){
                    OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
                    return Apache2::Const::OK;
                }

                my $titles_ref;

                ($recordlist,$hits)= $user->get_titles_of_tag({
                    loginname => $loginname,
                    tagid     => $searchtitoftag,
                    offset    => $offset,
                    hitrange  => $hitrange,
                });
            }
            else {
                ($recordlist,$hits)= $user->get_titles_of_tag({
                    tagid     => $searchtitoftag,
                    database  => $database,
                    offset    => $offset,
                    hitrange  => $hitrange,
                });
            }

            # Zugriff loggen
            $session->log_event({
		type      => 804,
                content   => $tag,
            });

        }

        $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
        
        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,

            query            => $query,
            template         => 'tt_tags_showtitlist_tname',
            location         => 'tags_loc',
            parameter        => {
                loginname    => $loginname,
                tag          => $tag,
                private_tags => $private_tags,
            },

            msg              => $msg,
        });
    }

    return Apache2::Const::OK;
}

sub showyyy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });    

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('num')    || 50;
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $tags           = decode_utf8($query->param('tags'))        || '';
    my $type           = $query->param('type')        || 1;

    my $oldtag         = $query->param('oldtag')      || '';
    my $newtag         = $query->param('newtag')      || '';
    
    # Actions
    my $format         = $query->param('format')      || 'format';
    my $private_tags   = $query->param('private_tags')   || 0;
    my $searchtitoftag = $query->param('searchtitoftag') || '';
    my $edit_usertags  = $query->param('edit_usertags')  || '';
    my $show_usertags  = $query->param('show_usertags')  || '';

    my $queryid        = $query->param('queryid')     || '';

    my $do_add         = $query->param('do_add')      || '';
    my $do_edit        = $query->param('do_edit')     || '';
    my $do_change      = $query->param('do_change')   || '';
    my $do_del         = $query->param('do_del')      || '';
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    unless($user->{ID} || $searchtitoftag){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{login_loc}?do_login=1");

        return Apache2::Const::OK;
    }

    my $loginname = $user->get_username();
    
    if ($do_add && $user->{ID}){

        $logger->debug("Aufnehmen/Aendern der Tags: $tags");
        
        $user->add_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
            type      => $type,
        });

        $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{search_loc}?db=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        return Apache2::Const::OK;
    }
    elsif ($do_del && $user->{ID}){

        $logger->debug("Loeschen der Tags $tags von $titdb:$titid");
        
        $user->del_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
        });

        if ($tags =~/^\w+$/){
            my $tagid = $user->get_id_of_tag({tag => $tags});
            $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{tags_loc}?searchtitoftag=$tagid;private_tags=1");
        }
        else {
            $r->internal_redirect("http://$r->get_server_name$self->param('path_prefix')/$config->{search_loc}?db=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        }
        return Apache2::Const::OK;

    }
    elsif ($do_change && $user->{ID}){
        
        $logger->debug("Aendern des Tags $oldtag in $newtag");
        
        my $status = $user->rename_tag({
            oldtag    => $oldtag,
            newtag    => $newtag,
            loginname => $loginname,
        });

        if ($status){
            OpenBib::Common::Util::print_warning("Die Ersetzung des Tags konnte nicht ausgeführt werden.",$r,$msg);
            return Apache2::Const::OK;
        }
        
        $r->internal_redirect("http://$r->get_server_name$self->param('path_prefix')/$config->{tags_loc}?show_usertags=1");
        return Apache2::Const::OK;

    }
    
    if ($edit_usertags && $user->{ID}){

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            targettype => $targettype,
            loginname  => $loginname,
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_tags_editusertags_tname},$ttdata,$r);
    }

    if ($show_usertags && $user->{ID}){

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            format     => $format,
            targettype => $targettype,
            loginname  => $loginname,
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_tags_showusertags_tname},$ttdata,$r);
    }
    
    if ($searchtitoftag) {
        my $recordlist = new OpenBib::RecordList::Title;
        my $hits       = 0;
        my $tag        = undef;
        
        if ($searchtitoftag =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            $tag = $user->get_name_of_tag({tagid => $searchtitoftag});
            
            if ($private_tags){
                if (!$user->{ID}){
                    OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
                    return Apache2::Const::OK;
                }

                my $titles_ref;

                ($recordlist,$hits)= $user->get_titles_of_tag({
                    loginname => $loginname,
                    tagid     => $searchtitoftag,
                    offset    => $offset,
                    hitrange  => $hitrange,
                });
            }
            else {
                ($recordlist,$hits)= $user->get_titles_of_tag({
                    tagid     => $searchtitoftag,
                    database  => $database,
                    offset    => $offset,
                    hitrange  => $hitrange,
                });
            }

            # Zugriff loggen
            $session->log_event({
		type      => 804,
                content   => $tag,
            });

        }

        $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
        
        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,

            query            => $query,
            template         => 'tt_tags_showtitlist_tname',
            location         => 'tags_loc',
            parameter        => {
                loginname    => $loginname,
                tag          => $tag,
                private_tags => $private_tags,
            },

            msg              => $msg,
        });
    }

    return Apache2::Const::OK;
}

sub showzzz {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });    

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('num')    || 50;
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $tags           = decode_utf8($query->param('tags'))        || '';
    my $type           = $query->param('type')        || 1;

    my $oldtag         = $query->param('oldtag')      || '';
    my $newtag         = $query->param('newtag')      || '';
    
    # Actions
    my $format         = $query->param('format')      || 'format';
    my $private_tags   = $query->param('private_tags')   || 0;
    my $searchtitoftag = $query->param('searchtitoftag') || '';
    my $edit_usertags  = $query->param('edit_usertags')  || '';
    my $show_usertags  = $query->param('show_usertags')  || '';

    my $queryid        = $query->param('queryid')     || '';

    my $do_add         = $query->param('do_add')      || '';
    my $do_edit        = $query->param('do_edit')     || '';
    my $do_change      = $query->param('do_change')   || '';
    my $do_del         = $query->param('do_del')      || '';
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    unless($user->{ID} || $searchtitoftag){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        $r->internal_redirect("http://$r->get_server_name$self->param('path_prefix')/$config->{login_loc}?do_login=1");

        return Apache2::Const::OK;
    }

    my $loginname = $user->get_username();
    
    if ($do_add && $user->{ID}){

        $logger->debug("Aufnehmen/Aendern der Tags: $tags");
        
        $user->add_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
            type      => $type,
        });

        $r->internal_redirect("http://$r->get_server_name$self->param('path_prefix')/$config->{search_loc}?db=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        return Apache2::Const::OK;
    }
    elsif ($do_del && $user->{ID}){

        $logger->debug("Loeschen der Tags $tags von $titdb:$titid");
        
        $user->del_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
        });

        if ($tags =~/^\w+$/){
            my $tagid = $user->get_id_of_tag({tag => $tags});
            $r->internal_redirect("http://$r->get_server_name$self->param('path_prefix')/$config->{tags_loc}?searchtitoftag=$tagid;private_tags=1");
        }
        else {
            $r->internal_redirect("http://$r->get_server_name$self->param('path_prefix')/$config->{search_loc}?db=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        }
        return Apache2::Const::OK;

    }
    elsif ($do_change && $user->{ID}){
        
        $logger->debug("Aendern des Tags $oldtag in $newtag");
        
        my $status = $user->rename_tag({
            oldtag    => $oldtag,
            newtag    => $newtag,
            loginname => $loginname,
        });

        if ($status){
            OpenBib::Common::Util::print_warning("Die Ersetzung des Tags konnte nicht ausgeführt werden.",$r,$msg);
            return Apache2::Const::OK;
        }
        
        $r->internal_redirect("http://$r->get_server_name$self->param('path_prefix')/$config->{tags_loc}?show_usertags=1");
        return Apache2::Const::OK;

    }
    
    if ($edit_usertags && $user->{ID}){

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            targettype => $targettype,
            loginname  => $loginname,
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_tags_editusertags_tname},$ttdata,$r);
    }

    if ($show_usertags && $user->{ID}){

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            format     => $format,
            targettype => $targettype,
            loginname  => $loginname,
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_tags_showusertags_tname},$ttdata,$r);
    }
    
    if ($searchtitoftag) {
        my $recordlist = new OpenBib::RecordList::Title;
        my $hits       = 0;
        my $tag        = undef;
        
        if ($searchtitoftag =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            $tag = $user->get_name_of_tag({tagid => $searchtitoftag});
            
            if ($private_tags){
                if (!$user->{ID}){
                    OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
                    return Apache2::Const::OK;
                }

                my $titles_ref;

                ($recordlist,$hits)= $user->get_titles_of_tag({
                    loginname => $loginname,
                    tagid     => $searchtitoftag,
                    offset    => $offset,
                    hitrange  => $hitrange,
                });
            }
            else {
                ($recordlist,$hits)= $user->get_titles_of_tag({
                    tagid     => $searchtitoftag,
                    database  => $database,
                    offset    => $offset,
                    hitrange  => $hitrange,
                });
            }

            # Zugriff loggen
            $session->log_event({
		type      => 804,
                content   => $tag,
            });

        }

        $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
        
        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,

            query            => $query,
            template         => 'tt_tags_showtitlist_tname',
            location         => 'tags_loc',
            parameter        => {
                loginname    => $loginname,
                tag          => $tag,
                private_tags => $private_tags,
            },

            msg              => $msg,
        });
    }

    return Apache2::Const::OK;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{resource_user_loc}/$userid/tag.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
