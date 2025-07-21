#####################################################################
#
#  OpenBib::API::HTTP::LobidGND.pm
#
#  Objektorientiertes Interface zum Lobid GND-API
#
#  basiert auf OpenBib::API::HTTP::LobidGND
#
#  Dieses File ist (C) 2020-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::API::HTTP::LobidGND;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode qw/decode decode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use Mojo::UserAgent;
use Storable;
use XML::LibXML;
use JSON::XS;
use URI::Escape;
use YAML ();
use Mojo::Base -strict, -signatures;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;

use base qw(OpenBib::API::HTTP);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Set defaults
    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}               : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;

    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;
    
    my $self = { };

    bless ($self, $class);
    
    my $ua = Mojo::UserAgent->new();
    $ua->transactor->name('USB Koeln/1.0');
    $ua->connect_timeout(5);
    $ua->request_timeout($config->{'lobidgnd'}{'api_timeout'});
    $ua->max_redirects(2);

    $self->{client}        = $ua;
        
    $self->{sessionID} = $sessionID;

    if ($config){
        $self->{_config}        = $config;
    }

    if ($queryoptions){
        $self->{_queryoptions}  = $queryoptions;
    }

    if ($searchquery){    
        $self->{_searchquery}   = $searchquery;
    }
    
    return $self;
}

sub get_titles_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
             ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : 'lobidgnd';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $record = new OpenBib::Record::Title({ database => $database, id => $id });

    my $memc = $config->get_memc;
	        
    my $url="https://lobid.org/gnd/$id.json";
        
    my $titles_ref = [];

    my $memc_key = "lobidgnd:authority:$url";

    $logger->debug("Memc: ".$memc);
    $logger->debug("Memcached: ".$config->{memcached});    
    
    if ($memc){
        my $fields_ref = $memc->get($memc_key);

	if ($fields_ref){
	    if ($logger->is_debug){
		$logger->debug("Got fields for key $memc_key from memcached");
	    }

	    $record->set_fields($fields_ref);
	    $record->set_holding([]);
	    $record->set_circulation([]);
	    
	    return $record;
	}
    }
    
    $logger->debug("Request: $url");

    my $json_result_ref = {};

    my $atime = new Benchmark;
    
    my $response = $ua->get($url)->result;

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    $resulttime = $resulttime * 1000.0; # to ms
    
    if ($resulttime > $config->{'lobidgnd'}{'api_logging_threshold'}){
	$logger->error("LobidGND API call $url took $resulttime ms");
    }
    
    if ($response->is_success){
	eval {
	    $json_result_ref = decode_json $response->body;
	};
	if ($@){
	    $logger->error('Decoding error: '.$@);
	    return $record;
	}	
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return $record;
    }

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }

    # Process json_result_ref;

    $logger->debug($json_result_ref);

    my $fields_ref = {};

    # Gesamtresponse in lobid_source
    push @{$fields_ref->{'lobid_source'}}, {
	content => $json_result_ref
    };

    push @{$fields_ref->{'T0010'}}, {
	content => $json_result_ref->{gndIdentifier},
	mult => 1,
	subfield => 'a',
    };
    
    push @{$fields_ref->{'T0331'}}, {
	content => $json_result_ref->{preferredName},
	mult => 1,
	subfield => 'a',
    };
    
    
    $record->set_fields_from_storable($fields_ref);
    
    $record->set_holding([]);
    $record->set_circulation([]);

    if ($memc){
	$memc->set($memc_key,$record->get_fields,$config->{memcached_expiration}{'ezb:title'});
    }
    
    return $record;
}

sub DESTROY {
    my $self = shift;

    return;
}


1;
__END__

=head1 NAME

 OpenBib::API::HTTP::LobidGND - Objekt zur Interaktion mit dem Lobid GND API

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib über das API von Lobid GND auf diesen Web-Dienst zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::API::HTTP::LobidGND;

 my $gnd = new OpenBib::API::HTTP::LobidGND();

 my $single_record_json = $eds->get_titles_record({ id => $gnd_id });

=head1 METHODS

=over 4

=item new()

Anlegen eines neuen LobidGND-Objektes.

=item get_titles_record({ id => $gnd_id })

Liefert die die Daten zur GND-ID $gnd_id als Antwort in JSON zurueck.
=back

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
