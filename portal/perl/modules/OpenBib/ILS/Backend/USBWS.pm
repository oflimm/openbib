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
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Config::LocationInfoTable;

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

    my $url = $config->get('usbauth_url');

    $url.="?userid=".uri_escape($username)."&password=".uri_escape($password);

    $logger->debug("Request-URL: ".$url);
    
    my $request = HTTP::Request->new('GET',$url);

    my $response = $ua->request($request);

    if ( $response->is_error() ) {
	return $userid; # 0 = generic error
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

    my $result_ref;
    
    unless (defined $response_username && $username eq $response_username){
	$userid = -3;  # Status: wrong password

	return $userid;
    }
        
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
    my ($self,$titleid) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config    = $self->get_config;
    my $database  = $self->get_database;
    
    my $result_ref = {};
    
    unless ($database && $titleid){
	$result_ref = {
	    timestamp   => $self->get_timestamp,
	    circulation => [],
	    error       => "missing parameters",	    
	};
	
	return $result_ref;
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
	    
	    my @args = ($titleid);
	    
	    my $uri = "urn:/Loan";
	    
	    if ($circinfotable->get($database)->{circdb} ne "sisis"){
		$uri = "urn:/Loan_inst";
		push @args, $database;
	    }
	    
	    $logger->debug("Trying connection to uri $uri at ".$config->get('usbws_url'));
	    
	    eval {
		my $soap = SOAP::Lite
		    -> uri($uri)
		    -> proxy($config->get('usbws_url'));
		my $result = $soap->show_all_items(@args);
		
		unless ($result->fault) {
		    $circexlist = $result->result;
		    if ($logger->is_debug){
			$logger->debug("SOAP Result: ".YAML::Dump($circexlist));
		    }
		}
		else {
		    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
		}
	    };
	    
	    if ($@){
		$logger->error("SOAP-Target ".$circinfotable->get($database)->{circcheckurl}." konnte nicht erreicht werden :".$@);
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

		$item_ref->{'label'} = $circ_ref->{'Signatur'};
		$item_ref->{'id'}    = $circ_ref->{'MedienNr'};

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

		if ($circ_ref->{LeihstatusText} eq "Präsenzbestand"){
		    push @$available_ref, {
			service => 'presence',
		    };
		}
		elsif ($circ_ref->{LeihstatusText} eq "bestellbar (Nutzung nur im Lesesaal)"){
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
		elsif ($circ_ref->{LeihstatusText} = "ausleihbar"){
		    push @$available_ref, {
			service => 'loan',
		    };
		}
		elsif ($circ_ref->{LeihstatusText} = "nicht entleihbar"){
		    push @$available_ref, {
			service => 'presence',
		    };
		}
		elsif ($circ_ref->{LeihstatusText} = "nur in bes. Lesesaal bestellbar"){
		    push @$available_ref, {
			service => 'order',
			limitation => $circ_ref->{LeihstatusText},
			type => 'Stationary',
		    };
		}
		elsif ($circ_ref->{LeihstatusText} = "nur Wochenende"){
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
		    };

		    push @$unavailable_ref, $this_unavailable_ref;
		    
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
    
    $result_ref = {
	id          => $titleid,
	database    => $database,
	items       => $items_ref,
	timestamp   => $self->get_timestamp,
    };
    
    $logger->debug("Circ: ".YAML::Dump($result_ref));
            
    return $result_ref;
}

sub get_timestamp {
    my $self = shift;
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $timestamp = sprintf ( "%04d-%02d-%02dT%02d:%02d:%02dZ",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $timestamp;
}

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
