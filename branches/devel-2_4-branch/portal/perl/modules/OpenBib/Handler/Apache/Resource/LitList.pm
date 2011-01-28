#####################################################################
#
#  OpenBib::Handler::Apache::Resource::LitList.pm
#
#  Copyright 2009-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::LitList;

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
        'show_public_collection_negotiate'            => 'show_public_collection_negotiate',
        'show_public_collection_as_html'              => 'show_public_collection_as_html',
        'show_public_collection_as_json'              => 'show_public_collection_as_json',
        'show_public_collection_as_rdf'               => 'show_public_collection_as_rdf',
        'show_public_collection_by_subject_negotiate' => 'show_public_collection_by_subject_negotiate',
        'show_public_collection_by_subject_as_html'   => 'show_public_collection_by_subject_as_html',
        'show_public_collection_by_subject_as_json'   => 'show_public_collection_by_subject_as_json',
        'show_public_collection_by_subject_as_rdf'    => 'show_public_collection_by_subject_as_rdf',
        'show_public_record_by_subject_negotiate'     => 'show_public_record_by_subject_negotiate',
        'show_record_negotiate'                       => 'show_record_negotiate',
        'create_record'                               => 'create_record',
        'update_record'                               => 'update_record',
        'delete_record'                               => 'delete_record',
        'create_entry'                                => 'create_entry',
        'update_entry'                                => 'update_entry',
        'delete_entry'                                => 'delete_entry',
        
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_public_collection_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$view/$config->{handler}{resource_litlist_public_loc}{name}.$negotiated_type_ref->{suffix}";

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

    return;
}

sub show_public_collection_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_public_collection;

    return;
}

sub show_public_collection_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_public_collection;

    return;
}

sub show_public_collection_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_public_collection;

    return;
}

# Alle oeffentlichen Literaturlisten
sub show_public_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $representation = $self->param('representation') || 'html';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    
    # NO CGI Args

    my $subjects_ref         = OpenBib::User->get_subjects;

    my $public_litlists_ref  = $user->get_public_litlists();

    my $content_type   = $config->{'content_type_map_rev'}{$representation};

    # TT-Data erzeugen
    my $ttdata={
        representation => $representation,
        content_type   => $content_type,
        
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},
        
        subjects       => $subjects_ref,
        user           => $user,
        
        public_litlists=> $public_litlists_ref,
        
        config         => $config,
        user           => $user,
        msg            => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_litlists_public_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub show_public_collection_by_subject_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$view/$config->{handler}{resource_litlist_public_subject_loc}{name}.$negotiated_type_ref->{suffix}";

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

    return;
}

sub show_public_collection_by_subject_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_public_collection_by_subject;

    return;
}

sub show_public_collection_by_subject_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_public_collection_by_subject;

    return;
}

sub show_public_collection_by_subject_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_public_collection_by_subject;

    return;
}

sub show_public_collection_by_subject {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || 'html';
    my $representation = $self->param('representation');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    
    my $showsubjects = 1;

    my $subjects_ref         = OpenBib::User->get_subjects;
    my $public_litlists_ref  = $user->get_public_litlists();

    my $content_type   = $config->{'content_type_map_rev'}{$representation};
    
    # TT-Data erzeugen
    my $ttdata={
        representation => $representation,
        content_type   => $content_type,
        showsubjects   => $showsubjects,
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},
        
        subjects       => $subjects_ref,
        user           => $user,
        
        public_litlists=> $public_litlists_ref,
        
        config         => $config,
        user           => $user,
        msg            => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_litlists_public_by_subject_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub show_public_record_by_subject_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $subjectid      = $self->param('subjectid')      || '';
    my $representation = $self->param('representation') || 'html';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');


    # Mit Suffix, dann keine Aushandlung des Typs

    my $representation = "";
    my $content_type   = "";

    my $thisid = "";
    if ($subjectid=~/^(.+?)(\.html|\.json|\.rdf)$/){
        $thisid           = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $config->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $thisid = $subjectid;
        my $negotiated_type = $self->negotiate_type;
        $representation = $negotiated_type->{suffix};
        $content_type   = $negotiated_type->{content_type};
    }

    $subjectid = $thisid;
    
    my $subjects_ref         = OpenBib::User->get_subjects;
    my $public_litlists_ref  = $user->get_public_litlists({ subjectid => $subjectid });
    
    # TT-Data erzeugen
    my $ttdata={
        representation => $representation,
        content_type   => $content_type,
        
        view           => $view,
        stylesheet     => $stylesheet,
        
        subjects       => $subjects_ref,
        subjectid      => $subjectid,
        user           => $user,
        
        public_litlists=> $public_litlists_ref,
        
        config         => $config,
        user           => $user,
        msg            => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_litlists_public_by_subject_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub show_record_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->param('litlistid')             || '';
    my $representation = $self->param('representation') || '';

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
    my $format         = $query->param('format')      || 'HTML';
    my $show           = $query->param('show')        || 'short';
    my $do_addentry    = $query->param('do_addentry')    || '';
    my $do_showlitlist = $query->param('do_showlitlist') || '';
    my $do_changelist  = $query->param('do_changelist')  || '';
    my $do_change      = $query->param('do_change')      || '';
    my $do_delentry    = $query->param('do_delentry')    || '';
    my $do_addlist     = $query->param('do_addlist')     || '';
    my $do_dellist     = $query->param('do_dellist')     || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
    my $subjectid      = $query->param('subjectid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = OpenBib::User->get_subjects;
    
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

    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype}),
        properties => $litlist_properties_ref,
    };
        
    if (!$user_owns_litlist){
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
    }
        
    # Thematische Einordnung
        
    my $litlist_subjects_ref   = OpenBib::User->get_subjects_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        representation  => $representation,
        
        user_owns_litlist => $user_owns_litlist,
        
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},
        
        subjects       => $subjects_ref,
        thissubjects   => $litlist_subjects_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        user           => $user,
        
        userrole       => $userrole_ref,
        
        format         => $format,
        show           => $show,
        
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
        
        config         => $config,
        user           => $user,
        msg            => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_resource_litlist_tname},$ttdata,$r);

    return Apache2::Const::OK;
}
sub show_recordxxx {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->param('litlistid')             || '';
    my $representation = $self->param('representation') || '';

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
    my $format         = $query->param('format')      || 'HTML';
    my $show           = $query->param('show')        || 'short';
    my $do_addentry    = $query->param('do_addentry')    || '';
    my $do_showlitlist = $query->param('do_showlitlist') || '';
    my $do_changelist  = $query->param('do_changelist')  || '';
    my $do_change      = $query->param('do_change')      || '';
    my $do_delentry    = $query->param('do_delentry')    || '';
    my $do_addlist     = $query->param('do_addlist')     || '';
    my $do_dellist     = $query->param('do_dellist')     || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
    my $subjectid      = $query->param('subjectid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = OpenBib::User->get_subjects;
    
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

    
    # Weiterschaltung, wenn eine neue Literaturliste angelegt wird
    if ($litlistid =~/add/){
        $self->add_list();
        return;
    }
    
    if ($litlist_is_public || $user_owns_litlist) {
        
        # Aktionen moeglich, wenn dem Nutzer die Liste gehoert
        if ($user_owns_litlist){
            
            if ($do_addentry) {
                
                if (!$litlistid || !$titid || !$titdb ){
                    OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste eingegeben oder Titel und Datenbank existieren nicht."),$r,$msg);
                    
                    return Apache2::Const::OK;
                }
                
                $user->add_litlistentry({ litlistid =>$litlistid, titid => $titid, titdb => $titdb});
                
                $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{resource_litlist_loc}{name}/$litlistid/?action=manage&do_showlitlist=1");
                return Apache2::Const::OK;
                
            }
            elsif ($do_delentry) {
                    
                    if (!$titid || !$titdb || !$litlistid) {
                        OpenBib::Common::Util::print_warning($msg->maketext("Keine Titelid, Titel-Datenbank oder Literaturliste vorhanden."),$r,$msg);
                        
                        return Apache2::Const::OK;
                    }
                    
                    $user->del_litlistentry({ titid => $titid, titdb => $titdb, litlistid => $litlistid});
                    
                    $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{resource_litlist_loc}{name}/$litlistid/");
                    return Apache2::Const::OK;
                    
                }
        }
        
        my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
        
        my $targettype    = $user->get_targettype_of_session($session->{ID});
        
        my $singlelitlist = {
            id         => $litlistid,
            recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype}),
            properties => $litlist_properties_ref,
        };
        
        if (!$user_owns_litlist){
            # Aufruf der Literaturlisten durch "Andere" loggen
            $session->log_event({
                type      => 800,
                content   => $litlistid,
            });
        }
        
        # Thematische Einordnung
        
        my $litlist_subjects_ref   = OpenBib::User->get_subjects_of_litlist({id => $litlistid});
        my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
        
        # TT-Data erzeugen
        my $ttdata={
            representation  => $representation,
            
            user_owns_litlist => $user_owns_litlist,
            
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},
            
            subjects       => $subjects_ref,
            thissubjects   => $litlist_subjects_ref,
            query          => $query,
            qopts          => $queryoptions->get_options,
            user           => $user,
            
            userrole       => $userrole_ref,
            
            format         => $format,
            show           => $show,
            
            litlist        => $singlelitlist,
            other_litlists => $other_litlists_of_user,
            
            dbinfo         => $dbinfotable,
            targettype     => $targettype,
            
            config         => $config,
            user           => $user,
            msg            => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{tt_resource_litlist_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }
    
    return Apache2::Const::OK;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $arg            = $self->param('arg')            || '';
    my $representation = $self->param('representation') || '';

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
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();

    if (! $user->{ID}){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;
        
        # Return-URL in der Session abspeichern
        
        $session->set_returnurl($return_url);
        
        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}/form");
        
        return Apache2::Const::OK;
    }
    
    my $userrole_ref = $user->get_roles_of_user($user->{ID});
    
    if ($title eq ""){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    my $litlistid = $user->add_litlist({ title =>$title, type => $type, subjectids => \@subjectids });
    
    # Wenn zusaetzlich ein Titel-Eintrag uebergeben wird, dann wird dieser auch
    # der soeben erzeugten Literaturliste hinzugefuegt.
    if ($titid && $titdb && $litlistid){
        $user->add_litlistentry({ litlistid =>$litlistid, titid => $titid, titdb => $titdb});
    }

    my $new_location = "$config->{base_loc}/$view/$config->{handler}{resource_litlist_loc}{name}/$litlistid.html";
    
    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);
    
    return;
}

sub update_record {
                
#             if (!$title || !$type || !$litlistid){
#                 OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel oder einen Typ f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
                
#                 return Apache2::Const::OK;
#             }


#             if (!$userrole_ref->{librarian} && !$userrole_ref->{lecturer}){
#                 $lecture = 0;
#             }
            
#             my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
            
#             if ($litlist_properties_ref->{userid} eq $user->{ID}){
#                 $user->change_litlist({ title => $title, type => $type, lecture => $lecture, litlistid => $litlistid, subjectids => \@subjectids });
#             }
            
#             $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{resource_litlist_loc}{name}/private/");
#             return Apache2::Const::OK;
            

}

sub delete_record {
    #             $user->del_litlist({ litlistid => $litlistid});
    
    #             $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{litlists_loc}{name}/private/");
    #             return Apache2::Const::OK;
}


sub create_entry {
            
#                     if (!$litlistid || !$titid || !$titdb ){
#                         OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste eingegeben oder Titel und Datenbank existieren nicht."),$r,$msg);
                        
#                         return Apache2::Const::OK;
#                     }
                    
#                     $user->add_litlistentry({ litlistid =>$litlistid, titid => $titid, titdb => $titdb});
                    
#                     $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{resource_litlist_loc}{name}/$litlistid/?action=manage&do_showlitlist=1");
#                     return Apache2::Const::OK;
#             my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});

#             my $targettype    = $user->get_targettype_of_session($session->{ID});
            
# 	    my $singlelitlist = {
#                 id         => $litlistid,
#                 recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype}),
#                 properties => $litlist_properties_ref,
#             };

#             if (!$user_owns_litlist){
#                 # Aufruf der Literaturlisten durch "Andere" loggen
#                 $session->log_event({
#                     type      => 800,
#                     content   => $litlistid,
#                 });
#             }
            
#             # Thematische Einordnung

#             my $litlist_subjects_ref   = OpenBib::User->get_subjects_of_litlist({id => $litlistid});
#             my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
                
#             # TT-Data erzeugen
# 	    my $ttdata={
#                 representation  => $representation,

#                 user_owns_litlist => $user_owns_litlist,
                
#                 view           => $view,
#                 stylesheet     => $stylesheet,
#                 sessionID      => $session->{ID},

#                 subjects       => $subjects_ref,
#                 thissubjects   => $litlist_subjects_ref,
#                 query          => $query,
#                 qopts          => $queryoptions->get_options,
#                 user           => $user,

#                 userrole       => $userrole_ref,
                
#                 format         => $format,
#                 show           => $show,
                
#                 litlist        => $singlelitlist,
#                 other_litlists => $other_litlists_of_user,
                
#                 dbinfo         => $dbinfotable,
#                 targettype     => $targettype,

#                 config         => $config,
#                 user           => $user,
#                 msg            => $msg,
#             };
	    
# 	    OpenBib::Common::Util::print_page($config->{tt_resource_litlist_tname},$ttdata,$r);
#             return Apache2::Const::OK;
                    
}

sub update_entry {
}

sub delete_entry {
                    
#                     if (!$titid || !$titdb || !$litlistid) {
#                         OpenBib::Common::Util::print_warning($msg->maketext("Keine Titelid, Titel-Datenbank oder Literaturliste vorhanden."),$r,$msg);
                        
#                         return Apache2::Const::OK;
#                     }
                    
#                     $user->del_litlistentry({ titid => $titid, titdb => $titdb, litlistid => $litlistid});
                    
#                     $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{resource_litlist_loc}{name}/$litlistid/");
#                     return Apache2::Const::OK;
                    
#                 }
#             my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});

#             my $targettype    = $user->get_targettype_of_session($session->{ID});
            
# 	    my $singlelitlist = {
#                 id         => $litlistid,
#                 recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype}),
#                 properties => $litlist_properties_ref,
#             };

#             if (!$user_owns_litlist){
#                 # Aufruf der Literaturlisten durch "Andere" loggen
#                 $session->log_event({
#                     type      => 800,
#                     content   => $litlistid,
#                 });
#             }
            
#             # Thematische Einordnung

#             my $litlist_subjects_ref   = OpenBib::User->get_subjects_of_litlist({id => $litlistid});
#             my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
                
#             # TT-Data erzeugen
# 	    my $ttdata={
#                 representation  => $representation,

#                 user_owns_litlist => $user_owns_litlist,
                
#                 view           => $view,
#                 stylesheet     => $stylesheet,
#                 sessionID      => $session->{ID},

#                 subjects       => $subjects_ref,
#                 thissubjects   => $litlist_subjects_ref,
#                 query          => $query,
#                 qopts          => $queryoptions->get_options,
#                 user           => $user,

#                 userrole       => $userrole_ref,
                
#                 format         => $format,
#                 show           => $show,
                
#                 litlist        => $singlelitlist,
#                 other_litlists => $other_litlists_of_user,
                
#                 dbinfo         => $dbinfotable,
#                 targettype     => $targettype,

#                 config         => $config,
#                 user           => $user,
#                 msg            => $msg,
#             };
	    
# 	    OpenBib::Common::Util::print_page($config->{tt_resource_litlist_tname},$ttdata,$r);
#             return Apache2::Const::OK;

}

1;
