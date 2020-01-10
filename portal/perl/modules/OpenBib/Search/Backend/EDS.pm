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

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::API::HTTP::EDS;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::Search);

sub search {
    my ($self) = @_;

    # Set defaults search parameters
#    my $serien            = exists $arg_ref->{serien}
#        ? $arg_ref->{serien}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;
    my $sessionID    = $self->get_sessionID;
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $arg_ref = {
	searchquery  => $searchquery,
	queryoptions => $queryoptions
    };
    
    my $eds = new OpenBib::API::HTTP::EDS($arg_ref);

    my $json_result_ref = $eds->search();
    
    my @matches = $self->process_matches($json_result_ref);

    $self->process_facets($json_result_ref);
        
#    if ($logger->is_debug){
#        $logger->debug("Found matches ".YAML::Dump(\@matches));
#    }
    
    # # Facets
    # $self->{categories} = $results->{aggregations};

#    if ($logger->is_debug){
#	$logger->debug("Results: ".YAML::Dump(\@matches));
#    }

    my $resultcount = $json_result_ref->{SearchResult}{Statistics}{TotalHits};

    $self->{resultcount} = $resultcount;

    if ($logger->is_debug){
         $logger->info("Found ".$self->{resultcount}." titles");
    }

    
    $self->{_matches}     = \@matches;


    # if ($logger->is_debug){
    #     $logger->info("Running query ".YAML::Dump($self->{_querystring})." with filters ".YAML::Dump($self->{_filter}));
    # }

#    $logger->info("Found ".scalar(@matches)." matches in database $self->{_database}") if (defined $self->{_database});

    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $searchtime   = timestr($stimeall,"nop");
	$searchtime      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Gesamtzeit fuer EDS-Suche $searchtime");
    }

    return;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;

    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;

    $self->matches;

#    if ($logger->is_debug){
#        $logger->debug(YAML::Dump(\@matches));
#    }

    foreach my $match (@matches) {

        my $id            = OpenBib::Common::Util::encode_id($match->{database}."::".$match->{id});
	my $fields_ref    = $match->{fields};

        $recordlist->add(OpenBib::Record::Title->new({database => 'eds', id => $id })->set_fields_from_storable($fields_ref));
    }

    # if ($logger->is_debug){
    # 	$logger->debug("Result-Recordlist: ".YAML::Dump($recordlist->to_list))
    # }
    
    return $recordlist;
}

sub process_matches {
    my ($self,$json_result_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;
    
    my @matches = ();
    
    foreach my $match (@{$json_result_ref->{SearchResult}{Data}{Records}}){
	my $fields_ref = {};

	my ($atime,$btime,$timeall);
	
	if ($config->{benchmark}) {
	    $atime=new Benchmark;
	}


	# Gesamtresponse in eds_source
	push @{$fields_ref->{'eds_source'}}, {
	    content => $match
	};
	
	# $logger->debug("Processing Record ".YAML::Dump($json_result_ref->{SearchResult}{Data}{Records}));
	foreach my $thisfield (keys %{$match->{RecordInfo}{BibRecord}{BibEntity}}){
	    
	    if ($thisfield eq "Titles"){
		foreach my $item (@{$match->{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		    push @{$fields_ref->{'T0331'}}, {
			content => $item->{TitleFull}
		    } if ($item->{Type} eq "main");
		    
		}
	    }
	}

	if (defined $match->{RecordInfo}{BibRecord} && defined $match->{RecordInfo}{BibRecord}{BibRelationships}){

	    if (defined $match->{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}){
		foreach my $item (@{$match->{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}}){
#		    $logger->debug("DebugRelationShips".YAML::Dump($item));
		    if (defined $item->{PersonEntity} && defined $item->{PersonEntity}{Name} && defined $item->{PersonEntity}{Name}{NameFull}){
			
			push @{$fields_ref->{'P0100'}}, {
			    content => $item->{PersonEntity}{Name}{NameFull},
			}; 
			
			push @{$fields_ref->{'PC0001'}}, {
			    content => $item->{PersonEntity}{Name}{NameFull},
			}; 
		    }
		}
	    }


	    if (defined $match->{RecordInfo}{BibRecord}{BibRelationships}{IsPartOfRelationships}){
		foreach my $partof_item (@{$match->{RecordInfo}{BibRecord}{BibRelationships}{IsPartOfRelationships}}){
		    if (defined $partof_item->{BibEntity}){
		
			foreach my $thisfield (keys %{$partof_item->{BibEntity}}){
			    
			    if ($thisfield eq "Titles"){
				foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    push @{$fields_ref->{'T0451'}}, {
					content => $item->{TitleFull}
				    };
				    
				}
			    }
			    
			    if ($thisfield eq "Dates"){
				foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    push @{$fields_ref->{'T0425'}}, {
					content => $item->{'Y'}
				    };
				    
				}
			    }
			}
		    }
		    
		}
	    }
	    
	}
	
        push @matches, {
            database => $match->{Header}{DbId},
            id       => $match->{Header}{An},
            fields   => $fields_ref,
        };

	if ($config->{benchmark}) {
	    my $stime        = new Benchmark;
	    my $stimeall     = timediff($stime,$atime);
	    my $parsetime   = timestr($stimeall,"nop");
	    $parsetime      =~s/(\d+\.\d+) .*/$1/;
	    
	    $logger->info("Zeit um Treffer zu parsen $parsetime");
	}

    }

    return @matches;
}

sub process_facets {
    my ($self,$json_result_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $ddatime   = new Benchmark;


    my $fields_ref = {};
    
    my $category_map_ref     = ();
    
    # Transformation Hash->Array zur Sortierung

    $logger->debug("Start processing facets: ".YAML::Dump($json_result_ref->{SearchResult}{AvailableFacets}));
    
    foreach my $eds_facet (@{$json_result_ref->{SearchResult}{AvailableFacets}}){

	my $id   = $eds_facet->{Id};
	my $type = $config->get('eds_facet_mapping')->{$id};

	$logger->debug("Process Id $id and type $type");
	
	next unless (defined $type) ;
	
        my $contents_ref = [] ;
        foreach my $item_ref (@{$eds_facet->{AvailableFacetValues}}) {
            push @{$contents_ref}, [
                $item_ref->{Value},
                $item_ref->{Count},
            ];
        }
        
        if ($logger->is_debug){
            $logger->debug("Facet for type $type ".YAML::Dump($contents_ref));
        }
        
        # Schwartz'ian Transform

        @{$category_map_ref->{$type}} = map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
                map { [$_, $_->[1]] }
                    @{$contents_ref};
    }

    if ($logger->is_debug){
	$logger->debug("All Facets ".YAML::Dump($category_map_ref));
    }

    my $ddbtime       = new Benchmark;
    my $ddtimeall     = timediff($ddbtime,$ddatime);
    my $drilldowntime    = timestr($ddtimeall,"nop");
    $drilldowntime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info("Zeit fuer categorized drilldowns $drilldowntime");

    $self->{_facets} = $category_map_ref;
    
    return; 
}

sub get_facets {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_facets};
}

1;

