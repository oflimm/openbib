#####################################################################
#
#  OpenBib::Mojo::Controller::Tags.pm
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

package OpenBib::Mojo::Controller::Tags;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Data::Pageset;
use URI::Escape;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use DBI;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

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

    # CGI-Parameter

    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');
    my $num    = $queryoptions->get_option('num');

    my $public_tags_ref = $user->get_public_tags({offset => $offset, num => $num});

    my $total_count = $user->get_number_of_public_tags();
    
    my $nav = Data::Pageset->new({
        'total_entries'    => $total_count,
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });

    # TT-Data erzeugen
    my $ttdata={
        total_count   => $total_count,
        nav           => $nav,
        public_tags   => $public_tags_ref,
    };

    return $self->print_page($config->{tt_tags_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');
    my $userid         = $self->param('userid');
    my $tagid          = $self->strip_suffix($self->param('tagid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $path_prefix    = $self->stash('path_prefix');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');

    # CGI Args
    my $method         = $r->param('_method')     || '';
    
    my $offset         = $r->param('offset')            || 0;
    my $num            = $r->param('num')               || 50;
    my $dbname          = $r->param('dbname')             || '';
    my $titisbn        = $r->param('titisbn')           || '';
    my $tags           = decode_utf8($r->param('tags')) || '';
    my $type           = $r->param('type')              || 1;

    my $oldtag         = $r->param('oldtag')            || '';
    my $newtag         = $r->param('newtag')            || '';
    
    # Actions
    my $format         = $r->param('format')            || 'cloud';
    my $private_tags   = $r->param('private_tags')      || 0;
    my $searchtitoftag = $r->param('searchtitoftag')    || '';
    my $edit_usertags  = $r->param('edit_usertags')     || '';
    my $show_usertags  = $r->param('show_usertags')     || '';

    my $queryid        = $r->param('queryid')           || '';

    
    my $recordlist = new OpenBib::RecordList::Title;
    my $hits       = 0;

    # Mit Suffix, dann keine Aushandlung des Typs

    my $tag        = undef;

    # Tags per id
    if ($tagid =~ /^\d+$/){
        # Zuerst Gesamtzahl bestimmen
        $tag = $user->get_name_of_tag({tagid => $tagid});
    }
    # Tags per name
    else {
        $tag = $tagid;

        $tagid = $user->get_id_of_tag({tag => $tag});
    }
    
    my $titles_ref;
    
    ($recordlist,$hits)= $user->get_titles_of_tag({
        tagid     => $tagid,
        offset    => $offset,
        hitrange  => $num,
    });
        
    # Zugriff loggen
    $session->log_event({
        type      => 804,
        content   => $tag,
    });

    if ($logger->is_debug){
        $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
    }

    $recordlist->load_brief_records;

    $recordlist->sort({order => $queryoptions->get_option('srto'), type => $queryoptions->get_option('srt')});
    
    my $ttdata = {
        sortorder        => $queryoptions->get_option('srto'),
        sorttype         => $queryoptions->get_option('srt'),
        hits             => $hits,
        offset           => $offset,
        num              => $num,

        recordlist       => $recordlist,
        query            => $r,
        tag              => $tag,
        tagid            => $tagid,
    };

    return $self->print_page($config->{'tt_tags_tname'},$ttdata);
}

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view')           || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $user           = $self->stash('user');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $r->param('offset')      || 0;
    my $hitrange       = $r->param('num')         || 50;
    my $database       = $r->param('db')          || '';
    my $sorttype       = $r->param('srt')         || "person";
    my $sortorder      = $r->param('srto')        || "asc";
    my $titleid        = $r->param('titleid')     || '';
    my $dbname         = $r->param('dbname')      || '';
    my $titisbn        = $r->param('titisbn')     || '';
    my $tags           = decode_utf8($r->param('tags'))        || '';
    my $type           = $r->param('type')        || 1;

    my $oldtag         = $r->param('oldtag')      || '';
    my $newtag         = $r->param('newtag')      || '';
    
    # Actions
    my $format         = $r->param('format')      || 'cloud';
    my $private_tags   = $r->param('private_tags')   || 0;
    my $searchtitoftag = $r->param('searchtitoftag') || '';
    my $edit_usertags  = $r->param('edit_usertags')  || '';
    my $show_usertags  = $r->param('show_usertags')  || '';

    my $queryid        = $r->param('queryid')     || '';

    my $queryoptions = $self->stash('qopts');

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        return $self->print_warning($msg->maketext("Ungültige Session"));
    }



    unless($user->{ID}){
        # Aufruf-URL
        my $return_uri = uri_escape($r->request_uri);

        # TODO internal redirect
        $self->redirect("$config->{base_loc}/$view/$config->{login_loc}?do_login=1;redirect_to=$return_uri");

        return;
    }

    my $targettype=$user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        targettype => $targettype,
        user       => $user,
        config     => $config,
        user       => $user,
        msg        => $msg,
    };

    return $self->print_page($config->{tt_users_tags_edit_tname},$ttdata);
}

# Alle oeffentlichen Literaturlisten
sub show_collection_recent {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $representation = $self->stash('representation');

    # CGI Args
    my $hitrange       = $r->param('num')    || 50;

    my @viewdbs         = $config->get_viewdbs($view);

    # Tag-Cloud ist View-abhaengig. Wenn View nur aus einer Datenbank besteht, dann werden alle Tags fuer Titel aus der Datenbank herausgegeben, sonst alle.
    # ToDo: fuer alle Datenbanken eines Views, d.h. auch bei mehr als einer...
    my $recent_tags_ref = ($database)?$user->get_recent_tags({ count => $hitrange, database => $database }):
        ($#viewdbs == 0)?$user->get_recent_tags({ count => $hitrange, database => $viewdbs[0] }): $user->get_recent_tags({ count => $hitrange });

    # TT-Data erzeugen
    my $ttdata={
        recent_tags    => $recent_tags_ref,
    };
    
    return $self->print_page($config->{tt_tags_collection_recent_tname},$ttdata);
}

# sub delete_record {
#     my $self = shift;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     return OpenBib::Mojo::Controller::Users::Tags::delete_record($self);
# }


sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->stash('view')           || '';
    my $userid         = $self->stash('userid')         || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/tags.html";

    # TODO GET?
    $self->res->headers->content_type('text/html');
    $self->redirect($new_location);

    return;
}

1;
