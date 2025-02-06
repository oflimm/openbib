####################################################################
#
#  OpenBib::Mojo::Controller::Connector::DAIA.pm
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

package OpenBib::Mojo::Controller::Connector::DAIA;

use strict;
use warnings;
no warnings 'redefine';

use URI;
use URI::Escape;

use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my $id          = $query->stash('id')        || '';
    my $format      = $query->stash('format')    || '';
    my $callback    = $query->stash('callback')  || '';
    my $patron      = $query->stash('patron')    || '';
    my $patrontype  = $query->stash('patron-type')    || '';
    my $accesstoken = $query->stash('access_token')    || '';
    my $suppressresponsecodes = $query->stash('suppress-response-codes')    || '';

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->new;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $locinfotable  = OpenBib::Config::LocationInfoTable->new;

    # Richtigen Content-Type setzen
    $self->stash('content_type','application/json');
    
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

    if ($logger->is_debug){
	$logger->debug(YAML::Dump(\@request_ids));
    }
    
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
		    $logger->error("SOAP-Target ".$circinfotable->get($thisdb)->{circcheckurl}." konnte nicht erreicht werden :".$@);
		}
		
	    }
	    
	    # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
	    # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
	    # titelbasierten Exemplardaten
	    
	    if (defined($circexlist)) {
		my $itemstring = (defined $circexlist->{Exemplardaten})?'Exemplardaten':'PresentExemplardaten';
		
		foreach my $nr (keys %{$circexlist->{$itemstring}}){
		    my $circ_ref = $circexlist->{$itemstring}{$nr};

		    if ($logger->is_debug){
			$logger->debug(YAML::Dump($circ_ref));
		    }
		    
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
	
        if ($logger->is_debug){
	    $logger->debug("Circ: ".YAML::Dump($item_ref));
	}
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
