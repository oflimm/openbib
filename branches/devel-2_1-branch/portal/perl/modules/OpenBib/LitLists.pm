#####################################################################
#
#  OpenBib::LitLists.pm
#
#  Copyright 2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::LitLists;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Encode 'decode_utf8';
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;
use OpenBib::User;

my $benchmark;

if ($OpenBib::Config::config{benchmark}) {
    use Benchmark ':hireswallclock';
}

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = new OpenBib::Session({
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
    my $litlistid      = $query->param('litlistid')   || undef;

    my $oldtag         = $query->param('oldtag')      || '';
    my $newtag         = $query->param('newtag')      || '';
    
    # Actions
    my $private_tags   = $query->param('private_tags')   || 0;
    my $searchtitoftag = $query->param('searchtitoftag') || '';
    my $edit_usertags  = $query->param('edit_usertags')  || '';
    my $action         = $query->param('action')         || '';

    my $queryid        = $query->param('queryid')     || '';

    my $do_addlist     = $query->param('do_addlist')     || '';
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
  
    my $queryoptions_ref
        = $session->get_queryoptions($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $targetdbinfo_ref
        = $config->get_targetdbinfo();

    my $targetcircinfo_ref
        = $config->get_targetcircinfo();

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        return OK;
    }
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    my $user = new OpenBib::User({sessionID => $session->{ID}});

    if ($action eq "manage" && $user->{ID}){
        
	if ($do_addlist) {
            
            if ($title eq ""){
                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
                
                return OK;
            }
            
            $user->add_litlist({ title =>$title, type => $type});
            
            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage");
            return OK;
            
	}
	if ($do_changelist) {
            
            if (!$title || !$type || !$litlistid){
                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel oder einen Typ f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
                
                return OK;
            }
            
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
            
            if ($litlist_properties_ref->{userid} eq $user->{ID}){
                $user->change_litlist({ title => $title, type => $type, litlistid => $litlistid});
            }
            
            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage");
            return OK;
            
	}
	elsif ($do_addentry) {
            
            if (!$litlistid || !$titid || !$titdb ){
                OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder keine entsprechende List oder Titel und Datenbank existieren nicht."),$r,$msg);
                
                return OK;
            }
            
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
            
            if ($litlist_properties_ref->{userid} eq $user->{ID}){
                $user->add_litlistentry({ litlistid =>$litlistid, titid => $titid, titdb => $titdb});
            }
            
            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage&do_showlitlist=1&litlistid=$litlistid");
            return OK;
	  
	} elsif ($do_delentry) {
	  
            if (!$titid || !$titdb || !$litlistid) {
                OpenBib::Common::Util::print_warning($msg->maketext("Keine Titelid, Titel-Datenbank oder Literaturliste vorhanden."),$r,$msg);
	    
                return OK;
            }

            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});

            if ($litlist_properties_ref->{userid} eq $user->{ID}) {
                $user->del_litlistentry({ titid => $titid, titdb => $titdb, litlistid => $litlistid});
            }

            $r->internal_redirect("http://$config->{servername}$config->{litlists_loc}?sessionID=$session->{ID}&action=manage&litlistid=$litlistid&do_showlitlist=1");
            return OK;
	  
	} elsif ($do_showlitlist) {
	  
            if (!$litlistid || !$user->{ID} ) {
                OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste oder Sie sind nicht authentifiziert."),$r,$msg);
	    
                return OK;
            }
	  
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
	  
            if ($litlist_properties_ref->{userid} eq $user->{ID}) {

                my $targettype    = $user->get_targettype_of_session($session->{ID});

                my $singlelitlist = {
                    itemlist => $user->get_litlistentries({litlistid => $litlistid}),
                    properties => $litlist_properties_ref,
                };
                # TT-Data erzeugen
                my $ttdata={
                    view       => $view,
                    stylesheet => $stylesheet,
                    sessionID  => $session->{ID},
                  
                    user         => $user,
                    litlist      => $singlelitlist,
                    targetdbinfo => $targetdbinfo_ref,
                    targettype   => $targettype,
                    
                    config     => $config,
                    msg        => $msg,
                };
              
                OpenBib::Common::Util::print_page($config->{tt_litlists_manage_singlelist_tname},$ttdata,$r);
            } else {
                OpenBib::Common::Util::print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."),$r,$msg);
            }
            return OK;
	  
        } else {
            
            my $litlists   = $user->get_litlists();
            my $targettype = $user->get_targettype_of_session($session->{ID});

            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
		      
                litlists   => $litlists,
                user       => $user,
                targettype => $targettype,
                config     => $config,
                msg        => $msg,
            };

            OpenBib::Common::Util::print_page($config->{tt_litlists_manage_lists_tname},$ttdata,$r);
            return OK;
	}
    } elsif ($action eq "show") {
        if ($user->litlist_is_public({litlistid => $litlistid}) || $user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid})) {
        
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
            
	    my $singlelitlist = {
                itemlist => $user->get_litlistentries({litlistid => $litlistid}),
                properties => $litlist_properties_ref,
            };

	    # TT-Data erzeugen
	    my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
                
                user       => $user,
                litlist    => $singlelitlist,
                targetdbinfo  => $targetdbinfo_ref,
                
                config     => $config,
                msg        => $msg,
            };
	    
	    OpenBib::Common::Util::print_page($config->{tt_litlists_show_singlelist_tname},$ttdata,$r);
            return OK;
        } else {
	    OpenBib::Common::Util::print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."),$r,$msg);
            return OK;
        }
    }
    return OK;
}

1;
