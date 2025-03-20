#####################################################################
#
#  OpenBib::Mojo::Controller::ServerActive
#
#  Dieses File ist (C) 2004-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::ServerActive;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r              = $self->stash('r');
    my $config         = OpenBib::Config->new;


    if ($config->local_server_is_active_and_searchable){
	$logger->debug("Server is active and searchable");

        $self->res->code(200);
        $self->res->headers->content_type('text/plain');
        $self->render( text => 'enabled');
    }
    else {
	$logger->debug("Server not available");
        $self->res->code(404);
        return;
    }
}

1;

