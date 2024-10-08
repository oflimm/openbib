#####################################################################
#
#  OpenBib::Catalog::Backend::LobidGND.pm
#
#  Objektorientiertes Interface zum Lobid GND API
#
#  Dieses File ist (C) 2023- Oliver Flimm <flimm@openbib.org>
#  basiert auf DBIS-Backend
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

package OpenBib::Catalog::Backend::LobidGND;

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
use JSON::XS;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::API::HTTP::LobidGND;
use OpenBib::Record::Title;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}        : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}          : OpenBib::Config->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($@){
	$logger->error($@);
    }
    
    my $api = new OpenBib::API::HTTP::LobidGND($arg_ref);
    
    my $self = { };

    bless ($self, $class);

    $self->{api} = $api;
    
    return $self;
}

sub load_full_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $id = OpenBib::Common::Util::decode_id($id);

    my $record = $self->get_api->get_titles_record({ database => $database, id => $id});

    return $record;
}

1;
__END__

=head1 NAME

OpenBib::Catalog::Backend::LobidGND - Objektorientiertes Interface zum LobidGND API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das API von Lobid GND zugegriffen werden, um auf einen Normdateneintrag als Katalog-Titel uber das vereinheitlichte OpenBib::Catalog Objekt zuzugreifen

=head1 SYNOPSIS

 use OpenBib::Catalog::Backend::LobidGND;

 my $gnd = OpenBib::Catalog::Backend::LobidGND->new({});

=head1 METHODS

=over 4

=item new({ })

Erzeugung des LobidGND Objektes.

=item load_full_title_record({ id => $gnd_id })

Abfrage des Records.

=item load_short_title_record({ id => $gvi_id })

Abfrage des Records. Nutzt load_full_title_record.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
