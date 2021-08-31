#####################################################################
#
#  OpenBib::ILS::Factory
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::ILS::Factory;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::ILS::Backend::USBWS;
use OpenBib::ILS::Backend::ALMA;
    
sub create_ils {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}     : undef;

    my $config    = exists $arg_ref->{config}
        ? $arg_ref->{config}       : OpenBib::Config->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    $arg_ref->{config} = $config;
    
    my $ils = $config->get_ils_of_database($database);

    if ($logger->is_debug){
        $logger->debug("Factory for database $database");
    }

    return new OpenBib::ILS::Backend::USBWS($arg_ref)  if ($ils eq "usbws");
    return new OpenBib::ILS::Backend::ALMA($arg_ref)   if ($ils eq "alma");
    
    # Default is USBWS
    return new OpenBib::ILS::Backend::USBWS($arg_ref);
}

1;
