#####################################################################
#
#  OpenBib::API::HTTP::JOP.pm
#
#  Objektorientiertes Interface zum Verfuegbarkeits-API
#  von Journals Online & Print (JOP)
#
#  Kein vollwertiges Recherche-API!
#  Daher keine Verwendung als OpenBib Search Backend moeglich!
#  Eigene Suchparameter, eigenes Suchergebnis
#
#  Dieses File ist (C) 2021-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::API::HTTP::JOP;

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

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

use base qw(OpenBib::API::HTTP);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Set defaults
    
    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;

    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    # Set API specific defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : $config->{ezb_bibid};

    my $client_ip = exists $arg_ref->{client_ip}
        ? $arg_ref->{client_ip}   : undef;
    
    my $self = { };

    bless ($self, $class);
    
    my $ua = Mojo::UserAgent->new();
    $ua->transactor->name('USB Koeln/1.0');
    $ua->connect_timeout(30);
    $ua->max_redirects(2);

    $self->{client}        = $ua;
        
    if ($config){
        $self->{_config}        = $config;
    }

    if ($searchquery){    
        $self->{_searchquery}   = $searchquery;
    }

    # Backend Specific Attributes
    $self->{bibid}           = $bibid;
    $self->{args}            = $arg_ref;
    
    return $self;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : $self->get_searchquery;
    
    my $config       = $self->get_config;
    
    $self->parse_query($searchquery);

    my $url="http://services.dnb.de/fize-service/gvr/full.xml?sid=bib:usbk&pid=bibid%3D".((defined $arg_ref->{bibid})?$arg_ref->{bibid}:$config->{ezb_bibid})."&".$self->querystring;

    $logger->debug("Request: $url");

    my $ua      = $self->get_client;

    my $response = $ua->get($url)->result;
    
    my $xmlresponse = "";
    
    if ($response->is_success){
	$xmlresponse = $response->body;
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }
    
    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }
    
    # Parse result and collect information in intermediate fields
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($xmlresponse);
    my $root   = $tree->getDocumentElement;

    my $result_ref = [];

    my $search_count = 0;

    my $electronic_states_ref = {
	'-1' => 'error', # ISSN nicht eindeutig
	    '0' => "green", # Standort-unabhängig frei zugänglich
	    '1' => 'green_yellow_red', # Standort-unabhängig teilweise zugänglich (Unschärfe bedingt durch unspezifische Anfrage oder Moving-Wall)
	    '2' => 'yellow', # Lizenziert
	    '3' => 'yellow_red', # Für gegebene Bibliothek teilweise lizenziert (Unschärfe bedingt durch unspezifische Anfrage oder Moving-Wall)
	    '4' => 'red', # nicht lizenziert
	    '5' => 'red', # Zeitschrift gefunden Angaben über Erscheinungsjahr, Datum ... liegen außerhalb des hinterlegten bibliothekarischen Zeitraums
	    '10' => 'unknown', # Unbekannt (ISSN unbekannt, Bibliothek unbekannt)
    };

    my $print_states_ref = {
	'-1' => 'error', # ISSN nicht eindeutig
	    '2' => "green", # Vorhanden
	    
	    '3' => 'green', # Teilweise vorhanden (Unschärfe bedingt durch unspezifische Anfrage bei nicht vollständig vorhandener Zeitschrift)
	    '4' => 'red', # Nicht vorhanden
	    '10' => 'unknown', # Unbekannt (ZDB-ID unbekannt, ISSN unbekannt, Bibliothek unbekannt)
    };

    foreach my $electronic_node ($root->findnodes('/OpenURLResponseXML/Full/ElectronicData/ResultList/Result')) {

	my $singleitem_ref = {};
	
        my $state                      = $electronic_node->findvalue('@state');

	next if ($state == -1 || $state == 10);
	
        $singleitem_ref->{state}       = $state;

	if (defined $electronic_states_ref->{$state}){
	    $singleitem_ref->{access}  = $electronic_states_ref->{$state};
	}
	
        $singleitem_ref->{title}       = $electronic_node->findvalue('Title');
        $singleitem_ref->{type}        = "online";
        $singleitem_ref->{journalurl}  = $electronic_node->findvalue('JournalURL');
        $singleitem_ref->{accessurl}   = $electronic_node->findvalue('AccessURL');
        $singleitem_ref->{accesslevel} = $electronic_node->findvalue('AccessLevel');
        $singleitem_ref->{readmeurl}   = $electronic_node->findvalue('ReadmeURL');
        $singleitem_ref->{interval}    = $electronic_node->findvalue('Additionals/Additional[@type="intervall"]');
        $singleitem_ref->{nali}        = $electronic_node->findvalue('Additionals/Additional[@type="nali"]');
        $singleitem_ref->{moving_wall} = $electronic_node->findvalue('Additionals/Additional[@type="moving_wall"]');

	push @$result_ref, $singleitem_ref;	
	$search_count++;
    }

    foreach my $print_node ($root->findnodes('/OpenURLResponseXML/Full/PrintData/ResultList/Result')) {
        my $singleitem_ref = {} ;
        
        my $state                      = $print_node->findvalue('@state');

	next if ($state == 0 || $state == 10);
	
        $singleitem_ref->{state}       = $state;

	if (defined $print_states_ref->{$state}){
	    $singleitem_ref->{access}  = $print_states_ref->{$state};
	}
	
        $singleitem_ref->{title}       = $print_node->findvalue('Title');
        $singleitem_ref->{type}        = "print";
        $singleitem_ref->{journalurl}  = $print_node->findvalue('JournalURL');
        $singleitem_ref->{accessurl}   = $print_node->findvalue('AccessURL');

        $singleitem_ref->{location}        = $print_node->findvalue('Location');
        $singleitem_ref->{period}          = $print_node->findvalue('Period');
        $singleitem_ref->{location_mark}   = $print_node->findvalue('Signature');
	$singleitem_ref->{holding_comment} = $print_node->findvalue('Holding_comment');
	$singleitem_ref->{holding_gaps}    = $print_node->findvalue('HoldingGaps');
	

	push @$result_ref, $singleitem_ref;
	$search_count++;
    }

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($result_ref));
    }
    
    $logger->debug("Found $search_count titles");
    
    $self->{resultcount}   = $search_count;
    $self->{_matches}      = $result_ref;
    
    return $self;
}

# Default: Convert result in intermediate fields to final fields in official metadata format as ResultList-Object
# This API: Just return results als arrayref
sub get_search_resultlist {
    my $self=shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $recordlist = OpenBib::RecordList::Title->new;
    
    my $result_id = 1;

    foreach my $result_ref ($self->matches){
	my $fields_ref = {};
	
	# Gesamtresponse in jop_source
	push @{$fields_ref->{'jop_source'}}, {
	    content => $result_ref
	};

	if ($result_ref->{title}){
	    push @{$fields_ref->{'T0331'}}, {
		content => $result_ref->{title},
	    };	    
	}

	if ($result_ref->{location_mark}){
	    push @{$fields_ref->{'X0014'}}, {
		content => $result_ref->{location_mark},
	    };	    
	}

	if ($result_ref->{accessurl} && $result_ref->{accesslevel} eq "article"){
	    if ($result_ref->{access} eq "green"){
		push @{$fields_ref->{'T4120'}}, {
		    content => $result_ref->{accessurl},
		    subfield => "g",
		}
	    }
	    elsif ($result_ref->{access} eq "yellow"){
		push @{$fields_ref->{'T4120'}}, {
		    content => $result_ref->{accessurl},
		    subfield => "y",
		    };
	    }
	    else { # unbestimmt
		push @{$fields_ref->{'T4120'}}, {
		    content => $result_ref->{accessurl},
		    subfield => " ",
		};
	    }
	}
	elsif ($result_ref->{accessurl} && $result_ref->{accesslevel} eq "homepage"){
	    push @{$fields_ref->{'T0662'}}, {
		content => $result_ref->{accessurl},
		subfield => "",
		mult => 1,
	    };
	    push @{$fields_ref->{'T0663'}}, {
		content => "Homepage",
		subfield => "",
		mult => 1,
	    };
	}
	
	if ($result_ref->{type}){
	    push @{$fields_ref->{'T0800'}}, {
		content => $result_ref->{type},
	    };	    
	}
	
	
	my $record = new OpenBib::Record::Title({ database => 'jop', id => $result_id++ });
    	
	$record->set_fields_from_storable($fields_ref);
	
	$recordlist->add($record);
    }
    
    return $recordlist;
}

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    # Specific searchfields for this API like searchfield definition in portal.yml
    my $api_searchfield_ref = {
	issn => {
	    type => "ft",
	},
	genre => {
	    type => "ft",
	},
	volume => {
	    type => "ft",
	},
	issue => {
	    type => "ft",
	},
	pages => {
	    type => "ft",
	},
	date => {
	    type => "ft",
	},
    };
    
    my @searchstrings = ();

    foreach my $field (keys %{$api_searchfield_ref}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{val})?$searchquery->get_searchfield($field)->{val}:'';

	# genre mandatory
	if ($field eq "genre" && $searchtermstring eq ""){
	    my $issn = (defined $searchquery->get_searchfield('issn')->{val})?$searchquery->get_searchfield('issn')->{val}:'';
	    my $title = (defined $searchquery->get_searchfield('title')->{val})?$searchquery->get_searchfield('title')->{val}:'';
	    my $volume = (defined $searchquery->get_searchfield('volume')->{val})?$searchquery->get_searchfield('volume')->{val}:'';

	    if ($issn){
		if ($title){
		    $searchtermstring='article';
		}
		elsif ($volume){
		    $searchtermstring='article';		    
		}
		else {
		    $searchtermstring='journal';		    
		}
	    }
	}
	
        if ($searchtermstring){ 
            # Alle besetzten Parameter 1:1 uebernehmen
            push @searchstrings, $field."=".$searchtermstring;
        }
    }        

    my $apiquerystring = join("&",@searchstrings);

    $logger->debug("API-Querystring: $apiquerystring");

    $self->{_querystring} = $apiquerystring;

    return $self;
}

sub DESTROY {
    my $self = shift;

    return;
}


1;
__END__

=head1 NAME

 OpenBib::API::HTTP::JOP - Objekt zur Interaktion mit Journals Online & Print (JOP)

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib über das API von JOP auf diesen Web-Dienst zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::API::HTTP::JOP;
 use OpenBib::SearchQuery;

 my $query = new OpenBib::SearchQuery;

 $query->set_searchfield('issn',$issn);
 $query->set_searchfield('genre','journal');

 my $api = OpenBib::API::HTTP::JOP->new({ bibid => $bibid, searchquery => $query });

 my $search = $api->search();

 my $hits   = $search->get_resultcount;
 my $result = $search->get_search_resultlist;

=head1 METHODS

=over 4

=item new({ bibid => $bibid, client_ip => $clientip, searchquery => $searchquery })

Anlegen eines neuen JOP-Objektes. Für den Zugriff über das
JOP-API muss eine Bibliothekskennzeichnung $bibid oder IP-Addresse $client_ip mitgegeben werden, um die genaue Verfuegbarkeit bestimmen zu koennen.

Die Suchbegriffe werden ueber ein SearchQuery-Objekt uebergeben.

=item search({ searchquery => $searchquery })

Fuehre die Suche aus. Falls noch nicht bei der Erzeugung uebergeben kann hier 
explizit eine Suchanfrage mit $searchquery uebergeben werden

=item get_search_resultlist()

Liefert die JOP Suchergebnisse in JSON zurueck.

=item get_resultcount()

Liefert die Zahl der Treffer in JOP zurueck.

=item parse_query()

Umwandlung Suchparameter aus SearchQuery-Objekt in API-Spezifische Parameter

=back

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
