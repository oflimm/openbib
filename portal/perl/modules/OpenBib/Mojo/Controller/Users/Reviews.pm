#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Reviews.pm
#
#  Copyright 2007-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::Reviews;

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
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Users';

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $username       = $user->get_username();
    my $targettype     = $user->get_targettype_of_session($session->{ID});
    my $reviewlist_ref = $user->get_reviews({username => $username});
    
    foreach my $review_ref (@$reviewlist_ref){
        my $titelidn = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
        $review_ref->{titnormset} = OpenBib::Record::Title->new({database => $database, config => $config })->load_brief_record({id=>$titelidn})->to_rawdata;
    }
    
    # TT-Data erzeugen
    my $ttdata={
        queryoptions_ref => $queryoptions->get_options,
        targettype       => $targettype,
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

    # Dispatched Args    
    my $view           = $self->param('view')           || '';
    my $reviewid       = $self->param('reviewid')       || '';

    # Shared Args  
    my $r              = $self->stash('r');
    my $queryoptions   = $self->stash('qopts');
    my $msg            = $self->stash('msg');
    my $user           = $self->stash('user');
    my $session        = $self->stash('session');
    my $config         = $self->stash('config');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');

    # CGI Args
    my $offset         = $r->param('offset')      || 0;
    my $hitrange       = $r->param('hitrange')    || 50;
    my $queryid        = $r->param('queryid')     || '';
    my $database       = $r->param('db')    || '';
    my $sorttype       = $r->param('srt')    || "person";
    my $sortorder      = $r->param('srto')   || "asc";
    $reviewid          = $r->param('reviewid')    || '';
    my $titleid        = $r->param('titleid')       || '';
    my $dbname         = $r->param('dbname')       || '';
    my $titisbn        = $r->param('titisbn')     || '';
    my $title          = decode_utf8($r->param('title'))    || '';
    my $review         = decode_utf8($r->param('review'))   || '';
    my $nickname       = decode_utf8($r->param('nickname')) || '';
    my $rating         = $r->param('rating')      || 0;

    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    if (!$session->is_valid()){
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

    if (!$user->{ID}){
        return $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
    }
    
    $logger->debug("Aufnehmen/Aendern des Reviews");
    
    $user->add_review({
        titleid   => $titleid,
        dbname    => $dbname,
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
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view')           || '';
    my $reviewid       = $self->stash('reviewid')         || '';


    # Shared Args  
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');

    if (!$session->is_valid()){
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }

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
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view')           || '';
    my $reviewid       = $self->stash('reviewid')       || '';

    # Shared Args  
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $r->param('offset')      || 0;
    my $hitrange       = $r->param('hitrange')    || 50;
    my $queryid        = $r->param('queryid')     || '';
    my $database       = $r->param('db')    || '';
    my $sorttype       = $r->param('srt')    || "person";
    my $sortorder      = $r->param('srto')   || "asc";
    my $titleid          = $r->param('titleid')       || '';
    my $dbname          = $r->param('dbname')       || '';
    my $titisbn        = $r->param('titisbn')     || '';
    my $title          = decode_utf8($r->param('title'))    || '';
    my $review         = decode_utf8($r->param('review'))   || '';
    my $nickname       = decode_utf8($r->param('nickname')) || '';
    my $rating         = $r->param('rating')      || 0;

    if (!$session->is_valid()){
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }

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
        
        $review_ref->{titnormset} = OpenBib::Record::Title->new({database => $database, config => $config })->load_brief_record({id=>$titelidn})->to_rawdata;
    }
    
    # TT-Data erzeugen
    my $ttdata={
        view             => $view,
        stylesheet       => $stylesheet,
        queryoptions_ref => $queryoptions->get_options,
        sessionID        => $session->{ID},
        targettype       => $targettype,
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
    my $config         = $self->stash('config');
    my $path_prefix    = $self->stash('path_prefix');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/reviews.html";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

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
        topics => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        
    };
}

1;
