#####################################################################
#
#  OpenBib::Search::Backend::DBIS.pm
#
#  Objektorientiertes Interface zum DBIS XML-API
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Backend::DBIS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode qw(decode decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::API::HTTP::DBIS;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Catalog::Factory;

use base qw(OpenBib::Search);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Processing access rights
    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;
    
    $arg_ref->{access_green}    = $queryoptions->get_option('access_green') || 0;
    $arg_ref->{access_yellow}   = $queryoptions->get_option('access_yellow') || 0;
    $arg_ref->{access_ppu}      = $queryoptions->get_option('access_ppu') || 0;
    $arg_ref->{access_national} = $queryoptions->get_option('access_national') || 0;
    $arg_ref->{access_red}      = $queryoptions->get_option('access_red') || 0;
    $arg_ref->{srt}             = $queryoptions->get_option('srt') || '';
    
    my $api = new OpenBib::API::HTTP::DBIS($arg_ref);
    
    my $self = { };

    bless ($self, $class);

    $self->{api}  = $api;
    $self->{args} = $arg_ref;
          
    return $self;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->get_api->search($arg_ref);
        
    return $self;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;

    my $catalog = OpenBib::Catalog::Factory->create_catalog($self->{args});
    
    my $classifications_ref = $catalog->get_classifications;

    my $popular_records = new OpenBib::RecordList::Title;

    my $searchquery = $self->{args}{searchquery};

    my $gebiet = 0;

    if (ref $searchquery eq "OpenBib::SearchQuery"){
	$gebiet = $searchquery->get_searchfield('classification')->{val};
    }
    
    if ($gebiet){
	$popular_records = $self->get_api->get_popular_records($gebiet);
    }
    
    my $container = OpenBib::Container->instance;

    $container->register('classifications_dbis',$classifications_ref->{items});
    $container->register("popular_dbis_records_$gebiet",$popular_records->to_serialized_reference);    

    if ($logger->is_debug){    
	$logger->debug(YAML::Dump($classifications_ref));
	$logger->debug("Popular".YAML::Dump($popular_records->to_serialized_reference));
    }
    
    my $recordlist = $self->get_api->get_search_resultlist;

    return $recordlist;
}

sub get_resultcount {
    my $self = shift;

    return $self->get_api->get_resultcount;
}

sub get_facets {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->get_api->get_facets;    
}

sub have_results {
    my $self = shift;

    my $resultcount = $self->get_api->get_resultcount;
    
    return ($resultcount)?$resultcount:0;
}

1;
__END__

=head1 NAME

OpenBib::Search::Backend::DBIS - Objektorientiertes Interface zum DBIS XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API des
Datenbankinformationssystems (DBIS) in Regensburg für Rechercheanfragen zugegriffen werden.

=head1 SYNOPSIS

=head1 METHODS

=over 4

=item XXX

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
