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
use OpenBib::L10N;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}           : undef;

    my $config    = exists $arg_ref->{config}
        ? $arg_ref->{config}       : OpenBib::Config->new;

    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}     : undef;

    my $lang      = exists $arg_ref->{lang}
        ? $arg_ref->{lang}         : 'de';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $ils_ref = $config->get_ils_of_database($database);

    my $self = { };

    bless ($self, $class);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    $self->{database} = $database;
    $self->{msg}      = $msg;    
    $self->{ils}      = $ils_ref;
    $self->{_config}  = $config;
    
    return $self;
}

# Gemeinsame Dienstmethoden fuer alle Backends (Campuslieferdienst, Elektronischer Semesterapparat

sub make_campus_order {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $title            = exists $arg_ref->{title}
        ? $arg_ref->{title}           : undef;
    
    my $katkey           = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}         : undef;

    my $author           = exists $arg_ref->{author}
        ? $arg_ref->{author}          : undef;
    
    my $corporation      = exists $arg_ref->{corporation}
        ? $arg_ref->{corporation}     : undef;
    
    my $publisher        = exists $arg_ref->{publisher}
        ? $arg_ref->{publisher}       : undef;
    
    my $year             = exists $arg_ref->{year}
        ? $arg_ref->{year}            : undef;
    
    my $numbering        = exists $arg_ref->{numbering}
        ? $arg_ref->{numbering}       : undef;

    my $label            = exists $arg_ref->{label}    # Signatur/Mediennummer
        ? $arg_ref->{label}           : undef;

    my $isbn             = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}            : undef;
    
    my $issn             = exists $arg_ref->{issn}
        ? $arg_ref->{issn}            : undef;
    
    my $articleauthor    = exists $arg_ref->{articleauthor}
        ? $arg_ref->{articleauthor}   : undef;
    
    my $articletitle     = exists $arg_ref->{artitletitle}
        ? $arg_ref->{artitletitle}    : undef;
    
    my $volume           = exists $arg_ref->{volume}
        ? $arg_ref->{volume}          : undef;
    
    my $issue           = exists $arg_ref->{issue}
        ? $arg_ref->{issue}           : undef;
    
    my $pages           = exists $arg_ref->{pages}
        ? $arg_ref->{pages}           : undef;
    
    my $refid           = exists $arg_ref->{refid}
        ? $arg_ref->{refid}           : undef;
    
    my $userid          = exists $arg_ref->{userid}
        ? $arg_ref->{userid}          : undef;
    
    my $username        = exists $arg_ref->{username}
        ? $arg_ref->{username}        : undef;
    
    my $receipt         = exists $arg_ref->{receipt}
        ? $arg_ref->{receipt}         : undef;
    
    my $email           = exists $arg_ref->{email}
        ? $arg_ref->{email}           : undef;
    
    my $remark          = exists $arg_ref->{remark}
        ? $arg_ref->{remark}          : undef;
    
    my $zweig           = exists $arg_ref->{unit}     # Zweigstelle
        ? $arg_ref->{unit}            : undef;

    my $zweigabteil     = exists $arg_ref->{location}
        ? $arg_ref->{location}        : undef;

    my $domain          = exists $arg_ref->{domain}
        ? $arg_ref->{domain}          : undef;
    
    my $subdomain       = exists $arg_ref->{subdomain}
        ? $arg_ref->{subdomain}       : undef;
        
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Making order via USB-SOAP");

    unless ($username && $label && $zweig >= 0){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }
    
    my @args = ($title, $katkey, $author, $corporation, $publisher, $year, $numbering, $label,$isbn, $issn, $articleauthor, $articletitle, $volume, $issue, $pages,$refid, $userid, $username, $receipt, $email, $remark, $zweig, $zweigabteil,$domain,$subdomain);
	    
    my $uri = "urn:/MyBib";
	        
    if ($logger->is_debug){    
	$logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));    
	$logger->debug("Using args ".YAML::Dump(\@args));    
    }
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->submit_campusorder(@args);
	
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
	    error_description => "Problem bei der Verbindung zum MyBib-System",
	};
	
	return $response_ref;
    }

    # Allgemeine Fehler
    if (defined $result_ref->{NotOK} ){
	$response_ref = {
	    "code" => 400,
		"error" => "error",
		"error_description" => $result_ref->{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    
    if (defined $result_ref->{order_acquire} && defined $result_ref->{order_acquire}{Error} ){
	$response_ref = {
	    "code" => 403,
		"error" => "order acquire failed",
		"error_description" => $result_ref->{order_acquire}{Error},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    elsif (defined $result_ref->{OK}){
	$response_ref = {
	    "successful" => 1,
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

sub make_pda_order {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $title            = exists $arg_ref->{title}
        ? $arg_ref->{title}           : undef;
    
    my $katkey           = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}         : undef;

    my $database         = exists $arg_ref->{database} # PDA Katalogname
        ? $arg_ref->{database}        : undef;

    my $author           = exists $arg_ref->{author}
        ? $arg_ref->{author}          : undef;
    
    my $corporation      = exists $arg_ref->{corporation}
        ? $arg_ref->{corporation}     : undef;
    
    my $publisher        = exists $arg_ref->{publisher}
        ? $arg_ref->{publisher}       : undef;
    
    my $year             = exists $arg_ref->{year}
        ? $arg_ref->{year}            : undef;
    
    my $isbn             = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}            : undef;
    
    my $price            = exists $arg_ref->{price}
        ? $arg_ref->{price}           : undef;

    my $classification   = exists $arg_ref->{classification}
        ? $arg_ref->{classification}  : undef;
        
    my $userid          = exists $arg_ref->{userid}
        ? $arg_ref->{userid}          : undef;

    my $external_userid = exists $arg_ref->{external_userid}
        ? $arg_ref->{external_userid}          : undef;
    
    my $username        = exists $arg_ref->{username}
        ? $arg_ref->{username}        : undef;
    
    my $reservation     = exists $arg_ref->{reservation}
        ? $arg_ref->{reservation}     : undef;

    my $receipt         = exists $arg_ref->{receipt}
        ? $arg_ref->{receipt}         : undef;
    
    my $email           = exists $arg_ref->{email}
        ? $arg_ref->{email}           : undef;
            
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Making order via USB-SOAP");

    unless ($username && $katkey && $database){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }

    my $pda_id = $database.":".$katkey;
    
    my @args = ($title, $pda_id, $author, $corporation, $publisher, $year, $isbn, $price, $classification, $userid, $username, $reservation, $receipt, $email, $external_userid);
	    
    my $uri = "urn:/PDA";
	        
    if ($logger->is_debug){    
	$logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));	
	$logger->debug("Using args ".YAML::Dump(\@args));    
    }
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->submit_pda(@args);
	
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
	    error_description => "Problem bei der Verbindung",
	};
	
	return $response_ref;
    }

    if (defined $result_ref->{OK}){
	$response_ref = {
	    "successful" => 1,
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }

    if (defined $result_ref->{NotOK}){
	$response_ref = {
	    "error" => "error",
		"error_description" => $result_ref->{NotOK},
		"code" => 405,
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

sub make_ilias_order {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $title            = exists $arg_ref->{title}
        ? $arg_ref->{title}           : undef;
    
    my $katkey           = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}         : undef;

    my $author           = exists $arg_ref->{author}
        ? $arg_ref->{author}          : undef;
    
    my $corporation      = exists $arg_ref->{corporation}
        ? $arg_ref->{corporation}     : undef;
    
    my $publisher        = exists $arg_ref->{publisher}
        ? $arg_ref->{publisher}       : undef;
    
    my $year             = exists $arg_ref->{year}
        ? $arg_ref->{year}            : undef;
    
    my $numbering        = exists $arg_ref->{numbering}
        ? $arg_ref->{numbering}       : undef;

    my $label            = exists $arg_ref->{label}    # Signatur/Mediennummer
        ? $arg_ref->{label}           : undef;

    my $isbn             = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}            : undef;
    
    my $issn             = exists $arg_ref->{issn}
        ? $arg_ref->{issn}            : undef;
    
    my $articleauthor    = exists $arg_ref->{articleauthor}
        ? $arg_ref->{articleauthor}   : undef;
    
    my $articletitle     = exists $arg_ref->{artitletitle}
        ? $arg_ref->{artitletitle}    : undef;
    
    my $volume           = exists $arg_ref->{volume}
        ? $arg_ref->{volume}          : undef;
    
    my $issue           = exists $arg_ref->{issue}
        ? $arg_ref->{issue}           : undef;
    
    my $pages           = exists $arg_ref->{pages}
        ? $arg_ref->{pages}           : undef;
    
    my $refid           = exists $arg_ref->{refid}
        ? $arg_ref->{refid}           : undef;
    
    my $userid          = exists $arg_ref->{userid}
        ? $arg_ref->{userid}          : undef;
    
    my $username        = exists $arg_ref->{username}
        ? $arg_ref->{username}        : undef;
    
    my $receipt         = exists $arg_ref->{receipt}
        ? $arg_ref->{receipt}         : undef;
    
    my $email           = exists $arg_ref->{email}
        ? $arg_ref->{email}           : undef;
    
    my $remark          = exists $arg_ref->{remark}
        ? $arg_ref->{remark}          : undef;
    
    # my $zweig           = exists $arg_ref->{unit}     # Zweigstelle
    #     ? $arg_ref->{unit}            : undef;

    # my $zweigabteil     = exists $arg_ref->{location}
    #     ? $arg_ref->{location}        : undef;

    # my $domain          = exists $arg_ref->{domain}
    #     ? $arg_ref->{domain}          : undef;
    
    # my $subdomain       = exists $arg_ref->{subdomain}
    #     ? $arg_ref->{subdomain}       : undef;
        
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database = $self->get_database;
    my $config   = $self->get_config;

    my $response_ref = {};
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    $logger->debug("Making order via USB-SOAP");

    unless ($userid && $refid && $katkey && $label){
	$response_ref =  {
	    error => "missing parameter",
	};

	return $response_ref;
    }
    
    my @args = ($title, $katkey, $author, $corporation, $publisher, $year, $numbering, $label,$isbn, $issn, $articleauthor, $articletitle, $volume, $issue, $pages,$refid, $userid, $username, $receipt, $email, $remark);
	    
    my $uri = "urn:/MyBib";
	        
    if ($logger->is_debug){    
	$logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));	
	$logger->debug("Using args ".YAML::Dump(\@args));    
    }
    
    my $result_ref;
    
    eval {
	my $soap = SOAP::Lite
	    -> uri($uri)
	    -> proxy($config->get('usbws_url'));
	my $result = $soap->submit_iliasorder(@args);
	
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
	    error_description => "Problem bei der Verbindung zum MyBib-System",
	};
	
	return $response_ref;
    }

    # Allgemeine Fehler
    if (defined $result_ref->{NotOK} ){
	$response_ref = {
	    "code" => 400,
		"error" => "error",
		"error_description" => $result_ref->{NotOK},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    
    if (defined $result_ref->{order_acquire} && defined $result_ref->{order_acquire}{Error} ){
	$response_ref = {
	    "code" => 403,
		"error" => "order acquire failed",
		"error_description" => $result_ref->{order_acquire}{Error},
	};
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    elsif (defined $result_ref->{OK}){
	$response_ref = {
	    "successful" => 1,
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

sub get_config {
    my $self = shift;

    return $self->{_config};    
}

sub get_database {
    my $self = shift;

    return $self->{database};    
}

sub get_msg {
    my $self = shift;

    return $self->{msg};    
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

sub get_timestamp {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $timestamp = sprintf ( "%04d-%02d-%02dT%02d:%02d:%02dZ",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $timestamp;
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

OpenBib::ILS - Objekt zur Anbindung eines Integrierten Bibliothekssystems (Authentifizierung, Ausleihe, Medienstatus)

=head1 DESCRIPTION

Dieses Objekt stellt Funktionen eines ILS bereit

=head1 SYNOPSIS

 use OpenBib::ILS;

 my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

=head1 GENERELLES

=over 4

=item Instanziierung

Die Instanziierung erfolgt immer ueber die Methode create_ils inder Klasse
OpenBib::ILS::Factory

=item Bezug zum Bibliothekssystem

Das Objekt weiss anhand des Uebergebenen Parameters $database in create_ils, 
wie es sich mit dem jeweiligen Bibliothekssystem verbindung muss (via Backends) 
und speichert $database intern im Objekt ab

=back

=head1 METHODS

=over 4

=item authenticate({username => $username, password => $password})

Authentifizierung des Nutzers $username mit dem Passwort $password an ILS zu $database (via create_ils einmalig uebergeben)

=item get_mediastatus($titleid)

Liefere alle Exemplare mit ihren Ausleihstatus-Informationen zum Titel mit der $titleid zurueck

=item get_loans($username)

Liefere alle getaetigten Ausleihen des Nutzers mit dem Namen $username zurueck

=item get_orders($username)

Liefere alle getaetigten Bestellungen des Nutzers mit dem Namen $username zurueck

=item get_reservations($username)

Liefere alle getaetigten Reservierungen von Medien des Nutzers mit dem Namen $username zurueck

=item get_fees($username)

Liefere alle Gebuehren des Nutzers mit dem Namen $username zurueck

=item get_items($username)

Liefere in einem Request alle Informationen von get_loans, get_orders und get_reservations in einem Request 
zum nutzer mit dem Namen $username zurueck

=item check_order({ username => $username, holdingid => $mediennr, unit => $zweigstelle })

Ueberpruefe, ob eine Bestellung auf die Mediennummer $mediennr in der (Teil)Bibliothek $zweigstelle durchgefuehrt werden kann 
und liefere eine Auswahl der Ausgabeorte (pickup_locations) fuer den Aufruf der Methode make_order zurueck.

=item make_order({ username => $username, holdingid => $mediennr, unit => $zweigstelle, pickup_location => $ausgabeort })

Fuehre eine Bestellung eines Mediums mit der Mediennummer $mediennr in der (Teil)Bibliothek $zweigstelle und dem Ausgabeort $ausgabeort durch

=item check_reservation({ username => $username, holdingid => $mediennr, unit => $zweigstelle })

Ueberpruefe, ob eine Vormerkung auf das Medium $mediennr in der (Teil)Bibliothek $zweigstelle  durchgefuehrt werden kann 
und liefere eine Auswahl der Ausgabeorte (pickup_locations) fuer den Aufruf der Methode make_reservation zurueck.

=item make_reservation({ username => $username, holdingid => $mediennr, unit => $zweigstelle, $pickup_location => $ausgabeort, titleid => $katkey, type => $type })

Fuehre entweder 
a) eine vollqualifizierte Vormerkung auf das Medium $mediennr in der (Teil)Bibliothek $zweigstelle mit dem Ausgabeort $ausgabeort oder
b) eine teilqualifizierte Vormerkung auf ein beliebiges Exemplar des Titels mit der ID $katkey in der Zweigstelle $zweigstelle mit dem Ausgabeort $ausgabeort und dem Type $type="unqualified" durch

=item cancel_reservation({ username => $username, holdingid => $mediennr, unit => $zweigstelle, titleid => $katkey })

Storniere 
a) eine vollqualifizierte Vormerkung auf das Medium $mediennr in der (Teil)Bibliothek $zweigstelle oder
b) eine teilqualifizierte Vormerkung auf ein beliebiges Exemplar des Titels mit der ID $katkey in der Zweigstelle $zweigstelle

=item renew_loans($username)

Fuehre eine Gesamtkontoverlaengerung fuer den Account des Nutzers $username durch

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Der Verzicht auf den Exporter 
bedeutet weniger Speicherverbrauch und mehr Performance auf 
Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
