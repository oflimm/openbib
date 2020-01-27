#####################################################################
#
#  OpenBib::API::HTTP::Example.pm
#
#  Objektorientiertes Interface zum einem Beispiel API
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

package OpenBib::API::HTTP::Example;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Storable;
use JSON::XS;
use URI::Escape;
use YAML ();

use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::API::HTTP);

# In der Regel muessen fuer ein API-Objekt mindestens folgende Methoden
# implementiert werden:
#
# - new: Uebergabe aller relevanten Informationen bei der Erzeugung des Objekts
# - search: Stellen der Suchanfrage und Abspeichern des Ergebnisses im Objekt
# - get_search_resultlist: Rueckliefern des Suchergebnis via RecordList-Objekt
# - get_record: Anfordern und Zurueckliefern eines Titels zur Vollanzeige
#
# Hilfsmethoden idR
#
# - parse_query: Parsen der in searchquery und queryoptions
#   gelieferten Informatione und umschreiben in Anfrageinformationen
#   fuer das API.
#
# API-Objekte werden idR jeweils in den jeweiligen Backends fuer
# Search und Catalog verwendet, die fuer das entsprechende API jeweils
# ebenfalls implementiert werden muessen

sub new {
    my ($class,$arg_ref) = @_;

    # Setzen von Api-spezifischen Parametern, wie API-Key usw.
    # my $api_key = exists $arg_ref->{api_key}
    #    ? $arg_ref->{api_key}     : undef;

    # Normalerweise immer notwendige Parameter
    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}     : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;
    
    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);
    
    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    $self->{client}        = $ua;
        
    # $self->{api_key}  = (defined $api_key )?$api_key :(defined $config->{eds}{passwd} )?$config->{eds}{passwd} :undef;
    
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


# Abholen eines Einzeltreffers mit dem API
sub get_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
        ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $record = new OpenBib::Record::Title({ database => $database, id => $id });

    my $fields_ref = ();

    # Code fuer das Abholen eines Einzeltreffers per API, parsen des Ergebnisses und dem Setzen der entsprechenden Felder in fields_ref folgt hier:
    
    $record->set_fields_from_storable($fields_ref);
    
    $record->set_holding([]);
    $record->set_circulation([]);
    
    return $record;
}

# Suche per API mit Suchbegriffen aus $searchquery und Suchparametern $queryoptions

sub search {
    my ($self,$arg_ref) = @_;

    # Set defaults search parameters
    my $options_ref          = exists $arg_ref->{options}
        ? $arg_ref->{options}        : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;

    # Used Parameters
    my $sorttype          = (defined $self->{_options}{srt})?$self->{_options}{srt}:$queryoptions->get_option('srt');
    my $sortorder         = (defined $self->{_options}{srto})?$self->{_options}{srto}:$queryoptions->get_option('srto');
    my $defaultop         = (defined $self->{_options}{dop})?$self->{_options}{dop}:$queryoptions->get_option('dop');
    my $facets            = (defined $self->{_options}{facets})?$self->{_options}{facets}:$queryoptions->get_option('facets');
    my $gen_facets        = ($facets eq "none")?0:1;
    
    if ($logger->is_debug){
        $logger->debug("Options: ".YAML::Dump($options_ref));
    }
    
    # Pagination parameters
    my $page              = (defined $self->{_options}{page})?$self->{_options}{page}:$queryoptions->get_option('page');
    my $num               = (defined $self->{_options}{num})?$self->{_options}{num}:$queryoptions->get_option('num');
    my $collapse          = (defined $self->{_options}{clp})?$self->{_options}{clp}:$queryoptions->get_option('clp');

    my $offset            = $page*$num-$num;

    # Umschreiben der Suchanfrage entsprechen der Syntax des APIs
    # ueber die Hilfsmethode parse_query, die eigens zum API in diesem
    # Objekt noch zu implementieren ist.
    $self->parse_query($searchquery);

    my $titles_ref  = [];
    my $resultcount = 0;
    
    # Stellen der Anfrage per API und Verarbeitung des Ergebnisses
    # Mindestens zwei Informationen muessen abgespeichert werden:
    #
    # 1.) Der Trefferlisten-Teil der Anfrage als Liste fuer die Ausgabe in
    #     $self->{_matches}
    #
    # 2.) die Zahl der Gesamttreffer in
    #     $self->{resultcount}


    # ...
    
    # Beispiel fuer die Organisation der Trefferlisteninhalte:
    # push @$titles_ref, {
    #                      id       => <Titelid>,
    #                      database => <Datenbankname>,
    #                      fields   => <Felder pro Treffer>,
    #                    };
    # Abspeichern der Trefferzahl und der aktuellen Teil-Trefferliste im Objekt
    $self->{resultcount}   = $resultcount;
    $self->{_matches}      = $titles_ref;
    
    return $self;
}

# Ruecklieferung der Trefferliste in einem OpenBib::RecordList::Title-Objekt
sub get_search_resultlist {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;

    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;

    # Zugriff auf die interne Form der Struktur der
    # Trefferlisteneintraege und Erzeugung eines standardisierten
    # OpenBib::RecordList::Title Listen-Objektes bestehend aus
    # OpenBib::Record::Title Objekten
    
    foreach my $match_ref (@matches) {

        my $id            = OpenBib::Common::Util::encode_id($match_ref->{database}."::".$match_ref->{id});
	my $fields_ref    = $match_ref->{fields};

        $recordlist->add(OpenBib::Record::Title->new({database => 'eds', id => $id })->set_fields_from_storable($fields_ref));
    }

    return $recordlist;
}

# Hilfsmethode zum Umschreiben der Suchbegriffe der entsprechenden
# OpenBib-Objekte in die Such-Syntax des jeweilige APIs
sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    # Aufbau des example searchquerystrings
    my @example_querystrings = ();
    my $example_querystring  = "";

    # Aufbau des example_filterstrings
    my @example_filterstrings = ();
    my $example_filterstring  = "";

    my $query_count  = 1;
    my $query_ref    = [];
    my $filter_count = 1;    
    my $filter_ref   = [];
    
    # Entsprechender Code folgt hier..

    if ($logger->is_debug){
        $logger->debug("Query: ".YAML::Dump($query_ref));
        $logger->debug("Filter: ".YAML::Dump($filter_ref));
    }

    # Abspeichern der Informationen im Objekt
    $self->{_query}  = $query_ref;
    $self->{_filter} = $filter_ref;

    return $self;
}

sub DESTROY {
    my $self = shift;

    return;
}


1;
__END__

=head1 NAME

 OpenBib::API::HTTP::Example - Objekt zur Interaktion mit dem API

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib über das API auf einen Web-Dienst zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::API::HTTP::Example;

 my $api = new OpenBib::API::HTTP::Example({ searchquery => $searchquery, queryoptions => queryoptions});

 $api->search();

 my $result_recordlist = $api->get_search_resultlist;

 my $single_record     = $api->get_record({ database => $database, id => $id });

=head1 METHODS

=over 4

=item new({ searchquery => $searchquery, queryoptions => queryoptions });

Anlegen eines neuen API-Objektes. Für den Zugriff über das
API koennen weitere Parameter wie z.B. ein API-Key $api_key oder ein API-Nutzer $api_user
mit uebergeben werden. Diese können direkt bei der Objekt-Erzeugung angegeben
werden, ansonsten werden etwaig vorhandene  Standard-Keys aus OpenBib::Config 
respektive portal.yml verwendet.

=item search()

Stellen der Suchanfrage und Abspeichern des Ergebnisses (Liste plus Trefferzahl) im API-Objekt.

=item get_search_resultlist()

Liefert nach dem Stellen der Suchanfrage mit search() das Ergebnis als RecordList zurueck

=item get_record({ database => $database, id => $id })

Liefert eine OpenBib::Record-Objekt zurueck.

=back

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
