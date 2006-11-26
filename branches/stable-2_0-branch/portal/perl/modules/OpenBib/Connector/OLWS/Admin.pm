####################################################################
#
#  OpenBib::Connector::OLWS::Admin.pm
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Connector::OLWS::Admin;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Admin;
use OpenBib::Config;

sub create_catalogue {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();

    return;
}

sub change_catalogue {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();

    return;
}

sub remove_catalogue {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();

    return;
}

1;
