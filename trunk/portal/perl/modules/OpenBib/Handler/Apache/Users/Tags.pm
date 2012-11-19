#####################################################################
#
#  OpenBib::Handler::Apache::Users::Tags.pm
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

package OpenBib::Handler::Apache::Users::Tags;

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
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'show_collection_form'                 => 'show_collection_form',
        'show_record'                          => 'show_record',
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

    # CGI Args
    my $format         = $query->param('format')      || 'cloud';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $username   = $user->get_username();
    my $targettype = $user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        format     => $format,
        targettype => $targettype,
        username   => $username,
    };

    $self->print_page($config->{tt_users_tags_collection_tname},$ttdata,$r);

    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $tagid          = $self->strip_suffix($self->param('tagid'));

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
    my $content_type   = $self->param('content_type');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $offset         = $query->param('offset') || 0;
    my $hitrange       = $query->param('num')    || 50;
    my $database       = $query->param('db')     || '';
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my $format         = $query->param('format') || 'cloud';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $username   = $user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title;
    my $hits       = 0;

    my $tag        = undef;
    
    if ($tagid =~ /^\d+$/){
        # Zuerst Gesamtzahl bestimmen
        $tag = $user->get_name_of_tag({tagid => $tagid});
    }
    
    my $titles_ref;
    
    ($recordlist,$hits)= $user->get_titles_of_tag({
        username  => $username,
        tagid     => $tagid,
        offset    => $offset,
        hitrange  => $hitrange,
    });
        
    # Zugriff loggen
    $session->log_event({
        type      => 804,
        content   => $tag,
    });
    
    $logger->debug("Titel-IDs: ".YAML::Dump($recordlist->to_ids));
    
    $recordlist->print_to_handler({
        representation   => $representation,
        content_type     => $content_type,
        database         => $database,
        sortorder        => $sortorder,
        sorttype         => $sorttype,
        apachereq        => $r,
        stylesheet       => $stylesheet,
        view             => $view,
        hits             => $hits,
        offset           => $offset,
        hitrange         => $hitrange,
        query            => $query,
        template         => 'tt_users_tags_tname',
        location         => 'users_loc',
        parameter        => {
            username     => $username,
            tag          => $tag,
            private_tags => 1,
        },
        
        msg              => $msg,
    });

    return Apache2::Const::OK;
}

sub show_collection_form {
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
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $targettype=$user->get_targettype_of_session($session->{ID});

    # TT-Data erzeugen
    my $ttdata={
        targettype => $targettype,
    };
    
    $self->print_page($config->{tt_users_tags_edit_tname},$ttdata);
    return Apache2::Const::OK;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/tags.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
