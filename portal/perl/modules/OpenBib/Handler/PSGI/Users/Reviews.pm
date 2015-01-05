#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Reviews.pm
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

package OpenBib::Handler::PSGI::Users::Reviews;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

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

use base 'OpenBib::Handler::PSGI::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'show_record_form'                     => 'show_record_form',
        'create_record'                        => 'create_record',
        'update_record'                        => 'update_record',
        'delete_record'                        => 'delete_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $username       = $user->get_username();
    my $targettype     = $user->get_targettype_of_session($session->{ID});
    my $reviewlist_ref = $user->get_reviews({username => $username});
    
    foreach my $review_ref (@$reviewlist_ref){
        my $titelidn = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
        $review_ref->{titnormset} = OpenBib::Record::Title->new({database=>$database})->load_brief_record({id=>$titelidn})->to_rawdata;
    }
    
    # TT-Data erzeugen
    my $ttdata={
        queryoptions_ref => $queryoptions->get_options,
        targettype       => $targettype,
        dbinfo           => $dbinfotable,
        reviews          => $reviewlist_ref,
    };
    
    return $self->print_page($config->{tt_users_reviews_tname},$ttdata);
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
    
    my $query  = $r;

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
    $reviewid       = $query->param('reviewid')    || '';
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
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});


    if (!$user->{ID}){
        return $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
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
    
    my $query  = $r;

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    my $username  = $user->get_username();

    if (!$user->{ID}){
        return $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
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
    
    my $query  = $r;

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
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }

    my $user = OpenBib::User->instance({sessionID => $session->{ID}});

    if (! $user->{ID}){
        # Aufruf-URL
        my $return_uri = uri_escape($r->request_uri);
        
        return $self->redirect("$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri");
    }

    my $user_owns_review = ($user->{ID} eq $user->get_review_owner({reviewid => $reviewid}))?1:0;

    unless($user_owns_review){
        return $self->print_warning("Der Zugriff ist nicht authorisiert. Melden Sie sich als zugeh&ouml;riger Nutzer an. User:$user->{ID}");
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
    
    return $self->print_page($config->{tt_reviews_edit_tname},$ttdata);
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

    # Shared Args
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/reviews.html";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

    return;
}

1;
