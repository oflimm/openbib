#####################################################################
#
#  OpenBib::Search::Z3950
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

package OpenBib::Search::Z3950;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

# Hier folgen alle verfuegbaren Z3950-Module. Der letzte Teil des
# Methoden-Namens gibt den Datenbanknamen dieses Kataloges in
# der Web-Administration an
use OpenBib::Search::Z3950::USBK;

# Dispatcher-Methode
sub new {
    my ($class,$subclassname) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $subclassname = "OpenBib::Search::Z3950::$subclassname";
    my $subclass = "$subclassname"->new();
    
    return $subclass ;
}

1;

