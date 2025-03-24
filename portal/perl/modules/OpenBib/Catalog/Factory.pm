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

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Catalog::Backend::BibSonomy;
use OpenBib::Catalog::Backend::EZB;
use OpenBib::Catalog::Backend::EDS;
use OpenBib::Catalog::Backend::DBIS;
use OpenBib::Catalog::Backend::DBISJSON;
use OpenBib::Catalog::Backend::GVI;
use OpenBib::Catalog::Backend::Gesis;
use OpenBib::Catalog::Backend::LobidGND;
use OpenBib::Catalog::Backend::PostgreSQL;
    
sub create_catalog {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;

    my $system = $config->get_system_of_db($database);

    if ($logger->is_debug){
        $logger->debug("Factory for database $database with system $system");
    }

    return new OpenBib::Catalog::Backend::BibSonomy($arg_ref)  if ($system eq "Backend: BibSonomy");
    return new OpenBib::Catalog::Backend::EZB($arg_ref)  if ($system eq "Backend: EZB");
    return new OpenBib::Catalog::Backend::DBIS($arg_ref) if ($system eq "Backend: DBIS");
    return new OpenBib::Catalog::Backend::DBISJSON($arg_ref) if ($system eq "Backend: DBIS-JSON");
    return new OpenBib::Catalog::Backend::EDS($arg_ref) if ($system eq "Backend: EDS");
    return new OpenBib::Catalog::Backend::GVI($arg_ref) if ($system eq "Backend: GVI");
    return new OpenBib::Catalog::Backend::Gesis($arg_ref) if ($system eq "Backend: Gesis");
    return new OpenBib::Catalog::Backend::LobidGND($arg_ref) if ($system eq "Backend: LobidGND");
    return new OpenBib::Catalog::Backend::PostgreSQL($arg_ref); # Default
}

1;
