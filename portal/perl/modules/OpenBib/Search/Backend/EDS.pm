#####################################################################
#
#  OpenBib::Search::Backend::EDS
#
#  Dieses File ist (C) 2012-2019 Oliver Flimm <flimm@openbib.org>
#  Codebasis von ElasticSearch.pm
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

package OpenBib::Search::Backend::EDS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Storable;
use String::Tokenizer;
use URI::Escape;
use YAML ();

use OpenBib::API::HTTP::EDS;
use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::Search);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}        : undef;
    
    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}          : OpenBib::Config->new;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
	my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $database})->single;
	
	my $user     = $dbinfo_ref->remoteuser;
	my $password = $dbinfo_ref->remotepassword;
	my $profile  = $dbinfo_ref->remotepath;
	
	$logger->debug("EDS API-Credentials for db $database: $user - $password - $profile");
	
	if ($user && $password && $profile){
	    $arg_ref->{api_user}     = $user;
	    $arg_ref->{api_password} = $password;
	    $arg_ref->{api_profile}  = $profile;
	}
    };

    if ($@){
	$logger->error($@);
    }
    
    my $api = new OpenBib::API::HTTP::EDS($arg_ref);
    
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

sub get_resultcount {
    my $self = shift;

    return $self->get_api->get_resultcount;
}

sub get_autocorrected_terms {
    my $self = shift;
    
    return $self->get_api->get_autocorrected_terms;
}

sub get_autosuggested_terms {
     my $self = shift;
    
    return $self->get_api->get_autosuggested_terms;
}

sub get_date_range_start {
    my $self = shift;

    return $self>get_api->get_date_range_start;
}

sub get_date_range_end {
    my $self = shift;

    return $self>get_api->get_date_range_end;
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

