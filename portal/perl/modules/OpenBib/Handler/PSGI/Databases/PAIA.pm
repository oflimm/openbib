####################################################################
#
#  OpenBib::Handler::PSGI::Databases::PAIA.pm
#
#  Dieses File ist (C) 2020- Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Handler::PSGI::Databases::PAIA;

use strict;
use warnings;
no warnings 'redefine';

use URI;
use URI::Escape;

use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Session::Token;
use Template;
use Encode 'decode_utf8';
use JSON::XS qw/encode_json decode_json/;
use XML::Simple;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Enrichment;
use OpenBib::L10N;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'authenticate'       => 'authenticate',
        'core_get_services'  => 'core_get_services',
        'core_post_services' => 'core_post_services',
        'patron'             => 'patron',
        'update_patron'      => 'update_patron',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub authenticate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $service        = $self->param('serviceid');

    # Shared Args
    my $query          = $self->query();

    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';
    
    my $valid_services_ref = {
	login  => 1,
	logout => 1,
    };
    
    if (defined $valid_services_ref->{$service} && $valid_services_ref->{$service}){
	return $self->${service};
    }
    else {
	$logger->error("invalid service");
	
	my $response_ref = {
	    error => 'Missing or invalid query parameters',
	    code  => 422
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 422); # invalid request
	    
	}

	return decode_utf8(encode_json $response_ref);
    }
        
    return;
}

sub core_get_services {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $userid         = $self->param('userid');    
    my $service        = $self->param('serviceid');

    # Shared Args
    my $query          = $self->query();

    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';

    my $valid_services_ref = {
	items         => 1,
	fees          => 1,
	notifications => 1,
    };
    
    if (defined $valid_services_ref->{$service} && $valid_services_ref->{$service}){
	return $self->${service};
    }
    else {
	$logger->error("invalid service");
	
	my $response_ref = {
	    error => 'Missing or invalid query parameters',
	    code  => 422
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 422); # invalid request
	    
	}

	return decode_utf8(encode_json $response_ref);
    }
        
    return;
}

sub core_post_services {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $userid         = $self->param('userid');    
    my $service        = $self->param('serviceid');

    # Shared Args
    my $query          = $self->query();

    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';

    my $valid_services_ref = {
	request  => 1,
	renew    => 1,
	cancel   => 1,
    };
    
    if (defined $valid_services_ref->{$service} && $valid_services_ref->{$service}){
	return $self->${service};
    }
    else {
	$logger->error("invalid service");
	
	my $response_ref = {
	    error => 'Missing or invalid query parameters',
	    code  => 422
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 422); # invalid request
	    
	}

	return decode_utf8(encode_json $response_ref);
    }
        
    return;
}

sub patron {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $username       = uri_unescape($self->param('userid'));    

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');

   
    # CGI Args
    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';

    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    
    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');
    $self->header_add('Cache-Control' => 'no-store');
    $self->header_add('Pragma' => 'no-cache');
    $self->header_add('Content-Language' => $lang);

    my $valid_paia = $self->user_has_valid_token($username);
    
    if (!$valid_paia){
	my $response_ref = {
	    "error" => "access_denied",
		"error_description" => "invalid patron or password",
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 403); # forbidden
	}

	return decode_utf8(encode_json $response_ref);
    }

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    my $url            = $config->get('usbauth_url');
    my $masterpassword = $config->get('usbauth_masterpass');
    
    $url.="?userid=".uri_escape($username)."&password=".uri_escape($masterpassword);

    $logger->debug("Request-URL: ".$url);
    
#    my $response = $ua->post($url, userid => uri_escape($username), password => uri_escape($password));

    my $request = HTTP::Request->new('GET',$url);

    my $response = $ua->request($request);

    if ( $response->is_error() ) {
	my $response_ref = {
	    error => 'Missing or invalid query parameters',
	    code  => 422
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 422); # invalid request
	    
	}

	return decode_utf8(encode_json $response_ref);
    }

    $self->header_add('X-Accepted-OAuth-Scopes' => 'read_patron');

    $logger->debug($response->content);

    my $ref = XMLin($response->content);
    
    my $account_ref = {};
    
    foreach my $field (keys %{$ref->{slnpValue}}){
	$account_ref->{$field} = $ref->{slnpValue}{$field}{content};
    }

    my $response_ref = {
	name    => $account_ref->{FullName},
	email   => $account_ref->{Email1},
	expires => $account_ref->{AusweisEnde},
	type    => $scheme."://".$servername.$path_prefix."/".$config->get('databases_loc')."/id/$database/usergroup/".$account_ref->{BenutzerGruppe},
    };

    my $address = ($account_ref->{Strasse1})?$account_ref->{Strasse1}.", ":"";
    $address .= ($account_ref->{Plz1})?$account_ref->{Plz1}." ":"";
    $address .= ($account_ref->{Ort1})?$account_ref->{Ort1}:"";

    $response_ref->{address} = $address if ($address);

    my $returnvalue;

    eval {
	$returnvalue = encode_json $response_ref;    
    };

    if ($@){
	$logger->error($@);
    }
    
    $logger->debug("Returnvalue: ".$returnvalue);
    
    return $returnvalue;
}

sub logout {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');

    # Shared Args
    my $query          = $self->query();
    my $lang           = $self->param('lang');

    # CGI Args
    my $username       = $query->param('patron')        || '';
    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');
    $self->header_add('Cache-Control' => 'no-store');
    $self->header_add('Pragma' => 'no-cache');
    $self->header_add('Content-Language' => $lang);

    my $valid_paia = $self->user_has_valid_token($username);
    
    if (!$valid_paia){
	my $response_ref = {
	    "error" => "access_denied",
		"error_description" => "invalid patron or password",
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 403); # forbidden
	}

	return decode_utf8(encode_json $response_ref);
    }    
    else {    
	$valid_paia->delete;
    }
 
    my $returnvalue;

    eval {
	$returnvalue = decode_utf8(encode_json { patron => $username });    
    };

    if ($@){
	$logger->error($@);
    }
    
    $logger->debug("Returnvalue: ".$returnvalue);
    
    return $returnvalue;
}


sub login {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view        = $self->param('view');
    my $database    = $self->param('database');

    # Shared Args
    my $query       = $self->query();
    my $config      = $self->param('config');
    my $lang        = $self->param('lang');

    # CGI Args
    my $username    = $query->param('username')      || '';
    my $password    = $query->param('password')      || '';
    my $granttype   = $query->param('grant_type')    || 'password';

    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');
    $self->header_add('Cache-Control' => 'no-store');
    $self->header_add('Pragma' => 'no-cache');
    $self->header_add('Content-Language' => $lang);

    if ($granttype ne "password" || ($granttype eq "password" && !$username && !$password)){
	my $response_ref = {
	    error => 'Missing or invalid query parameters',
	    code  => 422
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 422); # invalid request
	    
	}

	return decode_utf8(encode_json $response_ref);
    }    

    $logger->debug("Authenticate info via USB Authentication-Service");

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    my $url = $config->get('usbauth_url');

    $url.="?userid=".uri_escape($username)."&password=".uri_escape($password);

    $logger->debug("Request-URL: ".$url);
    
#    my $response = $ua->post($url, userid => uri_escape($username), password => uri_escape($password));

    my $request = HTTP::Request->new('GET',$url);

    my $response = $ua->request($request);

    if ( $response->is_error() ) {
	my $response_ref = {
	    error => 'Missing or invalid query parameters',
	    code  => 422
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 422); # invalid request
	    
	}

	return decode_utf8(encode_json $response_ref);
    }

    $logger->debug($response->content);

    my $ref = XMLin($response->content);
    
    my $account_ref = {};
    
    foreach my $field (keys %{$ref->{slnpValue}}){
	$account_ref->{$field} = $ref->{slnpValue}{$field}{content};
    }

    my $response_username = $account_ref->{'BenutzerNummer'};

    $logger->debug("Request  Username: ".$username);
    
    $logger->debug("Response Username: ".$response_username);

    my $result_ref;
    
    if (defined $response_username && $username eq $response_username){

	my $token = Session::Token->new->get;
	
	$result_ref = {
	    "access_token"   => $token,
		"token_type" => "Bearer",
		"expires_in" => 3600,
		"patron"     => $response_username,
		"scope"      => "read_patron read_fees read_items write_items read_notifications delete_notifications"
	};

	my $paia = $config->get_schema->resultset('Paia')->single(
	    {
		username => $response_username,
	    },
	    );

	if ($paia){
	    $paia->delete;
	}
	
	$config->get_schema->resultset('Paia')->create(
	    {
		username => $response_username,
		token    => $token
	    }
	    );


	# Save Userdata in Account;


	
    }
    else {
	$result_ref = {
	    "error" => "access_denied",
		"error_description" => "invalid patron or password",
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 403); # forbidden
	}
    }
    
    $logger->debug(YAML::Dump($result_ref));
 
    my $returnvalue;

    eval {
	$returnvalue = decode_utf8(encode_json $result_ref);    
    };

    if ($@){
	$logger->error($@);
    }
    
    $logger->debug("Returnvalue: ".$returnvalue);
    
    return $returnvalue;
}

sub update_patron {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');

    my $response_ref = {
	"error" => "not_implemented",
	    "error_description" => "Known but unsupported request URL",
    };
    
    
    $self->header_add('Status' => 501); 

    return decode_utf8(encode_json $response_ref);
}

sub items {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $username       = uri_unescape($self->param('userid'));    

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');

    # CGI Args
    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';


    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    
    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');
    $self->header_add('Cache-Control' => 'no-store');
    $self->header_add('Pragma' => 'no-cache');
    $self->header_add('Content-Language' => $lang);

    my $valid_paia = $self->user_has_valid_token($username);
    
    if (!$valid_paia){
	my $response_ref = {
	    "error" => "access_denied",
		"error_description" => "invalid patron or password",
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 403); # forbidden
	}

	return decode_utf8(encode_json $response_ref);
    }    

    my $itemlist=undef;
    
    if ($circinfotable->has_circinfo($database) && defined $circinfotable->get($database)->{circ}) {
	
	$logger->debug("Getting Circulation info via USB-SOAP");
	
	my @args = ($username,'ALLES');
	
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
		$logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
	    }
	};
	
	if ($@){
	    $logger->error("SOAP-Target ".$config->get('usbws_url')." konnte nicht erreicht werden :".$@);
	}
	
    }
    
    # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
    # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
    # titelbasierten Exemplardaten
    
    my $response_ref = [];

    if (defined($itemlist) && %{$itemlist->{Konto}}) {
	my $all_items_ref = [];

	foreach my $nr (sort keys %{$itemlist->{Konto}}){
	    push @$all_items_ref, $itemlist->{Konto}{$nr};
	}
	
	foreach my $item_ref (@$all_items_ref){
	    my @titleinfo = ();
	    push @titleinfo, $item_ref->{Verfasser} if ($item_ref->{Verfasser});
	    push @titleinfo, $item_ref->{Titel} if ($item_ref->{Titel});

	    my $about = join(': ',@titleinfo);

	    my $starttime = $item_ref->{Datum};
	    my $endtime   = $item_ref->{RvDatum};

	    push @$response_ref, {
		about   => $about,
		edition => $scheme."://".$servername.$path_prefix."/databases/id/$database/titles/id/".$item_ref->{Titlecatkey},
		item    => $scheme."://".$servername.$path_prefix."/databases/id/$database/titles/id/".$item_ref->{Titlecatkey}."/items/id/".uri_escape($item_ref->{MedienNummer}),
		renewals => $item_ref->{VlAnz};
	    };
	    
	}
    }
    
    my $returnvalue;

    eval {
	$returnvalue = encode_json $response_ref;    
    };

    if ($@){
	$logger->error($@);
    }
    
    $logger->debug("Returnvalue: ".$returnvalue);
    
    return $returnvalue;
}

sub fees {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');

    my $response_ref = {
	"error" => "not_implemented",
	    "error_description" => "Known but unsupported request URL",
    };
    
    
    $self->header_add('Status' => 501); 

    return decode_utf8(encode_json $response_ref);
}

sub notifications {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');

    my $response_ref = {
	"error" => "not_implemented",
	    "error_description" => "Known but unsupported request URL",
    };
    
    
    $self->header_add('Status' => 501); 

    return decode_utf8(encode_json $response_ref);
}

sub request {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');

    my $response_ref = {
	"error" => "not_implemented",
	    "error_description" => "Known but unsupported request URL",
    };
    
    
    $self->header_add('Status' => 501); 

    return decode_utf8(encode_json $response_ref);
}

sub renew {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');

    my $response_ref = {
	"error" => "not_implemented",
	    "error_description" => "Known but unsupported request URL",
    };
    
    
    $self->header_add('Status' => 501); 

    return decode_utf8(encode_json $response_ref);
}

sub cancel {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    $self->param('represenation','json');
    
    $self->header_add('X-PAIA-Version' => '1.3.4');
    $self->header_add('X-OAuth-Scopes' => 'read_patron read_fees read_items write_items read_notifications delete_notifications');

    my $response_ref = {
	"error" => "not_implemented",
	    "error_description" => "Known but unsupported request URL",
    };
    
    
    $self->header_add('Status' => 501); 

    return decode_utf8(encode_json $response_ref);
}

sub user_has_valid_token {
    my ($self,$username) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r              = $self->param('r');
    my $config         = $self->param('config');

    # Header
    my $authorization  = $r->header('Authorization') || '';

    my $token = "";
    if ($authorization){
	($token) = $authorization =~m/^Bearer (.+)$/;
    }		

    my $paia = $config->get_schema->resultset('Paia')->single(
	{
	    username => $username,
	    token    => $token,
	},
	);

    
    return $paia if ($paia);

    return;
}

sub get_timestamp {
    my $self = shift;
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $timestamp = sprintf ( "%04d-%02d-%02dT%02d:%02d:%02dZ",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $timestamp;
}

1;
