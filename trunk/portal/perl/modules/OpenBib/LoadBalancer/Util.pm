#####################################################################
#
#  OpenBib::LoadBalancer::Util
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::LoadBalancer::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Reload;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

sub benachrichtigung {
    my ($message)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Benachrichtigung via mail
    open(MAIL,"| $config->{mail_prog} -s \"KUG-Probleme\" $config->{admin_email}") or $logger->error_die("Problem-Mail konnte nicht verschickt werden");
    print MAIL << "MAILENDE";
Es ist ein Problem mit dem KUG aufgetreten.

$message

MAILENDE
    close(MAIL);
}

1;
