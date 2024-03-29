#####################################################################
#
#  OpenBib::Handler::PSGI::Users::LitLists.pm
#
#  Copyright 2009-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::LitLists;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use Email::Valid;
use Email::Stuffer;
use File::Slurper 'read_binary';
use DBI;
use JSON::XS;
use Data::Pageset;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape;
use XML::RSS;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Handler::PSGI::Users::LitLists::Item;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Users';

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
        'confirm_delete_record'                    => 'confirm_delete_record',
        'mail_record'                              => 'mail_record',
        'mail_record_send'                         => 'mail_record_send',
	
        'dispatch_to_representation'               => 'dispatch_to_representation',
        'dispatch_to_user'                         => 'dispatch_to_user',
#        'show_collection_by_topic'           => 'show_collection_by_topic',
#        'show_record_by_topic'               => 'show_record_by_topic',
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
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{litlists_loc}";
        
        return $self->redirect($new_location,303);
    }

    return;
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
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $topics_ref = $user->get_topics;
    my $userrole_ref = $user->get_roles_of_user($user->{ID});
    my $litlists     = $user->get_litlists({view => $view});
    my $targettype   = $user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        topics   => $topics_ref,
        litlists   => $litlists,
        qopts      => $queryoptions->get_options,
        targettype => $targettype,
    };
    
    return $self->print_page($config->{tt_users_litlists_tname},$ttdata);
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

    my $topics_ref   = $user->get_topics;

    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");

    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$litlist_is_public){

        if (! $user->{ID}){
            if ($self->param('representation') eq "html"){
                # Aufruf-URL
                my $return_uri = uri_escape($r->request_uri);
                
                return $self->redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
            }
            else {
                return $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
            }   
        }

        if (!$user_owns_litlist && !$user->is_admin){
            $logger->debug("UserID: $self->{ID} trying to delete litlistid $litlistid");
            
            # Aufruf der privaten Literaturlisten durch "Andere" loggen
            $session->log_event({
                type      => 800,
                content   => $litlistid,
            });
            
            return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
        }
    }

    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");
    
    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }
    
    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid, view => $view});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, queryoptions => $queryoptions, view => $view}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid, view => $view});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        topics         => $topics_ref,
        thistopics     => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        targettype     => $targettype,
        litlistid      => $litlistid,
    };
    
    return $self->print_page($config->{tt_users_litlists_record_tname},$ttdata);
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

    my $topics_ref   = $user->get_topics;
    
    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$user_owns_litlist){
        # Aufruf der privaten Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });

        return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }

    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid, view => $view});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, queryoptions => $queryoptions, view => $view}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid, view => $view});

    my $total_count = $user->get_number_of_litlistentries({ litlistid => $litlistid, view => $view });
    
    my $nav = Data::Pageset->new({
        'total_entries'    => $total_count,
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });
    
    # TT-Data erzeugen
    my $ttdata={
	nav          => $nav,
        user_owns_litlist => $user_owns_litlist,
        topics       => $topics_ref,
        thistopics   => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        targettype     => $targettype,
        litlistid      => $litlistid,
	total_count    => $total_count,
    };
    
    return $self->print_page($config->{tt_users_litlists_record_edit_tname},$ttdata);
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
    my $titleid        = $query->param('titleid')      || '';
    my $litlistid      = $query->param('litlistid')    || '';
    my $dbname         = $query->param('dbname')       || '';

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (! $user->{ID}){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    $self->param('userid',$user->{ID});
    
    # Wenn Litlistid mitgegeben wurde, dann Shortcut
    # Hintergrund: So kann der Nutzer im Web-UI per CGI-Parameter auch eine bestehende Literaturliste
    #              auswaehlen

    if (!$litlistid){
        if ($input_data_ref->{title} eq ""){
            return $self->print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."));
        }
        
        # Sonst muss Litlist neu erzeugt werden
        
        $litlistid = $user->add_litlist({ title =>$input_data_ref->{title}, type => $input_data_ref->{type}, topics => $input_data_ref->{topics} });
    }

    # Wenn zusaetzlich ein Titel-Eintrag uebergeben wird, dann wird dieser auch
    # der gerade erzeugten neuen Literaturliste bzw. der mitgegebenen Literaturlisten-ID hinzugefuegt.
    if ($titleid && $dbname && $litlistid){
        my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
        
        if (!$user_owns_litlist) {
            # Aufruf der Literaturlisten durch "Andere" loggen
            $session->log_event({
                type      => 800,
                content   => $litlistid,
            });
            
            return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
        }
        
        $user->add_litlistentry({ litlistid =>$litlistid, titleid => $titleid, dbname => $dbname});

        if ($self->param('representation') eq "html"){
            if ($query->param('redirect_to')){
                my $new_location = uri_unescape($query->param('redirect_to'));
                return $self->redirect($new_location,303);
            }
            else {
                $self->return_baseurl;
            }
        }

        $self->return_baseurl;
        
        return;
    }

    
    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($litlistid){
            if ($query->param('redirect_to')){
                my $new_location = uri_unescape($query->param('redirect_to'));
                return $self->redirect($new_location,303);
            }
            else {                
                $logger->debug("Weiter zum Record $litlistid");
                $self->param('status',201);
                $self->param('litlistid',$litlistid);
                $self->param('location',"$location/$litlistid");
                $self->show_record;
            }
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
        return $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
    }
    
    $input_data_ref->{litlistid} = $litlistid;
    
    if (!$input_data_ref->{title} || !$input_data_ref->{type} || !$litlistid){
        return $self->print_warning($msg->maketext("Sie müssen einen Titel oder einen Typ f&uuml;r Ihre Literaturliste eingeben."));
    }

    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
    
    if (!$user_owns_litlist) {
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
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
    my $user           = $self->param('user');
    my $properties     = $user->get_litlist_properties({ litlistid => $litlistid, view => $view });
    
    my $ttdata={
        litlistid => $litlistid,
	properties => $properties,
    };
    
    $logger->debug("Asking for confirmation");
    return $self->print_page($config->{tt_users_litlists_record_delete_confirm_tname},$ttdata);
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
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }

    $self->param('userid',$user->{ID});    

    $user->del_litlist({ litlistid => $litlistid});

    return $self->return_baseurl;
}

sub mail_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');    
    my $litlistid      = $self->param('litlistid');

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
    my $format                  = $query->param('format')                || '';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");
    
    my $username=$user->get_username();

    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$litlist_is_public && !$user_owns_litlist){            
	return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }

    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid, view => $view});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, queryoptions => $queryoptions, view => $view}),
        properties => $litlist_properties_ref,
    };

    
    # TT-Data erzeugen
    my $ttdata={
        qopts       => $queryoptions->get_options,				
        format      => $format,

        username    => $username,
	properties  => $litlist_properties_ref,
        litlist     => $singlelitlist,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
	
    };
    
    return $self->print_page($config->{tt_litlists_record_mail_tname},$ttdata);
}

sub mail_record_send {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid');    
    my $litlistid      = $self->param('litlistid');

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
    my $email     = ($query->param('email'))?$query->param('email'):'';
    my $subject   = ($query->param('subject'))?$query->param('subject'):'Ihre Literaturliste';
    my $mail      = $query->param('mail');
    my $format    = $query->param('format')||'';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        return $self->print_warning($msg->maketext("Sie haben keine Mailadresse eingegeben."));
    }

    unless (Email::Valid->address($email)) {
        return $self->print_warning($msg->maketext("Sie haben eine ungültige Mailadresse eingegeben."));
    }	

    my $sysprofile= $config->get_profilename_of_view($view);

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");
    
    my $username=$user->get_username();

    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$litlist_is_public && !$user_owns_litlist){            
	return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }

    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid, view => $view});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, queryoptions => $queryoptions, view => $view}),
        properties => $litlist_properties_ref,
    };

    # TT-Data erzeugen
    
    my $ttdata={
        view        => $view,
        sysprofile  => $sysprofile,
        stylesheet  => $stylesheet,
        sessionID   => $session->{ID},
	qopts       => $queryoptions->get_options,
        format      => $format,
	properties  => $litlist_properties_ref,
        litlist     => $singlelitlist,
        
        config      => $config,
        user        => $user,
        msg         => $msg,

	highlightquery    => \&highlightquery,
	sort_circulation  => \&sort_circulation,
	
    };

    my $maildata="";
    my $ofile="literaturliste-" . $$ .".txt";

    my $datatemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        ABSOLUTE      => 1,
        #        INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $ofile,
    });
  

    my $mimetype="text/html";
    my $filename="unikatalog-literaturliste";
    my $datatemplatename=$config->{tt_litlists_record_mail_html_tname};

    $logger->debug("Using view $view in profile $sysprofile");
    
    if ($format eq "short" || $format eq "full") {
        $filename.=".html";
    }
    else {
        $mimetype="text/plain";
        $filename.=".txt";
        $datatemplatename=$config->{tt_litlists_record_mail_plain_tname};
    }

    $datatemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $datatemplatename,
    });

    $logger->debug("Using database/view specific Template $datatemplatename");
    
    $datatemplate->process($datatemplatename, $ttdata) || do {
        $logger->error($datatemplate->error());
        $self->header_add('Status',400); # server error
        return;
    };
  
    my $afile = "an." . $$;

    my $mainttdata = {
	msg => $msg,	
    };

    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        ABSOLUTE      => 1,
        #        INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });

    my $messagetemplatename = $config->{tt_litlists_record_mail_message_tname};
    
    $messagetemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $messagetemplatename,
    });

    $logger->debug("Using database/view specific Template $messagetemplatename");

    $maintemplate->process($messagetemplatename, $mainttdata ) || do { 
    };
    
    my $anschfile="/tmp/" . $afile;
    my $mailfile ="/tmp/" . $ofile;
    
    Email::Stuffer->to($email)
	->from($config->{contact_email})
	->subject($subject)
	->text_body(read_binary($anschfile))
	->attach_file($mailfile)
	->send;

    unlink $anschfile;
    unlink $mailfile;

    return $self->print_page($config->{tt_litlists_record_mail_success_tname},$ttdata);
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $lang           = $self->param('lang')           || '';
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{litlists_loc}.html?l=$lang";

    return $self->redirect($new_location,303);
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
