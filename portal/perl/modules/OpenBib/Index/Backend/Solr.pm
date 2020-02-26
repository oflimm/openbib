#####################################################################
#
#  OpenBib::Index::Backend::Solr
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
#
#  basiert auf OpenBib::Index::Backend::ElasticSearch
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

package OpenBib::Index::Backend::Solr;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Catmandu::Importer::Solr;
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Common::Util;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::Index);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database         = exists $arg_ref->{database}
        ? $arg_ref->{database}                      : undef;

    my $indextype        = exists $arg_ref->{index_type}
        ? $arg_ref->{index_type}                    : 'readonly';

    my $createindex      = exists $arg_ref->{create_index}
        ? $arg_ref->{create_index}                  : undef;

    my $self = { };

    bless ($self, $class);

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    $self->{config} = $config;
    
    unless ($database){
        $logger->error("No database argument given");
        return $self;
    }
    
    if ($database){
        $self->{_database}      = $database;

        {   # get locationid and save to object
            my $locationid = $config->get_locationid_of_database($database);
            my $locationid_norm =  OpenBib::Common::Util::normalize({ content => $locationid});
            $locationid_norm=~s/\W/_/g;
            $self->{_locationid}      = $locationid;
            $self->{_locationid_norm} = $locationid_norm;
        }
    }

    $logger->debug("Creating elasticsearch DB-Object for database $self->{_database}");

    my $solr_base = $config->get('solr')->{base_url};
    
    eval {
    	my $store = Catmandu::Store::Solr->new(url => $solr_base, bag_field => 'db', id_field => 'fullid' );

    	if ($createindex){
    	    $store->transaction(sub{
    		$store->bag($database)->delete_all();
		$store->bag($database)->commit();
  #  		die("oops, didn't want to do that!");
    				});
    	}
	

    	$self->{_index} = $store->bag($database);
    };
    
    if ($@) {
        $logger->error("Database: $self->{_database} - :".$@);
        return $self;
    }        
        
    # Backend Specific Attributes
    
    return $self;
}

sub get_index {
    my $self         = shift;

    return $self->{_index};
}

sub set_stopper {
    my $self         = shift;

    # my $config = $self->{config};
    
    # my $stopwordfile = shift || $config->{stopword_filename};

    # my $stopword_ref={};
    
    # if (-e $stopwordfile){
    #     open(SW,$stopwordfile);
    #     while (my $stopword=<SW>){
    #         chomp $stopword ;
    #         $stopword = OpenBib::Common::Util::normalize({
    #             content  => $stopword,
    #         });
            
    #         $stopword_ref->{$stopword}=1;
    #     }
    #     close(SW);
    # }

    # my $stopwords = join(' ',keys %$stopword_ref);
    
    # $self->{_stopper} = ...

    return $self;
}

sub have_stopper {
    my $self = shift;

    if (defined $self->{_stopper}){
        return 1;
    }
   
    return 0;
}

sub get_stopper {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->have_stopper){
        return $self->{_stopper};
    }

    $logger->fatal("No stopper defined");
    
    return undef;
}

sub set_termgenerator {
    my $self = shift;

#    $self->{_tg} = new Search::Xapian::TermGenerator();
#    $self->{_tg}->set_stopper($self->get_stopper);

    return $self;
}

sub have_termgenerator {
    my $self = shift;

    if (defined $self->{_tg}){
        return 1;
    }
   
    return 0;
}

sub get_termgenerator {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->have_termgenerator){
        return $self->{_tg};
    }

    $logger->fatal("No termgenerator defined");
    
    return undef;
}

sub create_document {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $document    = exists $arg_ref->{document}
        ? $arg_ref->{document}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # We always need a stopper 
    if (!$self->have_stopper){
        $self->set_stopper;
    }

    # and a termgenerator (which in turn needs a stopper)
    if (!$self->have_termgenerator){
        $self->set_termgenerator;
    }
    
    my $config = $self->{config};

    my $index_ref  = $document->get_index;
    my $record_ref = $document->get_data;

    my $id            = $record_ref->{id};
    my $thisdbname    = $record_ref->{database};
    my $locations_ref = $record_ref->{locations};
    
    my $doc_ref = {
	fullid     => "$thisdbname:$id",
	id         => $id,
	db         => $thisdbname,
	fullrecord => encode_json($record_ref),
    };

    # Searchfields
    foreach my $searchfield (keys %{$config->{searchfield}}) {
	next if ($searchfield eq "id" || $searchfield eq "db" || $searchfield eq "dbstring");
	my $searchfield_content_ref = [];
	foreach my $xapian_weight (keys %{$index_ref->{$searchfield}}){
	    foreach my $item_ref (@{$index_ref->{$searchfield}{$xapian_weight}}){
		push @$searchfield_content_ref, $item_ref->[1];
	    }
	}
	$doc_ref->{$searchfield} = $searchfield_content_ref;
    }

    # Facets
    foreach my $type (keys %{$config->{xapian_facet_value}}){
	my %seen_terms = ();
        my @unique_terms = grep { defined $_ && ! $seen_terms{$_} ++ } @{$index_ref->{"facet_".$type}}; 

	$doc_ref->{"facet_$type"} = \@unique_terms;
    }
    
    $logger->debug(encode_json($doc_ref));
    
    return $doc_ref;
}

sub create_record {
    my ($self,$doc) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Creating Record $doc->{id} - ".ref($doc));
    
    eval {
	$self->get_index->add($doc);
    };
    
    if ($@){
        $logger->error($@);
    }

    return $self;
}

sub update_record {
    my ($self,$id,$new_doc) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->{config};

    $logger->error("Not implemented yet!");

    return $self;    
}

sub delete_record {
    my ($self,$id) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->{config};

    $logger->error("Not implemented yet!");

    return $self;
}

sub commit {
    my ($self,$doc) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Commit");
    
    eval {
	$self->get_index->commit();
    };
    
    if ($@){
        $logger->error($@);
    }

    return $self;
}

1;

