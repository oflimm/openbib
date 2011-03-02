#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Status
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin::Status;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'               => 'process_show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub process_show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $stid           = $self->param('stid')           || '';
    my $action         = $self->param('action')         || '';
    my $representation = $self->param('representation') || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    # Ist der Nutzer ein Admin?
    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

    # Admin-SessionID ueberpruefen
    # Entweder als Master-Adminuser eingeloggt, oder der Benutzer besitzt die Admin-Rolle
    my $adminsession = $session->is_authenticated_as($adminuser) || $user->is_admin;

    if (!$adminsession) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return Apache2::Const::OK;
    }

    $logger->debug("Server: ".$r->get_server_name);

    my $loadbalancertargets_ref = $config->get_loadbalancertargets;
    
    my $ttdata = {
        loadbalancertargets => $loadbalancertargets_ref,

        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    my $templatename = ($stid && $stid ne "default")?"tt_admin_showoperations_".$stid."_tname":"tt_admin_showoperations_tname";
    
    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
}

1;
