#####################################################################
#
#  OpenBib::Handler::PSGI::LitLists.pm
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

package OpenBib::Handler::PSGI::LitLists;

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
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_record'                              => 'show_record',
        'save_record'                              => 'save_record',
        'mail_record'                              => 'mail_record',
        'mail_record_send'                         => 'mail_record_send',
        'print_record'                             => 'print_record',	
        'show_collection'                          => 'show_collection',
        'show_collection_recent'                   => 'show_collection_recent',
        'show_collection_by_topic'                 => 'show_collection_by_topic',
        'show_collection_by_user'                  => 'show_collection_by_user',
        'show_collection_by_single_topic'          => 'show_collection_by_single_topic',
        'show_collection_by_single_user'           => 'show_collection_by_single_user',
        'show_collection_by_single_topic_recent'   => 'show_collection_by_single_topic_recent',
        'dispatch_to_representation'           => 'dispatch_to_representation',
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

    # CGI-Parameter

    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');
    my $num    = $queryoptions->get_option('num');
    
    my $topics_ref           = $user->get_topics;
    my $public_litlists_ref  = $user->get_public_litlists({ offset => $offset, num => $num, view => $view });

    my $nav = Data::Pageset->new({
        'total_entries'    => $user->get_number_of_public_litlists(),
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });
    
    # TT-Data erzeugen
    my $ttdata={
        nav            => $nav,
        topics         => $topics_ref,
        public_litlists=> $public_litlists_ref,
    };
    
    return $self->print_page($config->{tt_litlists_tname},$ttdata);
}

# Alle oeffentlichen Literaturlisten
sub show_collection_recent {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';

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

    # CGI Args
    my $hitrange       = $query->param('num')    || 50;

    my $topics_ref         = $user->get_topics;
    my $public_litlists_ref  = $user->get_recent_litlists({ count => $hitrange, view => $view });

    # TT-Data erzeugen
    my $ttdata={
        topics       => $topics_ref,
        public_litlists=> $public_litlists_ref,
    };
    
    return $self->print_page($config->{tt_litlists_recent_tname},$ttdata);
}

sub show_collection_by_topic {
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

    my $topics_ref           = $user->get_topics;
    my $public_litlists_ref  = $user->get_public_litlists({view => $view});

    # TT-Data erzeugen
    my $ttdata={
        showtopics   => 1,
        topics       => $topics_ref,
        public_litlists=> $public_litlists_ref,
    };
    
    return $self->print_page($config->{tt_litlists_by_topic_tname},$ttdata);
}

sub show_collection_by_single_topic_recent {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $topicid      = $self->param('topicid');

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

    # CGI Args
    my $hitrange       = $query->param('num')    || 50;

    my $topics_ref           = $user->get_topics;
    my $public_litlists_ref  = $user->get_recent_litlists({ topicid => $topicid, count => $hitrange, view => $view });

    # TT-Data erzeugen
    my $ttdata={
        topics       => $topics_ref,
        topicid      => $topicid,
        public_litlists=> $public_litlists_ref,
    };
    
    return $self->print_page($config->{tt_litlists_by_single_topic_recent_tname},$ttdata);
}

sub show_collection_by_single_topic {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $topicid        = $self->strip_suffix($self->param('topicid'));

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
#    my $location       = $self->param('location');

    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');
    my $num    = $queryoptions->get_option('num');
        
    my $topics_ref           = $user->get_topics;
    my $public_litlists_ref  = $user->get_public_litlists({ topicid => $topicid, offset => $offset, num => $num, view => $view });

    my $nav = Data::Pageset->new({
        'total_entries'    => $user->get_number_of_public_litlists({ topicid => $topicid }),
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });
    
    # TT-Data erzeugen
    my $ttdata={
        nav             => $nav,
        topics          => $topics_ref,
        topicid         => $topicid,
        public_litlists => $public_litlists_ref,
    };
    
    return $self->print_page($config->{tt_litlists_by_single_topic_tname},$ttdata);
}

sub show_collection_by_single_userxxx {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));
    my $litlistid         = $self->strip_suffix($self->param('litlistid'));

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
    
    # CGI Args
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my $lecture        = $query->param('lecture')     || 0;
    my $format         = $query->param('format')      || 'HTML';
    my $show           = $query->param('show')        || 'short';
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

    # Mit Suffix, dann keine Aushandlung des Typs

    my $representation = "";
    my $content_type   = "";

    my $thisid = "";
    if ($litlistid=~/^(.+?)(\.html|\.json|\.rdf)$/){
        $thisid           = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $config->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $thisid = $litlistid;
        my $negotiated_type = $self->negotiate_type;
        $representation = $negotiated_type->{suffix};
        $content_type   = $negotiated_type->{content_type};
    }

    $litlistid = $thisid;

    if (!$user_owns_litlist && !$litlist_is_public){
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
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype, view => $view}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid, view => $view});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        topics       => $topics_ref,
        thistopics   => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        show           => $show,        
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,        
        targettype     => $targettype,
    };
    
    return $self->print_page($config->{tt_litlists_record_tname},$ttdata);
}

sub show_collection_by_single_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));
    my $litlistid         = $self->strip_suffix($self->param('litlistid'));

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
    
    # CGI Args
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my $lecture        = $query->param('lecture')     || 0;
    my $format         = $query->param('format')      || 'HTML';
    my $show           = $query->param('show')        || 'short';
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

    # Mit Suffix, dann keine Aushandlung des Typs

    my $representation = "";
    my $content_type   = "";

    my $thisid = "";
    if ($litlistid=~/^(.+?)(\.html|\.json|\.rdf)$/){
        $thisid           = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $config->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $thisid = $litlistid;
        my $negotiated_type = $self->negotiate_type;
        $representation = $negotiated_type->{suffix};
        $content_type   = $negotiated_type->{content_type};
    }

    $litlistid = $thisid;

    if (!$user_owns_litlist && !$litlist_is_public){
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
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype, view => $view}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid, view => $view});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        topics       => $topics_ref,
        thistopics   => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        show           => $show,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        targettype     => $targettype,
    };
    
    return $self->print_page($config->{tt_litlists_record_tname},$ttdata);
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/litlists.html";

    $logger->debug("Returning to $new_location");

    return $self->redirect($new_location,303);
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
                return $self->tunnel_through_authenticator;            
            }
            else {
                return $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
            }   
        }

        if (!$user_owns_litlist){
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
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $queryoptions->get_option('srto'), sorttype => $queryoptions->get_option('srt'), view => $view}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid, view => $view});
    
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
        targettype     => $targettype,
    };
    
    return $self->print_page($config->{tt_litlists_record_tname},$ttdata);
}


sub print_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatches Args
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
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $queryoptions->get_option('srto'), sorttype => $queryoptions->get_option('srt'), view => $view}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid, view => $view});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        thistopics     => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        targettype     => $targettype,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
    };
        
    return $self->print_page($config->{tt_litlists_record_print_tname},$ttdata);
}

sub save_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched_args
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
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $queryoptions->get_option('srto'), sorttype => $queryoptions->get_option('srt'), view => $view}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid, view => $view});

    my $filename = "Literaturliste ".$litlist_properties_ref->{title}." ".$format;

    $filename =~s/\W/_/g;

    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        thistopics     => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        targettype     => $targettype,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
    };
    
    $self->param('content_type','text/plain');
    $self->header_add("Content-Disposition" => "attachment;filename=\"${filename}.txt\"");
    return $self->print_page($config->{tt_litlists_record_save_tname},$ttdata);

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
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $queryoptions->get_option('srto'), sorttype => $queryoptions->get_option('srt'), view => $view}),
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
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $queryoptions->get_option('srto'), sorttype => $queryoptions->get_option('srt'), view => $view}),
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

sub highlightquery {
    my ($searchquery,$content) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Highlight Query

    return $content unless ($searchquery);
    
    my $term_ref = $searchquery->get_searchterms();

    return $content if (scalar(@$term_ref) <= 0);

    if ($logger->is_debug){
        $logger->debug("Terms: ".YAML::Dump($term_ref));
    }
    
    my $terms = join("|", grep /^\w{3,}/ ,@$term_ref);

    return $content if (!$terms);
    
    if ($logger->is_debug){
        $logger->debug("Term_ref: ".YAML::Dump($term_ref)."\nTerms: $terms");
        $logger->debug("Content vor: ".$content);
    }
    
    $content=~s/\b($terms)/<span class="ob-highlight_searchterm">$1<\/span>/ig unless ($content=~/http/);

    if ($logger->is_debug){
        $logger->debug("Content nach: ".$content);
    }
    
    return $content;
}

sub sort_circulation {
    my $array_ref = shift;

    # Schwartz'ian Transform
        
    my @sorted = map { $_->[0] }
    sort { $a->[1] cmp $b->[1] }
    map { [$_, sprintf("%03d:%s:%s:%s",$_->{department_id},$_->{department},$_->{storage},$_->{location_mark})] }
    @{$array_ref};
        
    return \@sorted;
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
