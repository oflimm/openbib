#####################################################################
#
#  OpenBib::Catalog::Backend::EDS.pm
#
#  Objektorientiertes Interface zum EDS API
#
#  Dieses File ist (C) 2008-2019 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Catalog::Backend::EDS;

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
use OpenBib::API::HTTP::EDS;
use OpenBib::Record::Title;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Set defaults
    my $lang      = exists $arg_ref->{l}
        ? $arg_ref->{l}              : undef;

    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    my $config    = exists $arg_ref->{config}
        ? $arg_ref->{config}         : OpenBib::Config->new;
        
    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}      : undef;
    
    my $self = { };

    bless ($self, $class);

    $self->{database}      = $database;
    
    $self->{have_field_content} = {};

    if ($config){
        $self->{_config}        = $config;
    }
    
    if (defined $sessionID){
        $self->{sessionID} = $sessionID;
    }

    $logger->debug("Creating Catalog::EDS");
    $logger->debug("Config Type".ref($self->{config}));    
    return $self;
}

sub load_full_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    $logger->debug("Config Type".ref($self->{config}));
    
    my $edsid = OpenBib::Common::Util::decode_id($id);

    my $database;
    
    ($database,$edsid)=$edsid=~m/^(.+?)::(.+)$/;

    my $eds = new OpenBib::API::HTTP::EDS({ sessionID => $self->{sessionID} });
    
    my $record = $eds->get_record({ database => $database, id => $edsid});

    return $record;
}

sub load_brief_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->load_full_title_record($arg_ref);
}

1;
__END__

=head1 NAME

OpenBib::Catalog::Backend::EDS - Objektorientiertes Interface zum EDS-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das JSON-API von EDS zugegriffen werden, um auf einen Katalog-Titel uber das vereinheitlichte OpenBib::Catalog Objekt zuzugreifen

=head1 SYNOPSIS

 use OpenBib::Catalog::Backend::EDS;

 my $eds = OpenBib::Catalog::Backend::EDS->new({});

=head1 METHODS

=over 4

=item new({ sessionID => $sessionID, id => $edsid })

Erzeugung des EDS Objektes. sessionID wird benoetigt, um OpenBib-Sessionbasiert das EDS-Sessiontoken via memcached zwischenzuspeichern.

=item load_full_title_record({ id => "$database::$edsid" })

Abfrage des Records.

=item load_short_title_record({ id => "$database::$edsid" })

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
