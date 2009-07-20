#####################################################################
#
#  OpenBib::Handler::Apache::UserReviews.pm
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

package OpenBib::Handler::Apache::UserReviews;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest (); # internal_redirect
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
use OpenBib::Search::Util;
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
    my $queryid        = $query->param('queryid')     || '';
    my $database       = $query->param('database')    || '';
    my $sorttype       = $query->param('sorttype')    || "author";
    my $sortorder      = $query->param('sortorder')   || "up";
    my $reviewid       = $query->param('reviewid')    || '';
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $title          = decode_utf8($query->param('title'))    || '';
    my $review         = decode_utf8($query->param('review'))   || '';
    my $nickname       = decode_utf8($query->param('nickname')) || '';
    my $rating         = $query->param('rating')      || 0;

    my $do_show        = $query->param('do_show')     || '';
    my $do_add         = $query->param('do_add')      || '';
    my $do_change      = $query->param('do_change')   || '';
    my $do_edit        = $query->param('do_edit')     || '';
    my $do_del         = $query->param('do_del')      || '';
    my $do_vote        = $query->param('do_vote')      || '';
    
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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

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

    my $loginname  = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});


    if ($do_show){

        if (!$user->{ID}){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return Apache2::Const::OK;
        }

        my $reviewlist_ref = $user->get_reviews({loginname => $loginname});

        foreach my $review_ref (@$reviewlist_ref){
            my $titelidn = $review_ref->{titid};
            my $database = $review_ref->{titdb};

            $review_ref->{titnormset} = OpenBib::Record::Title->new({database=>$database})->load_brief_record({id=>$titelidn})->to_rawdata;
        }
        
        # TT-Data erzeugen
        my $ttdata={
            view             => $view,
            stylesheet       => $stylesheet,
            queryoptions_ref => $queryoptions->get_options,
            sessionID        => $session->{ID},
            targettype       => $targettype,
            dbinfo           => $dbinfotable,
            reviews          => $reviewlist_ref,

            config           => $config,
            user             => $user,
            msg              => $msg,
        };

        OpenBib::Common::Util::print_page($config->{tt_userreviews_show_tname},$ttdata,$r);

        return Apache2::Const::OK;
    }

    if ($do_add){

        if (!$user->{ID}){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return Apache2::Const::OK;
        }

        $logger->debug("Aufnehmen/Aendern des Reviews");
        
        $user->add_review({
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
            nickname  => $nickname,
            title     => $title,
            review    => $review,
            rating    => $rating,
        });
        
        $r->internal_redirect("http://$config->{servername}$config->{search_loc}?sessionID=$session->{ID};database=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        return Apache2::Const::OK;
    }

    if ($do_change){

        if (!$user->{ID}){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return Apache2::Const::OK;
        }

        $logger->debug("Aufnehmen/Aendern des Reviews");
        
        $user->add_review({
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
            nickname  => $nickname,
            title     => $title,
            review    => $review,
            rating    => $rating,
        });
        
        $r->internal_redirect("http://$config->{servername}$config->{userreviews_loc}?sessionID=$session->{ID};do_show=1");
        return Apache2::Const::OK;
    }

    if ($do_vote){

        if (!$user->{ID}){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um diese Rezension zu beurteilen",$r,$msg);
            return Apache2::Const::OK;
        }

        my $status = $user->vote_for_review({
            reviewid  => $reviewid,
            rating    => $rating,
            loginname => $loginname,
        });

        if ($status == 1){
            OpenBib::Common::Util::print_warning("Sie haben bereits diese Rezension beurteilt",$r,$msg);
            return Apache2::Const::OK;
        }
        
        $r->internal_redirect("http://$config->{servername}$config->{search_loc}?sessionID=$session->{ID};database=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        return Apache2::Const::OK;

    }

        if ($do_del){

        if (!$user->{ID}){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return Apache2::Const::OK;
        }

        $user->del_review_of_user({
            id        => $reviewid,
            loginname => $loginname,
        });

        $r->internal_redirect("http://$config->{servername}$config->{userreviews_loc}?sessionID=$session->{ID};do_show=1");
        return Apache2::Const::OK;

    }

            
    if ($do_edit){
        
        if (!$user->{ID}){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return Apache2::Const::OK;
        }

        my $review_ref = $user->get_review_of_user({id => $reviewid, loginname => $loginname});

        {
            my $titelidn = $review_ref->{titid};
            my $database = $review_ref->{titdb};

            $review_ref->{titnormset} = OpenBib::Record::Title->new({database=>$database})->load_brief_record({id=>$titelidn})->to_rawdata;
        }
        
        # TT-Data erzeugen
        my $ttdata={
            view             => $view,
            stylesheet       => $stylesheet,
            queryoptions_ref => $queryoptions->get_options,
            sessionID        => $session->{ID},
            targettype       => $targettype,
            dbinfo           => $dbinfotable,
            review           => $review_ref,

            config           => $config,
            user             => $user,
            msg              => $msg,
        };

        OpenBib::Common::Util::print_page($config->{tt_userreviews_edit_tname},$ttdata,$r);
        
        return Apache2::Const::OK;
    }

    return Apache2::Const::OK;
}

1;
