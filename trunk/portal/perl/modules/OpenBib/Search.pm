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

use Apache2::Reload;
use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode qw(decode decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

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
        ? $arg_ref->{authority}       : undef;
    
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
    
    # Achtung: searchprofile und database werden fuer search direkt aus dem SearchQuery-Objekt verwendet.

    # Backend Specific Attributes
    
    return $self;
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

    my $recordlist = new OpenBib::RecordList::Title;

    my @matches = $self->matches;
    
    foreach my $match_ref (@matches) {        
        if ($logger->is_debug){
            $logger->debug("Record: ".$match_ref );
        }

        # Create and populate record

        # and add to recordlist
    }

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

sub get_facets {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return {};
}

sub DESTROY {
    my $self = shift;

    return;
}

1;
