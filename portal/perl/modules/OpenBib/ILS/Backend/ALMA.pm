#####################################################################
#
#  OpenBib::ILS::Backend::ALMA
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

package OpenBib::ILS::Backend::ALMA;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::ILS);

use Cache::Memcached::Fast;
use Encode qw(decode_utf8 encode_utf8);
use HTTP::Request::Common;
use JSON::XS qw/decode_json/;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use MLDBM qw(DB_File Storable);
use SOAP::Lite;
use Storable ();
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Config::CirculationInfoTable;

######################################################################
# Authentication
######################################################################

sub authenticate {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username    = exists $arg_ref->{username}
        ? $arg_ref->{username}       : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}       : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $userid = 0;

    my $config  = $self->get_config;
    my $dbname  = $self->get('name');

    # Validate password for user
    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    # Todo
    
    $logger->debug("Authentication successful");
    
    # Gegebenenfalls Benutzer lokal eintragen
    $logger->debug("Save new user");

    my $user = new OpenBib::User;
    
    # Eintragen, wenn noch nicht existent
    # USBWS-Kennungen werden NICHT an einen View gebunden, damit mit der gleichen Kennung verschiedene lokale Bibliothekssysteme genutzt werden koennen - spezifisch fuer die Universitaet zu Koeln
    if (!$user->user_exists_in_view({ username => $username, authenticatorid => $self->get('id'), viewid => undef })) {
	# Neuen Satz eintragen
	$userid = $user->add({
	    username        => $username,
	    hashed_password => undef,
	    authenticatorid => $self->get('id'),
	    viewid          => undef,
			     });
	
	$logger->debug("User added with new id $userid");
    }
    else {
	my $local_user = $config->get_schema->resultset('Userinfo')->search_rs(
	    {
		username        => $username,
		viewid          => undef,
		authenticatorid => $self->get('id'),
	    },
	    undef
	    )->first;
	
	if ($local_user){
	    $userid = $local_user->get_column('id');
	}
	
	$logger->debug("User exists with id $userid");
	
    }
    
    # Benuzerinformationen eintragen
    #$user->set_private_info($username,\%userinfo);
    
    #$logger->debug("Updated private user info");

    return $userid;
}

######################################################################
# Circulation
######################################################################

sub get_renewals {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};
    
    # todo

    return $result_ref;
}

# Bestellungen
sub get_orders {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};
    # todo 

    return $result_ref;
}

# Vormerkungen
sub get_reservations {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

# Mahnungen
sub get_reminders {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

# Aktive Ausleihen
sub get_borrows {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

# Aktive Ausleihen
sub get_idn_of_borrows {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

# Titel vormerken
sub make_reservation {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

# Vormerken wiederrufen
sub cancel_reservation {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

# Titel bestellen
sub make_order {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

# Gesamtkonto verlaengern
sub renew_loans {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

######################################################################
# Mediastatus
######################################################################

sub get_mediastatus {
    my ($self,$arg_ref) = @_;

    my $result_ref = {};

    # todo

    return $result_ref;
}

1;
__END__

=head1 NAME

OpenBib::ILS::Backend::ALMA - Backend zur Anbindung eines ILS mittels ALMA Webservice

=head1 DESCRIPTION

Dieses Backend stellt die Methoden zur Authentifizierung, Ausleihe und Medienstatus ueber einen ALMA Webservice bereit

=head1 SYNOPSIS

 use OpenBib::ILS::Factory;

 my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

 my $userid = $ils->authenticate({ viewname => 'kug', username => 'abc', password => '123' });

 if ($userid > 0){
    # Erfolgreich authentifiziert und Userid in $userid gespeichert
 }
 else {
    # $userid ist Fehlercode
 }


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
