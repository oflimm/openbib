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
use JSON::XS qw/encode_json/;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Config::DatabaseInfoTable;
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
        'show'          => 'show',
        'authenticate'  => 'authenticate',
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
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if ($service eq "login" || $service eq "logout"){
	$self->${service};
    }
    else {
	$logger->error("invalid service");
    }
        
    return;
}

sub login {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

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

    $logger->debug($response->content);

    my ($response_username) = $response->content=~m/<slnpValue id=\"BenutzerNummer\">(.+?)<\/slnpValue>/;

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


sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $id          = $query->param('id')        || '';
    my $format      = $query->param('format')    || '';
    my $callback    = $query->param('callback')  || '';
    my $patron      = $query->param('patron')    || '';
    my $patrontype  = $query->param('patron-type')    || '';
    my $accesstoken = $query->param('access_token')    || '';
    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->new;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    # Richtigen Content-Type setzen
    $self->param('content_type','application/json');
    
    $self->header_add('X-DAIA-Version' => '1.0.0');
    $self->header_add('Content-Language' => $lang);

    if ($format && $format ne 'json'){
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

    my @request_ids = ();
    
    if ($id =~m/\\|/){ # multiple
	$logger->debug("Multiple");
	@request_ids = split("\\|",$id);
    }
    else {
	push @request_ids, $id;
    }

    $logger->debug(YAML::Dump(\@request_ids));

    my $all_items_ref = [];

    foreach my $request_id (@request_ids){
	my ($thisdb,$thisid)=$request_id=~m/^(.+?):(.+)$/;
	
	# Ausleihinformationen der Exemplare
	my $circulation_ref = [];
	{
	    my $circexlist=undef;
	    
	    if ($circinfotable->has_circinfo($thisdb) && defined $circinfotable->get($thisdb)->{circ}) {
		
		$logger->debug("Getting Circulation info via USB-SOAP");

		my @args = ($thisid);
		
		my $uri = "urn:/Loan";

		if ($circinfotable->get($thisdb)->{circdb} ne "sisis"){
		    $uri = "urn:/Loan_inst";
		    push @args, $thisdb;
		}
		    
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
		    $logger->error("SOAP-Target ".$circinfotable->get($thisdb)->{circcheckurl}." konnte nicht erreicht werden :".$@);
		}
		
	    }
	    
	    # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
	    # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
	    # titelbasierten Exemplardaten
	    
	    if (defined($circexlist)) {
		foreach my $nr (keys %{$circexlist->{Exemplardaten}}){
		    my $circ_ref = $circexlist->{Exemplardaten}{$nr};

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

		    push @$circulation_ref, $circ_ref;
		}
	    }	    
	}

	# Cleanup USBWS-Messages 
	foreach my $circ_ref (@$circulation_ref){
	}
	
	my $item_ref = {
	    id => $thisid,
	    database => $thisdb,
	    circulation => $circulation_ref,
	};
	
	push @$all_items_ref,  $item_ref;
	
	$logger->debug("Circ: ".YAML::Dump($item_ref));
    }
    
    my $ttdata={
	timestamp => $self->get_timestamp,
	items     => $all_items_ref,
    };
    
    return $self->print_page($config->{tt_connector_daia_tname},$ttdata);
}

sub get_timestamp {
    my $self = shift;
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $timestamp = sprintf ( "%04d-%02d-%02dT%02d:%02d:%02dZ",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $timestamp;
}

1;
