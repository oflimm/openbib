#####################################################################
#
#  OpenBib::Handler::PSGI::Tags.pm
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

package OpenBib::Handler::PSGI::Tags;

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

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'show_collection_recent'               => 'show_collection_recent',
        'show_collection_form'                 => 'show_collection_form',
        'show_record'                          => 'show_record',
        # Redirect delete to Users::Tags
#        'delete_record'                        => 'delete_record',
        
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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $path_prefix    = $self->param('path_prefix');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');

    # CGI Args
    my $method         = $query->param('_method')     || '';
    
    my $offset         = $query->param('offset')            || 0;
    my $num            = $query->param('num')               || 50;
    my $dbname          = $query->param('dbname')             || '';
    my $titisbn        = $query->param('titisbn')           || '';
    my $tags           = decode_utf8($query->param('tags')) || '';
    my $type           = $query->param('type')              || 1;

    my $oldtag         = $query->param('oldtag')            || '';
    my $newtag         = $query->param('newtag')            || '';
    
    # Actions
    my $format         = $query->param('format')            || 'cloud';
    my $private_tags   = $query->param('private_tags')      || 0;
    my $searchtitoftag = $query->param('searchtitoftag')    || '';
    my $edit_usertags  = $query->param('edit_usertags')     || '';
    my $show_usertags  = $query->param('show_usertags')     || '';

    my $queryid        = $query->param('queryid')           || '';

    
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
        query            => $query,
        tag              => $tag,
        tagid            => $tagid,
    };

    return $self->print_page($config->{'tt_tags_tname'},$ttdata);
}

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $path_prefix    = $self->param('path_prefix');
    my $user           = $self->param('user');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    
    my $query  = $r;

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')      || 0;
    my $hitrange       = $query->param('num')    || 50;
    my $database       = $query->param('db')    || '';
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $tags           = decode_utf8($query->param('tags'))        || '';
    my $type           = $query->param('type')        || 1;

    my $oldtag         = $query->param('oldtag')      || '';
    my $newtag         = $query->param('newtag')      || '';
    
    # Actions
    my $format         = $query->param('format')      || 'cloud';
    my $private_tags   = $query->param('private_tags')   || 0;
    my $searchtitoftag = $query->param('searchtitoftag') || '';
    my $edit_usertags  = $query->param('edit_usertags')  || '';
    my $show_usertags  = $query->param('show_usertags')  || '';

    my $queryid        = $query->param('queryid')     || '';

    my $queryoptions = $self->param('qopts');

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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $representation = $self->param('representation');

    # CGI Args
    my $hitrange       = $query->param('num')    || 50;

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

#     return OpenBib::Handler::PSGI::Users::Tags::delete_record($self);
# }


sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/tags.html";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

    return;
}

1;
