#####################################################################
#
#  OpenBib::Authenticator::Backend::ILS
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

package OpenBib::Authenticator::Backend::ILS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::Authenticator);

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
use OpenBib::ILS::Factory;

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
    my $user    = $self->get_user;
    my $dbname  = $self->get('name');

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $dbname });

    my $result_ref = $ils->authenticate({ username => $username, password => $password});

    if ($logger->is_debug){
	$logger->debug("Authentication result ".YAML::Dump($result_ref));
    }
    
    my $max_login_failure = $config->get('max_login_failure');

    # Bestimmung einer etwaig bereits vorhandenen Userid, um Fehlversuche zu loggen 
    # ILS-Nutzer haben keine View-Zuordnung, damit sie einheitlich mit ihrem
    # ein und demselben Account auch verschiedenen Views nutzen koennen
    my $thisuser = $config->get_schema->resultset('Userinfo')->search_rs(
        {
            username        => $username,
	    viewid          => undef,
	    authenticatorid => $self->{id},
        },
        {
            select => ['id', 'login_failure','status'],
            as     => ['thisid','thislogin_failure','thisstatus'],
	    order_by => ['id asc'],
        }
            
    )->first;
    
    if ($thisuser){
	my $login_failure = $thisuser->get_column('thislogin_failure');
	my $status        = $thisuser->get_column('thisstatus') || '';
        $userid           = $thisuser->get_column('thisid');
	
        $logger->debug("Got Userid $userid with login failure $login_failure and status $status");

	if ($userid && $login_failure > $max_login_failure){
	    $userid = -8; # Status: max_login_failure reached
	    return $userid;
	}
	elsif ($userid) {
	    # User exists, so we can log failure
	    if (defined $result_ref->{failure} && $result_ref->{failure}{code} <= 0){
	       $user->add_login_failure({ userid => $userid});
               $userid = -3;  # Status: wrong password
	       return $userid;
	    }
	    # or login successful, so we can reset failure counter
            elsif (defined $result_ref->{successful} && $result_ref->{successful}){
               $user->reset_login_failure({ userid => $userid});
            }
	}
	else {
	    $userid = -3;  # Status: wrong password
	    return $userid;
	}
    }
    elsif (defined $result_ref->{failure} && $result_ref->{failure}{code} <= 0){
	$userid = -3;  # Status: wrong password
	return $userid;
    }
    elsif (defined $result_ref->{failure}){
	$userid = 0;  # Status: unspecified
	return $userid;
    }

    # Ab hier nur weiter, wenn Authentifizierung positiv successful war!
    unless (defined $result_ref->{successful} && $result_ref->{successful}){
	$userid = 0;  # Status: unspecified
	return $userid;
    }
    
    $logger->debug("Authentication via ILS successful");
    
    # Eintragen, wenn noch nicht existent
    # OLWS-Kennungen werden NICHT an einen View gebunden, damit mit der gleichen Kennung verschiedene lokale Bibliothekssysteme genutzt werden koennen - spezifisch fuer die Universitaet zu Koeln
    unless ($thisuser) {
	# Gegebenenfalls Benutzer lokal eintragen
	$logger->debug("Save new user");
	
	# Neuen Satz eintragen
	$userid = $user->add({
	    username        => $username,
	    hashed_password => undef,
	    authenticatorid => $self->{id},
	    viewid          => undef,
	    token           => undef,
			     });
	
	$logger->debug("User $username added to authenticator ".$self->{id}." with new id $userid");
    }
    
    # Benuzerinformationen temporaer eintragen
    $user->set_private_info($userid,$result_ref->{userinfo});
    
    #$logger->debug("Updated private user info");

    return $userid;
}

1;
__END__

=head1 NAME

OpenBib::Authenticator::Backend::ILS - Backend zur Authentifizierung mittels eines Integrierten Bibliothekssystems (ILS) via Objekt OpenBib::ILS

=head1 DESCRIPTION

Dieses Backend stellt die Methode authenticate zur Authentifizierung eines Nutzer an einem ILS bereit

=head1 SYNOPSIS

 use OpenBib::Authenticator::Factory;

 my $authenticator = OpenBib::Authenticator::Factory->create_authenticator(1);

 my $userid = $authenticator->authenticate({ viewname => 'kug', username => 'abc', password => '123' });

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
