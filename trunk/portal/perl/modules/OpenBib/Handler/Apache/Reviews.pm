#####################################################################
#
#  OpenBib::Handler::Apache::Reviews.pm
#
#  Copyright 2007-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Reviews;

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
use URI::Escape;

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
        'show_collection_by_isbn_negotiate'    => 'show_collection_by_isbn_negotiate',
        'show_record_negotiate'                => 'show_record_negotiate',
        'show_record_form'                     => 'show_record_form',
        'create_record'                        => 'create_record',
        'update_record'                        => 'update_record',
        'delete_record'                        => 'delete_record',
        'update_vote'                          => 'update_vote',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection_by_isbn_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Entered show_collection");
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $isbn           = $self->param('isbn')           || '';

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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $reviewid       = $query->param('reviewid')    || '';
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

    if (!$user->{ID}){
        $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
        return Apache2::Const::OK;
    }
    
    my $reviewlist_ref = $user->get_reviews({username => $username});
    
    foreach my $review_ref (@$reviewlist_ref){
        my $titelidn = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
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
    
    $self->print_page($config->{tt_reviews_by_isbn_tname},$ttdata);
    
    return Apache2::Const::OK;
}

# Vote for record
sub update_vote {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $reviewid       = $self->param('reviewid')         || '';
    
    
    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    my $rating         = $query->param('rating')      || 0;

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    if (!$session->is_valid()){
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});


    if (!$user->{ID}){
        $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
        return Apache2::Const::OK;
    }
    
    $logger->debug("Vote abgeben fuer Review");

    if (!$user->{ID}){
        $self->print_warning("Sie müssen sich authentifizieren, um diese Rezension zu beurteilen");
        return Apache2::Const::OK;
    }
    
    my $status = $user->vote_for_review({
        reviewid  => $reviewid,
        rating    => $rating,
        username  => $username,
    });
    
    if ($status == 1){
        $self->print_warning("Sie haben bereits diese Rezension beurteilt");
        return Apache2::Const::OK;
    }
    
    $self->return_baseurl;

    return;
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
    my $reviewid       = $self->param('reviewid')         || '';
    
    
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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $reviewid       = $query->param('reviewid')    || '';
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});


    if (!$user->{ID}){
        $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
        return Apache2::Const::OK;
    }
    
    $logger->debug("Aufnehmen/Aendern des Reviews");
    
    $user->add_review({
        titleid     => $titleid,
        dbname     => $dbname,
        username  => $username,
        nickname  => $nickname,
        title     => $title,
        review    => $review,
        rating    => $rating,
    });

    $self->return_baseurl;

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $reviewid       = $self->param('reviewid')         || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $username  = $user->get_username();

    if (!$user->{ID}){
        $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
        return Apache2::Const::OK;
    }
    
    $logger->debug("Loeschung des Reviews");

    $user->del_review_of_user({
        id        => $reviewid,
        username  => $username,
    });

    $self->return_baseurl;

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $reviewid       = $self->param('reviewid')       || '';
    my $path_prefix    = $self->param('path_prefix');

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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    if (! $user->{ID}){
        # Aufruf-URL
        my $return_uri = uri_escape($r->parsed_uri->unparse);
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
        
        return Apache2::Const::OK;
    }

    my $user_owns_review = ($user->{ID} eq $user->get_review_owner({reviewid => $reviewid}))?1:0;

    unless($user_owns_review){
        $self->print_warning("Der Zugriff ist nicht authorisiert. Melden Sie sich als zugeh&ouml;riger Nutzer an. User:$user->{ID}");
        return Apache2::Const::OK;
    }

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

    my $review_ref = $user->get_review_of_user({id => $reviewid, username => $username});
    
    {
        my $titelidn = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
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
    
    $self->print_page($config->{tt_reviews_edit_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_record_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')           || '';
    my $reviewid       = $self->param('reviewid')           || '';
    my $path_prefix    = $self->param('path_prefix');

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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $title          = decode_utf8($query->param('title'))    || '';
    my $review         = decode_utf8($query->param('review'))   || '';
    my $nickname       = decode_utf8($query->param('nickname')) || '';
    my $rating         = $query->param('rating')      || 0;

    my $method         = $query->param('_method')     || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    if (! $user->{ID}){
        # Aufruf-URL
        my $return_uri = uri_escape($r->parsed_uri->unparse);
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
        
        return Apache2::Const::OK;
    }
    
    unless($user->{ID} eq $userid){
        $self->print_warning("Der Zugriff ist nicht authorisiert. Melden Sie sich als zugeh&ouml;riger Nutzer an. User:$user->{ID}");
        return Apache2::Const::OK;
    }

    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

    my $review_ref = $user->get_review_of_user({id => $reviewid, username => $username});
    
    {
        my $titelidn = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
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
    
    $self->print_page($config->{tt_reviews_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_record_negotiatex {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')           || '';
    my $reviewid       = $self->param('reviewid')           || '';
    my $path_prefix    = $self->param('path_prefix');

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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $title          = decode_utf8($query->param('title'))    || '';
    my $review         = decode_utf8($query->param('review'))   || '';
    my $nickname       = decode_utf8($query->param('nickname')) || '';
    my $rating         = $query->param('rating')      || 0;

    my $method         = $query->param('_method')     || '';
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
        $self->print_warning($msg->maketext("Ungültige Session"));

        return Apache2::Const::OK;
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    if (! $user->{ID}){
        # Aufruf-URL
        my $return_uri = uri_escape($r->parsed_uri->unparse);
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
        
        return Apache2::Const::OK;
    }
    
    unless($user->{ID} eq $userid){
        $self->print_warning("Der Zugriff ist nicht authorisiert. Melden Sie sich als zugeh&ouml;riger Nutzer an. User:$user->{ID}");
        return Apache2::Const::OK;
    }

    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

    my $review_ref = $user->get_review_of_user({id => $reviewid, username => $username});
    
    {
        my $titelidn = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
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
    
    $self->print_page($config->{tt_reviews_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $reviewid       = $self->param('reviewid')       || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/reviews.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
