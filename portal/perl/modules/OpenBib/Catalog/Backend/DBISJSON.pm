#####################################################################
#
#  OpenBib::Catalog::Backend::DBISJSON.pm
#
#  Objektorientiertes Interface zum DBIS JSON-API
#
#  Dieses File ist (C) 2008-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Catalog::Backend::DBISJSON;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::API::HTTP::DBISJSON;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $api = new OpenBib::API::HTTP::DBISJSON($arg_ref);
    
    my $self = { };

    bless ($self, $class);

    $self->{api} = $api;
    
    return $self;
}


1;
__END__

=head1 NAME

OpenBib::Catalog::Backend::DBISJSON - Objektorientiertes Interface zum DBIS JSON-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das JSON-API des
Datenbankinformationssystems (DBIS) in Regensburg zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::DBIS;

 my $dbis = OpenBib::Catalog::Factory->create_catalog({ database => 'dbisjson', ...});

=head1 METHODS implemented via OpenBib::API::HTTP::DBISJSON

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
