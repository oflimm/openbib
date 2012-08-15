#####################################################################
#
#  OpenBib::Handler::Apache::LitList.pm
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

package OpenBib::Handler::Apache::LitList;

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
use URI::Escape;
use XML::RSS;

use OpenBib::Search::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Handler::Apache::LitList::Item;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                          => 'show_collection',
        'show_collection_recent'                   => 'show_collection_recent',
        'show_collection_by_subject'               => 'show_collection_by_subject',
        'show_collection_by_user'                  => 'show_collection_by_user',
        'show_collection_by_single_subject'        => 'show_collection_by_single_subject',
        'show_collection_by_single_user'           => 'show_collection_by_single_user',
        'show_collection_by_single_subject_recent' => 'show_collection_by_single_subject_recent',
        'show_record'                              => 'show_record',
        'show_record_form'                         => 'show_record_form',
        'create_record'                            => 'create_record',
        'update_record'                            => 'update_record',
        'delete_record'                            => 'delete_record',
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
    
    my $subjects_ref         = $user->get_subjects;
    my $public_litlists_ref  = $user->get_public_litlists();

    # TT-Data erzeugen
    my $ttdata={
        subjects       => $subjects_ref,
        public_litlists=> $public_litlists_ref,
    };
    
    $self->print_page($config->{tt_litlist_collection_tname},$ttdata);
    return Apache2::Const::OK;
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

    my $subjects_ref         = $user->get_subjects;
    my $public_litlists_ref  = $user->get_recent_litlists({ count => $hitrange });

    # TT-Data erzeugen
    my $ttdata={
        subjects       => $subjects_ref,
        public_litlists=> $public_litlists_ref,
    };
    
    $self->print_page($config->{tt_litlist_collection_recent_tname},$ttdata);
    return Apache2::Const::OK;
}

sub show_collection_by_subject {
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

    my $subjects_ref         = $user->get_subjects;
    my $public_litlists_ref  = $user->get_public_litlists();

    # TT-Data erzeugen
    my $ttdata={
        showsubjects   => 1,
        subjects       => $subjects_ref,
        public_litlists=> $public_litlists_ref,
    };
    
    $self->print_page($config->{tt_litlist_collection_by_subject_tname},$ttdata);
    return Apache2::Const::OK;
}

sub show_collection_by_single_subject_recent {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $subjectid      = $self->param('subjectid');

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

    my $subjects_ref         = $user->get_subjects;
    my $public_litlists_ref  = $user->get_recent_litlists({ subjectid => $subjectid, count => $hitrange });

    # TT-Data erzeugen
    my $ttdata={
        subjects       => $subjects_ref,
        subjectid      => $subjectid,
        public_litlists=> $public_litlists_ref,
    };
    
    $self->print_page($config->{tt_litlist_collection_by_single_subject_recent_tname},$ttdata);
    return Apache2::Const::OK;
}

sub show_collection_by_single_subject {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $subjectid      = $self->strip_suffix($self->param('subjectid'));

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

    my $subjects_ref         = $user->get_subjects;
    my $public_litlists_ref  = $user->get_public_litlists({ subjectid => $subjectid });

    # TT-Data erzeugen
    my $ttdata={
        subjects       => $subjects_ref,
        subjectid      => $subjectid,
        public_litlists=> $public_litlists_ref,
    };
    
    $self->print_page($config->{tt_litlist_collection_by_single_subject_tname},$ttdata);
    return Apache2::Const::OK;
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
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
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
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
    my $subjectid      = $query->param('subjectid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = $user->get_subjects;
    
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
        
    my $litlist_subjects_ref   = $user->get_subjects_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        subjects       => $subjects_ref,
        thissubjects   => $litlist_subjects_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        show           => $show,        
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,        
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
    };
    
    $self->print_page($config->{tt_litlist_tname},$ttdata);

    return Apache2::Const::OK;
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
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
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
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
    my $subjectid      = $query->param('subjectid')   || undef;

    
    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = $user->get_subjects;
    
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
        
    my $litlist_subjects_ref   = $user->get_subjects_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        subjects       => $subjects_ref,
        thissubjects   => $litlist_subjects_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        show           => $show,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
    };
    
    $self->print_page($config->{tt_litlist_tname},$ttdata);

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
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my $lecture        = $query->param('lecture')     || 0;
    my $format         = $query->param('format')      || 'short';
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
    my $subjectid      = $query->param('subjectid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = $user->get_subjects;
    
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
                $self->print_warning($msg->maketext("Die sind nicht authentifiziert."));
            }   
            return Apache2::Const::OK;
        }

        if (!$user_owns_litlist){
            $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
            
            # Aufruf der privaten Literaturlisten durch "Andere" loggen
            $session->log_event({
                type      => 800,
                content   => $litlistid,
            });
            
            return;
        }
    }
    
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
        
    my $litlist_subjects_ref   = $user->get_subjects_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        subjects       => $subjects_ref,
        thissubjects   => $litlist_subjects_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
    };
    
    $self->print_page($config->{tt_litlist_tname},$ttdata);

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
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
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
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
    my $subjectid      = $query->param('subjectid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = $user->get_subjects;
    
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
        
    my $litlist_subjects_ref   = $user->get_subjects_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        subjects       => $subjects_ref,
        thissubjects   => $litlist_subjects_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
    };
    
    $self->print_page($config->{tt_litlist_edit_tname},$ttdata);

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
    
    # CGI Args
    my $titid          = $query->param('titid')       || '';
    my $litlistid      = $query->param('litlistid')   || '';
    my $titdb          = $query->param('titdb')       || '';

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
    if ($titid && $titdb && $litlistid){
        $user->add_litlistentry({ litlistid =>$litlistid, titid => $titid, titdb => $titdb});
        $self->return_baseurl;
        return;
    }

    my $userrole_ref = $user->get_roles_of_user($user->{ID});
    
    if ($input_data_ref->{title} eq ""){
        $self->print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."));
        
        return Apache2::Const::OK;
    }

    # Sonst muss Litlist neu erzeugt werden
    
    $litlistid = $user->add_litlist({ title =>$input_data_ref->{title}, type => $input_data_ref->{type}, subjects => $input_data_ref->{subjects} });

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
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();

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
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{user_loc}/$userid/litlist.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

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
        subjects => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        
    };
}

1;
