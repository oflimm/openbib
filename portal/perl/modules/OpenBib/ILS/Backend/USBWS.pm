#####################################################################
#
#  OpenBib::ILS::Backend::USBWS
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

package OpenBib::ILS::Backend::USBWS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::ILS);

use Benchmark;
use Cache::Memcached::Fast;
use Encode qw/decode_utf8 encode_utf8/;
use HTTP::Request::Common;
use JSON::XS qw/encode_json decode_json/;
use LWP::UserAgent;
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use SOAP::Lite;
use Storable ();
use URI::Escape;
use URI;
use XML::Simple;
use YAML::Syck;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Config::LocationInfoTable;
use OpenBib::User;

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

    $logger->debug("Authenticate info via USB Authentication-Service");

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    my $response_ref = {
	database => $dbname,
	ils => 'usbws',
    };
        
    my $url = $config->get('usbauth_url');

    $url.="?userid=".uri_escape($username)."&password=".uri_escape($password);

    $logger->debug("Request-URL: ".$url);
    
    my $request = HTTP::Request->new('GET',$url);

    my $response = $ua->request($request);

    if ( $response->is_error() ) {
	$response_ref->{failure} = {
	    error => 'Missing or invalid query parameters',
	    code => -3,  # Status: wrong password
	};

	return $response_ref;
    }

    $logger->debug($response->content);

    my $ref = XMLin($response->content);
    
    my $account_ref = {};

    if ($logger->is_debug){
	$logger->debug("Response: ".YAML::Dump($ref));
    }

    if ($ref->{slnpValue}{id} ne "ERROR"){    
	foreach my $field (keys %{$ref->{slnpValue}}){
	    $account_ref->{$field} = $ref->{slnpValue}{$field}{content};
	}
    }

    if ($logger->is_debug){
	$logger->debug("Account: ".YAML::Dump($account_ref));
    }

    my $response_username = $account_ref->{'BenutzerNummer'};

    $logger->debug("Request  Username: ".$username);
    
    $logger->debug("Response Username: ".$response_username);

    unless (defined $response_username && $username eq $response_username){
	$response_ref->{failure} = {
	    error => 'wrong password',
	    code => -3,  # Status: wrong password
	};

	return $response_ref;
    }
        
    $logger->debug("Authentication successful");

    $response_ref->{successful} = 1;
    
    # Essential Data
    $response_ref->{userinfo}{username} = $username;    
    $response_ref->{userinfo}{fullname} = $account_ref->{FullName};
    $response_ref->{userinfo}{surname}  = $account_ref->{Nachname};
    $response_ref->{userinfo}{forename} = $account_ref->{Vorname};
    $response_ref->{userinfo}{email}    = $account_ref->{Email1};

    return $response_ref;
}

######################################################################
# Circulation
######################################################################

# Bestellunge, Vormerkungen und Ausleihen in einer Abfrage
sub get_items {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $response_ref = ();

    my $orders_ref       = $self->get_orders($username);
    my $reservations_ref = $self->get_reservations($username);
    my $loans_ref      = $self->get_loans($username);    

    if (defined $orders_ref->{no_orders}){
	$response_ref->{no_orders} = $orders_ref->{no_orders};
    }
    elsif (defined $orders_ref->{items}){
	push @{$response_ref->{items}}, @{$orders_ref->{items}};
    }

    if (defined $reservations_ref->{no_reservations}){
	$response_ref->{no_reservations} = $reservations_ref->{no_reservations};
    }
    elsif (defined $reservations_ref->{items}){
	push @{$response_ref->{items}}, @{$reservations_ref->{items}};
    }
    
    if (defined $loans_ref->{no_loans}){
	$response_ref->{no_loans} = $loans_ref->{no_loans};
    }
    elsif (defined $loans_ref->{items}){
	push @{$response_ref->{items}}, @{$loans_ref->{items}};
    }
        
    return $response_ref;
}

# Bestellungen
sub get_orders {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $database = $self->get_database;
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    
    my $response_ref = {};

    if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {

	$logger->debug("Getting Circulation info via USB-SOAP");

	my $request_types_ref = [
	    {
		type   => 'BESTELLUNGEN',
		status => 2,
	    },
	    ];
	
	$response_ref = $self->send_account_request({ username => $username, types => $request_types_ref});
    }
    
    return $response_ref;
}

# Vormerkungen
sub get_reservations {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $database = $self->get_database;
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    
    my $response_ref = {};

    if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {

	$logger->debug("Getting Circulation info via USB-SOAP");

	my $request_types_ref = [
	    {
		type   => 'VORMERKUNGEN',
		status => 1,
	    },
	    ];
	
	$response_ref = $self->send_account_request({ username => $username, types => $request_types_ref});
    }
    
    return $response_ref;
}

# Gebuehren abfragen
sub get_fees {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $database = $self->get_database;
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    
    my $response_ref = {};

    if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {

	$logger->debug("Getting Circulation info via USB-SOAP");

	my $request_types_ref = [
	    {
		type   => 'OFFENEGEBUEHREN',
	    },
	    ];
	
	$response_ref = $self->send_account_request({ username => $username, types => $request_types_ref});
    }
    
    return $response_ref;
}

# Aktive Ausleihen
sub get_loans {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $database = $self->get_database;
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    
    my $response_ref = {};

    if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {

	$logger->debug("Getting Circulation info via USB-SOAP");

	my $request_types_ref = [
	    {
		type   => 'AUSLEIHEN',
		status => 3,
	    },
	    ];
	
	$response_ref = $self->send_account_request({ username => $username, types => $request_types_ref});
    }
    
    return $response_ref;
}

# Titel vormerken
sub make_reservation {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $gsi             = exists $arg_ref->{holdingid}  # Mediennummer
        ? $arg_ref->{holdingid}      : undef;

    my $zw              = exists $arg_ref->{unit}     # Zweigstelle
        ? $arg_ref->{unit}           : undef;

    my $aort            = exists $arg_ref->{pickup_location} # Ausgabeort
        ? $arg_ref->{pickup_location}       : undef;

    my $katkey          = exists $arg_ref->{titleid}  # Katkey fuer teilqualifizierte Vormerkung
        ? $arg_ref->{titleid}           : undef;

    my $type            = exists $arg_ref->{type}    # Typ (voll/teilqualifizierte Vormerkung)
        ? $arg_ref->{type}              : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    unless ($username && $gsi && $zw >= 0 && $katkey && $aort >= 0){
	$response_ref =  {
	    error => "missing parameter (username: $username - gsi: $gsi - zw: $zw - katkey: $katkey - aort: $aort)",
	};

	return $response_ref;
    }

    $type = ($type eq "by_title")?"TEIL":"VOLL";
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Making reservation via USB-SOAP");
	    
    my @args = ($username,$gsi,$zw,$aort,$katkey,$type);
	    
    my $uri = "urn:/Loan";
	    
    if ($circinfotable->get($database)->{circdb} ne "sisis"){
	$uri = "urn:/Loan_inst";
    }
	        
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->make_reservation(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };

	    return $response_ref;
	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{Vormerkung} && defined $result_ref->{Vormerkung}{NotOK} ){
	$response_ref = {
	    "code" => 403,
		"error" => "already lent",
		"error_description" => $result_ref->{Vormerkung}{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    elsif (defined $result_ref->{Vormerkung} && defined $result_ref->{Vormerkung}{OK} ){
	$response_ref = {
	    "successful" => 1,
		"message"   => $result_ref->{Vormerkung}{OK},
		"author"    => $result_ref->{Vormerkung}{Verfasser},
		"title"     => $result_ref->{Vormerkung}{Titel},
		"holdingid" => $result_ref->{Vormerkung}{MedienNummer},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
       
    $response_ref = $result_ref;

    return $response_ref;
}

# Vormerkung widerrufen
sub cancel_reservation {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $katkey          = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}        : undef;

    my $gsi             = exists $arg_ref->{holdingid} # Mediennummer
        ? $arg_ref->{holdingid}      : undef;

    my $zw              = exists $arg_ref->{unit}     # Zweigstelle
        ? $arg_ref->{unit}           : undef;
        
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Cancel reservation via USB-SOAP");

    unless ($username && ($gsi || $katkey) && $zw >= 0){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }

    # Obskures Tunneln des Katkeys in den USBWS...
    if ($katkey){
	$gsi = "Titel-Nr: $katkey";
    }
    
    my @args = ($username,$gsi,$zw);
	    
    my $uri = "urn:/Loan";
	    
    if ($circinfotable->get($database)->{circdb} ne "sisis"){
	$uri = "urn:/Loan_inst";
    }
	        
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));    
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->cancel_reservation(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
	    
	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };
	    
	    return $response_ref;

	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{VormerkBestellStorno} && defined $result_ref->{VormerkBestellStorno}{NotOK} ){
	$response_ref = {
	    "code" => 403,
		"error" => "reservation error",
		"error_description" => $result_ref->{VormerkBestellStorno}{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    elsif (defined $result_ref->{VormerkBestellStorno} && defined $result_ref->{VormerkBestellStorno}{OK} ){
	$response_ref = {
	    "successful" => 1,
		"message" => $result_ref->{VormerkBestellStorno}{OK},
		"title"   => $result_ref->{VormerkBestellStorno}{Titel},
		"author"  => $result_ref->{VormerkBestellStorno}{Verfasser},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }

    $response_ref = {
	"code" => 405,
	    "error" => "unknown error",
	    "error_description" => "Unbekannter Fehler",
    };
    
    return $response_ref;
}

# Titel bestellen

sub make_order {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $katkey          = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}        : undef;

    my $gsi             = exists $arg_ref->{holdingid} # Mediennummer
        ? $arg_ref->{holdingid}      : undef;

    my $zw              = exists $arg_ref->{unit}     # Zweigstelle
        ? $arg_ref->{unit}           : undef;
    
    my $aort            = exists $arg_ref->{pickup_location} # Ausgabeort
        ? $arg_ref->{pickup_location}       : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Making order via USB-SOAP");

    unless ($username && $gsi && $zw >= 0 && $aort >= 0){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }
    
    my @args = ($username,$gsi,$zw,$aort);
	    
    my $uri = "urn:/Loan";
	    
    if ($circinfotable->get($database)->{circdb} ne "sisis"){
	$uri = "urn:/Loan_inst";
    }
	        
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));    
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->make_order(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
	    
	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };
	    
	    return $response_ref;

	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{OpacBestellung} && defined $result_ref->{OpacBestellung}{NotOK} ){
	$response_ref = {
	    "code" => 403,
		"error" => "already lent",
		"error_description" => $result_ref->{OpacBestellung}{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    elsif (defined $result_ref->{OpacBestellung} && defined $result_ref->{OpacBestellung}{OK} ){
	$response_ref = {
	    "successful" => 1,
		"message" => $result_ref->{OpacBestellung}{OK},
		"title"   => $result_ref->{OpacBestellung}{Titel},
		"author"  => $result_ref->{OpacBestellung}{Verfasser},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }

    $response_ref = {
	    "code" => 405,
		"error" => "unknown error",
		"error_description" => "Unbekannter Fehler",
	};

    if ($logger->is_debug){
	$response_ref->{debug} = $result_ref;
    }

    return $response_ref;    
}

# Magazinbestellung widerrufen (via Mail)
sub cancel_order {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $katkey          = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}        : undef;

    my $gsi             = exists $arg_ref->{holdingid} # Mediennummer
        ? $arg_ref->{holdingid}      : undef;

    my $zw              = exists $arg_ref->{unit}     # Zweigstelle
        ? $arg_ref->{unit}           : undef;

    my $zwname          = exists $arg_ref->{unitname} # Zweigstellename
        ? $arg_ref->{unitname}       : undef;

    my $title           = exists $arg_ref->{title}
        ? $arg_ref->{title}          : '';

    my $author          = exists $arg_ref->{author}
        ? $arg_ref->{author}         : '';

    my $date            = exists $arg_ref->{date}
        ? $arg_ref->{date}           : '';

    my $receipt         = exists $arg_ref->{receipt}
        ? $arg_ref->{receipt}           : '';

    my $remark          = exists $arg_ref->{remark}
        ? $arg_ref->{remark}            : '';
    
    my $username_full   = exists $arg_ref->{username_full} # Vorname Nachname
        ? $arg_ref->{username_full}            : '';
    
    my $email           = exists $arg_ref->{email}
        ? $arg_ref->{email}             : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Cancel reservation via USB-SOAP");

    unless ($username && ($gsi || $katkey)){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }
	
    my @args = ($title, $author, $gsi, $zwname, $date, $username, $username_full, $receipt, $email, $remark);
	    
    my $uri = "urn:/Mail";
	    
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbwsmail_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));    
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbwsmail_url'));
	my $result = $soap->submit_storno(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
	    
	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };
	    
	    return $response_ref;

	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbwsmail_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if ($logger->is_debug){
	$logger->debug("Cancel order result".YAML::Dump($result_ref));
    }

    if (defined $result_ref->{OK} ){
	$response_ref = {
	    "successful"   => 1,
	     author        => $author,
	     title         => $title,
	     username_full => $username_full,
	     email         => $email,
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
	
    }
    else {
	$response_ref = {
	    "code" => 403,
		"error" => "cancel order failed",
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    
    return $response_ref;
}

# Gesamtkonto verlaengern
sub renew_loans {
    my ($self,$username) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Renew loans via USB-SOAP");

    unless ($username){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }
    
    my @args = ($username);
	    
    my $uri = "urn:/Account";
	    
    if ($circinfotable->get($database)->{circdb} ne "sisis"){
	$uri = "urn:/Account_inst";
    }
	        
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));    
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->renew_loans(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
	    
	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };
	    
	    return $response_ref;

	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{GesamtVerlaengerung} && defined $result_ref->{GesamtVerlaengerung}{NotOK} ){
	$response_ref = {
	    "code" => 403,
		"error" => "renew loans failed",
		"error_description" => $result_ref->{OpacBestellung}{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    # result-hash: First element (0) is overview followed by itemlist
    elsif ($result_ref->{GesamtVerlaengerung}{'0'}{OK}){
	$response_ref->{"successful"} = 1;
	
	foreach my $resultid (sort keys %{$result_ref->{GesamtVerlaengerung}}){
	    if ($resultid == 0){
		$response_ref->{num_successful_renewals} = $result_ref->{GesamtVerlaengerung}{$resultid}{AnzPos};
		$response_ref->{num_failed_renewals} = $result_ref->{GesamtVerlaengerung}{$resultid}{AnzNeg};
	    }
	    else {
		push @{$response_ref->{"items"}}, {
		    holdingid       => $result_ref->{GesamtVerlaengerung}{$resultid}{MedienNummer},
		    author          => $result_ref->{GesamtVerlaengerung}{$resultid}{Verfasser},
		    title           => $result_ref->{GesamtVerlaengerung}{$resultid}{Titel},
		    renewal_message => $result_ref->{GesamtVerlaengerung}{$resultid}{Ergebnismeldung},
		    location_mark   => $result_ref->{GesamtVerlaengerung}{$resultid}{Signatur},
		    department_id   => $result_ref->{GesamtVerlaengerung}{$resultid}{EntleihZweig},
		    department_desc => $result_ref->{GesamtVerlaengerung}{$resultid}{EntleihZweigTxt},
		    reminder_level  => $result_ref->{GesamtVerlaengerung}{$resultid}{MahnStufe},

		};
	    }
	}

	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref;    
    }

    $response_ref = {
	    "code" => 405,
		"error" => "unknown error",
		"error_description" => "Unbekannter Fehler",
	};

    if ($logger->is_debug){
	$response_ref->{debug} = $result_ref;
    }

    return $response_ref;    
}

# Einzelausleihe verlaengern
sub renew_single_loan {
    my ($self,$username,$holdingid,$unit) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Renew loans via USB-SOAP");

    unless ($username && $holdingid && $unit >=0 ){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }
    
    my @args = ($username,$holdingid,$unit);
	    
    my $uri = "urn:/Account";
	    
    if ($circinfotable->get($database)->{circdb} ne "sisis"){
	$uri = "urn:/Account_inst";
    }
	        
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));    
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->renew_singleloan(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
	    
	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };
	    
	    return $response_ref;

	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{EinzelVerlaengerung} && defined $result_ref->{EinzelVerlaengerung}{NotOK} ){
	$response_ref = {
	    "code" => 403,
		"error" => "renew single loan failed",
		"error_description" => $result_ref->{EinzelVerlaengerung}{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    # result-hash: First element (0) is overview followed by itemlist
    elsif ($result_ref->{EinzelVerlaengerung}{OK}){
	$response_ref->{"successful"} = 1;
	
	$response_ref->{"message"}   = $result_ref->{EinzelVerlaengerung}{OK};
	$response_ref->{"holdingid"} = $result_ref->{EinzelVerlaengerung}{MedienNummer};	
	$response_ref->{"author"}    = $result_ref->{EinzelVerlaengerung}{Verfasser};
	$response_ref->{"title"}     = $result_ref->{EinzelVerlaengerung}{Titel};
	$response_ref->{"location_mark"} = $result_ref->{EinzelVerlaengerung}{Signatur};
	$response_ref->{"new_date"}  = $result_ref->{EinzelVerlaengerung}{LeihfristendeNeu};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}
	
	return $response_ref;    
    }

    $response_ref = {
	    "code" => 405,
		"error" => "unknown error",
		"error_description" => "Unbekannter Fehler",
	};

    if ($logger->is_debug){
	$response_ref->{debug} = $result_ref;
    }

    return $response_ref;    
}

######################################################################
# Mediastatus
######################################################################

sub get_mediastatus {
    my ($self,$titleid) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config    = $self->get_config;
    my $database  = $self->get_database;
    
    my $response_ref = {};
    
    unless ($database && $titleid){
	$response_ref = {
	    timestamp   => $self->get_timestamp,
	    circulation => [],
	    error       => "missing parameters",	    
	};
	
	return $response_ref;
    }
    
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->new;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    my $items_ref = [];

    # Ausleihinformationen der Exemplare
    {
	my $circexlist=undef;
	
	if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {
	    
	    $logger->debug("Getting Circulation info via USB-SOAP");
	    
	    my @args = ($titleid,"0"); # Immer mit Zweigstelle 0 starten
	    
	    my $uri = "urn:/Loan";
	    
	    if ($circinfotable->get($database)->{circdb} ne "sisis"){
		$uri = "urn:/Loan_inst";
		push @args, undef; # Keine Benutzernummer		
		push @args, $database;
	    }
	    
	    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
	    
	    eval {
		my $soap = SOAP::Lite
		    -> uri($uri)
		    -> proxy($config->get('usbws_url'));
		my $result = $soap->show_items(@args);
		
		unless ($result->fault) {
		    $circexlist = $result->result;
		    if ($logger->is_debug){
			$logger->debug("SOAP Result: ".YAML::Dump($circexlist));
		    }
		}
		else {
		    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);

		    $response_ref = {
			error => $result->faultcode,
			error_description => $result->faultstring,
		    };
		    
		    return $response_ref;		    
		}
	    };
	    
	    if ($@){
		$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

		$response_ref = {
		    error => "connection error",
		    error_description => "Problem bei der Verbindung zum Ausleihsystem",
		};
		
		return $response_ref;		
	    }
	    
	}
	
	# Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
	# in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
	# titelbasierten Exemplardaten
	
	if (defined($circexlist)) {
	    my $itemstring = (defined $circexlist->{Exemplardaten})?'Exemplardaten':'PresentExemplardaten';
	    
	    foreach my $nr (keys %{$circexlist->{$itemstring}}){
		my $circ_ref = $circexlist->{$itemstring}{$nr};
		
		$logger->debug(YAML::Dump($circ_ref));
		
		my $zweigabteil = $circ_ref->{'ZweigAbteil'};
		
		$logger->debug("Matching $zweigabteil");
		if ($zweigabteil=~m/^\$msg\{USB-KUG-Locations,(.+?)\}/){
		    my $isil=$1;
		    
		    my $zweigname = $locinfotable->get('identifier')->{$isil}{description};
		    $logger->debug("Found $zweigname");
		    
		    $circ_ref->{'ZweigAbteil'} =~s/^\$msg\{USB-KUG-Locations,.+?\}/$zweigname/;		    		    		    
		}
		else {
		    $logger->debug("No match");
		}

		# Umwandeln
		my $item_ref = {};

		if ($config->get('debug_ils')){
		    $item_ref->{debug} = $circ_ref;
		}

		# Spezialanpassungen USB Koeln

		# Ende Spezialanpassungen
		
		$item_ref->{'label'}  = $circ_ref->{'Signatur'};
		$item_ref->{'id'}     = $circ_ref->{'MedienNr'};
		$item_ref->{'remark'} = $circ_ref->{'FussNoten'};
		$item_ref->{'boundcollection'} = $circ_ref->{'BoundCollection'};

		$item_ref->{'full_location'} = $circ_ref->{ZweigAbteil};
		
		if ($circ_ref->{'ZweigAbteil'} =~/^(.+?)\s+\/\s+(.+?)$/){
		    $circ_ref->{'ZweigName'} = $1;
		    $circ_ref->{'AbteilName'} = $2;
		}
		
		if ($circ_ref->{'ZweigName'} && $circ_ref->{'AbteilName'}){
		    $item_ref->{'department'} = {
			content => $circ_ref->{ZweigName},
			id      => $circ_ref->{Zweigstelle},
		    };
		    $item_ref->{'storage'} = {
			content => $circ_ref->{AbteilName},
		    };
		}
		else {
		    $item_ref->{'department'} = {
			content => $circ_ref->{ZweigAbteil},
			id      => $circ_ref->{Zweigstelle},
		    };
		}

		my $available_ref   = [];
		my $unavailable_ref = [];

		my $use_leihstatustext = 0; # sonst: Verwende Leihstatus

		if ($use_leihstatustext){
		    if ($circ_ref->{LeihstatusText} =~m/Präsenzbestand/){
			push @$available_ref, {
			    service => 'presence',
			    content => 
			};
		    }
		    elsif ($circ_ref->{LeihstatusText} =~m/^bestellbar.*Lesesaal/){
			push @$available_ref, {
			    service => 'loan',
			    limitation => "bestellbar (Nutzung nur im Lesesaal)",
			    type => 'Stationary',
			};
		    }
		    elsif ($circ_ref->{LeihstatusText} =~m/bestellbar/ || $circ_ref->{LeihstatusText} =~m/verfügbar/){
			push @$available_ref, {
			    service => 'order',
			};
		    }
		    elsif ($circ_ref->{LeihstatusText} eq "ausleihbar"){
			push @$available_ref, {
			    service => 'loan',
			};
		    }
		    elsif ($circ_ref->{LeihstatusText} eq "nicht entleihbar"){
			push @$available_ref, {
			    service => 'presence',
			};
		    }
		    elsif ($circ_ref->{LeihstatusText} eq "nur in bes. Lesesaal bestellbar"){
			push @$available_ref, {
			    service => 'order',
			    limitation => $circ_ref->{LeihstatusText},
			    type => 'Stationary',
			};
		    }
		    elsif ($circ_ref->{LeihstatusText} eq "nur Wochenende"){
			push @$available_ref, {
			    service => 'loan',
			    limitation => $circ_ref->{LeihstatusText},
			    type => 'ShortLoan',
			};
		    }
		    elsif ($circ_ref->{LeihstatusText} =~m/entliehen/){
			my $this_unavailable_ref = {
			    service => 'loan',
			    expected => $circ_ref->{RueckgabeDatum},
			};
			
			if ($circ_ref->{VormerkAnzahl}){
			    $this_unavailable_ref->{queue} = $circ_ref->{VormerkAnzahl} ;
			}
			
			push @$unavailable_ref, $this_unavailable_ref;
			
		    }
		    elsif ($circ_ref->{LeihstatusText} =~m/vermisst/){
			my $this_unavailable_ref = {
			    service => 'loan',
#			    expected => 'lost',
			};
			
			push @$unavailable_ref, $this_unavailable_ref;
			
		    }
		}
		else { # verwende Leihstatus
		    if ($circ_ref->{Leihstatus} =~m/^(LSNichtLeihbar)$/){
			push @$available_ref, {
			    service => 'presence',
			    content => $circ_ref->{LeihstatusText},
			};
		    }
		    elsif ($circ_ref->{Leihstatus} =~m/^(LSLeihbarMagLE)$/){
			push @$available_ref, {
			    service => 'order',
			    content => $circ_ref->{LeihstatusText},
			    limitation => "bestellbar (Nutzung nur im Lesesaal)",
			    type => 'Stationary',
			};
		    }
		    elsif ($circ_ref->{Leihstatus} =~m/^(LSLeihbarMag|LSLeihbarZWMag)$/ ){
			push @$available_ref, {
			    service => 'order',
			    content => $circ_ref->{LeihstatusText},
			};
		    }
		    elsif ($circ_ref->{Leihstatus} =~m/^(LSLeihbar|LSLeihbarZWNoBS)$/){
			push @$available_ref, {
			    service => 'loan',
			    content => $circ_ref->{LeihstatusText},
			};
		    }
		    elsif ($circ_ref->{Leihstatus} =~m/^(LSEntliehen|LSEntliehenLE)$/){
			my $this_unavailable_ref = {
			    service => 'loan',
			    content => $circ_ref->{LeihstatusText},
			    expected => $circ_ref->{RueckgabeDatum},
			};
			
			if ($circ_ref->{VormerkAnzahl} >= 0){
			    $this_unavailable_ref->{queue} = $circ_ref->{VormerkAnzahl} ;
			}
			
			push @$unavailable_ref, $this_unavailable_ref;
			
		    }
		    elsif ($circ_ref->{Leihstatus} =~m/^(LSEntliehenNoVM)$/){
			my $this_unavailable_ref = {
			    service => 'loan',
			    content => $circ_ref->{LeihstatusText},
			    expected => $circ_ref->{RueckgabeDatum},
			};

			# no queue = no reservation!
			push @$unavailable_ref, $this_unavailable_ref;
			
		    }
		    elsif ($circ_ref->{Leihstatus} =~m/^(LSVermisst)$/){
			my $this_unavailable_ref = {
			    service => 'loan',
			    content => $circ_ref->{LeihstatusText},
#			    expected => 'lost',
			};
			
			push @$unavailable_ref, $this_unavailable_ref;
			
		    }
		}
		
		if (@$available_ref){
		    $item_ref->{available} = $available_ref;
		}
		
		if (@$unavailable_ref){
		    $item_ref->{unavailable} = $unavailable_ref;
		}
		
		push @$items_ref, $item_ref;
	    }
	    
	}	    
    }
    
    $response_ref = {
	id          => $titleid,
	database    => $database,
	items       => $items_ref,
	timestamp   => $self->get_timestamp,
    };
    
    $logger->debug("Circ: ".YAML::Dump($response_ref));
            
    return $response_ref;
}

######################################################################
# Hilfsmethoden
######################################################################

sub get_timestamp {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $timestamp = sprintf ( "%04d-%02d-%02dT%02d:%02d:%02dZ",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $timestamp;
}

# Titelbestellung ueberpruefen => Ausgabeort bestimmen
sub check_order {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $gsi             = exists $arg_ref->{holdingid} # Mediennummer
        ? $arg_ref->{holdingid}        : undef;

    my $zw              = exists $arg_ref->{unit}     # Zweigstelle
        ? $arg_ref->{unit}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    unless ($username && $gsi && $zw >= 0){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }

    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Checking order via USB-SOAP");
	    
    my @args = ($username,$gsi,$zw);
	    
    my $uri = "urn:/Loan";
	    
    if ($circinfotable->get($database)->{circdb} ne "sisis"){
	$uri = "urn:/Loan_inst";
    }
	        
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->check_order(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    # Problem ohne Loesung: In bestimmten Funktionen bricht der externe USBWS die Anfrage per
	    # Logger->error_die einfach ab. Entsprechende faultcodes und
	    # faultstrings werden dann zwar via SOAP zurueckgeliefert, aber der weitere
	    # Code in diesem Modul bricht dann einfach ab und liefert {} zurueck
	    # und nicht response_ref mit error und error_description

	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);

	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };
	    
	    return $response_ref;
	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{OpacBestellung} && defined $result_ref->{OpacBestellung}{NotOK}){
	my $error = "unknown order failure";
	
	if ($result_ref->{OpacBestellung}{ErrorCode} eq "OpsOrderMehrfExemplBestellt"){
	    $error = "already ordered";
	}
	elsif ($result_ref->{OpacBestellung}{ErrorCode} eq "OpsOrderVomAnderemBenEntl"){
	    $error = "already lent by other user";	    
	}
	
	$response_ref = {
	    "code" => 403,
		"error" => $error,
		"error_description" => $result_ref->{OpacBestellung}{NotOK},
	};

	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}
	
	return $response_ref	    
    }
    # at least one pickup location
    elsif (scalar keys %{$result_ref->{OpacBestellung}} >= 1){
	$response_ref->{"successful"} = 1;
	foreach my $pickupid (sort keys %{$result_ref->{OpacBestellung}}){
	    push @{$response_ref->{"pickup_locations"}}, {
		name        => $pickupid,
		about       => $result_ref->{OpacBestellung}{$pickupid},
	    };
	}

	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}	
    }
    else {
	$response_ref = {
	    "code" => 404,
		"error" => "failure",
		"error_description" => "undefined error",
	};

	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}
	
	return $response_ref;
    }

    # Beispielrueckgabe
    #
    # pickup_locations:
    #   - about: Abholregale (zur Ausleihe)
    #     pickupid: 0
    #   - about: Lesesaalausgabe (Nutzung nur im Lesesaal)
    #     pickupid: 1

    
    return $response_ref;
}

sub check_reservation {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $gsi             = exists $arg_ref->{holdingid}  # Mediennummer
        ? $arg_ref->{holdingid}      : undef;

    my $zw              = exists $arg_ref->{unit}     # Zweigstelle
        ? $arg_ref->{unit}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    unless ($username && $gsi && $zw >= 0){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Checking reservation via USB-SOAP");
	    
    my @args = ($username,$gsi,$zw);
	    
    my $uri = "urn:/Loan";
	    
    if ($circinfotable->get($database)->{circdb} ne "sisis"){
	$uri = "urn:/Loan_inst";
    }
	    
    
    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
    
    $logger->debug("Using args ".YAML::Dump(\@args));
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));

	
	my $result = $soap->check_reservation(@args);
	
	unless ($result->fault) {
	    $result_ref = $result->result;
	    if ($logger->is_debug){
		$logger->debug("SOAP Result: ".YAML::Dump($result_ref));
	    }
	}
	else {
	    # Problem ohne Loesung: In bestimmten Funktionen bricht der externe USBWS die Anfrage per
	    # Logger->error_die einfach ab. Entsprechende faultcodes und
	    # faultstrings werden dann zwar via SOAP zurueckgeliefert, aber der weitere
	    # Code in diesem Modul bricht dann einfach ab und liefert {} zurueck
	    # und nicht response_ref mit error und error_description
	    
	    $logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);

	    $response_ref = {
		error => $result->faultcode,
		error_description => $result->faultstring,
	    };
	    
	    return $response_ref;
	}
    };
	    
    if ($@){
	$logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	$response_ref = {
	    error => "connection error",
	    error_description => "Problem bei der Verbindung zum Ausleihsystem",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{VormerkungMoeglich} && defined $result_ref->{VormerkungMoeglich}{NotOK} ){
	$response_ref = {
	    "code" => 403,
		"error" => "failure",
		"error_description" => $result_ref->{VormerkungMoeglich}{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    # at least one pickup location
    elsif (scalar keys %{$result_ref->{VormerkungMoeglich}} >= 1){
	$response_ref->{"successful"} = 1;
	foreach my $pickupid (sort keys %{$result_ref->{VormerkungMoeglich}}){
	    push @{$response_ref->{"pickup_locations"}}, {
		name        => $pickupid,
		about       => $result_ref->{VormerkungMoeglich}{$pickupid},
	    };
	}

	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref;
    }
    else {
	$response_ref = {
	    "code" => 404,
		"error" => "failure",
		"error_description" => "undefined error",
	};

	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}
	
	return $response_ref;
    }
    
    return $response_ref;
}

sub send_account_request {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Set defaults
    my $types_ref      = exists $arg_ref->{types}
    ? $arg_ref->{types}        : [];
    
    my $username       = exists $arg_ref->{username}
        ? $arg_ref->{username} : undef;

    my $database       = $self->get_database;
    my $config         = $self->get_config;
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $itemlist     = undef;
    my $response_ref = {};

    foreach my $type_ref (@$types_ref){
	my @args = ($username,$type_ref->{type});
	
	my $uri = "urn:/Account";
	
	if ($circinfotable->get($database)->{circdb} ne "sisis"){
	    $uri = "urn:/Account_inst";
	    push @args, $database;
	}
	
	eval {
	    my $soap = SOAP::Lite
		-> uri($uri)
		-> proxy($config->get('usbws_url'));
	    my $result = $soap->show_account(@args);
	    
	    unless ($result->fault) {
		$itemlist = $result->result;
		if ($logger->is_debug){
		    $logger->debug("SOAP Result: ".YAML::Dump($itemlist));
		}
	    }
	    else {
		$logger->error("SOAP Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);

		$response_ref = {
		    error => $result->faultcode,
		    error_description => $result->faultstring,
		};
		
		return $response_ref;		
	    }
	};
	
	if ($@){
	    $logger->error("SOAP-Target ".$config->get('usbws_url')." with Uri $uri konnte nicht erreicht werden: ".$@);

	    $response_ref = {
		error => "connection error",
		error_description => "Problem bei der Verbindung zum Ausleihsystem",
	    };
	    
	    return $response_ref;
	}
	
	# Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
	# in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
	# titelbasierten Exemplardaten
	
	
	if (defined($itemlist)) {

	    if ( %{$itemlist->{Konto}} && ($type_ref->{type} eq "AUSLEIHEN" || $type_ref->{type} eq "BESTELLUNGEN" || $type_ref->{type} eq "VORMERKUNGEN")){
		if (defined $itemlist->{Konto}{KeineVormerkungen}){
		    if ($logger->is_debug){
			$response_ref->{debug} = $itemlist;
		    }
		    $response_ref->{no_reservations} = 1;
		    next;
		}
		if (defined $itemlist->{Konto}{KeineBestellungen}){
		    if ($logger->is_debug){
			$response_ref->{debug} = $itemlist;
		    }
		    $response_ref->{no_orders} = 1;
		    next;
		}
		if (defined $itemlist->{Konto}{KeineAusleihen}){
		    if ($logger->is_debug){
			$response_ref->{debug} = $itemlist;
		    }
		    $response_ref->{no_loans} = 1;
		    next;
		}
		
		my $all_items_ref = [];
		
		foreach my $nr (sort keys %{$itemlist->{Konto}}){
		    next if ($itemlist->{Konto}{$nr}{KtoTyp});
		    push @$all_items_ref, $itemlist->{Konto}{$nr};
		}
		
		foreach my $item_ref (@$all_items_ref){
		    my @titleinfo = ();
		    push @titleinfo, $item_ref->{Verfasser} if ($item_ref->{Verfasser});
		    push @titleinfo, $item_ref->{Titel} if ($item_ref->{Titel});
		    
		    my $about = join(': ',@titleinfo);
		    
		    my $label     = $item_ref->{Signatur};
		    
		    my $this_response_ref = {
			about   => $about,
			edition => $item_ref->{Titlecatkey},
			item    => $item_ref->{MedienNummer},
			renewals => $item_ref->{VlAnz},
			status   => $type_ref->{status},
			label     => $label,
		    };

		    if ($item_ref->{EntlZweig} >= 0 && $item_ref->{EntlZweigTxt}){
			$this_response_ref->{department} = {
			    id => $item_ref->{EntlZweig},
			    about => $item_ref->{EntlZweigTxt},
			};
		    }
		    
		    if ($type_ref->{type} eq "AUSLEIHEN"){
			$this_response_ref->{starttime} = $item_ref->{Datum};
			$this_response_ref->{endtime}   = $item_ref->{RvDatum};
		    }
		    elsif ($type_ref->{type} eq "VORMERKUNGEN"){
			$this_response_ref->{starttime} = $item_ref->{Datum};
			$this_response_ref->{endtime}   = $item_ref->{VmEnd};
			$this_response_ref->{queue}     = $item_ref->{VmAnz};
		    }
		    elsif ($type_ref->{type} eq "BESTELLUNGEN"){
                        # Todo: Fernleihbestellungen erkennung und zurueckgeben
			if ($item_ref->{LesesaalTxt} && $this_response_ref->{department}{about}){
			    $this_response_ref->{department}{about}.=" / ".$item_ref->{LesesaalTxt};
			}
			$this_response_ref->{starttime} = $item_ref->{Datum};
			$this_response_ref->{endtime}   = $item_ref->{RvDatum};
		    }

		    push @{$response_ref->{items}}, $this_response_ref;
		}
	    }
	    elsif ($type_ref->{type} eq "OFFENEGEBUEHREN"){
		#		next if (defined $itemlist->{Konto}{KeineOffenenGebuehren});
		my $all_items_ref = [];

		my $fee_sum = 0;
		foreach my $nr (sort keys %{$itemlist->{Konto}}){
		    next if ($itemlist->{Konto}{$nr}{KtoTyp});
		    push @$all_items_ref, $itemlist->{Konto}{$nr};
		    if ($itemlist->{Konto}{$nr}{Gebuehr}){
			my $gebuehr = $itemlist->{Konto}{$nr}{Gebuehr};
			$gebuehr=~s/\,/./;
			$fee_sum+=$gebuehr;
		    }
		}

		$response_ref->{amount} = $fee_sum." EUR";
		
		foreach my $item_ref (@$all_items_ref){
		    my $this_response_ref = {};
		    
		    my $gebuehr = $item_ref->{Gebuehr};
		    $gebuehr=~s/\,/./;

		    my @titleinfo = ();
		    push @titleinfo, $item_ref->{Verfasser} if ($item_ref->{Verfasser});
		    push @titleinfo, $item_ref->{Titel} if ($item_ref->{Titel});
		    
		    my $description = join(': ',@titleinfo);
		    
		    $this_response_ref->{label} = $item_ref->{Signatur};
		    
		    $this_response_ref->{amount} = $gebuehr. "EUR";

		    $this_response_ref->{about}   = $description;
		    $this_response_ref->{type}    = $item_ref->{Text};
		    $this_response_ref->{edition} = $item_ref->{Titlecatkey},
		    $this_response_ref->{item}    = $item_ref->{MedienNummer},

		    my ($day,$month,$year) = $item_ref->{Datum} =~m/^(\d+)\.(\d+)\.(\d+)$/;
		    $this_response_ref->{date} = $year."-".$month."-".$day."T12:00:00Z";
		    
		    push @{$response_ref->{items}}, $this_response_ref;
		}
	    }
	}
    }

    if ($logger->is_debug){
	$response_ref->{debug} = $itemlist;
    }
    
    return $response_ref;
}

# Definition der USBWS:
#
# /opt/ip/var/cgi-intern/loan.pl
# /opt/ips/usr/perl/USB/SOAP/S***s/Loan.pm
# /opt/ips/usr/config/gateway_usb/ubkloan.xml
# /opt/ips/usr/templates/appltemplates/USB/template.loanxml.tpl
# /opt/ips/usr/templates/appltemplates/USB/template.loan.tpl

1;
__END__

=head1 NAME

OpenBib::ILS::Backend::USBWS - Backend zur Anbindung eines ILS mittels USB Webservice

=head1 DESCRIPTION

Dieses Backend stellt die Methoden zur Authentifizierung, Ausleihe und Medienstatus ueber einen USB Webservice bereit

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