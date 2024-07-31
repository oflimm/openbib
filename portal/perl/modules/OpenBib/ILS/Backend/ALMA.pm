#####################################################################
#
#  OpenBib::ILS::Backend::ALMA
#
#  Dieses File ist (C) 2021- Oliver Flimm <flimm@openbib.org>
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

use Benchmark ':hireswallclock';
use Cache::Memcached::Fast;
use Encode qw(decode_utf8 encode_utf8);
use HTTP::Cookies;
use HTTP::Request;
use JSON::XS qw/decode_json encode_json/;
use List::MoreUtils qw(none);
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
use OpenBib::L10N;

######################################################################
# Authentication
######################################################################

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

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout($config->get('alma')->{api_timeout});

    # Only valid and defined languages. Fallback 'de'
    $lang = "de" if (none { $_ eq $lang } @{$config->get('lang')});

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $circulation_config = $config->load_yaml('/opt/openbib/conf/alma-circulation.yml');
    
    $self->{client}       = $ua;    
    $self->{database}     = $database;    
    $self->{ils}          = $ils_ref;
    $self->{msg}          = $msg;
    $self->{lang}         = $lang;
    $self->{_config}      = $config;
    $self->{_circ_config} = $circulation_config;

#    $self->connectMemcached();
    
    return $self;
}

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
    my $msg     = $self->get_msg;

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

    unless (defined $ldaps) {
	$logger->error("LDAPS object NOT created");
	$response_ref->{failure} = {
	    error => 'wrong password',
	    code => -3,  # Status: wrong password
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
	    $response_ref->{failure} = {
		error => 'wrong password',
		code => -3,  # Status: wrong password
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

    unless ($result && ! $result->code){
	$logger->error("Error searching user $username: ".$result->error );
	$response_ref->{failure} = {
	    error => 'wrong password',
	    code => -3,  # Status: wrong password
	};
	
	return $response_ref;
    }
	    
    my $userdn = "";	
    my $account_ref = {};
    
    unless ($result && $result->count == 1) {
	$response_ref->{failure} = {
	    error => 'wrong password',
	    code => -3,  # Status: wrong password
	};
	
	return $response_ref;
    }
	
    my $entry = $result->entry(0);
    
    $userdn = $entry->dn();
    
    # Essential Data
    $account_ref->{username}  = $entry->get_value('USBportalName');
    $account_ref->{fullname}  = $entry->get_value('cn');
    $account_ref->{surname}   = $entry->get_value('sn');
    $account_ref->{forename}  = $entry->get_value('givenName');
    $account_ref->{email}     = $entry->get_value('USBEmailAdr');
    $account_ref->{alma_id}   = $entry->get_value('uid');    
    $account_ref->{alma_gid}  = $entry->get_value('gidNumber');    
    
    if ($logger->is_debug){
	$logger->debug(YAML::Dump($entry));
	
    }
    
    $logger->debug("Got userdn $userdn");
    
    if ($userdn){
	my $user_msg = $ldaps->bind(
	    $userdn,
	    password => $password,
	    );
	
	
	unless ($user_msg && $user_msg->code() == 0){
	$response_ref->{failure} = {
	    error => 'wrong password',
	    code => -3,  # Status: wrong password
	};
	
	return $response_ref;
	}
	    
	$success = 1;
	
	# Store essential data
	$response_ref->{userinfo}{username}       = $account_ref->{username};    
	$response_ref->{userinfo}{fullname}       = $account_ref->{fullname};
	$response_ref->{userinfo}{surname}        = $account_ref->{surname};
	$response_ref->{userinfo}{forename}       = $account_ref->{forename};
	$response_ref->{userinfo}{email}          = $account_ref->{email};
	$response_ref->{userinfo}{external_id}    = $account_ref->{alma_id};	
	$response_ref->{userinfo}{external_group} = $account_ref->{alma_gid};	
	
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

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->update_sis({ type => 'email', username => $username, new_data => $email });    
}

sub update_pin {
    my ($self,$username,$pin) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->update_sis({ type => 'pin', username => $username, new_data => $pin });    
}

sub update_password {
    my ($self,$username,$oldpassword,$newpassword) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->update_sis({ type => 'password', username => $username, new_data => $newpassword, old_data => $oldpassword });
}

sub update_phone {
    my ($self) = @_;
    
    my $response_ref = {};
    
    # Wird aus Gruenden der Datensparsamkeit nicht mehr erhoben. Wurde nur waehrend der Corona-Zeit 2020-2022 benoetigt

    return $response_ref;
}

# Bestellungen, Vormerkungen und Ausleihen in einer Abfrage
sub get_items {
    my ($self,$username) = @_;

    # In Alma nicht vorhanden und Modellierung mit einzelnen Requests
    # (get_loans, get_reservations, get_orders) wegen des concurrent
    # request API-Limits kritisch

    my $msg         = $self->get_msg;

    my $response_ref = {
	"code" => 400,
	    "error" => "error",
	    "error_description" => "Das Bibliothekssystem Alma bietet keine Abfrage der Bestellungen, Vormerkungen und Ausleihen in einer Abfrage an",
    };

    return $response_ref;
}

# Accountinformationen (Anzahl Ausleihen, Vormerkungen, Bestellungen, Gebuehren)
sub get_accountinfo {
    my ($self,$username) = @_;

    # In Alma nicht vorhanden und Modellierung mit einzelnen Requests
    # (get_loans, get_reservations, get_orders) wegen des concurrent
    # request API-Limits kritisch

    my $msg         = $self->get_msg;
    
    my $response_ref = {
	"code" => 400,
	    "error" => "error",
	    "error_description" => "Das Bibliothekssystem Alma bietet keine Abfrage der Zahl an Bestellungen, Vormerkungen und Ausleihen in einer Abfrage an",
    };
    
    return $response_ref;
}

# Accountinformationen (Adresse, E-Mail, etc.)
sub get_userdata {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $config  = $self->get_config;
    my $dbname  = $self->get_database;
    my $msg     = $self->get_msg;
    
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
    

    unless ($proxy_msg && ! $proxy_msg->code()){
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
    $response_ref->{external_id}       = $entry->get_value('uid');
    $response_ref->{external_group}    = $entry->get_value('gidNumber');
    
    my @block_reasons                  = $entry->get_value('ALMASperrgrund');

    @block_reasons = map { m/^([^:]+)::/ } @block_reasons;
    
    $response_ref->{block_reason}      = join (' ; ',@block_reasons);
       
    if ($logger->is_debug){
	$logger->debug(YAML::Dump($entry));
	
    }

    foreach my $key (keys %$response_ref){
	$response_ref->{$key} = decode_utf8($response_ref->{$key});
    }
    
    return $response_ref;
}

sub get_article_orders {
    my ($self,$username,$start,$count) = @_;
    
    my $response_ref = {};
    
    # Ersetzt durch und integriert in Fernleihportal des hbz

    return $response_ref;
}

sub get_zfl_orders {
    my ($self,$username,$start,$count) = @_;
    
    my $response_ref = {};

    # Ersetzt durch und integriert in Fernleihportal des hbz    

    return $response_ref;
}

sub get_orders {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    return $self->get_alma_request($username,'order');
}

sub get_reservations {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    return $self->get_alma_request($username,'reservation');
}

sub get_fees {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');
    
    my $response_ref = {};

    $username = $self->get_externalid_of_user($username);
    
    unless ($username){
	$response_ref = {
	    timestamp   => $self->get_timestamp,
	    error => 'error',
	    error_description       => "missing or wrong parameters",
	};
	
	return $response_ref;
    }
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    my $items_ref = [];

    # Ausleihinformationen der Exemplare
    {
	my $json_result_ref = {};

	$logger->debug("Getting Circulation info via ALMA API");
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = $config->get('alma')->{'api_baseurl'}."/users/$username/fees?user_id_type=all_unique&status=ACTIVE&lang=$lang&apikey=$api_key";
	
	my $api_result_ref = $self->send_alma_api_call({ method => 'GET', url => $url });

	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){
	    return $api_result_ref->{'response'}
	}

	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}

	# Processing data
	
	# Keine Gebuehren?
	if (defined $json_result_ref->{'total_record_count'} && defined $json_result_ref->{'total_sum'} && !$json_result_ref->{'total_sum'} ){
	    if ($logger->is_debug){
		$response_ref->{debug} = $json_result_ref;
	    }
	    $response_ref->{no_fees} = 1;

	    return $response_ref;
	}
	
	if (defined $json_result_ref->{'fee'}) {

	    my $total_amount = $json_result_ref->{'total_sum'}." ".$json_result_ref->{'currency'};

	    $response_ref->{amount} = $total_amount;

	    foreach my $item_ref (@{$json_result_ref->{'fee'}}){

		my $about = $item_ref->{'title'};

		my $label     = $item_ref->{barcode}{value};
		
		my $this_response_ref = {
		    about   => $about,
		    edition => '', # Keine mms_id
		    item    => $item_ref->{'id'}, # Hier Fee ID
		    reason  => $item_ref->{'type'}{'desc'},
		    label   => $label,
		    amount  => $item_ref->{'original_amount'}." ".$json_result_ref->{'currency'},
		    date    => $item_ref->{'creation_time'},
		};

		if ($logger->is_debug){
		    $this_response_ref->{debug} = $json_result_ref;
		}
		
		if (defined $item_ref->{'owner'}){
		    $this_response_ref->{'department'} = {
			id => $item_ref->{'owner'}{'value'},
			about => $item_ref->{'owner'}{'desc'},
		    };
		}

		push @{$response_ref->{items}}, $this_response_ref;
	    }
	}
    }
    
    if ($logger->is_debug){    
	$logger->debug("Loan: ".YAML::Dump($response_ref));
    }
    
    return $response_ref;
}

sub get_loans {
    my ($self,$username,$page) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');

    my $num         = 10;    
    my $offset      = $page*$num - $num;    
    
    my $response_ref = {};

    $username = $self->get_externalid_of_user($username);
    
    unless ($username){
	$response_ref = {
	    timestamp   => $self->get_timestamp,
	    error => 'error',
	    error_description       => "missing or wrong parameters",
	};
	
	return $response_ref;
    }
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    my $items_ref = [];

    # Ausleihinformationen der Exemplare
    {
	my $json_result_ref = {};
	
	$logger->debug("Getting Circulation info via ALMA API");
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = $config->get('alma')->{'api_baseurl'}."/users/$username/loans?user_id_type=all_unique&expand=renewable&limit=$num&offset=$offset&order_by=due_date&direction=ASC&loan_status=Active&lang=$lang&apikey=$api_key";
	
	my $api_result_ref = $self->send_alma_api_call({ method => 'GET', url => $url });
	
	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){
	    return $api_result_ref->{'response'}
	}
	
	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}

	# Empty response
	$response_ref = {
	    items => $items_ref,
	    num_renewables => 0,
	    num_total => 0,
	};
	
	# Processing data
	if (defined $json_result_ref->{'item_loan'}) {

	    my $num_renewables = 0;
	    
	    if ($logger->is_debug){
		$response_ref->{debug} = $json_result_ref;
	    }

	    foreach my $item_ref (@{$json_result_ref->{'item_loan'}}){
		
		if ($logger->is_debug){    
		    $logger->debug(YAML::Dump($item_ref));
		}
		
		my $about = $item_ref->{'title'} || $item_ref->{'item_barcode'};
		
		my $label     = $item_ref->{item_barcode}; # Signatur wird nicht zurueckgeliefert, muss aus PostgreSQL geholt werden...
		
		my $this_response_ref = {
		    about    => $about,
		    edition  => $item_ref->{'mms_id'},
		    item     => $item_ref->{'holding_id'}."|".$item_ref->{'item_id'},
		    loanid   => $item_ref->{'loan_id'},
		    renewals => '',
		    status   => $item_ref->{'process_type'},
		    label    => $label,
		};
		
		if (defined $item_ref->{'library'}){
		    $this_response_ref->{'department'} = {
			id => $item_ref->{'library'}{'value'},
			about => $item_ref->{'library'}{'desc'},
		    };
		}

		if (defined $item_ref->{'location_code'}){
		    $this_response_ref->{'storage'} = {
			id => $item_ref->{'location_code'}{'value'},
			about => $item_ref->{'location_code'}{'name'},
		    };
		}

		if (defined $item_ref->{'item_policy'}){
		    $this_response_ref->{'policy'} = $item_ref->{'item_policy'}{'description'};
		}

		if (defined $item_ref->{'process_status'} && $item_ref->{'process_status'} eq "RECALL"){
		    $this_response_ref->{'recall'} = 1;
		}
		
		# if (defined $item_ref->{LesesaalNr} && $item_ref->{LesesaalNr} >= 0 && $item_ref->{LesesaalTxt} ){
		#     $this_response_ref->{pickup_location} = {
		# 	about => $item_ref->{LesesaalTxt},
		# 	id => $item_ref->{LesesaalNr}
		#     }
		# }
		    

		$this_response_ref->{starttime} = $item_ref->{'loan_date'};
		$this_response_ref->{endtime}   = $item_ref->{'due_date'};

		# Zurueckgefordert?
		# if ($item_ref->{Rueckgef} eq "J"){
		#     $this_response_ref->{reclaimed} = 1;
		# }
		
		if (defined $item_ref->{renewable} && $item_ref->{renewable}){
		    $this_response_ref->{renewable} = 1;
		    $num_renewables++;
		}
			
		if (defined $item_ref->{last_renew_status} && $item_ref->{last_renew_status}{desc}){
		    $this_response_ref->{renewable_remark} = $item_ref->{last_renew_status}{desc};
		}
		
		if (defined $item_ref->{Star}){
		    $this_response_ref->{emergency_remark} = $item_ref->{Star};
		}
		
		# Infotext?
		if (defined $item_ref->{Text}){
		    $this_response_ref->{info} = $item_ref->{Text};
		}

		push @{$response_ref->{items}}, $this_response_ref;
	    }

	    $response_ref->{num_renewables} = $num_renewables;
	}

	if (defined $json_result_ref->{'total_record_count'}){ 
	    $response_ref->{num_total} = $json_result_ref->{'total_record_count'};
	}
    }
    
    if ($logger->is_debug){    
	$logger->debug("Loan: ".YAML::Dump($response_ref));
    }
    
    return $response_ref;
}

sub make_reservation {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $arg_ref->{alma_request_type} = "reservation";
    
    return $self->make_alma_request($arg_ref);    
}

sub cancel_reservation {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $arg_ref->{alma_request_type} = "reservation";
    
    return $self->cancel_alma_request($arg_ref);    
}

sub make_order {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $arg_ref->{alma_request_type} = "order";
    
    return $self->make_alma_request($arg_ref);
}

sub cancel_order {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->cancel_order_by_mail($arg_ref);        
};

sub cancel_order_by_api {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    $arg_ref->{alma_request_type} = "order";
    
    return $self->cancel_alma_request($arg_ref);    
}

sub cancel_order_by_mail {
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

    $SIG{'DIE'} = 'IGNORE';

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
	    
    if ($logger->is_debug){    
	$logger->debug("Trying connection to uri $uri at ".$config->get('usbwsmail_url'));    
	$logger->debug("Using args ".YAML::Dump(\@args));    
    }
    
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

	if (defined $result_ref->{NotOK}){
	    $response_ref->{error_description} = $result_ref->{NotOK};
	}
	
	if ($logger->is_debug){
	    $response_ref->{debug} = $result_ref;
	}

	return $response_ref	
    }
    
    return $response_ref;
}

sub cancel_alma_request {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $mmsid           = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}        : undef;

    my $requestid       = exists $arg_ref->{requestid} # Alma: requestid
        ? $arg_ref->{requestid}      : undef;

    my $department_id   = exists $arg_ref->{unit}     # Alma: library
        ? $arg_ref->{unit}           : undef;
    
    my $pickup_location = exists $arg_ref->{pickup_location} # Ausgabeort
        ? $arg_ref->{pickup_location}       : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');
    
    my $response_ref = {};

    $logger->debug("requistid: $requestid");

    $username = $self->get_externalid_of_user($username);
    
    unless ($username && $requestid){
	$response_ref =  {
	    timestamp   => $self->get_timestamp,	    
	    error => "missing parameter",
	};

	return $response_ref;
    }

    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $json_result_ref = {};

    {
	$logger->debug("Making order via Alma-API");
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = $config->get('alma')->{'api_baseurl'}."/users/$username/requests/$requestid";
	
	# Default args
	my $args = "reason=CancelledAtPatronRequest&notify_user=false&lang=$lang&apikey=$api_key";
	
	$url.="?$args";

	my $api_result_ref = $self->send_alma_api_call({ method => 'DELETE', url => $url });

	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){
	    return $api_result_ref->{'response'}
	}

	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}

	# Processing data
	if (defined $api_result_ref->{'http_status_code'} && $api_result_ref->{'http_status_code'} == 204) {
	    $response_ref = {
		"successful" => 1,
		    "message" => "Die Bestellung wurde storniert",
		    "title"   => $json_result_ref->{title},
		    "author"  => $json_result_ref->{author},
	    };
	    
	    if ($logger->is_debug){
		$response_ref->{debug} = $json_result_ref;
	    }
	    
	    return $response_ref	
	}
    }
    
    $response_ref = {
	"code" => 405,
	    "error" => "unknown error",
	    "error_description" => "Unbekannter Fehler",
    };
    
    if ($logger->is_debug){
	$response_ref->{debug} = $json_result_ref;
    }
    
    return $response_ref;    
}
    
sub renew_loans {
    my ($self,$username) = @_;

    my $msg         = $self->get_msg;
    
    my $response_ref = {
		"code" => 400,
		    "error" => "error",
		    "error_description" => "Das Bibliothekssystem Alma bietet keine Gesamtkontoverlängerung an",
    };

    return $response_ref;
}

sub renew_single_loan {
    my ($self,$username,$holdingid,$unit,$loanid) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');
    
    my $response_ref = {};

    $logger->debug("username: $username - holdingid: $holdingid - unit: $unit - loanid: $loanid");
    
    $username = $self->get_externalid_of_user($username);
    
    unless ($username && $loanid){
	$response_ref =  {
	    timestamp   => $self->get_timestamp,	    
	    error => "missing parameter",
	};

	return $response_ref;
    }

    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $json_result_ref = {};
    
    {
	$logger->debug("Making order via Alma-API");
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = $config->get('alma')->{'api_baseurl'}."/users/$username/loans/$loanid";
	
	# Default args
	my $args = "op=renew&user_id_type=all_unique&lang=$lang&apikey=$api_key";
	
	$url.="?$args";
	
	my $api_result_ref = $self->send_alma_api_call({ method => 'POST', url => $url });

	if ($logger->is_debug){
	    $logger->debug("Renew API Result: ".YAML::Dump($api_result_ref));
	}
	   	
	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){
	    return $api_result_ref->{'response'}
	}
	
	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}

	# Processing data	    
	if (defined $json_result_ref->{'loan_id'}) {
	    
	    my @titleinfo = ();
	    push @titleinfo, $json_result_ref->{author} if ($json_result_ref->{author});
	    if ($json_result_ref->{title}){
		push @titleinfo, $json_result_ref->{title} 
	    }
	    elsif ($json_result_ref->{item_barcode}){
		push @titleinfo, $json_result_ref->{item_barcode}; 
	    }
	    
	    my $about = join(': ',@titleinfo);
	    
	    my $label     = $json_result_ref->{item_barcode}; # Keine Signatur, muss ggf. aus PostgreSQL geholt werden	    
	    $response_ref->{about}           = $about;
	    $response_ref->{edition}         = $json_result_ref->{mms_id};
	    $response_ref->{item}            = $json_result_ref->{holding_id}."|".$json_result_ref->{item_id};
	    $response_ref->{label}           = $label;
#	    $response_ref->{info}            = $json_result_ref->{OK};	
#	    $response_ref->{num_renewals}    = $json_result_ref->{AnzVl};	
#	    $response_ref->{renewal_message} = $json_result_ref->{Ergebnismeldung};
#	    $response_ref->{reminder_level}  = $json_result_ref->{MahnStufe};
	

	    if (defined $json_result_ref->{library}){
		$response_ref->{department} = {
		    id => $json_result_ref->{library}{value},
		    about => $json_result_ref->{library}{desc},
		};
	    }
	    
	    
	    $response_ref->{"endtime"}  = $json_result_ref->{due_date};
	    
	    if ($logger->is_debug){
		$response_ref->{debug} = $json_result_ref;
	    }

	    $response_ref->{"successful"} = 1;
	    
	    return $response_ref;
	}
    }
    
    $response_ref = {
	"code" => 405,
	    "error" => "unknown error",
	    "error_description" => "Unbekannter Fehler",
    };
    
    if ($logger->is_debug){
	$response_ref->{debug} = $json_result_ref;
    }
    
    return $response_ref;    
}

sub get_mediastatus {
    my ($self,$titleid) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');
    
    my $response_ref = {};
    
    unless ($database && $titleid){
	$response_ref = {
	    timestamp   => $self->get_timestamp,
	    circulation => [],
	    error       => "missing parameters",	    
	};
	
	return $response_ref;
    }
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    my $items_ref = [];

    # Ausleihinformationen der Exemplare
    {
	my $json_result_ref = {};

	$logger->debug("Getting Circulation info via ALMA API");
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = $config->get('alma')->{'api_baseurl'}."/bibs/$titleid/holdings/ALL/items?limit=100&offset=0&expand=due_date,due_date_policy,requests&view=brief&lang=$lang&apikey=$api_key&order_by=library,location,enum_a,enum_b&direction=asc";
	
	my $api_result_ref = $self->send_alma_api_call({ method => 'GET', url => $url });

	if ($logger->is_debug){
	    $logger->debug("api_result_ref: ".YAML::Dump($api_result_ref));
	}
	
	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){

	    $logger->debug("XXX".$api_result_ref->{'data'}{'errorList'}{'error'}[0]{'errorCode'});

	    # MMSID not valid = NZ MSSID, then ignore and return no items
	    if ($api_result_ref->{'response'}{'error_code'} == 402203){
		return {
		    id          => $titleid,
		    database    => $database,
		    items       => [],
		    timestamp   => $self->get_timestamp,
		    };
	    }
	    
	    return $api_result_ref->{'response'}
	}
	
	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}	    
	
	# Processing data	    
	if (defined $json_result_ref->{'item'}) {
	    
	    foreach my $circ_ref (@{$json_result_ref->{'item'}}){
		
		if ($logger->is_debug){    
		    $logger->debug(YAML::Dump($circ_ref));
		}
		
		# Umwandeln
		my $item_ref = {};
		
		if ($config->get('debug_ils')){
		    $item_ref->{debug} = $json_result_ref
		}

		# Spezialanpassungen USB Koeln

		# Ende Spezialanpassungen
		
		$item_ref->{'label'}           = $circ_ref->{'holding_data'}{'call_number'} || $circ_ref->{'item_data'}{'alternative_call_number'} || $circ_ref->{'item_data'}{'barcode'}; # Signatur
		$item_ref->{'barcode'}         = $circ_ref->{'item_data'}{'barcode'}; # Mediennummer Neu fuer Alma
		$item_ref->{'id'}              = $circ_ref->{'holding_data'}{'holding_id'}."|".$circ_ref->{'item_data'}{'pid'}; # holdingid|itemid

		my @remarks = ();

		if ($circ_ref->{'item_data'}{'description'}){
		    push @remarks, $circ_ref->{'item_data'}{'description'};
		}

		if($circ_ref->{'item_data'}{'public_note'}){
		    push @remarks, $circ_ref->{'item_data'}{'public_note'};
		}

		$item_ref->{'remark'} = '';
		
		if (@remarks){
		    $item_ref->{'remark'}      = join(' ; ',@remarks);
		}
		
		$item_ref->{'boundcollection'} = ""; # In Alma gibt es keine Bindeeinheiten

		my $process_type  = $circ_ref->{'item_data'}{'process_type'}{'value'};
		
		my $department    = $circ_ref->{'item_data'}{'library'}{'desc'};
		my $department_id = $circ_ref->{'item_data'}{'library'}{'value'};
		$item_ref->{'department'} = {
		    content => $department,
		    id      => $department_id,
		};

		my $storage    = $circ_ref->{'item_data'}{'location'}{'desc'};
		my $storage_id = $circ_ref->{'item_data'}{'location'}{'value'};
		
		$item_ref->{'storage'} = {
		    content => $storage,
		    id      => $storage_id,
		};

		$item_ref->{'full_location'} = "$department / $storage";

		my $available_ref   = [];
		my $unavailable_ref = [];


		# Temporary locations => nicht entleihbar weil Schimmel, Ausstellung etc.

		my $in_temporary_location = (defined $circ_ref->{'holding_data'}{'in_temp_location'} && $circ_ref->{'holding_data'}{'in_temp_location'})?1:0;

		my $temporary_location_desc = "";
		
		if ($in_temporary_location){
		    if (defined $circ_ref->{'holding_data'}{'temp_policy'}{'desc'}){
			$temporary_location_desc .= $circ_ref->{'holding_data'}{'temp_policy'}{'desc'};
		    }

		    if (defined $circ_ref->{'holding_data'}{'temp_location'}{'desc'}){
			$temporary_location_desc .= " (".$circ_ref->{'holding_data'}{'temp_location'}{'desc'}.")";
		    }
		}

		if ($logger->is_debug){
		    $logger->debug("in_temporary_location: $in_temporary_location / desc: $temporary_location_desc");
		}
		
		# See Configuration->Fulfillment->Physical Fulfillment->Item Policy (here: from sandbox for testing)
		my $policy      = $circ_ref->{'item_data'}{'policy'}{'value'}; # Ausleihkonditionen fuer dieses Item
		my $policy_desc = $circ_ref->{'item_data'}{'policy'}{'desc'}; # Ausleihkonditionen fuer dieses Item

		# Moeglich Werte fuer Policy:
		#
		# A: ausleihbar oder bestellbar
		# T: Testothek ausleihbar mit verkuerzter Leihfrist
		# X: nicht ausleihbar
		# L: nur ausleihbar oder bestellbar in den Lesesaal
		# LBS: Lehrbuchsammlug ausleihbar

		my $base_status = $circ_ref->{'item_data'}{'base_status'}{'value'}; # 1: Am Ort / 0: Nicht am Ort
		
		my $this_circ_conf = {};

		if (defined $circ_config->{$department_id} && defined $circ_config->{$department_id}{$storage_id}){
		    $this_circ_conf = $circ_config->{$department_id}{$storage_id};
		}
		else {
		    $logger->error("Unknown status for department $department_id and storage $storage_id");
		}

		my $circulation_desk = 0; # Lesesaalausleihe

		if (defined $this_circ_conf->{pickup_locations}){
		    my ($ref) = grep { $_->{'desc'} =~m/Lesesaal/i } @{$this_circ_conf->{pickup_locations}};
		    $circulation_desk = 1 if ($ref);
		}

		# Temporaere Location
		if ($in_temporary_location){
		    my $this_unavailable_ref = {
			service => 'loan',
			content => $temporary_location_desc,
			expected => "temporarily unavailable",
		    };

		    push @$unavailable_ref, $this_unavailable_ref;
		}
		# Bestell-/ausleihbar in den Lesesaal
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 1 && $policy eq "L" ){ # ggf. auch $policy = L = Lesesaalausleihe
		    push @$available_ref, {
			service => 'order',
			content => "bestellbar in Lesesaal",
			limitation => "bestellbar (Nutzung nur im Lesesaal)",
			type => 'Stationary',
		    };
		}
		# Bestellbar
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 1 && ($policy eq "A"  || $policy eq "LBS" || $policy eq "T") && $this_circ_conf->{'order'} && ( !defined $circ_ref->{'item_data'}{'requested'} || !$circ_ref->{'item_data'}{'requested'}) ){ 
		    push @$available_ref, {
			service => 'order',
			content => "bestellbar",
		    };
		}
		# Ausleihbar vor Ort
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 1 && ($policy eq "A" || $policy eq "LBS" || $policy eq "T") && $this_circ_conf->{'loan'}){ 
		    push @$available_ref, {
			service => 'loan',
			content => "ausleihbar",
		    };
		}
		# Praesenzbestand
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 1 && $policy eq "X"){
		    push @$available_ref, {
			service => 'presence',
			content => "Präsenzbestand",
		    };
		}
		# Bereits bestellt mit Vormerkmoeglichkeit
#		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 1 && defined $circ_ref->{'item_data'}{'requested'} && $this_circ_conf->{'reservation'}){ 
		# im Transfer?
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 0 && $process_type eq "TRANSIT"){
		    my $this_unavailable_ref = {
			service => 'loan',
			content => "noch nicht verfügbar (im Transfer)",
			expected => 'transfer',
		    };
		    
		    push @$unavailable_ref, $this_unavailable_ref;
		    
		}
		elsif (defined $circ_ref->{'item_data'}{'requested'} && $circ_ref->{'item_data'}{'requested'} ){ 
		    my $this_unavailable_ref = {
			service => 'order',
			content => "bestellt",
			queue   => ($circ_ref->{'item_data'}{'requested'})?1:0,
#			expected => $circ_ref->{'item_data'}{'expected_arrival_date'},
#			expected => $circ_ref->{'item_data'}{'due_date'},
		    };
		    
		    push @$unavailable_ref, $this_unavailable_ref;
		    
		}
		# Sonst, wenn am Ort: Praesenzbestand
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 1){
		    push @$available_ref, {
			service => 'presence',
			content => "Präsenzbestand",
		    };
		}
		# Entliehen mit Vormerkmoeglichkeit
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 0 && $process_type eq "LOAN" && $this_circ_conf->{'reservation'}){

		    my $this_unavailable_ref = {
			service => 'loan',
			content => "entliehen",
#			expected => $circ_ref->{'item_data'}{'expected_arrival_date'},
			expected => $circ_ref->{'item_data'}{'due_date'},
		    };

		    if ($policy eq "L" ){ # $policy = L = Lesesaalausleihe
			$this_unavailable_ref->{limitation} = "vormerkbar (Nutzung nur im Lesesaal)";
			$this_unavailable_ref->{type}       = 'Stationary';

		    }

		    # Vormerk-Rang wird von Alma nicht geliefert
		    if ($circ_ref->{VormerkAnzahl} >= 0){
			$this_unavailable_ref->{queue} = $circ_ref->{VormerkAnzahl} ;
		    }

		    $this_unavailable_ref->{queue} = "Unbekannt";
		    
		    push @$unavailable_ref, $this_unavailable_ref;
		    
		}
		# Entliehen ohne Vormerkmoeglichkeit
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 0 && $process_type eq "LOAN" && !$this_circ_conf->{'reservation'}){
		    my $this_unavailable_ref = {
			service => 'loan',
			content => "entliehen",
#			expected => $circ_ref->{'item_data'}{'expected_arrival_date'},
			expected => $circ_ref->{'item_data'}{'due_date'},
		    };

		    # no queue = no reservation!
		    push @$unavailable_ref, $this_unavailable_ref;
		    
		}
		# vermisst?
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 0 && $process_type eq "MISSING"){
		    my $this_unavailable_ref = {
			service => 'loan',
			content => "vermisst",
			expected => 'missing',
		    };
		    
		    push @$unavailable_ref, $this_unavailable_ref;
		    
		}
		# im Erwerbungsvorgang?
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 0 && $process_type eq "ACQ"){
		    my $this_unavailable_ref = {
			service => 'loan',
			content => "noch nicht verfügbar (im Erwerbungsvorgang)",
			expected => 'acquisition',
		    };
		    
		    push @$unavailable_ref, $this_unavailable_ref;
		    
		}
		# Sonst, wenn nicht am Ort: entliehen
		elsif ($circ_ref->{'item_data'}{'base_status'}{'value'} == 0 ){
		    my $this_unavailable_ref = {
			service => 'loan',
			content => "entliehen",
			#			    expected => 'lost',
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
    
    $response_ref = {
	id          => $titleid,
	database    => $database,
	items       => $items_ref,
	timestamp   => $self->get_timestamp,
    };
    
    if ($logger->is_debug){    
	$logger->debug("Circ: ".YAML::Dump($response_ref));
    }
            
    return $response_ref;
}

sub check_order {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $arg_ref->{alma_request_type} = "order";
    
    return $self->check_alma_request($arg_ref);
}

sub check_reservation {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $arg_ref->{alma_request_type} = "reservation";
    
    return $self->check_alma_request($arg_ref);
}

sub check_alma_request {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username        = exists $arg_ref->{username}  # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $combinedid      = exists $arg_ref->{holdingid} # Alma: holdingid|item_id
        ? $arg_ref->{holdingid}      : undef;

    my $department_id   = exists $arg_ref->{unit}     # Alma: library
        ? $arg_ref->{unit}           : undef;

    my $storage_id      = exists $arg_ref->{storage}  # Alma: location
        ? $arg_ref->{storage}        : undef;
    
    my $mmsid           = exists $arg_ref->{titleid}  # Katkey fuer teilqualifizierte Vormerkung
        ? $arg_ref->{titleid}        : undef;

    my $type            = exists $arg_ref->{type}     # Typ (voll/teilqualifizierte Vormerkung) by_title/by_holding
        ? $arg_ref->{type}           : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database    = $self->get_database;
    my $config      = $self->get_config;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');

    my $pickup_locations_ref = [];
    
    if (defined $circ_config->{$department_id} && defined $circ_config->{$department_id}{$storage_id} && defined $circ_config->{$department_id}{$storage_id}{'pickup_locations'}){
	$pickup_locations_ref = $circ_config->{$department_id}{$storage_id}{'pickup_locations'};
    }

    if ($logger->is_debug){
	$logger->debug("Pickup locations: ".YAML::Dump($pickup_locations_ref));
    }
    
    my $response_ref = {};

    $logger->debug("Combinedid: $combinedid");
    my ($holdingid,$itempid) = split('\|',$combinedid);

    $logger->debug("holdingid: $holdingid - itempid: $itempid");
    
    unless ($username && $department_id && ( $combinedid || $mmsid) ){
	$response_ref =  {
	    error => "missing parameter (username: $username - department_id: $department_id - mmsid: $mmsid / holdingid: $combinedid)",
	};

	return $response_ref;
    }

    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $http_status_code;

    {
	my $json_result_ref = {};
	
	$logger->debug("Making reservation via ALMA API");
		
	my $alma_userid = $self->get_externalid_of_user($username);
	
	unless ($alma_userid){
	    $response_ref =  {
		error => "No ALMA userid found",
	    };
	    
	    return $response_ref;
	}
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = "";
	
	if ($type eq "by_title"){ # Teilqualifizierte Vormerkung
	    $url = $config->get('alma')->{'api_baseurl'}."/bibs/$mmsid/request-options?lang=$lang&apikey=$api_key&user_id=$alma_userid";
	}
	else {
	    unless ($holdingid && $itempid){
		$response_ref =  {
		    error => "missing parameter (username: $username - department_id: $department_id - mmsid: $mmsid)",
		};
		
		return $response_ref;
	    }
	    
	    $url = $config->get('alma')->{'api_baseurl'}."/bibs/$mmsid/holdings/$holdingid/items/$itempid/request-options?lang=$lang&apikey=$api_key&user_id=$alma_userid";
	}

	my $api_result_ref = $self->send_alma_api_call({ method => 'GET', url => $url });
	
	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){
	    return $api_result_ref->{'response'}
	}
	
	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}

	# Empty response, eg blocked user
	if (! %{$json_result_ref}){
	    $logger->fatal("Empty response (Status code: ".$api_result_ref->{'http_status_code'}." - Method: GET - URL: $url)");

	    $response_ref = {
		"code" => 403,
		    "error" => "user blocked",
		    "error_description" => $msg->maketext("Eine Bestellung bzw. Vormerkung dieses Mediums wurde vom Cloud-Bibliothekssystem Alma ohne Nennung von Gründen abgelehnt. Ursache könnte erfahrungsgemäß u.a. eine Sperrung Ihres Benutzerausweises sein."),
	    };
	    
	    return $response_ref;
	}
	
	# Processing data	    
	if (defined $json_result_ref->{'request_option'}){
	    my $hold_available = 0;
	    
	    foreach my $item_ref (@{$json_result_ref->{'request_option'}}){
		if ($item_ref->{'type'}{'value'} eq "HOLD"){
		    $hold_available = 1;
		}
	    }
	    
	    # Auswertung: Bestellung nicht moeglich
	    unless ($hold_available){
		$response_ref = {
		    "code" => 403,
			"error" => "order option not available",
			"error_description" => "Eine Bestellung ist nicht möglich",
		};
		
		if ($logger->is_debug){
		    $response_ref->{debug} = $json_result_ref;
		    $logger->debug("Response failed: ".YAML::Dump($response_ref));		}
		
		return $response_ref	
	    }
	    
	    # oder: Bestellung moeglich

	    $response_ref->{"successful"} = 1;
	    foreach my $pickup_ref (@$pickup_locations_ref){
		push @{$response_ref->{"pickup_locations"}}, {
		    name        => $pickup_ref->{id},
		    about       => $pickup_ref->{desc},
		};
	    }
	    
	    if ($logger->is_debug){
		$response_ref->{debug} = $json_result_ref;
		$logger->debug("Response: ".YAML::Dump($response_ref));
	    }
	    
	    return $response_ref;	
	}
    }
    
    $response_ref = {
	"code" => 400,
	    "error" => "error",
	    "error_description" => "General error",
    };

    if ($logger->is_debug){
	$logger->debug("Response failed: ".YAML::Dump($response_ref));
    }
    
    return $response_ref;
}

sub get_client {
    my ($self) = @_;

    return $self->{client};
}

sub get_circulation_config {
    my ($self) = @_;

    return $self->{_circ_config};
}

# Alma-ID fuer den Nuter username bestimmen (Bei Anmeldung am SIS in Feld external_id abgespeichert
sub get_externalid_of_user {
    my ($self,$username) = @_;

    my $user = OpenBib::User->new;

    my $externalid = $user->get_info($user->get_userid_for_username($username))->{external_id};
    
    return ($externalid)?$externalid:undef;
}

sub make_alma_request {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username          = exists $arg_ref->{username} # Nutzername im Bibliothekssystem
        ? $arg_ref->{username}       : undef;
    
    my $mmsid             = exists $arg_ref->{titleid}  # Katkey
        ? $arg_ref->{titleid}        : undef;

    my $combinedid        = exists $arg_ref->{holdingid} # Alma: holdingid|item_id
        ? $arg_ref->{holdingid}      : undef;

    my $department_id     = exists $arg_ref->{unit}     # Alma: library
        ? $arg_ref->{unit}           : undef;
    
    my $storage_id        = exists $arg_ref->{storage}  # Alma: location
        ? $arg_ref->{storage}        : undef;

    my $pickup_location   = exists $arg_ref->{pickup_location} # Ausgabeort
        ? $arg_ref->{pickup_location}       : undef;

    my $alma_request_type = exists $arg_ref->{alma_request_type} # Request Type: order | reservation
        ? $arg_ref->{alma_request_type}     : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');
    
    my $response_ref = {};

    $logger->debug("Combinedid: $combinedid");
    my ($holdingid,$itempid) = split('\|',$combinedid);

    $logger->debug("holdingid: $holdingid - itempid: $itempid");
    
    $username = $self->get_externalid_of_user($username);
    
    unless ($username && ( $combinedid || $mmsid) && $department_id && $storage_id && $pickup_location){
	$response_ref =  {
	    timestamp   => $self->get_timestamp,	    
	    error => "missing parameter",
	};

	return $response_ref;
    }


    my $json_result_ref = {};

    {
	$logger->debug("Making order via Alma-API");
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = $config->get('alma')->{'api_baseurl'}."/users/$username/requests";
	
	# Default args
	my $args = "user_id_type=all_unique&lang=$lang&apikey=$api_key";
	
	# Vollqualifizierte Bestellung	    
	if ($itempid){
	    $args.="&item_pid=$itempid";		
	}
	# Teilqualifizierte Bestellung
	elsif ($mmsid){
	    $args.="'mms_id=$mmsid";
	}
	
	$url.="?$args";
	
	my $data_ref = {};
	
	$data_ref->{request_type} = "HOLD";
	
	my $pickup_data_ref = {};
	
	my $valid_pickup_location = 0;
	
	if (defined $circ_config->{$department_id}{$storage_id}{pickup_locations}){
	    foreach my $pickup_ref (@{$circ_config->{$department_id}{$storage_id}{pickup_locations}}){
		if ($pickup_ref->{id} eq $pickup_location){
		    $pickup_data_ref       = $pickup_ref;
		    $valid_pickup_location = 1;
		    last;
		}
	    }
	}
	
	if (!$valid_pickup_location || ($pickup_data_ref->{type} ne "CIRCULATION_DESK" && $pickup_data_ref->{type} ne "LIBRARY")){
	    $response_ref =  {
		timestamp => $self->get_timestamp,	    
		error     => "invalid pickup location",
	    };
	    
	    return $response_ref;
	}
	
	$data_ref->{pickup_location_type}             = $pickup_data_ref->{type}; # LIBRARY or CIRCULATION_DESK
	$data_ref->{pickup_location_library}          = $department_id;
	
	if ($pickup_data_ref->{type} eq "CIRCULATION_DESK"){
	    $data_ref->{pickup_location_circulation_desk} = $pickup_location;
	    #		$data_ref->{pickup_location_institution}      = $storage_id;
	}

	my $api_result_ref = $self->send_alma_api_call({ method => 'POST', url => $url, post_data => $data_ref });
	
	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){
	    return $api_result_ref->{'response'}
	}
	
	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}
	
	# Processing data	    
	if (defined $json_result_ref->{'request_id'}) {
	    my $success_message = $msg->maketext("Das Exemplar wurde bestellt.");
	    if ($alma_request_type eq "reservation"){
		$success_message = $msg->maketext("Das Exemplar wurde vorgemerkt.");
	    }
	    
	    $response_ref = {
		"successful" => 1,
		    "message" => $success_message,
		    "title"   => $json_result_ref->{title},
		    "author"  => $json_result_ref->{author},
	    };

	    if ($logger->is_debug){
		$response_ref->{debug} = $json_result_ref;
	    }
	    
	    return $response_ref	
	}
    }

    $response_ref = {
	"code" => 405,
	    "error" => "unknown error",
	    "error_description" => "Unbekannter Fehler",
    };
    
    if ($logger->is_debug){
	$response_ref->{debug} = $json_result_ref;
    }
    
    return $response_ref;    
}

sub get_alma_request {
    my ($self,$username,$request_type) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');
    
    my $response_ref = {};

    $username = $self->get_externalid_of_user($username);
    
    unless ($username){
	$response_ref = {
	    timestamp   => $self->get_timestamp,
	    error => 'error',
	    error_description       => "missing or wrong parameters",
	};
	
	return $response_ref;
    }

    $logger->debug("Processing request type $request_type");
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    my $items_ref = [];

    # Ausleihinformationen der Exemplare
    {
	my $json_result_ref = {};

	$logger->debug("Getting Circulation info via ALMA API");
	
	my $api_key = $config->get('alma')->{'api_key'};
	
	my $url     = $config->get('alma')->{'api_baseurl'}."/users/$username/requests?user_id_type=all_unique&limit=100&request_type=HOLD&offset=0&status=active&lang=$lang&apikey=$api_key";
	
	my $api_result_ref = $self->send_alma_api_call({ method => 'GET', url => $url });
	
	# Preprocessed response? Return it
	if (defined $api_result_ref->{'response'}){
	    return $api_result_ref->{'response'}
	}
	
	# Result data? Use it for further processing
	if (defined $api_result_ref->{'data'}){
	    $json_result_ref = $api_result_ref->{'data'};
	}
	
	# Processing data	    
	if (defined $json_result_ref->{'user_request'} && $json_result_ref->{'total_record_count'}) {
	    
	    foreach my $item_ref (@{$json_result_ref->{'user_request'}}){

		if ($logger->is_debug){    
		    $logger->debug(YAML::Dump($item_ref));		
		}
		
		my @titleinfo = ();
		
		push @titleinfo, $item_ref->{'author'} if ($item_ref->{'author'});
		push @titleinfo, $item_ref->{'title'} if ($item_ref->{'title'});
		
		my $about = join(': ',@titleinfo);

		$about.=" Band: ".$item_ref->{'volume'}.")" if ($item_ref->{'volume'});
		$about.=" Teil: ".$item_ref->{'part'}.")" if ($item_ref->{'part'});
		
		my $label     = $item_ref->{'barcode'}; # Signatur wird nicht zurueckgeliefert, muss aus PostgreSQL geholt werden...
		
		my $this_response_ref = {
		    about     => $about,
		    edition   => $item_ref->{'mms_id'},
		    item      => $item_ref->{'item_id'},
		    requestid => $item_ref->{'request_id'},
		    renewals  => '',
		    status    => $item_ref->{'request_status'},
		    label     => $label,
		};

		if ($logger->is_debug){
		    $this_response_ref->{debug} = $item_ref;
		}
		
		if (defined $item_ref->{'managed_by_library'} && defined $item_ref->{'managed_by_library_code'}){
		    $this_response_ref->{'department'} = {
			id => $item_ref->{'managed_by_library_code'},
			about => $item_ref->{'managed_by_library'},
		    };
		}

		# if (defined $item_ref->{'location_code'}){
		#     $this_response_ref->{'storage'} = {
		# 	id => $item_ref->{'location_code'}{'value'},
		# 	about => $item_ref->{'location_code'}{'name'},
		#     };
		# }
		
		if (defined $item_ref->{'pickup_location'} && $item_ref->{'pickup_location'} && $item_ref->{'pickup_location_library'} ){
		    my $pickup_location = $item_ref->{'pickup_location'};
		    
		    # Circulation Desk?
		    if (defined $item_ref->{'managed_by_circulation_desk_code'} && $item_ref->{'managed_by_circulation_desk_code'} && $item_ref->{'managed_by_circulation_desk_code'} ne "DEFAULT_CIRC_DESK"){

			$pickup_location.= " / ".$item_ref->{'managed_by_circulation_desk_code'};
		    }
		    
		    $this_response_ref->{'pickup_location'} = {
			about => $pickup_location,
			id    => $item_ref->{'pickup_location_library'}
		    }
		}

		if (defined $item_ref->{'booking_start_date'} && defined $item_ref->{'due_back_date'}){
		    $this_response_ref->{starttime} = $item_ref->{'booking_start_date'};
		    $this_response_ref->{endtime}   = $item_ref->{'due_back_date'};
		}
		else {
		    $this_response_ref->{starttime} = $item_ref->{'request_date'};
		    $this_response_ref->{endtime}   = $item_ref->{'expiry_date'};
		}

		# Nur Datum des Zeitstempels
		$this_response_ref->{starttime} =~s/(\d\d\d\d-\d\d-\d\d).*/$1/;
		$this_response_ref->{endtime}   =~s/(\d\d\d\d-\d\d-\d\d).*/$1/;

		# Zurueckgefordert?
		# if ($item_ref->{Rueckgef} eq "J"){
		#     $this_response_ref->{reclaimed} = 1;
		# }
		
		# # Verlaengerbar?
		# if ($item_ref->{VlBar} eq "1"){
		#     $this_response_ref->{renewable} = 1;
		# }
			
		# if (defined $item_ref->{VlText}){
		#     $this_response_ref->{renewable_remark} = $item_ref->{VlText};
		# }
		
		# if (defined $item_ref->{Star}){
		#     $this_response_ref->{emergency_remark} = $item_ref->{Star};
		# }
		
		# Infotext?
		if (defined $item_ref->{'description'}){
		    $this_response_ref->{info} = $item_ref->{'description'};
		}

		# Fernleihbestellung?

		if (defined $item_ref->{'resource_sharing'}){
		    if (defined $item_ref->{'resource_sharing'}{'status'}){
			$this_response_ref->{ill_status} = $item_ref->{'resource_sharing'}{'status'};
		    }
		    if (defined $item_ref->{'resource_sharing'}{'status'}){
			$this_response_ref->{ill_status} = {
			    id    => $item_ref->{'resource_sharing'}{'status'}{'value'},
			    about => $item_ref->{'resource_sharing'}{'status'}{'desc'},
			};
		    }
		}
		
		my $is_reservation = 0;
		
		# Platz in der Queue
		if (defined $item_ref->{'place_in_queue'} && $item_ref->{'place_in_queue'} > 0){
		    $this_response_ref->{queue} = $item_ref->{'place_in_queue'};
		}

		if (defined $this_response_ref->{queue} && $this_response_ref->{queue} && !defined $this_response_ref->{'ill_status'}){
		    $is_reservation = 1 
		}
		
		if ($request_type eq "reservation" && $is_reservation){
		    push @{$response_ref->{items}}, $this_response_ref;
		}
		elsif ($request_type eq "order" && !$is_reservation) {
		    push @{$response_ref->{items}}, $this_response_ref;		    
		}
	    }
	}
    }
    
    if ($logger->is_debug){    
	$logger->debug("Loan: ".YAML::Dump($response_ref));
    }
            
    return $response_ref;
}

sub update_sis {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $type        = exists $arg_ref->{type}
        ? $arg_ref->{type}         : undef;

    my $username    = exists $arg_ref->{username}
        ? $arg_ref->{username}     : undef;

    my $new_data        = exists $arg_ref->{new_data}
        ? $arg_ref->{new_data}     : undef;

    my $old_data        = exists $arg_ref->{old_data}
        ? $arg_ref->{old_data}     : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $msg         = $self->get_msg;

    my $response_ref = {};

    my $uid = $self->get_externalid_of_user($username);
    
    unless ($uid || $new_data){
	my $error_message = $msg->maketext("Fehlende oder falsche Parameter.");
	
	$response_ref = {
	    timestamp   => $self->get_timestamp,
	    error => 'error',
	    error_description       => $error_message,
	};
	
	return $response_ref;
    }
    
    if ($type eq "password"){	
	if (!$old_data){
	    my $error_message = $msg->maketext("Fehlende oder falsche Parameter.");
	    
	    $response_ref = {
		timestamp   => $self->get_timestamp,
		error => 'error',
		error_description       => $error_message,
	    };
	    
	    return $response_ref;
	}

	my $authresult_ref = $self->authenticate({ username => $username, password => $old_data });

	if (!defined $authresult_ref->{successful} || !$authresult_ref->{successful}){
	    my $error_message = $msg->maketext("Falsche Eingabe des aktuellen Passworts.");
	    
	    $response_ref = {
		timestamp   => $self->get_timestamp,
		error => 'error',
		error_description       => $error_message,
	    };

	    return $response_ref;
	}
    }

    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    {
	my $json_result_ref = {};

	if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {
	    
	    $logger->debug("Updating $type via SIS API for Alma");

	    my $authcookies = HTTP::Cookies->new();
	    
	    $ua->cookie_jar($authcookies);   
	    
	    my $authdata_ref = {
		username => $config->get('sis')->{'api_user'},
		password => $config->get('sis')->{'api_password'},
	    };
	    
	    my $auth_url = $config->get('sis')->{'api_authurl'};

	    if ($logger->is_debug()){
		$logger->debug("Request URL: $auth_url");
	    }
	    
	    my $authrequest = HTTP::Request->new('POST', $auth_url, [ 'Accept' => 'application/json', 'Content-Type' => 'application/json' ]);
	    my $authinfo = encode_json($authdata_ref);

	    if ($logger->is_debug){
		$logger->debug("Auth Info: ".$authinfo);
	    }
	    
	    $authrequest->content($authinfo);

	    my $authresponse = $ua->request($authrequest);
	    
	    if ($logger->is_debug){
		$logger->debug("Auth Response Headers: ".$authresponse->headers_as_string);
		$logger->debug("Auth Response: ".$authresponse->content);
		$logger->debug("Auth Response Code: ".$authresponse->code);
	    }
	    
	    if (!$authresponse->is_success) {
		$logger->info($authresponse->code . ' - ' . $authresponse->message);
		$response_ref = {
		    "code" => 405,
			"error" => "authentication error",
			"error_description" => "Interner SIS-API Authentifizierungsfehler",
		};
		
		return $response_ref;
	    }
	    
	    my $api_call_ref = {
		'email'    => "/setEmail/",
		'pin'      => "/setPin/",
		'password' => "/setPassword/",
	    };

	    my $url     = $config->get('sis')->{'api_baseurl'}.$api_call_ref->{$type};
	    
	    if ($logger->is_debug()){
		$logger->debug("Request URL: $url");
	    }

	    my $data_ref = {
		uid => $uid,
		$type => $new_data,
	    };
	    
	    my $request = HTTP::Request->new('PUT', $url, [ 'Accept' => 'application/json', 'Content-Type' => 'application/json' ]);
	    my $datainfo = encode_json($data_ref);
	    $request->content($datainfo);
	    
	    my $response = $ua->request($request);
	    
	    if ($logger->is_debug){
		$logger->debug("Response Code: ".$response->code);				
		$logger->debug("Response Headers: ".$response->headers_as_string);
		$logger->debug("Response: ".$response->content);
	    }
	    
	    if (!$response->is_success) {
		$logger->info($response->code . ' - ' . $response->message);
		
		$response_ref = {
		    "code" => 400,
		    "error" => "error",
		    "error_description" => "Fehler bei Aktualisierung der Kontoinformationen",
		};
		
		return $response_ref;
	    }
	    
	    if ($response->code == 200){
		eval {
		    $json_result_ref = decode_json $response->content;
		};
		
		if ($@){
		    $logger->error('Decoding error: '.$@);
		}
		
		if ($logger->is_debug){
		    $response_ref->{debug} = $json_result_ref;
		}

		my $success_message = $msg->maketext("Kontoinformationen erfolgreich aktualisiert.");

		$response_ref = {
		    "successful" => 1,
			"message" => $success_message,
		};
		
		return $response_ref;
	    }
	}
    }

    $response_ref = {
	"code" => 405,
	    "error" => "unknown error",
	    "error_description" => "Unbekannter Fehler",
    };
    
    return $response_ref;
}

sub send_alma_api_call {
    my ($self,$arg_ref) = @_;

    # Returns either 'response' for immediate response or 'data' for further processing
    
    # Set defaults
    my $url        = exists $arg_ref->{url}
        ? $arg_ref->{url}                     : undef;

    my $method     = exists $arg_ref->{method}
        ? $arg_ref->{method}                  : undef;
    
    my $post_data_ref  = exists $arg_ref->{post_data}
        ? $arg_ref->{post_data}               : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->get_config;
    my $database    = $self->get_database;
    my $ua          = $self->get_client;
    my $circ_config = $self->get_circulation_config;
    my $msg         = $self->get_msg;
    my $lang        = $self->get('lang');

    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $api_result_ref = {};

    my $http_status_code;
    
    if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {
	
	if ($logger->is_debug()){
	    $logger->debug("Request URL: $url");
	    $logger->debug("Request POST body data: ".YAML::Dump($post_data_ref));

	}

	my $atime=new Benchmark;
	
	my $request = HTTP::Request->new($method, $url, [ 'Accept' => 'application/json', 'Content-Type' => 'application/json' ]);
	
	if ($method eq "POST" && defined $post_data_ref){
	    $request->content(encode_json($post_data_ref));
	}
	
	my $response = $ua->request($request);
	
	$api_result_ref->{'http_status_code'}    = $response->code();
	$api_result_ref->{'http_status_message'} = $response->message();	

	my $btime      = new Benchmark;
	my $timeall    = timediff($btime,$atime);
	my $resulttime = timestr($timeall,"nop");
	$resulttime    =~s/(\d+\.\d+) .*/$1/;
	$resulttime = $resulttime * 1000.0; # to ms

	if ($resulttime > $config->get('alma')->{'api_logging_threshold'}){
	    $url =~s/\?.+$//; # Don't log args
	    $logger->error("Alma API call $url took $resulttime ms");
	}

	if ($logger->is_debug){
	    $logger->debug("Response Headers: ".$response->headers_as_string);
	    $logger->debug("Response: ".$response->content);
	    $logger->debug("Status Code: ".$api_result_ref->{'http_status_code'});

	}

	# $api_result_ref->{'http_status_code'} = 429; # Testfall concurrent AP request limit reached see: https://developers.exlibrisgroup.com/alma/apis/
	
	# Concurrent API-Limit reached
	if ($api_result_ref->{'http_status_code'} == 429){
	    $logger->fatal("Alma concurrent API request limit reached");
	    
	    $api_result_ref->{'response'} = {
		"code" => $api_result_ref->{'http_status_code'},
		    "error" => "error",
		    "error_description" => $msg->maketext("Ihre Anfrage konnte nicht bearbeitet werden, da das Cloud-Bibliothekssystem Alma derzeit überlastet ist und keine Anfragen mehr annimmt. Bitte versuchen Sie es später noch einmal."),
	    };
	    
	    return $api_result_ref;
	}

	# Timeout reached
	if ($api_result_ref->{'http_status_code'} == 500 && $api_result_ref->{'http_status_message'} eq "read timeout"){
	    $logger->fatal("Timeout reached");
	    
	    $api_result_ref->{'response'} = {
		"code" => $api_result_ref->{'http_status_code'},
		    "error" => "error",
		    "error_description" => $msg->maketext("Ihre Anfrage konnte nicht bearbeitet werden, da das Cloud-Bibliothekssystem Alma derzeit zu langsam antwortet und der Timeout von 30 Sekunden erreicht wurde."),
	    };
	    
	    return $api_result_ref;
	}
	
	if (!$response->is_success && $response->code != 400) {
	    $logger->info($response->code . ' - ' . $response->message);
	    return $api_result_ref;
	}	    
	
	eval {
	    $api_result_ref->{'data'} = decode_json $response->content;
	};
	
	if ($@){
	    $logger->error('Decoding error: '.$@);
	}
    }
    
    # Allgemeine Fehler
    if (defined $api_result_ref->{'data'}{'errorsExist'} && $api_result_ref->{'data'}{'errorsExist'} eq "true" ){
	$api_result_ref->{'response'} = {
	    "code" => 400,
		"error" => "error",
		"error_description" => $api_result_ref->{'data'}{'errorList'}{'error'}[0]{'errorMessage'},
		"error_code" => $api_result_ref->{'data'}{'errorList'}{'error'}[0]{'errorCode'},
	};
	
	return $api_result_ref;
    }

    return $api_result_ref;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = $self->get_config;

    if (!defined $config->{memcached}){
      $logger->debug("No memcached configured");
      return;
    }

    # Verbindung zu Memchached herstellen
    $self->{memc} = new Cache::Memcached::Fast(
	$self->{memcached},        
	compress_methods => [
            sub { ${$_[1]} = Compress::LZ4::compress(${$_[0]})   },
            sub { ${$_[1]} = Compress::LZ4::decompress(${$_[0]}) },
        ],
	);

    $logger->debug("Storing ".$self->{memc});

    if (!$self->{memc}->set('isalive',1)){
        $logger->fatal("Unable to connect to memcached");
        $self->disconnectMemcached;
    }

    return;
}

sub disconnectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Disconnecting memcached");
    
    $self->{memc}->disconnect_all if (defined $self->{memc});
    delete $self->{memc};

    return;
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

Authentifizierung am SIS

=item update_email

Aktualisierung der Mail-Adresse im SIS und ILS

=item update_phone

Aktualisierung der Telefonnummer im ILS

Entfaellt: Diese Information wird aus Datenschutzgruenden nicht mehr gespeichert

=item update_pin

Aktualisierung der Ausleih-PIN im SIS und ILS

=item update_password

Aktualisierung des Passworts im ILS

=item get_items

Bestellungen, Vormerkungen und Ausleihen in einer Abfrage aus dem ILS holen

Entfaellt: Alma stellt keine derartige API-Abfrage bereit und
Modellierung mit mehreren Requests wegen des concurrent request
API-Limits kritisch

=item get_accountinfo

Zusammenfassung des Nutzers aus ILS holen (Zahl Ausleihen, Vormerkunge, etc.)

Entfaellt: Alma stellt keine derartige API-Abfrage bereit und
Modellierung mit mehreren Requests wegen des concurrent request
API-Limits kritisch

=item get_userdata

Adressinformationen des Nutzer aus dem SIS holen

=item get_article_orders

Artikel-Fernleihbestellung aus dem ILS oder Medea holen

Entfaellt: Ausgelagert in Fernleihportal

=item get_zfl_orders

Buch-Fernleihbestellungen aus dem ILS oder ZFL holen

Entfaellt: Ausgelagert in Fernleihportal

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

Entfaellt: Alma stellt keine derartige API-Abfrage bereit und
Modellierung mit mehreren Requests wegen des concurrent request
API-Limits kritisch

=item renew_single_loan

Die Verlaengerung eines einzelnen Mediums im ILS durchfuehren

=item get_mediastatus

Liste der Exemplare mit Ausleihinformationen aus dem ILS holen

=item check_order

Bestellung ueberpruefen

=item check_reservation

Vormerkung ueberpruefen

=item make_alma_request

Hilfsmethode: Vereinheitlichtes Erzeugen eines Alma Requests
fuer Vormerkungen und Bestellungen

=item cancel_alma_request

Hilfsmethode: Vereinheitlichtes Loeschen eines Alma Requests
fuer Vormerkungen und Bestellungen

=item update_sis

Hilfsmethode: Absetzen eines API Request an die SIS-Anwendung der USB
Koeln zur Aktualisierung von Informationen dort (E-Mail, Passwort,
Ausleih-Pin) bzw. ueber die Anwendung parallel in Alma (E-Mail,
Ausleih-Pin)

=item send_alma_api_call

Hilfsmethode: Absetzen eines Alma API Request. Liefert Hashref-Elment
'response' fuer bereits vorverarbeitete Response, die direkt als
Ergebnis zurueckgeliefert werden kann bzw. 'data' fuer vom API
zurueckgelieferte Daten, die noch individuell prozessiert werden
muessen

=item get_timestamp

Hilfsmethode: Aktuellen Timestamp generieren

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Der Verzicht auf den Exporter 
bedeutet weniger Speicherverbrauch und mehr Performance auf 
Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
