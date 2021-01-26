#####################################################################
#
#  OpenBib::Search.pm
#
#  Objektorientiertes Interface fuer Suchanfragen
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Cache::Memcached::Fast;
use Compress::LZ4;
use DBI;
use LWP;
use Encode qw(decode decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::SearchQuery;
use OpenBib::QueryOptions;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::Catalog::Factory;
use OpenBib::Container;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $searchprofile   = exists $arg_ref->{searchprofile}
        ? $arg_ref->{searchprofile}           : undef;

    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;

    my $authority          = exists $arg_ref->{authority}
        ? $arg_ref->{authority}               : undef;

    my $options            = exists $arg_ref->{options}
        ? $arg_ref->{options}                 : {};

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;
    
    my $sessionID            = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}                 : undef;

    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;
    
    my $self = { };

    bless ($self, $class);

    # Entweder genau eine Datenbank via database oder (allgemeiner) ein Suchprofil via searchprofile mit einer oder mehr Datenbanken

    if ($searchprofile){
        $self->{_searchprofile} = $searchprofile 
    }
    
    if ($database){
        $self->{_database}      = $database;
    }

    if ($authority){
        $self->{_authority}     = $authority;
    }

    if ($options){
        $self->{_options}       = $options;
    }

    if ($config){
        $self->{_config}        = $config;
    }

    if ($sessionID){
        $self->{_sessionID}       = $sessionID;
    }
    
    if ($queryoptions){
        $self->{_queryoptions}  = $queryoptions;
    }

    if ($searchquery){    
        $self->{_searchquery}   = $searchquery;
    }
    
    # Achtung: searchprofile und database werden fuer search direkt aus dem SearchQuery-Objekt verwendet.

    # Backend Specific Attributes
    
    return $self;
}

sub get_config {
    my ($self) = @_;

    return $self->{_config};
}

sub get_sessionID {
    my ($self) = @_;

    return $self->{_sessionID};
}

sub get_searchquery {
    my ($self) = @_;

    return $self->{_searchquery};
}

sub get_queryoptions {
    my ($self) = @_;

    return $self->{_queryoptions};
}

sub is_authority {
    my $self = shift;

    return $self->{_authority};
}

sub search {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $matches_ref = [];
    my $search_count = 0;
    
    $self->{resultcount}   = $search_count;
    $self->{_matches}      = $matches_ref;
    
    return $self;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $recordlist = $self->get_api->get_search_resultlist;

    return $recordlist;
}

sub matches {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self->{_matches}));
    }
    
    return @{$self->{_matches}};
}

sub querystring {
    my $self=shift;
    return $self->{_querystring};
}

sub have_results {
    my $self = shift;
    return ($self->{resultcount})?$self->{resultcount}:0;
}

sub get_resultcount {
    my $self = shift;
    return $self->{resultcount};
}

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Construct individual Querystring
    my $querystring = "";
    $self->{_querystring} = $querystring;

    return $self;
}

sub get_query {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_query};
}

sub get_facets {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_facets};
}

sub have_filter {
    my $self = shift;
    return (defined $self->{_filter} && @{$self->{_filter}})?1:0;
}

sub get_filter {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_filter};
}

sub get_number_of_documents {
    my ($self,$database)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;

    $database = (defined $database)?$database:
    (defined $self->{_database})?$self->{_database}:undef;

    return -1 unless $database;

    my $num = 0;

    # Insert Code to get Documents in Index
    
    return $num;
}       

sub get_database {
    my $self = shift;

    return $self->{_database};
}

sub get_api {
    my $self = shift;

    return $self->{api};
}

sub get_indexterms {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}      : undef;
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $indexterms_ref = [];

    # to implement ....

    return $indexterms_ref;    
}

sub get_values {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}      : undef;
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $values_ref = {};

    # to implement ...
    
    return $values_ref;
}

sub get_data {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}      : undef;
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $data = "";
    
    # to implement ....
        
    return $data;
}


# sub connectMemcached {
#     my $self = shift;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $config = get_config;
    
#     if (!defined $config->{memcached}){
#       $logger->debug("No memcached configured");
#       return;
#     }

#     # Verbindung zu Memchached herstellen
#     $self->{memc} = new Cache::Memcached::Fast(
# 	$config->{memcached},        
# 	compress_methods => [
#             sub { ${$_[1]} = Compress::LZ4::compress(${$_[0]})   },
#             sub { ${$_[1]} = Compress::LZ4::decompress(${$_[0]}) },
#         ],
# 	);

#     if (!$self->{memc}->set('isalive',1)){
#         $logger->fatal("Unable to connect to memcached");
#         $self->disconnectMemcached;
#     }

#     return;
# }

# sub disconnectMemcached {
#     my $self = shift;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     $logger->debug("Disconnecting memcached");
    
#     $self->{memc}->disconnect_all if (defined $self->{memc});
#     delete $self->{memc};

#     return;
# }

sub DESTROY {
    my $self = shift;

    return;
}

1;
