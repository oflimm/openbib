#####################################################################
#
#  OpenBib::API.pm
#
#  Objektorientiertes Interface zum Zugriff auf beliebige APIs
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

package OpenBib::API;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Record::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $self = { };

    bless ($self, $class);
    
    return $self;
}

sub get_titles_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
    ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : 'dbis';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });

    # Do stuff to get record information and popularte Record-Object
    
    return $record;
}

# Helper methods

sub get_config {
    my ($self) = @_;

    return $self->{_config};
}

sub get_client {
    my ($self) = @_;

    return $self->{client};
}

sub get_searchquery {
    my ($self) = @_;

    return $self->{_searchquery};
}

sub get_queryoptions {
    my ($self) = @_;

    return $self->{_queryoptions};
}

sub have_field_content {
    my ($self,$field,$content)=@_;

    my $have_field = 0;
    
    eval {
	$have_field = $self->{have_field_content}{$field}{$content};
    };

    $self->{have_field_content}{$field}{$content} = 1;

    return $have_field;
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

sub get_resultcount {
    my $self = shift;

    return $self->{resultcount};
}

sub get_persons {
    my ($self,$arg_ref) = @_;

    my $persons_ref = [];
    my $hits = 0;
    
    return {
	items => $persons_ref,
	hits  => $hits,
    };
}

sub get_corporatebodies {
    my ($self,$arg_ref) = @_;

    my $corporatebodies_ref = [];
    my $hits = 0;
    
    return {
	items => $corporatebodies_ref,
	hits => $hits,
    };
}

sub get_classifications {
    my ($self,$arg_ref) = @_;

    my $classifications_ref = [];
    my $hits = 0;
    
    return {
	items => $classifications_ref,
	hits => $hits,
    };
}

sub get_subjects {
    my ($self,$arg_ref) = @_;

    my $subjects_ref = [];
    my $hits = 0;
    
    return {
	items => $subjects_ref,
	hits => $hits,
    };
}

sub DESTROY {
    my $self = shift;

    return;
}

1;
