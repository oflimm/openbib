#####################################################################
#
#  OpenBib::Catalog::Factory
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Catalog::Factory;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use OpenBib::Config;
use OpenBib::Catalog::Backend::EZB;
use OpenBib::Catalog::Backend::DBIS;
use OpenBib::Catalog::Backend::Local;
    
sub create_catalog {
    my $self = shift;
    my $database = shift;

    my $config = OpenBib::Config->instance;

    my $system = $config->get_system_of_db($database);

    return new OpenBib::Catalog::Backend::EZB($database)  if ($system eq "Backend: EZB");
    return new OpenBib::Catalog::Backend::DBIS($database) if ($system eq "Backend: DBIS");
    return new OpenBib::Catalog::Backend::Local($database); # Default
}

1;
