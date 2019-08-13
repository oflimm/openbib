#####################################################################
#
#  OpenBib::Authenticator
#
#  Dieses File ist (C) 2019 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Authenticator;

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
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    $config = ($config)?$config:OpenBib::Config->new;

    my $authenticator_ref = $config->get_authenticator_by_id($id);

    my $self = { };

    bless ($self, $class);

    $self->{id}     = $id;
    $self->{_config} = $config;
    
    foreach my $key (keys %{$authenticator_ref}){
	$self->{$key}     = $authenticator_ref->{$key};
    }

    
    return $self;
}

sub authenticate {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $viewname    = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}       : undef;
    
    my $username    = exists $arg_ref->{username}
        ? $arg_ref->{username}       : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}       : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($userid,$viewid) = (0,0);

    my $config = $self->get_config;

    eval {
	$viewid = $config->get_viewinfo->single({ viewname => $viewname })->id;
    };

    if ($@){
	$logger->error($@);

	return $userid;
    }

    # Hier kommt der Code zur Authentifizierung an einem Externen System
    # Bei erfolgreicher Authentifizierung wird ueberprueft, ob der Nutzername im entsprechenden
    # Portal (view) und diesem Authentifizierungsverfahren bereits existiert.
    # Ansonsten wird ein neuer Nutzer mit den Informationen Nutzername, View und Authentizierungsid erzeugt
    # Egal, ob vorhanden oder neu erzeugt. Die lokale Benutzernummer > 0 wird zurueckgeliefert
    # Benutzernummern <= 0 werden als Fehlercode angesehen
    
    return $userid;
}

sub get_config {
    my $self = shift;

    return $self->{_config};    
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Destroying Authenticator-Object $self");

    return;
}

1;
__END__

=head1 NAME

OpenBib::Authenticator - Objekt zur Authentifizierung mit einem definierten Verfahren (LDAP, OLWS, Selbstregistrierung

=head1 DESCRIPTION

Dieses Objekt authentifiziert einen Nutzer an einem Zielsystem

=head1 SYNOPSIS

 use OpenBib::Authenticator;

 my $authenticator = OpenBib::Authenticator::Factory->create_authenticator(1);

=head1 Returncodes

=over 4

=item -1 

Sie haben entweder kein Passwort oder keinen Usernamen eingegeben

=item -2

Sie konnten mit Ihrem angegebenen Benutzernamen und Passwort nicht erfolgreich authentifiziert werden

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
