#####################################################################
#
#  OpenBib::Handler::PSGI::Tags::Names.pm
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

package OpenBib::Handler::PSGI::Tags::Names;

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
use URI::Escape;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use DBI;
use JSON::XS;
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

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'show_collection_recent'               => 'show_collection_recent',
        'show_record'                          => 'show_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
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

    # CGI-Parameter

    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');
    my $num    = $queryoptions->get_option('num');

    my $tags_ref = $user->get_public_tags_by_name({offset => $offset, num => $num});

    my $nav = Data::Pageset->new({
        'total_entries'    => $tags_ref->{count},
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });

    # TT-Data erzeugen
    my $ttdata={
        total_count   => $tags_ref->{count},
        nav           => $nav,
        public_tags   => $tags_ref->{tags},
    };
    
    $self->print_page($config->{tt_tags_names_tname},$ttdata);

    return Apache2::Const::OK;
}

sub show_collection_recent {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
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

    # CGI-Parameter
    my $num  = $query->param('num') || 20;

    my $recent_tags_ref = $user->get_recent_tags_by_name({count => $num});

    # TT-Data erzeugen
    my $ttdata={
        recent_tags   => $recent_tags_ref,
    };
    
    $self->print_page($config->{tt_tags_names_recent_tname},$ttdata);

    return Apache2::Const::OK;
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
    my $tagname        = $self->strip_suffix($self->param('tagname'));

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

        if (! $user->{ID} || ($userid &&  $user->{ID} ne $userid)){
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
        
        $self->query->method('GET');
        $self->query->content_type('text/html');
        $self->query->headers_out->add(Location => $new_location);
        $self->query->status(Apache2::Const::REDIRECT);        

        return;
    }
    
    my $recordlist = new OpenBib::RecordList::Title;
    my $hits       = 0;

    my $tagid = $user->get_id_of_tag({tag => $tagname});
    
    my $titles_ref;
    
    ($recordlist,$hits)= $user->get_titles_of_tag({
        tagid     => $tagid,
        offset    => $offset,
        hitrange  => $num,
    });
        
    # Zugriff loggen
    $session->log_event({
        type      => 804,
        content   => $tagname,
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
        tagname          => $tagname,
        tagid            => $tagid,
    };

    $self->print_page($config->{'tt_tags_names_record_tname'},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_collection_form {
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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    unless($user->{ID}){
        # Aufruf-URL
        my $return_uri = uri_escape($r->parsed_uri->unparse);

        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?do_login=1;redirect_to=$return_uri");

        return Apache2::Const::OK;
    }

    my $targettype=$user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        targettype => $targettype,
        user       => $user,
        config     => $config,
        user       => $user,
        msg        => $msg,
    };
    $self->print_page($config->{tt_users_tags_edit_tname},$ttdata);
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

sub update_record {
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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    unless($user->{ID}){
        # Aufruf-URL
        my $return_uri = uri_escape($r->parsed_uri->unparse);

        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");

        return Apache2::Const::OK;
    }

    my $username = $user->get_username();

    $logger->debug("Aendern des Tags $oldtag in $newtag");
    
    my $status = $user->rename_tag({
        oldtag    => $oldtag,
        newtag    => $newtag,
        username  => $username,
    });
    
    if ($status){
        $self->print_warning("Die Ersetzung des Tags konnte nicht ausgeführt werden.");
        return Apache2::Const::OK;
    }

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/tag.html";
    
    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

# # Alle oeffentlichen Literaturlisten
# sub show_collection_recent {
#     my $self = shift;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     # Dispatched Args
#     my $view           = $self->param('view');
#     my $database       = $self->param('database');

#     # Shared Args
#     my $query          = $self->query();
#     my $r              = $self->param('r');
#     my $config         = $self->param('config');
#     my $session        = $self->param('session');
#     my $user           = $self->param('user');
#     my $msg            = $self->param('msg');
#     my $queryoptions   = $self->param('qopts');
#     my $stylesheet     = $self->param('stylesheet');
#     my $useragent      = $self->param('useragent');
#     my $representation = $self->param('representation');

#     # CGI Args
#     my $hitrange       = $query->param('num')    || 50;

#     my @viewdbs         = $config->get_viewdbs($view);

#     # Tag-Cloud ist View-abhaengig. Wenn View nur aus einer Datenbank besteht, dann werden alle Tags fuer Titel aus der Datenbank herausgegeben, sonst alle.
#     # ToDo: fuer alle Datenbanken eines Views, d.h. auch bei mehr als einer...
#     my $recent_tags_ref = ($database)?$user->get_recent_tags({ count => $hitrange, database => $database }):
#         ($#viewdbs == 0)?$user->get_recent_tags({ count => $hitrange, database => $viewdbs[0] }): $user->get_recent_tags({ count => $hitrange });

#     # TT-Data erzeugen
#     my $ttdata={
#         recent_tags    => $recent_tags_ref,
#     };
    
#     $self->print_page($config->{tt_tags_collection_recent_tname},$ttdata);
#     return Apache2::Const::OK;
# }

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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    unless($user->{ID} || $searchtitoftag){
        # Aufruf-URL
        my $return_uri = uri_escape($r->parsed_uri->unparse);

        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?do_login=1;redirect_to=$return_uri");

        return Apache2::Const::OK;
    }

    my $username = $user->get_username();
    
    if ($do_add && $user->{ID}){

        $logger->debug("Aufnehmen/Aendern der Tags: $tags");
        
        $user->add_tags({
            tags      => $tags,
            titleid   => $titleid,
            dbname    => $dbname,
            userid    => $user->{ID},
            type      => $type,
        });

        $r->internal_redirect("$config->{base_loc}/$view/$config->{search_loc}?db=$dbname;searchsingletit=$titleid;queryid=$queryid;no_log=1");
        return Apache2::Const::OK;
    }
    elsif ($do_del && $user->{ID}){

        $logger->debug("Loeschen der Tags $tags von $dbname:$titleid");
        
        $user->del_tags({
            tags      => $tags,
            titleid     => $titleid,
            dbname     => $dbname,
            username  => $username,
        });

        if ($tags =~/^\w+$/){
            my $tagid = $user->get_id_of_tag({tag => $tags});
            $r->internal_redirect("$config->{base_loc}/$view/$config->{tags_loc}?searchtitoftag=$tagid;private_tags=1");
        }
        else {
            $r->internal_redirect("$config->{base_loc}/$view/$config->{search_loc}?db=$dbname;searchsingletit=$titleid;queryid=$queryid;no_log=1");
        }
        return Apache2::Const::OK;

    }
    elsif ($do_change && $user->{ID}){
        
        $logger->debug("Aendern des Tags $oldtag in $newtag");
        
        my $status = $user->rename_tag({
            oldtag    => $oldtag,
            newtag    => $newtag,
            username  => $username,
        });

        if ($status){
            $self->print_warning("Die Ersetzung des Tags konnte nicht ausgeführt werden.");
            return Apache2::Const::OK;
        }
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{tags_loc}?show_usertags=1");
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
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        $self->print_page($config->{tt_tagss_editusertags_tname},$ttdata);
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
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        $self->print_page($config->{tt_tagss_showusertags_tname},$ttdata);
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
                    $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
                    return Apache2::Const::OK;
                }

                my $titles_ref;

                ($recordlist,$hits)= $user->get_titles_of_tag({
                    username  => $username,
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

        if ($logger->is_debug){
            $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
        }
        
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
            template         => 'tt_tagss_showtitlist_tname',
            location         => 'tags_loc',
            parameter        => {
                username     => $username,
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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    unless($user->{ID} || $searchtitoftag){
        # Aufruf-URL
        my $return_uri = uri_escape($r->parsed_uri->unparse);

        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?do_login=1;redirect_to=$return_uri");

        return Apache2::Const::OK;
    }

    my $username = $user->get_username();
    
    if ($do_add && $user->{ID}){

        $logger->debug("Aufnehmen/Aendern der Tags: $tags");
        
        $user->add_tags({
            tags     => $tags,
            titleid  => $titleid,
            dbname   => $dbname,
            userid   => $user->{ID},
            type     => $type,
        });

        $r->internal_redirect("$config->{base_loc}/$view/$config->{search_loc}?db=$dbname;searchsingletit=$titleid;queryid=$queryid;no_log=1");
        return Apache2::Const::OK;
    }
    elsif ($do_del && $user->{ID}){

        $logger->debug("Loeschen der Tags $tags von $dbname:$titleid");
        
        $user->del_tags({
            tags      => $tags,
            titleid     => $titleid,
            dbname     => $dbname,
            username  => $username,
        });

        if ($tags =~/^\w+$/){
            my $tagid = $user->get_id_of_tag({tag => $tags});
            $r->internal_redirect("$config->{base_loc}/$view/$config->{tags_loc}?searchtitoftag=$tagid;private_tags=1");
        }
        else {
            $r->internal_redirect("$config->{base_loc}/$view/$config->{search_loc}?db=$dbname;searchsingletit=$titleid;queryid=$queryid;no_log=1");
        }
        return Apache2::Const::OK;

    }
    elsif ($do_change && $user->{ID}){
        
        $logger->debug("Aendern des Tags $oldtag in $newtag");
        
        my $status = $user->rename_tag({
            oldtag    => $oldtag,
            newtag    => $newtag,
            username  => $username,
        });

        if ($status){
            $self->print_warning("Die Ersetzung des Tags konnte nicht ausgeführt werden.");
            return Apache2::Const::OK;
        }
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{tags_loc}?show_usertags=1");
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
            user       => $user,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        $self->print_page($config->{tt_tagss_editusertags_tname},$ttdata);
    }

    if ($show_usertags && $user->{ID}){

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            format     => $format,
            targettype => $targettype,
        };
        $self->print_page($config->{tt_tagss_showusertags_tname},$ttdata);
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
                    $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
                    return Apache2::Const::OK;
                }

                my $titles_ref;

                ($recordlist,$hits)= $user->get_titles_of_tag({
                    username  => $username,
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

        if ($logger->is_debug){
            $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
        }
        
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
            template         => 'tt_tagss_showtitlist_tname',
            location         => 'tags_loc',
            parameter        => {
                username    => $username,
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

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/tag.html";

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
