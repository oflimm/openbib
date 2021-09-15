#####################################################################
#
#  OpenBib::Authenticator::Factory
#
#  Dieses File ist (C) 2019-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Authenticator::Factory;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::User;
use OpenBib::Authenticator::Backend::SelfRegistration;
use OpenBib::Authenticator::Backend::PAIA;
use OpenBib::Authenticator::Backend::OLWS;
use OpenBib::Authenticator::Backend::LDAP;
use OpenBib::Authenticator::Backend::ILS;
    
sub create_authenticator {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id          = exists $arg_ref->{id}
        ? $arg_ref->{id}           : undef;

    my $config    = exists $arg_ref->{config}
        ? $arg_ref->{config}       : OpenBib::Config->new;

    my $user      = exists $arg_ref->{user}
        ? $arg_ref->{user}         : OpenBib::User->new;

    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    $arg_ref->{config} = $config;
    $arg_ref->{user}   = $user;
    
    my $authenticator_ref = $config->get_authenticator_by_id($id);

    if ($logger->is_debug){
        $logger->debug("Factory for authenticator $id with type ".$authenticator_ref->{type});
    }

    return new OpenBib::Authenticator::Backend::PAIA($arg_ref)  if ($authenticator_ref->{type} eq "paia");
    return new OpenBib::Authenticator::Backend::OLWS($arg_ref)  if ($authenticator_ref->{type} eq "olws");
    return new OpenBib::Authenticator::Backend::LDAP($arg_ref)  if ($authenticator_ref->{type} eq "ldap");
    return new OpenBib::Authenticator::Backend::ILS($arg_ref)  if ($authenticator_ref->{type} eq "ils");
    
    # Default is selfregistration
    return new OpenBib::Authenticator::Backend::SelfRegistration($arg_ref);
}

1;
