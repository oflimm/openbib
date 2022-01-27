#####################################################################
#
#  OpenBib::Search::Backend::EZB.pm
#
#  Objektorientiertes Interface zum EZB XML-API
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Backend::EZB;

use strict;
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

use OpenBib::API::HTTP::EZB;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::Catalog::Factory;
use OpenBib::Container;

use base qw(OpenBib::Search);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $api = new OpenBib::API::HTTP::EZB($arg_ref);
    
    my $self = { };

    bless ($self, $class);

    $self->{api}  = $api;
    $self->{args} = $arg_ref;

    return $self;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->get_api->search($arg_ref);
    
    return $self;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $catalog = OpenBib::Catalog::Factory->create_catalog($self->{args});
    
    my $classifications_ref = $catalog->get_classifications;

    my $container = OpenBib::Container->instance;

    $container->register('classifications_ezb',$classifications_ref);
    
    my $recordlist = $self->get_api->get_search_resultlist;
    
    return $recordlist;
}

sub get_resultcount {
    my $self = shift;

    return $self->get_api->get_resultcount;
}

sub get_facets {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->get_api->get_facets;    
}

sub have_results {
    my $self = shift;

    my $resultcount = $self->get_api->get_resultcount;
    
    return ($resultcount)?$resultcount:0;
}


1;
__END__

=head1 NAME

OpenBib::Search::Backend::EZB - Objektorientiertes Interface zum EZB XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API der
Elektronischen Zeitschriftenbibliothek (EZB) in Regensburg zugegriffen werden.

=head1 SYNOPSIS

=head1 METHODS

=over 4

=item XXX

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
