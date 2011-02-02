#####################################################################
#
#  OpenBib::Handler::Apache::Resource::User::Review.pm
#
#  Copyright 2007-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::User::Review;

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

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection_negotiate'            => 'show_collection_negotiate',
        'show_collection_as_html'              => 'show_collection_as_html',
        'show_collection_as_json'              => 'show_collection_as_json',
        'show_collection_as_rdf'               => 'show_collection_as_rdf',
        'show_record_negotiate'                => 'show_record_negotiate',
        'show_record_form'                     => 'show_record_form',
        'create_record'                        => 'create_record',
        'update_record'                        => 'update_record',
        'delete_record'                        => 'delete_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')             || '';
    my $userid         = $self->param('userid')           || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$view/$config->{handler}{resource_user_loc}{name}/$userid/review.$negotiated_type_ref->{suffix}";

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

    return;
}

sub show_collection_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_collection;

    return;
}

sub show_collection_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_collection;

    return;
}

sub show_collection_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_collection;

    return;
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Entered show_collection");
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('hitrange')    || 50;
    my $queryid        = $query->param('queryid')     || '';
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
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

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $loginname  = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

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
    
    OpenBib::Common::Util::print_page($config->{tt_resource_user_review_tname},$ttdata,$r);
    
    return Apache2::Const::OK;
}

sub create_record {
    my $self = shift;

    $self->update_record;

    return;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('hitrange')    || 50;
    my $queryid        = $query->param('queryid')     || '';
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
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

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $loginname  = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});


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

    $self->return_basurl;

    return;
}


sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')           || '';
    my $reviewid       = $self->param('reviewid')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('hitrange')    || 50;
    my $queryid        = $query->param('queryid')     || '';
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
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

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    if (! $user->{ID}){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;
        
        # Return-URL in der Session abspeichern
        
        $session->set_returnurl($return_url);
        
        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}");
        
        return Apache2::Const::OK;
    }
    
    unless($user->{ID} eq $userid){
        OpenBib::Common::Util::print_warning("Der Zugriff ist nicht authorisiert. Melden Sie sich als zugeh&ouml;riger Nutzer an. User:$user->{ID}",$r,$msg);
        return Apache2::Const::OK;
    }

    my $loginname  = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

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
    
    OpenBib::Common::Util::print_page($config->{tt_resource_user_review_single_edit_tname},$ttdata,$r);
    
    return Apache2::Const::OK;
}

sub show_collectionxxx {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('hitrange')    || 50;
    my $queryid        = $query->param('queryid')     || '';
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "author";
    my $sortorder      = $query->param('srto')   || "up";
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
        
        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{search_loc}{name}?database=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
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
        
        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{search_loc}{name}?database=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
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

        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{userreviews_loc}{name}?do_show=1");
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
