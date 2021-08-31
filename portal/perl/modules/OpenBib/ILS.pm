#####################################################################
#
#  OpenBib::ILS
#
#  Einheitliche Kapselung der Anbindung an Integrierte Bibliothekssysteme
#  (Integrated Library Systems ILS)
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

package OpenBib::ILS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Cache::Memcached::Fast;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Config;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}           : undef;

    my $config    = exists $arg_ref->{config}
        ? $arg_ref->{config}       : OpenBib::Config->new;

    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}     : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $ils_ref = $config->get_ils_of_database($database);

    my $self = { };

    bless ($self, $class);

    $self->{database}= $database;    
    $self->{ils}     = $ils_ref;
    $self->{_config} = $config;
    
    return $self;
}

sub get_config {
    my $self = shift;

    return $self->{_config};    
}

sub get_database {
    my $self = shift;

    return $self->{database};    
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Destroying ILS-Object $self");

    return;
}

1;
__END__

=head1 NAME

OpenBib::ILS - Objekt zur Anbindung eines Integrierten Bibliothekssystems (Authentifizierung, Ausleihe)

=head1 DESCRIPTION

Dieses Objekt stellt Funktionen eines ILS bereit

=head1 SYNOPSIS

 use OpenBib::ILS;

 my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

=head1 Returncodes

=over 4

=item -1 

Es existiert keine ILS-Anbindung fuer die Datenbank $database


=head1 METHODS

=over 4

=item new

Erzeugung des Objektes

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Der Verzicht auf den Exporter 
bedeutet weniger Speicherverbrauch und mehr Performance auf 
Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
