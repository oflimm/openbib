#####################################################################
#
#  OpenBib::Handler::Apache::Resource::LitLists.pm
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

package OpenBib::Handler::Apache::LitLists;

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
        'add'                => 'add_private_list',
        'private'            => 'show_private_lists',
        'public'             => 'show_public_lists',
        'public_by_subject'  => 'show_public_lists_by_subject',
    );
    
    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_public_lists {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $arg            = $self->param('arg')            || '';
    my $representation = $self->param('dispatch_url_remainder');

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
    
    # TT-Data erzeugen
    my $ttdata={
        representation => $representation,
        
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

sub show_public_lists_by_subject {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $arg            = $self->param('arg')            || '';
    my $remaining_uri  = $self->param('dispatch_url_remainder');

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

    my ($subjectid,$representation)=(undef,'');

    # Processing Remaining URI
    if ($remaining_uri=~m/^(\d+)\/([^\/]+)$/){
        $subjectid      = $1;
        $representation = $2;
    }
    elsif ($remaining_uri=~m/^(\d+)/){
        $subjectid      = $1;
        $representation = '';
    }
    elsif ($remaining_uri=~m/^([^\/]+)$/){
        $subjectid      = undef;
        $representation = $1;
    }
    else {
        $subjectid      = undef;
        $representation = '';
    }

    my $showsubjects = 0;
    
    if (!$subjectid){
        $showsubjects = 1 ;
    }

    my $subjects_ref         = OpenBib::User->get_subjects;
    my $public_litlists_ref  = $user->get_public_litlists({ subjectid => $subjectid });
    
    # TT-Data erzeugen
    my $ttdata={
        representation => $representation,

        showsubjects   => $showsubjects,
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},
        
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

sub show_private_lists {
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
    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('num')         || 50;
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my $lecture        = $query->param('lecture')     || 0;
    my $format         = $query->param('format')      || 'HTML';
    my $show           = $query->param('show')        || 'short';
    my $litlistid      = $query->param('litlistid')   || undef;
    my $showsubjects   = $query->param('showsubjects') || undef;
    my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
    my $subjectid      = $query->param('subjectid')   || undef;
    my $oldtag         = $query->param('oldtag')      || '';
    my $newtag         = $query->param('newtag')      || '';
    
    # Actions
    my $private_tags   = $query->param('private_tags')   || 0;
    my $searchtitoftag = $query->param('searchtitoftag') || '';
    my $edit_usertags  = $query->param('edit_usertags')  || '';
    my $action         = $query->param('action')         || '';

    my $queryid        = $query->param('queryid')     || '';

    my $do_addlist     = $query->param('do_addlist')     || '';
    my $do_dellist     = $query->param('do_dellist')     || '';
    my $do_addentry    = $query->param('do_addentry')    || '';
    my $do_showlitlist = $query->param('do_showlitlist') || '';
    my $do_changelist  = $query->param('do_changelist')  || '';
    my $do_change      = $query->param('do_change')      || '';
    my $do_delentry    = $query->param('do_delentry')    || '';
  
    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = OpenBib::User->get_subjects;
    
    if (! $user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie sind nicht authentifiziert"),$r,$msg);
        return Apache2::Const::OK;
    }
    
    my $userrole_ref = $user->get_roles_of_user($user->{ID});
    
    my $litlists   = $user->get_litlists();
    my $targettype = $user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        representation  => $representation,
        
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        subjects   => $subjects_ref,
        litlists   => $litlists,
        qopts      => $queryoptions->get_options,
        user       => $user,
        targettype => $targettype,
        config     => $config,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_litlists_manage_lists_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

# sub show_publicxxxx_lists {
#     my $self = shift;
    
#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     # Dispatched Args
#     my $r              = $self->param('r');
#     my $view           = $self->param('view')           || '';
#     my $representation = $self->param('representation') || '';

#     # Shared Args
#     my $query          = $self->query();
#     my $config         = $self->param('config');    
#     my $session        = $self->param('session');
#     my $user           = $self->param('user');
#     my $msg            = $self->param('msg');
#     my $queryoptions   = $self->param('qopts');
#     my $stylesheet     = $self->param('stylesheet');    
#     my $useragent      = $self->param('useragent');
    
#     # CGI Args
#     my $offset         = $query->param('offset')      || 0;
#     my $hitrange       = $query->param('num')         || 50;
#     my $sorttype       = $query->param('srt')    || "author";
#     my $sortorder      = $query->param('srto')   || "up";
#     my $titid          = $query->param('titid')       || '';
#     my $titdb          = $query->param('titdb')       || '';
#     my $titisbn        = $query->param('titisbn')     || '';
#     my $title          = decode_utf8($query->param('title'))        || '';
#     my $type           = $query->param('type')        || 1;
#     my $lecture        = $query->param('lecture')     || 0;
#     my $format         = $query->param('format')      || 'HTML';
#     my $show           = $query->param('show')        || 'short';
#     my $litlistid      = $query->param('litlistid')   || undef;
#     my $showsubjects   = $query->param('showsubjects') || undef;
#     my @subjectids     = ($query->param('subjectids'))?$query->param('subjectids'):();
#     my $subjectid      = $query->param('subjectid')   || undef;
#     my $oldtag         = $query->param('oldtag')      || '';
#     my $newtag         = $query->param('newtag')      || '';
    
#     my $do_addlist     = $query->param('do_addlist')     || '';
#     my $do_dellist     = $query->param('do_dellist')     || '';
#     my $do_change      = $query->param('do_change')      || '';
#     my $do_delentry    = $query->param('do_delentry')    || '';
  
#     #####                                                          ######
#     ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
#     #####                                                          ######

#     my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
    
#     # Basisipfad entfernen
#     my $basepath = $config->{base_loc}."/$view/".$config->{resource_litlist_loc};
#     $path=~s/$basepath//;
    
#     $logger->debug("Path: $path without basepath $basepath");
    
#     # Service-Parameter aus URI bestimmen
#     my $representation;
    
#     my @valid_representations = (
#         'html',
#         'bibtex',
#         'json',
#     );
    
#     my $valid_representations_regexp = join("\|",@valid_representations);
    
#     $logger->debug("ValidRepRegexp:".$valid_representations_regexp);
#     if ($path=~m/^\/(\d+)\/($valid_representations_regexp)$/){
#         $litlistid       = $1;
#         $representation = $2;
#         $action         = "single_list";
#     }
#     elsif ($path=~m/^\/(\d+)/){
#         $litlistid       = $1;
#         $representation = '';
#         $action         = "single_list";
#     }
#     elsif ($path=~m/^\/public_all\/($valid_representations_regexp)$/){
#         $litlistid       = $1;
#         $representation = $2;
#         $action   = "show_public_lists";
#     }    
#     elsif ($path=~m/^\/public_all/){
#         $litlistid       = $1;
#         $representation = '';
#         $action   = "show_public_lists";
#     }    
#     elsif ($path=~m/^\/public_by_subject\/($valid_representations_regexp)$/){
#         $litlistid       = $1;
#         $representation = $2;
#         $action   = "show_public_lists";
#         $showsubjects = 1;
#     }    
#     elsif ($path=~m/^\/public_by_subject/){
#         $litlistid       = $1;
#         $representation = '';
#         $action   = "show_public_lists";
#         $showsubjects = 1;
#     }    
#     elsif ($path=~m/^\/private\/($valid_representations_regexp)$/){
#         $litlistid       = $1;
#         $representation = $2;
#         $action   = "manage_private_lists";
#     }    
#     elsif ($path=~m/^\/private/){
#         $litlistid       = $1;
#         $representation = '';
#         $action   = "manage_private_lists";
#     }    
#     elsif ($path=~m/^\/($valid_representations_regexp)$/){
#         $litlistid       = $1;
#         $representation = $2;
#         $action   = "show_public_lists";
#     }    
#     elsif ($path=~m/^\/$/){
#         $litlistid       = $1;
#         $representation = '';
#         $action   = "show_public_lists";
#     }    
#     else {
#         return Apache2::Const::OK;        
#     }


#     my $user = OpenBib::User->instance({sessionID => $session->{ID}});
    
#     if (! $user->{ID} && $do_addlist){
#         # Aufruf-URL
#         my $return_url = $r->parsed_uri->unparse;

#         # Return-URL in der Session abspeichern

#         $session->set_returnurl($return_url);

#         $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{login_loc}?do_login=1");

#         return Apache2::Const::OK;
#     }

#     my $subjects_ref = OpenBib::User->get_subjects;

#     if ($action eq "manage_private_lists" && $user->{ID}){

#         my $userrole_ref = $user->get_roles_of_user($user->{ID});

# 	if ($do_addlist) {
            
#             if ($title eq ""){
#                 OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
                
#                 return Apache2::Const::OK;
#             }
            
#             my $litlistid = $user->add_litlist({ title =>$title, type => $type, subjectids => \@subjectids });
            
#             # Wenn zusaetzlich ein Titel-Eintrag uebergeben wird, dann wird dieser auch
#             # der soeben erzeugten Literaturliste hinzugefuegt.
#             if ($titid && $titdb && $litlistid){
#                 $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{resource_litlists_loc}/$litlistid/?action=manage&do_addentry=1&titid=$titid&titdb=$titdb");
#             }
            
#             $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{resource_litlists_loc}/private/");
#             return Apache2::Const::OK;
            
# 	}        
# 	elsif ($do_dellist) {
            
#             $user->del_litlist({ litlistid => $litlistid});
            
#             $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{litlists_loc}/private/");
#             return Apache2::Const::OK;
            
# 	}
#         elsif ($do_changelist) {
            
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
            
#             $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{resource_litlist_loc}/private/");
#             return Apache2::Const::OK;
            
# 	}
#         else {
            
#             my $litlists   = $user->get_litlists();
#             my $targettype = $user->get_targettype_of_session($session->{ID});

#             # TT-Data erzeugen
#             my $ttdata={
#                 representation  => $representation,
                
#                 view       => $view,
#                 stylesheet => $stylesheet,
#                 sessionID  => $session->{ID},

#                 subjects   => $subjects_ref,
#                 litlists   => $litlists,
#                 qopts      => $queryoptions->get_options,
#                 user       => $user,
#                 targettype => $targettype,
#                 config     => $config,
#                 user       => $user,
#                 msg        => $msg,
#             };

#             OpenBib::Common::Util::print_page($config->{tt_litlists_manage_lists_tname},$ttdata,$r);
#             return Apache2::Const::OK;
# 	}
#     }
#     elsif ($action eq "single_list"){
#         my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
#         my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
#         my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);
        
#         if ($litlist_is_public || $user_owns_litlist) {

#             # Aktionen moeglich, wenn dem Nutzer die Liste gehoert
#             if ($user_owns_litlist){

#                 if ($do_addentry) {
            
#                     if (!$litlistid || !$titid || !$titdb ){
#                         OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste eingegeben oder Titel und Datenbank existieren nicht."),$r,$msg);
                        
#                         return Apache2::Const::OK;
#                     }
                    
#                     $user->add_litlistentry({ litlistid =>$litlistid, titid => $titid, titdb => $titdb});
                    
#                     $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{resource_litlist_loc}/$litlistid/?action=manage&do_showlitlist=1");
#                     return Apache2::Const::OK;
                    
#                 }
#                 elsif ($do_delentry) {
                    
#                     if (!$titid || !$titdb || !$litlistid) {
#                         OpenBib::Common::Util::print_warning($msg->maketext("Keine Titelid, Titel-Datenbank oder Literaturliste vorhanden."),$r,$msg);
                        
#                         return Apache2::Const::OK;
#                     }
                    
#                     $user->del_litlistentry({ titid => $titid, titdb => $titdb, litlistid => $litlistid});
                    
#                     $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{resource_litlist_loc}/$litlistid/");
#                     return Apache2::Const::OK;
                    
#                 }
#             }
            
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
#         }
#         else {
# 	    OpenBib::Common::Util::print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."),$r,$msg);
#             return Apache2::Const::OK;
#         }
#     }
#     elsif ($action eq "show_public_lists") {
#         my $public_litlists_ref  = $user->get_public_litlists({ subjectid => $subjectid });

#         # TT-Data erzeugen
#         my $ttdata={
#             representation => $representation,
            
#             view           => $view,
#             stylesheet     => $stylesheet,
#             sessionID      => $session->{ID},

#             showsubjects   => $showsubjects,
#             subjects       => $subjects_ref,
#             subjectid      => $subjectid,
#             user           => $user,
            
#             public_litlists=> $public_litlists_ref,
                
#             config         => $config,
#             user           => $user,
#             msg            => $msg,
#         };
	    
#         OpenBib::Common::Util::print_page($config->{tt_resource_litlist_public_tname},$ttdata,$r);
#         return Apache2::Const::OK;
#     }
    
#     $logger->debug("Type: litlist - Key: $litlistid - Representation: $representation");

#     return Apache2::Const::OK;
# }

1;
