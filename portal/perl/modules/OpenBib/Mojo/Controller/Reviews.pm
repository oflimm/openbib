#####################################################################
#
#  OpenBib::Mojo::Controller::Reviews.pm
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

package OpenBib::Mojo::Controller::Reviews;

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
use URI::Escape;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection_by_isbn_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Entered show_collection");
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $queryoptions   = $self->stash('qopts');
    my $user           = $self->stash('user');
    my $session        = $self->stash('session');

    my $view           = $self->stash('view')           || '';
    my $isbn           = $self->stash('isbn')           || '';

    my $query  = $r;

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $r->param('offset')      || 0;
    my $hitrange       = $r->param('hitrange')    || 50;
    my $queryid        = $r->param('queryid')     || '';
    my $database       = $r->param('db')    || '';
    my $sorttype       = $r->param('srt')    || "person";
    my $sortorder      = $r->param('srto')   || "asc";
    my $reviewid       = $r->param('reviewid')    || '';
    my $titleid          = $r->param('titleid')       || '';
    my $dbname          = $r->param('dbname')       || '';
    my $titisbn        = $r->param('titisbn')     || '';
    my $title          = decode_utf8($r->param('title'))    || '';
    my $review         = decode_utf8($r->param('review'))   || '';
    my $nickname       = decode_utf8($r->param('nickname')) || '';
    my $rating         = $r->param('rating')      || 0;

    my $do_show        = $r->param('do_show')     || '';
    my $do_add         = $r->param('do_add')      || '';
    my $do_change      = $r->param('do_change')   || '';
    my $do_edit        = $r->param('do_edit')     || '';
    my $do_del         = $r->param('do_del')      || '';
    my $do_vote        = $r->param('do_vote')      || '';
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }



    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});

    if (!$user->{ID}){
        return $self->print_warning("Sie müssen sich authentifizieren, um taggen zu können");
    }
    
    my $reviewlist_ref = $user->get_reviews({username => $username});
    
    foreach my $review_ref (@$reviewlist_ref){
        my $titelidn = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
        $review_ref->{titnormset} = OpenBib::Record::Title->new({ database => $database, config => $config })->load_brief_record({id=>$titelidn})->to_rawdata;
    }
    
    # TT-Data erzeugen
    my $ttdata={
        view             => $view,
        stylesheet       => $stylesheet,
        queryoptions_ref => $queryoptions->get_options,
        sessionID        => $session->{ID},
        targettype       => $targettype,
        reviews          => $reviewlist_ref,
        
        config           => $config,
        user             => $user,
        msg              => $msg,
    };
    
    return $self->print_page($config->{tt_reviews_by_isbn_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $reviewid       = $self->strip_suffix($self->param('reviewid'));

    # Shared Args
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');
    
    my $review_ref = $user->get_review_properties({reviewid => $reviewid});
    
    {
        my $titleid  = $review_ref->{titleid};
        my $database = $review_ref->{dbname};
        
        $review_ref->{record} = OpenBib::Record::Title->new({id => $titleid, database => $database, config => $config })->load_brief_record;
    }

    if (! exists $review_ref->{id}){
        return $self->print_warning("Diese Rezension existiert nicht.");
    }
    
    # TT-Data erzeugen
    my $ttdata={
        review           => $review_ref,
    };
    
    return $self->print_page($config->{tt_reviews_record_tname},$ttdata);
}

1;
