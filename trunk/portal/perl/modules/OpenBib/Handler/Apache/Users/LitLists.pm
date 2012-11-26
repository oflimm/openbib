#####################################################################
#
#  OpenBib::Handler::Apache::Users::LitLists.pm
#
#  Copyright 2009-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Users::LitLists;

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
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::Handler::Apache::Users::LitLists::Item;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'                          => 'show_collection',

        'show_record'                              => 'show_record',
        'show_record_form'                         => 'show_record_form',
        'create_record'                            => 'create_record',
        'update_record'                            => 'update_record',
        'delete_record'                            => 'delete_record',
        'confirm_delete_record'     => 'confirm_delete_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
#        'show_collection_by_topic'           => 'show_collection_by_topic',
#        'show_record_by_topic'               => 'show_record_by_topic',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

# Alle oeffentlichen Literaturlisten
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
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $topics_ref = $user->get_topics;
    my $userrole_ref = $user->get_roles_of_user($user->{ID});
    my $litlists     = $user->get_litlists();
    my $targettype   = $user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        topics   => $topics_ref,
        litlists   => $litlists,
        qopts      => $queryoptions->get_options,
        targettype => $targettype,
    };
    
    $self->print_page($config->{tt_users_litlists_tname},$ttdata);
    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->strip_suffix($self->param('litlistid'))      || '';
    my $path_prefix    = $self->param('path_prefix');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    
    # CGI Args
    my $method         = $query->param('_method')     || '';
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my $lecture        = $query->param('lecture')     || 0;
    my $format         = $query->param('format')      || 'short';
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my @topicids     = ($query->param('topicids'))?$query->param('topicids'):();
    my $topicid      = $query->param('topicid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $topics_ref   = $user->get_topics;

    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");

    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$litlist_is_public){

        if (! $user->{ID}){
            if ($self->param('representation') eq "html"){
                # Aufruf-URL
                my $return_uri = uri_escape($r->parsed_uri->unparse);
                
                $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
            }
            else {
                $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
            }   
            return Apache2::Const::OK;
        }

        if (!$user_owns_litlist){
            $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));

            $logger->debug("UserID: $self->{ID} trying to delete litlistid $litlistid");
            
            # Aufruf der privaten Literaturlisten durch "Andere" loggen
            $session->log_event({
                type      => 800,
                content   => $litlistid,
            });
            
            return;
        }
    }

    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");
    
    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }
    
    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $queryoptions->get_option('srto'), sorttype => $queryoptions->get_option('srt')}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        topics       => $topics_ref,
        thistopics   => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
    };
    
    $self->print_page($config->{tt_litlists_record_tname},$ttdata);

    return Apache2::Const::OK;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->strip_suffix($self->param('litlistid'));

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    
    # CGI Args
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my $lecture        = $query->param('lecture')     || 0;
    my $format         = $query->param('format')      || 'short';
    my $do_addentry    = $query->param('do_addentry')    || '';
    my $do_showlitlist = $query->param('do_showlitlist') || '';
    my $do_changelist  = $query->param('do_changelist')  || '';
    my $do_change      = $query->param('do_change')      || '';
    my $do_delentry    = $query->param('do_delentry')    || '';
    my $do_addlist     = $query->param('do_addlist')     || '';
    my $do_dellist     = $query->param('do_dellist')     || '';
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my @topicids     = ($query->param('topicids'))?$query->param('topicids'):();
    my $topicid      = $query->param('topicid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $topics_ref   = $user->get_topics;
    
    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$user_owns_litlist){
        $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));

        # Aufruf der privaten Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });

        return;
    }

    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        topics       => $topics_ref,
        thistopics   => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
    };
    
    $self->print_page($config->{tt_users_litlists_record_edit_tname},$ttdata);

    return Apache2::Const::OK;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');
    
    # CGI Args
    my $titleid        = $query->param('titleid')       || '';
    my $litlistid      = $query->param('litlistid')   || '';
    my $dbname         = $query->param('dbname')       || '';

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

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

    $self->param('userid',$user->{ID});
    
    # Wenn Litlistid mitgegeben wurde, dann Shortcut zu create_entry
    # Hintergrund: So kann der Nutzer im Web-UI auch eine bestehende Literaturliste
    #              auswaehlen

    # Wenn zusaetzlich ein Titel-Eintrag uebergeben wird, dann wird dieser auch
    # der soeben erzeugten Literaturliste hinzugefuegt.
    if ($titleid && $dbname && $litlistid){
        $user->add_litlistentry({ litlistid =>$litlistid, titleid => $titleid, dbname => $dbname});
        $self->return_baseurl;
        return;
    }

    my $userrole_ref = $user->get_roles_of_user($user->{ID});
    
    if ($input_data_ref->{title} eq ""){
        $self->print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."));
        
        return Apache2::Const::OK;
    }

    # Sonst muss Litlist neu erzeugt werden
    
    $litlistid = $user->add_litlist({ title =>$input_data_ref->{title}, type => $input_data_ref->{type}, topics => $input_data_ref->{topics} });

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($litlistid){
            $logger->debug("Weiter zum Record $litlistid");
            $self->param('status',Apache2::Const::HTTP_CREATED);
            $self->param('litlistid',$litlistid);
            $self->param('location',"$location/$litlistid");
            $self->show_record;
        }
    }
    
    return;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $representation = $self->param('representation') || 'html';
    my $litlistid      = $self->param('litlistid')      || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    
    # CGI Args
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my @topicids     = ($query->param('topicids'))?$query->param('topicids'):();

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if ($input_data_ref == 1){
        $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
    }
    
    $input_data_ref->{litlistid} = $litlistid;
    
    if (!$input_data_ref->{title} || !$input_data_ref->{type} || !$litlistid){
        $self->print_warning($msg->maketext("Sie müssen einen Titel oder einen Typ f&uuml;r Ihre Literaturliste eingeben."));
        
        return Apache2::Const::OK;
    }

    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
    
    if (!$user_owns_litlist) {
        $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
        
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return;
    }

    $self->param('userid',$user->{ID});
    
    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$userrole_ref->{librarian} && !$userrole_ref->{lecturer} && !$userrole_ref->{admin}){
        $input_data_ref->{lecture} = "false";
    }
    
    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
    
    if ($litlist_properties_ref->{userid} eq $user->{ID}){
        $user->change_litlist($input_data_ref);
    }

    $self->return_baseurl;

    return;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $litlistid      = $self->strip_suffix($self->param('litlistid'));
    my $config         = $self->param('config');

    my $ttdata={
        litlistid => $litlistid,
    };
    
    $logger->debug("Asking for confirmation");
    $self->print_page($config->{tt_users_litlists_record_delete_confirm_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->param('litlistid')             || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');

    $self->param("userid",$user->{ID}) if ($user->{ID});
    
    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");
    
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    $logger->debug("UserID: $user->{ID} trying to delete litlistid $litlistid with result $user_owns_litlist");
    
    if (!$user_owns_litlist) {
        $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));

        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return;
    }

    $self->param('userid',$user->{ID});    

    $user->del_litlist({ litlistid => $litlistid});

    $self->return_baseurl;

    return;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $lang           = $self->param('lang')           || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{litlists_loc}.html?l=$lang";

    return $self->redirect($new_location,'303 See Other');

#    $self->query->method('GET');
#    $self->query->content_type('text/html');
#    $self->query->headers_out->add(Location => $new_location);
#    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        title => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        type => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        lecture => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },
        topics => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        
    };
}

1;
