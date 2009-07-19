#####################################################################
#
#  OpenBib::Handler::Apache::LitLists.pm
#
#  Copyright 2007-2009 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

#     my $status=$query->parse;

#     if ($status) {
#         $logger->error("Cannot parse Arguments");
#     }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('hitrange')    || 50;
    my $database       = $query->param('database')    || '';
    my $sorttype       = $query->param('sorttype')    || "author";
    my $sortorder      = $query->param('sortorder')   || "up";
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

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        return Apache2::Const::OK;
    }
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});
    
    if (! $user->{ID} && $do_addlist){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        $r->internal_redirect("http://$config->{servername}$config->{login_loc}?sessionID=$session->{ID};view=$view;do_login=1");

        return Apache2::Const::OK;
    }

    my $subjects_ref = OpenBib::User->get_subjects;

    if ($action eq "manage" && $user->{ID}){
        
	if ($do_addlist) {
            
            if ($title eq ""){
                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
                
                return Apache2::Const::OK;
            }
            
            my $litlistid = $user->add_litlist({ title =>$title, type => $type, subjectids => \@subjectids });

            # Wenn zusaetzlich ein Titel-Eintrag uebergeben wird, dann wird dieser auch
            # der soeben erzeugten Literaturliste hinzugefuegt.
            if ($titid && $titdb && $litlistid){
                $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage&do_addentry=1&titid=$titid&titdb=$titdb&litlistid=$litlistid");
            }
            
            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage");
            return Apache2::Const::OK;
            
	}

	if ($do_dellist) {
            
            $user->del_litlist({ litlistid => $litlistid});

            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage");
            return Apache2::Const::OK;
            
	}

        if ($do_changelist) {
            
            if (!$title || !$type || !$litlistid){
                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel oder einen Typ f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
                
                return Apache2::Const::OK;
            }

            my $userrole_ref = $user->get_roles_of_user($user->{ID});

            if (!$userrole_ref->{librarian} && !$userrole_ref->{lecturer}){
                $lecture = 0;
            }
            
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
            
            if ($litlist_properties_ref->{userid} eq $user->{ID}){
                $user->change_litlist({ title => $title, type => $type, lecture => $lecture, litlistid => $litlistid, subjectids => \@subjectids });
            }
            
            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage");
            return Apache2::Const::OK;
            
	}
	elsif ($do_addentry) {
            
            if (!$litlistid || !$titid || !$titdb ){
                OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste eingegeben oder Titel und Datenbank existieren nicht."),$r,$msg);
                
                return Apache2::Const::OK;
            }
            
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
            
            if ($litlist_properties_ref->{userid} eq $user->{ID}){
                $user->add_litlistentry({ litlistid =>$litlistid, titid => $titid, titdb => $titdb});
            }
            
            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage&do_showlitlist=1&litlistid=$litlistid");
            return Apache2::Const::OK;
	  
	}
        elsif ($do_delentry) {
	  
            if (!$titid || !$titdb || !$litlistid) {
                OpenBib::Common::Util::print_warning($msg->maketext("Keine Titelid, Titel-Datenbank oder Literaturliste vorhanden."),$r,$msg);
	    
                return Apache2::Const::OK;
            }

            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});

            if ($litlist_properties_ref->{userid} eq $user->{ID}) {
                $user->del_litlistentry({ titid => $titid, titdb => $titdb, litlistid => $litlistid});
            }

            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage&litlistid=$litlistid&do_showlitlist=1");
            return Apache2::Const::OK;
	  
	}
        elsif ($do_showlitlist) {
	  
            if (!$litlistid || !$user->{ID} ) {
                OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste oder Sie sind nicht authentifiziert."),$r,$msg);
	    
                return Apache2::Const::OK;
            }
	  
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
	  
            if ($litlist_properties_ref->{userid} eq $user->{ID}) {

                my $targettype    = $user->get_targettype_of_session($session->{ID});

                my $singlelitlist = {
                    id         => $litlistid,
                    recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype }),
                    properties => $litlist_properties_ref,
                };

                # TT-Data erzeugen
                my $ttdata={
                    view       => $view,
                    stylesheet => $stylesheet,
                    sessionID  => $session->{ID},

                    subjects     => $subjects_ref,
                    query        => $query,
                    qopts        => $queryoptions->get_options,
                    user         => $user,

                    format         => $format,
                    show           => $show,

                    litlist      => $singlelitlist,
                    dbinfo       => $dbinfotable,
                    targettype   => $targettype,
                    
                    config     => $config,
                    user       => $user,
                    msg        => $msg,
                };
              
                OpenBib::Common::Util::print_page($config->{tt_litlists_manage_singlelist_tname},$ttdata,$r);
            }
            else {
                OpenBib::Common::Util::print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."),$r,$msg);
            }
            return Apache2::Const::OK;
	  
        }
        else {
            
            my $litlists   = $user->get_litlists();
            my $targettype = $user->get_targettype_of_session($session->{ID});

            # TT-Data erzeugen
            my $ttdata={
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
    }
    elsif ($action eq "show") {
        if ($user->litlist_is_public({litlistid => $litlistid}) || $user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid})) {
        
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
            
	    my $singlelitlist = {
                id         => $litlistid,
                recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype}),
                properties => $litlist_properties_ref,
            };

            # Aufruf der Literaturlisten loggen
            $session->log_event({
                type      => 800,
                content   => $litlistid,
            });

    # Thematische Einordnung

            my $litlist_subjects_ref   = OpenBib::User->get_subjects_of_litlist({id => $litlistid});
            my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
                
                # TT-Data erzeugen
	    my $ttdata={
                view           => $view,
                stylesheet     => $stylesheet,
                sessionID      => $session->{ID},

                subjects       => $subjects_ref,
                thissubjects   => $litlist_subjects_ref,
                query          => $query,
                qopts          => $queryoptions->get_options,
                user           => $user,

                format         => $format,
                show           => $show,
                
                litlist        => $singlelitlist,
                other_litlists => $other_litlists_of_user,
                
                dbinfo         => $dbinfotable,
                
                config         => $config,
                user           => $user,
                msg            => $msg,
            };
	    
	    OpenBib::Common::Util::print_page($config->{tt_litlists_show_singlelist_tname},$ttdata,$r);
            return Apache2::Const::OK;
        }
        else {
	    OpenBib::Common::Util::print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."),$r,$msg);
            return Apache2::Const::OK;
        }
    }
    elsif ($action eq "show_public_lists") {
        my $public_litlists_ref  = $user->get_public_litlists({ subjectid => $subjectid });

        # TT-Data erzeugen
        my $ttdata={
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},

            showsubjects   => $showsubjects,
            subjects       => $subjects_ref,
            subjectid      => $subjectid,
            user           => $user,
            
            public_litlists=> $public_litlists_ref,
                
            config         => $config,
            user           => $user,
            msg            => $msg,
        };
	    
        OpenBib::Common::Util::print_page($config->{tt_litlists_show_publiclists_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }
    return Apache2::Const::OK;
}

1;
