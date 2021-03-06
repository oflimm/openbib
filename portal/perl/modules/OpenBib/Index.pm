#####################################################################
#
#  OpenBib::Index.pm
#
#  Objektorientiertes Interface fuer die Indexierung in der Suchmaschine
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Index;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode qw(decode decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::Catalog::Factory;
use OpenBib::Container;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;

    my $self = { };

    bless ($self, $class);

    # Entweder genau eine Datenbank via database oder (allgemeiner) ein Suchprofil via searchprofile mit einer oder mehr Datenbanken
    
    if ($database){
        $self->{_database}      = $database;
    }
    
    # Backend Specific Attributes
    
    return $self;
}


sub DESTROY {
    my $self = shift;

    return;
}

1;
