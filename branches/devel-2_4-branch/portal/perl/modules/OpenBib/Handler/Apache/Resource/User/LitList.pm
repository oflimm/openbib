#####################################################################
#
#  OpenBib::Handler::Apache::Resource::User::LitList.pm
#
#  Copyright 2009-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::User::LitList;

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
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'negotiate_url'                        => 'negotiate_url',
        'show_collection_as_html'              => 'show_collection_as_html',
        'show_collection_as_json'              => 'show_collection_as_json',
        'show_collection_as_rdf'               => 'show_collection_as_rdf',
        'show_collection_by_subject_negotiate' => 'show_collection_by_subject_negotiate',
        'show_collection_by_subject_as_html'   => 'show_collection_by_subject_as_html',
        'show_collection_by_subject_as_json'   => 'show_collection_by_subject_as_json',
        'show_collection_by_subject_as_rdf'    => 'show_collection_by_subject_as_rdf',
        'show_record_by_subject_negotiate'     => 'show_record_by_subject_negotiate',
        
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

# Alle oeffentlichen Literaturlisten
sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $representation = $self->param('representation') || 'html';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    
    # NO CGI Args

    $logger->debug("SessionID: ".$session->{ID}." / UserID: ".$user->{ID}." / userid in URI: $userid");

    if (! $user->{ID}){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;
        
        # Return-URL in der Session abspeichern
        
        $session->set_returnurl($return_url);
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{login_loc}");
        
        return Apache2::Const::OK;
    }

    unless($user->{ID} eq $userid){
        OpenBib::Common::Util::print_warning("Der Zugriff ist nicht authorisiert. Melden Sie sich als zugeh&ouml;riger Nutzer an. User:$user->{ID}",$r,$msg);
        return Apache2::Const::OK;
    }
    
    my $subjects_ref = OpenBib::User->get_subjects;

    my $userrole_ref = $user->get_roles_of_user($user->{ID});
    
    my $litlists   = $user->get_litlists();
    my $targettype = $user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        representation  => $representation,

        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },
        
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        subjects   => $subjects_ref,
        litlists   => $litlists,
        qopts      => $queryoptions->get_options,
        user       => $user,
        targettype => $targettype,
        config     => $config,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_resource_user_litlist_collection_tname},$ttdata,$r);
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

    my $new_location = "$path_prefix/$config->{resource_user_loc}/$userid/litlist.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
