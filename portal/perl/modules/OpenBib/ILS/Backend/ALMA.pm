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
use Net::LDAP;
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
    my $dbname  = $self->get_database;

    my $response_ref = {
	database => $dbname,
	ils => 'alma',
    };
    
    my $sisauth_config;
    
    eval {
	$sisauth_config = $config->{sisauth};
    };

    unless ($sisauth_config){
	$response_ref->{failure} = {
	    error => 'Missing or invalid query parameters',
	    code => -3,  # Status: wrong password
	};

	return $response_ref;	
    }

    my @ldap_parameters = ($sisauth_config->{hostname});

    foreach my $parameter ('scheme','port','verify','timeout','onerror','cafile'){
	push @ldap_parameters, ($parameter,$sisauth_config->{$parameter}) if ($sisauth_config->{$parameter});

    }

    if ($logger->is_debug){
	$logger->debug("Using Parameters ".YAML::Dump(\@ldap_parameters));
    }
    
    my $ldaps ;

    eval {
	$ldaps = Net::LDAP->new(@ldap_parameters);
    };
    
    if ($@){
	$logger->error("LDAP-Fehler: ".$@);
	
	$response_ref->{failure} = {
	    error => 'Missing or invalid query parameters',
	    code => -3,  # Status: wrong password
	};

	return $response_ref;
    }
    
    my $success = 0;

    if (defined $ldaps) {
	my $match_user = $sisauth_config->{match_user};
	my $base_dn    = $sisauth_config->{base_dn};
	
	$match_user=~s/USER_NAME/$username/;
	
	$logger->debug("Checking $match_user in LDAP-Tree at base_dn $base_dn ");
	
	my $proxy_msg = $ldaps->bind(
	    $sisauth_config->{proxy_binddn}, 
	    password => $sisauth_config->{proxy_pw},
	    );
	
	
	if ($proxy_msg && $proxy_msg->code() == 0){
	    if ($logger->is_debug){
		$logger->debug("Proxy Authenticator LDAP: OK");
		$logger->debug("Returned: ".YAML::Dump($proxy_msg));
	    }
	    
	    my $result = $ldaps->search(
		base   => $sisauth_config->{basedn},
		filter => qq($match_user),
		);
	    
	    if ($result && $result->code){
		$logger->error("Error searching user $username: ".$result->error );
		$response_ref->{failure} = {
		    error => 'wrong password',
		    code => -3,  # Status: wrong password
		};
		
		return $response_ref;
	    }
	    
	    my $userdn = "";	
	    my $account_ref = {};
	    
	    if ($result && $result->count == 1) {	    
		my $entry = $result->entry(0);
		
		$userdn = $entry->dn();

		# Essential Data
		$account_ref->{username} = $entry->get_value('USBportalName');
		$account_ref->{fullname} = $entry->get_value('cn');
		$account_ref->{surname}  = $entry->get_value('sn');
		$account_ref->{forename} = $entry->get_value('givenName');
		$account_ref->{email}    = $entry->get_value('USBEmailAdr');
				
		if ($logger->is_debug){
		    $logger->debug(YAML::Dump($entry));
		    
		}
	    }

	    $logger->debug("Got userdn $userdn");
	    
	    if ($userdn){
		my $user_msg = $ldaps->bind(
		    $userdn,
		    password => $password,
		    );
		
		
		if ($user_msg && $user_msg->code() == 0){
		    $success = 1;

		    # Store essential data
		    $response_ref->{userinfo}{username} = $account_ref->{username};    
		    $response_ref->{userinfo}{fullname} = $account_ref->{fullname};
		    $response_ref->{userinfo}{surname}  = $account_ref->{surname};
		    $response_ref->{userinfo}{forename} = $account_ref->{forename};
		    $response_ref->{userinfo}{email}    = $account_ref->{email};
		    
		}
	    }
	    else {
		$logger->debug("Received error ".$proxy_msg->code().": ".$proxy_msg->error());
		$response_ref->{failure} = {
		    error => 'wrong password',
		    code => -3,  # Status: wrong password
		};
		
		return $response_ref;
	    }
	}
	else {
	    $response_ref->{failure} = {
		error => 'wrong password',
		code => -3,  # Status: wrong password
	    };
	    
	    return $response_ref;
	}
    }
    else {
	$logger->error("LDAPS object NOT created");
	$response_ref->{failure} = {
	    error => 'wrong password',
	    code => -3,  # Status: wrong password
	};
	
	return $response_ref;
    }
        
    $logger->debug("Authentication via LDAP done");
    
    if (!$success) {
	$response_ref->{failure} = {
	    error => 'wrong password',
	    code => -3,  # Status: wrong password
	};
	
	return $response_ref;
    }

    $logger->debug("Authentication successful");

    $response_ref->{successful} = 1;

    return $response_ref;
}

######################################################################
# Circulation
######################################################################

sub update_email {
    my ($self,$username,$email) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub update_phone {
    my ($self,$username,$phone) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub update_password {
    my ($self,$username,$oldpassword,$newpassword) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_items {
    my ($self,$username) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_accountinfo {
    my ($self,$username) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

# Accountinformationen
sub get_userdata {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $config  = $self->get_config;
    my $dbname  = $self->get_database;
    
    my $response_ref = {};
        
    unless ($circinfotable->has_circinfo($dbname) && defined $circinfotable->get($dbname)->{circ}) {
	$response_ref = {
	    error => "connection error",
	    error_description => "Problem mit der Verbindung zum SIS",
	};
	
	return $response_ref;
    }
	
    $logger->debug("Getting Circulation info via SIS LDAP");
        	
    my $sisauth_config;
    
    eval {
	$sisauth_config = $config->{sisauth};
    };
    
    unless ($sisauth_config){
	$response_ref = {
	    error => "connection error",
	    error_description => "Problem mit der Verbindung zum SIS",
	};
	
	return $response_ref;
    }
	
    my @ldap_parameters = ($sisauth_config->{hostname});
    
    foreach my $parameter ('scheme','port','verify','timeout','onerror','cafile'){
	push @ldap_parameters, ($parameter,$sisauth_config->{$parameter}) if ($sisauth_config->{$parameter});
	
    }
    
    if ($logger->is_debug){
	$logger->debug("Using Parameters ".YAML::Dump(\@ldap_parameters));
    }
    
    my $ldaps ;
    
    eval {
	$ldaps = Net::LDAP->new(@ldap_parameters);
    };
    
    if ($@){
	$logger->error("LDAP-Fehler: ".$@);
	
	$response_ref = {
	    error => "connection error",
	    error_description => "Problem mit der Verbindung zum SIS",
	};
	
	return $response_ref;
    }
    
    unless (defined $ldaps) {
	$response_ref = {
	    error => "connection error",
	    error_description => "Problem mit der Verbindung zum SIS",
	};

	return $response_ref;
    }
    
    my $match_user = $sisauth_config->{match_user};
    my $base_dn    = $sisauth_config->{base_dn};
    
    $match_user=~s/USER_NAME/$username/;
    
    $logger->debug("Checking $match_user in LDAP-Tree at base_dn $base_dn ");
    
    my $proxy_msg = $ldaps->bind(
	$sisauth_config->{proxy_binddn}, 
	password => $sisauth_config->{proxy_pw},
	);
    

    unless ($proxy_msg && $proxy_msg->code() == 0){
	$response_ref = {
	    error => "connection error",
	    error_description => "Problem mit der Verbindung zum SIS",
	};
	$response_ref = {
	    error => "user error",
	    error_description => "Ausweisnummer konnte nicht gefunden werden",
	};

	return $response_ref;
    }

    
    if ($logger->is_debug){
	$logger->debug("Proxy Authenticator LDAP: OK");
	$logger->debug("Returned: ".YAML::Dump($proxy_msg));
    }
    
    my $result = $ldaps->search(
	base   => $sisauth_config->{basedn},
	filter => qq($match_user),
	);

    unless ($result && $result->code() == 0){
	$response_ref = {
	    error => "user error",
	    error_description => "Ausweisnummer konnte nicht gefunden werden",
	};
	
	return $response_ref;
    }

    unless ($result && $result->count == 1){
	$response_ref = {
	    error => "user error",
	    error_description => "Ausweisnummer mehrfach vorhanden",
	};
	
	return $response_ref;
    }
    
    
    my $entry = $result->entry(0);

    $response_ref->{salutation}        = $entry->get_value('title');
    $response_ref->{username}          = $entry->get_value('USBuserNumber');
    $response_ref->{fullname}          = $entry->get_value('cn');
    $response_ref->{startdate}         = $entry->get_value('USBaufdatum');
    $response_ref->{enddate}           = $entry->get_value('USBawdatum');
    $response_ref->{birthdate}         = $entry->get_value('USBgedatum');
    $response_ref->{street}            = $entry->get_value('USBstr');
    $response_ref->{street2}           = $entry->get_value('USBzstr');
    $response_ref->{city}              = $entry->get_value('USBort');
    $response_ref->{city2}             = $entry->get_value('USBzort');
    $response_ref->{zip}               = $entry->get_value('USBplz');
    $response_ref->{zip2}              = $entry->get_value('USBzplz');
    $response_ref->{phone}             = $entry->get_value('USBtel');
    $response_ref->{phone2}            = $entry->get_value('USBztel');
    $response_ref->{email}             = $entry->get_value('USBEmailAdr');
    $response_ref->{email2}            = $entry->get_value('USB2Emailadr');
       
    if ($logger->is_debug){
	$logger->debug(YAML::Dump($entry));
	
    }
    
    return $response_ref;
}


sub get_address {
    my ($self,$username) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_article_orders {
    my ($self,$username,$start,$count) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_zfl_orders {
    my ($self,$username,$start,$count) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_orders {
    my ($self,$username) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_reservations {
    my ($self,$username) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_fees {
    my ($self,$username) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_loans {
    my ($self,$username) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub make_reservation {
    my ($self,$arg_ref) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub cancel_reservation {
    my ($self,$arg_ref) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub make_order {
    my ($self,$arg_ref) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub cancel_order {
    my ($self,$arg_ref) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub renew_loans {
    my ($self,$username) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub renew_single_loan {
    my ($self,$username,$holdingid,$unit) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_mediastatus {
    my ($self,$titleid) = @_;
    
    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub get_timestamp {
    my $self = shift;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub check_order {
    my ($self,$arg_ref) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
}

sub check_reservation {
    my ($self,$arg_ref) = @_;

    my $response_ref = {};
    
    # todo

    return $response_ref;
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

 my $result_ref = $ils->authenticate({ username => 'abc', password => '123' });

 if (defined $result_ref->{failure}){
    # Authentifizierungsfehler. Fehlercode in $result_ref->{failure}
 }
 else {
    # Erfolgreich authentifiziert. Nutzerinformationen in $result_ref->{userinfo}
 }

=head1 METHODS

=over 4

=item new

Erzeugung des Objektes

=item authenticate

Authentifizierung am ILS

=item update_email

Aktualisierung der Mail-Adress im ILS

=item update_phone

Aktualisierung der Telefonnummer im ILS

=item update_password

Aktualisierung des Passworts im ILS

=item get_items

Bestellungen, Vormerkungen und Ausleihen in einer Abfrage aus dem ILS holen

=item get_accountinfo

Zusammenfassung des Nutzers aus ILS holen (Zahl Ausleihen, Vormerkunge, etc.)

=item get_address

Adressinformationen des Nutzer aus dem ILS holen

=item get_article_orders

Artikel-Fernleihbestellung aus dem ILS oder Medea holen

=item get_zfl_orders

Buch-Fernleihbestellungen aus dem ILS oder ZFL holen

=item get_orders

Liste der Bestellungen eines Nutzers aus dem ILS holen

=item get_reservations

Liste der Vormerkungen eines Nutzers aus dem ILS holen

=item get_fees

Liste der Gebuehren eines Nutzers aus dem ILS holen

=item get_loans

Liste der Ausleihen eines Nutzers aus dem ILS holen

=item make_reservation

Eine Vormerkung im ILS taetigen

=item cancel_reservation

Eine getaetigte Vormerkung im ILS stornieren

=item make_order

Eine Bestellung im ILS taetigen

=item cancel_order

Eine Bestellung im ILS oder per Mail stornieren

=item renew_loans

Eine Gesamtkontoverlaengerung im ILS durchfuehren

=item renew_single_loan

Die Verlaengerung eines einzelnen Mediums im ILS durchfuehren

=item get_mediastatus

Liste der Exemplare mit Ausleihinformationen aus dem ILS holen

=item get_timestamp

Hilfsmethode: Aktuellen Timestamp generieren

=item check_order

Bestellung ueberpruefen

=item check_reservation

Vormerkung ueberpruefen

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Der Verzicht auf den Exporter 
bedeutet weniger Speicherverbrauch und mehr Performance auf 
Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
