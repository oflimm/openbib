#####################################################################
#
#  OpenBib::Handler::Apache::LoadBalancer
#
#  Dieses File ist (C) 1997-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::LoadBalancer;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestRec ();
use HTTP::Request;
use HTTP::Response;
use IO::Socket;
use LWP::UserAgent;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::LoadBalancer::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $urlquery=$r->args;      #query->url(-query=>1);

    $urlquery=~s/^.+?\?//;

    my $bestserver=OpenBib::Common::Util::get_loadbalanced_servername();
    
    # Wenn wir keinen 'besten Server' bestimmen konnten, dann sind alle
    # ausgefallen, dem Benutzer wird eine 'Hinweisseite' ausgegeben
    if ($bestserver eq "") {

        # TT-Data erzeugen
        my $ttdata={
            title        => 'KUG - Wartungsarbeiten',
            config       => $config,
            msg          => $msg,
        };

        OpenBib::Common::Util::print_page($config->{tt_loadbalancer_tname},$ttdata,$r);
        OpenBib::LoadBalancer::Util::benachrichtigung($msg->maketext("Achtung: Es sind *alle* Server ausgefallen"));

        return Apache2::Const::OK;
    }

    $self->header_type('redirect');
    $self->header_props(-type => 'text/html', -url => "http://$bestserver$path_prefix/$config->{startopac_loc}?$urlquery");
}

1;
