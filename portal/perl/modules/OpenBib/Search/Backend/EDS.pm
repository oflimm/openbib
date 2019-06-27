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

    # Used Parameters
    my $sorttype          = $queryoptions->get_option('srt');
    my $sortorder         = $queryoptions->get_option('srto');
    my $defaultop         = $queryoptions->get_option('dop');
    my $drilldown         = $queryoptions->get_option('dd');

    # Pagination parameters
    my $page              = $queryoptions->get_option('page');
    my $num               = $queryoptions->get_option('num');

    my $from              = ($page - 1)*$num;
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);
    
    $self->connect_eds($ua);

    if ($logger->is_debug){
	$logger->debug("Setting default header with x-authenticationToken: ".$self->get_authtoken." and x-sessionToken: ".$self->get_sessiontoken);
    }

    $ua->default_header('x-authenticationToken' => $self->get_authtoken, 'x-sessionToken' => $self->get_sessiontoken);

    my $url = $config->get('eds')->{'search_url'};

    # search options
    my @search_options = ();

    # Default
    push @search_options, "sort=relevance";
    push @search_options, "searchmode=all";
    push @search_options, "highlight=n";
    push @search_options, "includefacets=y";
    push @search_options, "autosuggest=n";
    push @search_options, "view=brief";
    #push @search_options, "view=detailed";    
    
    push @search_options, "resultsperpage=$num" if ($num);
    push @search_options, "pagenumber=$page" if ($page);

    $self->parse_query($searchquery);

    my $query_ref  = $self->get_query;
    my $filter_ref = $self->get_filter;

    push @$query_ref, @$filter_ref;    
    push @$query_ref, @search_options;
    
    my $args = join('&',@$query_ref);
    
    $url = $url."?$args";

    if ($logger->is_debug()){
	$logger->debug("Request URL: $url");
    }

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $request = HTTP::Request->new('GET' => $url);
    $request->content_type('application/json');
    
    my $response = $ua->request($request);

  
    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $searchtime   = timestr($stimeall,"nop");
	$searchtime      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Zeit fuer EDS HTTP-Request $searchtime");
    }
    


    if (!$response->is_success) {
	$logger->error($response->code . ' - ' . $response->message . " - ".$response->content);

	return;
    }

    
    $logger->info('ok');

    my $json_result_ref = {};
    
    eval {
	$json_result_ref = decode_json $response->content;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
    }
    
    # my $results = $es->search(
    #     index  => $index,
    #     type   => 'title',
    # 	body   => $body_ref,
    # );

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

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    # Aufbau des eds searchquerystrings
    my @eds_querystrings = ();
    my $eds_querystring  = "";

    # Aufbau des eds_filterstrings
    my @eds_filterstrings = ();
    my $eds_filterstring  = "";

    my $ops_ref = {
        'AND'     => 'AND ',
        'AND NOT' => 'NOT ',
        'OR'      => 'OR ',
    };

    my $query_count = 1;
    
    my $query_ref = [];

    my $mapping_ref = $config->get('eds_searchfield_mapping');
    
    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{val})?$searchquery->get_searchfield($field)->{val}:'';

        my $searchtermstring_from = (defined $searchquery->get_searchfield("${field}_from")->{norm})?$searchquery->get_searchfield("${field}_from")->{norm}:'';
        my $searchtermstring_to = (defined $searchquery->get_searchfield("${field}_to")->{norm})?$searchquery->get_searchfield("${field}_to")->{norm}:'';

	if ($field eq "year" && ($searchtermstring_from || $searchtermstring_to)){
	    if ($searchtermstring_from && $searchtermstring_to){
		push @$query_ref, "query-".$query_count."=AND%2CDT:".cleanup_eds_query($searchtermstring_from."-".$searchtermstring_to);
	    }
	    elsif ($searchtermstring_from){
		push @$query_ref, "query-".$query_count."=AND%2CDT:".cleanup_eds_query($searchtermstring_from."-9999");
	    }
	    elsif ($searchtermstring_to){
		# Keine Treffer im API, wenn aelter als 1800
		push @$query_ref, "query-".$query_count."=AND&2CDT:".cleanup_eds_query("1800-".$searchtermstring_to);
	    }
    	}	
        elsif ($searchtermstring) {
	    
	    if (defined $mapping_ref->{$field}){
		if ($mapping_ref->{$field} eq "TX"){
		    push @$query_ref, "query-".$query_count."=AND%2C".cleanup_eds_query($searchtermstring);
		}
		else {
		    push @$query_ref, "query-".$query_count."=AND%2C".$mapping_ref->{$field}.":".cleanup_eds_query($searchtermstring);
		}
		
		#push @$query_ref, "query-".$query_count."=AND%2C".cleanup_eds_query($mapping_ref->{$field}.":".$searchtermstring);
		$query_count++;
	    }
        }
    }

    # Filter

    my $filter_count = 1;
    
    my $filter_ref = [];

    if ($logger->is_debug){
        $logger->debug("All filters: ".YAML::Dump($searchquery->get_filter));
    }

    my $eds_reverse_facet_mapping_ref = $config->get('eds_reverse_facet_mapping');
    
    if (@{$searchquery->get_filter}){
        $filter_ref = [ ];
        foreach my $thisfilter_ref (@{$searchquery->get_filter}){
            my $field = $eds_reverse_facet_mapping_ref->{$thisfilter_ref->{field}};
            my $term  = $thisfilter_ref->{term};
#            $term=~s/_/ /g;
            
            $logger->debug("Facet: $field / Term: $term (Filter-Field: ".$thisfilter_ref->{field}.")");

	    if ($field && $term){
		push @$filter_ref, "facetfilter=".cleanup_eds_filter($filter_count.",$field:$term");
		$filter_count++;
	    }
        }
	
    }

    if ($logger->is_debug){
        $logger->debug("Query: ".YAML::Dump($query_ref));
        $logger->debug("Filter: ".YAML::Dump($filter_ref));
    }

    $self->{_query}  = $query_ref;
    $self->{_filter} = $filter_ref;

    return $self;
}

sub _create_authtoken {
    my ($self,$ua) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    
    if (!$ua){
	$ua = LWP::UserAgent->new();
	$ua->agent('USB Koeln/1.0');
	$ua->timeout(30);
    }

    my $request = HTTP::Request->new('POST' => $config->get('eds')->{auth_url});
    $request->content_type('application/json');

    my $json_request_ref = {
	'UserId'   => $config->get('eds')->{userid},
	'Password' => $config->get('eds')->{passwd},
    };
    
    $request->content(encode_json($json_request_ref));

    if ($logger->is_debug){
	$logger->info("JSON-Request: ".encode_json($json_request_ref));
    }
    
    my $response = $ua->request($request);

    if ($response->is_success) {
	if ($logger->is_debug()){
	    $logger->debug($response->content);
	}

	my $json_result_ref = {};

	eval {
	    $json_result_ref = decode_json $response->content;
	};

	if ($@){
	    $logger->error('Decoding error: '.$@);
	}
	
	if ($json_result_ref->{AuthToken}){
	    return $json_result_ref->{AuthToken};
	}
	else {
	    $logger->error('No AuthToken received'.$response->content);
	}
    } 
    else {
	$logger->error('Error in Request: '.$response->code.' - '.$response->message);
    }

    return;
}

sub _create_sessiontoken {
    my ($self, $authtoken, $ua) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    
    if (!$ua){
	$ua = LWP::UserAgent->new();
	$ua->agent('USB Koeln/1.0');
	$ua->timeout(30);
    }
    
    my $guest = 'n';

    my $request = HTTP::Request->new('POST' => $config->get('eds')->{session_url});
    $request->content_type('application/json');

    my $json_request_ref = {
	'Profile' => $config->get('eds')->{profile},
	'Guest'   => $guest,
    };

    my $json = encode_json $json_request_ref;
    
    $request->content($json);

    if ($logger->is_debug){
	$logger->info("JSON-Request: ".encode_json($json_request_ref));
    }

    $ua->default_header('x-authenticationToken' => $authtoken);
    
    my $response = $ua->request($request);

    if ($response->is_success) {
	if ($logger->is_debug()){
	    $logger->debug($response->content);
	}

	my $json_result_ref = {};

	eval {
	    $json_result_ref = decode_json $response->content;
	};
	
	if ($@){
	    $logger->error('Decoding error: '.$@);
	}
	
	if ($json_result_ref->{SessionToken}){
	    return $json_result_ref->{SessionToken};
	}
	else {
	    $logger->error('No SessionToken received'.$response->content);
	}

    } 
    else {
	$logger->error('Error in Request: '.$response->code.' - '.$response->message);
    }

    return;
}

sub connect_eds {
    my ($self,$ua) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    if (!$ua){
	$ua = LWP::UserAgent->new();
	$ua->agent('USB Koeln/1.0');
	$ua->timeout(30);
    }
    
    $self->{authtoken} = $self->_create_authtoken($ua);

    # second try... just in case ;-)
    if (!$self->{authtoken}){
	$self->{authtoken}  = $self->_create_authtoken($ua);
    }

    if (!$self->{authtoken}){
	$logger->error('No AuthToken available. Exiting...');
	return;	
    }
    
    $self->{sessiontoken} = $self->_create_sessiontoken($self->{authtoken},$ua);

    # second try... just in case ;-)
    if (!$self->{sessiontoken}){
	$self->{sessiontoken} = $self->_create_sessiontoken($self->{authtoken});
    }

    if (!$self->{sessiontoken}){
	$logger->error('No SessionToken available. Exiting...');
	return;	
    }

    return;
};

sub get_authtoken {
    my $self = shift;
    return $self->{authtoken};
}

sub get_sessiontoken {
    my $self = shift;
    return $self->{sessiontoken};
}

sub cleanup_eds_query {
    my $content = shift;

    $content =~ s{(,|\:|\(|\))}{\\$1}g;
 #   $content =~ s{\[}{%5B}g;
 #   $content =~ s{\]}{%5D}g;
    $content =~ s{\s+\-\s+}{ }g;
    $content =~ s{\s\s}{ }g;
    $content =~ s{^\s+|\s+$}{}g;
    $content =~ s{\s+(and|or|not)\s+}{ }gi;
#    $content =~ s{ }{\+}g;

    $content = uri_escape_utf8($content);
    
     # Runde Klammern in den Facetten duerfen nicht escaped und URL-encoded werden!
#    $content =~ s{\%5C\%28}{(}g; 
#    $content =~ s{\%5C\%29}{)}g;

    
    return $content;
}

sub cleanup_eds_filter {
    my $content = shift;

    $content = uri_escape_utf8($content);
    
     # Runde Klammern in den Facetten duerfen nicht escaped und URL-encoded werden!
    $content =~ s{\%5C\%28}{(}g; 
    $content =~ s{\%5C\%29}{)}g;

    
    return $content;
}

1;

