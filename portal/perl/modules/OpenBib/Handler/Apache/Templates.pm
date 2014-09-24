#####################################################################
#
#  OpenBib::Handler::Apache::Templates.pm
#
#  Copyright 2014 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Templates;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Reload;
use Apache2::Request;
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use JSON::XS;
use Data::Pageset;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape;
use XML::RSS;

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_record'                              => 'show_record',
        'show_collection'                          => 'show_collection',
        'dispatch_to_representation'               => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

# Alle beschreibbaren Templates
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

    # CGI-Parameter

    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');
    my $num    = $queryoptions->get_option('num');
    
    my $topics_ref           = $user->get_topics;
    my $public_litlists_ref  = $user->get_public_litlists({ offset => $offset, num => $num });

    my $nav = Data::Pageset->new({
        'total_entries'    => $user->get_number_of_public_litlists(),
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });
    
    # TT-Data erzeugen
    my $ttdata={
        nav            => $nav,
        topics         => $topics_ref,
        public_litlists=> $public_litlists_ref,
    };
    
    $self->print_page($config->{tt_litlists_tname},$ttdata);
    return Apache2::Const::OK;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/templates.html";

    $logger->debug("Returning to $new_location");

    return $self->redirect($new_location,'303 See Other');

#    $self->query->method('GET');
#    $self->query->content_type('text/html');
#    $self->query->headers_out->add(Location => $new_location);
#    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->strip_suffix($self->param('litlistid'))      || '';
    my $path_prefix    = $self->param('path_prefix');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    
    # CGI Args
    my $method         = $query->param('_method')     || '';
    my $titleid          = $query->param('titleid')       || '';
    my $dbname          = $query->param('dbname')       || '';
    my $title          = decode_utf8($query->param('title'))        || '';
    my $type           = $query->param('type')        || 1;
    my $lecture        = $query->param('lecture')     || 0;
    my $format         = $query->param('format')      || 'short';
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";
    my @topicids     = ($query->param('topicids'))?$query->param('topicids'):();
    my $topicid      = $query->param('topicid')   || undef;

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $topics_ref   = $user->get_topics;

    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");

    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$litlist_is_public){

        if (! $user->{ID}){
            if ($self->param('representation') eq "html"){
                return $self->tunnel_through_authenticator;            
            }
            else {
                $self->print_warning($msg->maketext("Sie sind nicht authentifiziert."));
            }   
            return Apache2::Const::OK;
        }

        if (!$user_owns_litlist){
            $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));

            $logger->debug("UserID: $self->{ID} trying to delete litlistid $litlistid");
            
            # Aufruf der privaten Literaturlisten durch "Andere" loggen
            $session->log_event({
                type      => 800,
                content   => $litlistid,
            });
            
            return;
        }
    }

    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");
    
    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }
    
    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
        
    my $targettype    = $user->get_targettype_of_session($session->{ID});
        
    my $singlelitlist = {
        id         => $litlistid,
        recordlist => $user->get_litlistentries({litlistid => $litlistid, sortorder => $queryoptions->get_option('srto'), sorttype => $queryoptions->get_option('srt')}),
        properties => $litlist_properties_ref,
    };
        
        
    # Thematische Einordnung
        
    my $litlist_topics_ref   = $user->get_topics_of_litlist({id => $litlistid});
    my $other_litlists_of_user = $user->get_other_litlists({litlistid => $litlistid});
    
    # TT-Data erzeugen
    my $ttdata={
        user_owns_litlist => $user_owns_litlist,
        topics       => $topics_ref,
        thistopics   => $litlist_topics_ref,
        query          => $query,
        qopts          => $queryoptions->get_options,
        userrole       => $userrole_ref,
        format         => $format,
        litlist        => $singlelitlist,
        other_litlists => $other_litlists_of_user,
        dbinfo         => $dbinfotable,
        targettype     => $targettype,
    };
    
    $self->print_page($config->{tt_litlists_record_tname},$ttdata);

    return Apache2::Const::OK;
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
