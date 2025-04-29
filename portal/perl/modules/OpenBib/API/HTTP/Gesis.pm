#####################################################################
#
#  OpenBib::API::HTTP::Gesis.pm
#
#  Objektorientiertes Interface zum HTTP JSON-API von Gesis
#
#  basiert auf OpenBib::API::HTTP
#
#  Dieses File ist (C) 2022- Oliver Flimm <flimm@openbib.org>
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

package OpenBib::API::HTTP::Gesis;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Storable;
use JSON::XS;
use URI::Escape;
use WWW::Curl::Easy;
use YAML ();
use Mojo::Base -strict, -signatures;

use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::API);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}     : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;
    
    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;

    my $userinfo       = exists $arg_ref->{userinfo}
        ? $arg_ref->{userinfo}                : $config->{elasticsearch}{userinfo};

    my $cxn_pool       = exists $arg_ref->{cxn_pool}
        ? $arg_ref->{cxn_pool}                : $config->{elasticsearch}{cxn_pool};

    my $nodes       = exists $arg_ref->{nodes}
        ? $arg_ref->{nodes}                   : $config->{elasticsearch}{nodes};
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    my $curl = WWW::Curl::Easy->new;
    $self->{client}        = $curl;
    
    # my $ua = LWP::UserAgent->new();
    # $ua->agent('USB Koeln/1.0');
    # $ua->timeout(30);

    # $self->{client}        = $ua;
        
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

sub send_retrieve_request {
    my ($self,$arg_ref) = @_;
    
    # Set defaults
    my $id       = exists $arg_ref->{id}
    ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;


    my $url = $config->get('gesis')->{'search_url'};

    # my $header = ['Content-Type' => 'application/json; charset=UTF-8'];
    # my $json_query_ref = {
    # 	'query' => { bool => { must => { match => { _id => $id}}}},
    # };

    # # my $encoded_json = encode_utf8(encode_json($json_query_ref));
    # my $encoded_json = encode_json($json_query_ref);

    # if ($logger->is_debug){
    # 	$logger->debug("Gesis JSON Query: $encoded_json");
    # }
    
    # my $request = HTTP::Request->new('POST',$url,$header,$encoded_json);
    
    # my $response = $ua->request($request);

    # if ($logger->is_debug()){
    # 	$logger->debug("Request URL: $url");
    # }
    
    # if ($logger->is_debug){
    # 	$logger->debug("Response: ".$response->content);
    # }
    
    # if (!$response->is_success && $response->code != 400) {
    # 	$logger->info($response->code . ' - ' . $response->message);
    # 	return;
    # }

    my $json_query_ref = {
    	'query' => { bool => { must => { match => { _id => $id}}}},
    };

    my $encoded_json = encode_json($json_query_ref);

    if ($logger->is_debug){
	$logger->debug("Gesis JSON Query: $encoded_json");
    }

    $ua->setopt(WWW::Curl::Easy::CURLOPT_HEADER(), 0);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_URL(), $url);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(), ['Content-Type: application/json; charset=UTF-8']);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_POST(), 1);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_POSTFIELDS(), $encoded_json);


    my $response;
    $ua->setopt(WWW::Curl::Easy::CURLOPT_WRITEDATA(), \$response);
    
    my $retcode = $ua->perform;
    if ($retcode != 0) {
	$logger->error('Decoding error: '.$ua->errbuf.' with code '.$retcode);
    }

    if ($logger->is_debug){
	$logger->debug("Gesis response: $response");
    }
    
    my $json_result_ref = {};
    
    eval {
	$json_result_ref = decode_json $response;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
    }
    
    return $json_result_ref;
}

sub send_search_request {
    my ($self,$arg_ref) = @_;

    # Set defaults search parameters
#    my $serien            = exists $arg_ref->{serien}
#        ? $arg_ref->{serien}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;

    # Used Parameters
    my $sorttype          = $queryoptions->get_option('srt')  || 'year';
    my $sortorder         = $queryoptions->get_option('srto') || 'desc';
    my $defaultop         = $queryoptions->get_option('dop');
    my $drilldown         = $queryoptions->get_option('dd');

    # Pagination parameters
    my $page              = $queryoptions->get_option('page') || 1;
    my $num               = $queryoptions->get_option('num')  || 10;

    my $from              = ($page - 1)*$num;
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    # Wenn srto in srt enthalten, dann aufteilen
    if ($sorttype =~m/^([^_]+)_([^_]+)$/){
        $sorttype=$1;
        $sortorder=$2;
        $logger->debug("srt Option split: srt = $sorttype, srto = $sortorder");
    }
    
    my $ua     = $self->get_client;
    
    $self->parse_query($searchquery);

    my $facets_ref = {};

    foreach my $facet (keys %{$config->{elasticsearch_facet_field}{gesis}}){
        $facets_ref->{"$facet"} = {
            terms => {
                field => $config->{elasticsearch_facet_field}{gesis}{$facet},
                size  => 25,
            }
        };
    }
	
    # Facetten filtern
	
    # foreach my $filter (keys %{$querystring->{filter}}){
    # 	$facets_ref->{$filter}{facet_filter}{term} = {
    # 	    "${filter}string" => $querystring->{filter}{$filter},
    # 	};
    # }    
    
    my $query_ref  = $self->get_query;
    my $filter_ref = $self->get_filter;

    if ($logger->is_debug){
	$logger->debug("Filter: ".YAML::Dump($filter_ref));
    }
    
    my $sort_ref = [];
    
    $logger->debug("Sorting with $sorttype and order $sortorder");

    # my $sortconf = $config->get('elasticsearch_facet_field')->{gesis};
    
    # if (defined $sortconf->{$sorttype}){
    # 	push @$sort_ref, { "$sortconf->{$sorttype}{field}" => { order => $sortorder }};
    # }
    # else { # Default by relevance
    #     push @$sort_ref, { "_score" => { order => 'desc' }};
    # }

    # Always sort by relevance
    push @$sort_ref, { "_score" => { order => 'desc' }};
    
    if ($logger->is_debug){
	$logger->debug("Sort ".YAML::Dump($sort_ref));
    }

    my $body_ref = {
	aggregations => $facets_ref,
	from   => $from,
	size   => $num,
	sort   => $sort_ref,
    };

    $body_ref->{query} = {
	bool => $query_ref,
    };
    
    if ($self->have_filter){
	$body_ref->{query}{bool}{filter} = $filter_ref;
    }
    else {
    }
    
    if ($logger->is_debug){
	$logger->debug("Request body ".YAML::Dump($body_ref));
    }

    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $timespan   = timestr($stimeall,"nop");
	$timespan      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Zeit fuer das Preprocessing der Suche $timespan");
    }
    
    my $url = $config->get('gesis')->{'search_url'};

    my $encoded_json = encode_json($body_ref);    

    $logger->debug("ElasticSearch JSON Query: $encoded_json");

    $ua->setopt(WWW::Curl::Easy::CURLOPT_HEADER(), 0);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_URL(), $url);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_HTTPHEADER(), ['Content-Type: application/json; charset=UTF-8']);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_POST(), 1);
    $ua->setopt(WWW::Curl::Easy::CURLOPT_POSTFIELDS(), $encoded_json);


    my $response;
    $ua->setopt(WWW::Curl::Easy::CURLOPT_WRITEDATA(), \$response);
    
    my $retcode = $ua->perform;
    if ($retcode != 0) {
	$logger->error('Decoding error: '.$ua->errbuf.' with code '.$retcode);
    }

    
    # my $header = ['Content-Type' => 'application/json; charset=UTF-8'];


    # my $encoded_json = encode_json($body_ref);    

    # $logger->debug("ElasticSearch JSON Query: $encoded_json");

    # my $request = HTTP::Request->new('POST',$url,$header,$encoded_json);
    
    # my $response = $ua->request($request);

    $logger->debug("Result: ".$response);

    my $results = {};
    
    # eval {
    # 	$results = decode_json $response->content;
    # };

    eval {
	$results = decode_json $response;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
    }

    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $timespan   = timestr($stimeall,"nop");
	$timespan      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Zeit fuer das Preprocessing und die Suche $timespan");
    }
    
    return $results;
}


sub get_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
        ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $json_result_ref = $self->send_retrieve_request($arg_ref);

    my $record = new OpenBib::Record::Title({ database => $database, id => $id });

    if ($logger->is_debug){
	$logger->debug("Gesis Hits: ".$json_result_ref->{hits}{total}{value});
	$logger->debug("Gesis JSON response: ".YAML::Dump($json_result_ref));
    }

    return $record if ($json_result_ref->{hits}{total}{value} != 1);

    if ($logger->is_debug){
	$logger->debug("Mapping response fields");
    }
    
    my $fields_ref = $self->match2fields($json_result_ref->{hits}{hits}[0]);

    $record->set_fields_from_storable($fields_ref);
    
    $record->set_holding([]);
    $record->set_circulation([]);
    
    return $record;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $json_result_ref = $self->send_search_request($arg_ref);

    my @matches = $self->process_matches($json_result_ref);

    $self->process_facets($json_result_ref);

    my $resultcount = $json_result_ref->{hits}{total}{value};
	
    if ($logger->is_debug){
        $logger->debug("Results: ".YAML::Dump($json_result_ref));
    }
    
    $self->{resultcount} = $resultcount;
    $self->{_matches}     = \@matches;
    
    return $self;
}

sub get_search_resultlist {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;
    
    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;

    foreach my $match_ref (@matches) {
	if ($logger->is_debug){
	    $logger->debug("Match ref: ".YAML::Dump($match_ref));
	}

        my $id            = OpenBib::Common::Util::encode_id($match_ref->{id});
	my $database      = $match_ref->{database};	
	my $fields_ref    = $match_ref->{fields};

        $recordlist->add(OpenBib::Record::Title->new({database => $database, id => $id })->set_fields_from_storable($fields_ref));
    }

    return $recordlist;
}

sub process_matches {
    my ($self,$results) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;
    
    my @matches = ();
    foreach my $match_ref (@{$results->{hits}->{hits}}){
	my ($atime,$btime,$timeall);
	
	if ($config->{benchmark}) {
	    $atime=new Benchmark;
	}

	my $fields_ref = $self->match2fields($match_ref);
		
        push @matches, {
            database => 'gesis', # set static. seems to be alias. request gets something like gesis_2022_04_01
            id       => $match_ref->{_id},
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
    
    if ($logger->is_debug){
        $logger->debug("Found matches ".YAML::Dump(\@matches));
    }

    return @matches;
}

sub match2fields {
    my ($self,$match_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $single_field_map_ref = {
	'title'    => "T0331",
	    'language'   => "T0015",
	    'issn'       => "T0543",
	    'source'     => "T0590",
	    'publisher'  => "T0412",
	    'date'       => "T0425",
	    'abstract'   => "T0750",
	    'format'     => "T0435",
	    'coverage'   => "T0433",
	    'data_source' => "T0590",	    	    
    };
    
    my $fields_ref = {};
    
    my $have_person_ref  = {};
    my $have_subject_ref = {};
    
    # Gesamtresponse in gesis_source
    push @{$fields_ref->{'gesis_source'}}, {
	content => $match_ref
    };
    
    foreach my $field (keys %$single_field_map_ref){
	if ($match_ref->{_source}{$field}){
	    if ($logger->is_debug){
		$logger->debug("Processing field $field: ".YAML::Dump($match_ref->{_source}{$field}));
	    }
	    if (ref $match_ref->{_source}{$field} eq "ARRAY"){
		my $mult = 1;
		foreach my $content (@{$match_ref->{_source}{$field}}){
		    push @{$fields_ref->{$single_field_map_ref->{$field}}}, {
			content  => $content,
			subfield => '',
			mult     => $mult++,
		    };
		}
	    }
	    else {
		push @{$fields_ref->{$single_field_map_ref->{$field}}}, {
		    content  => $match_ref->{_source}{$field},
		    subfield => '',
		    mult     => 1,
		};
	    }
	}
    }
    
    if ($match_ref->{_source}{coreAuthor}){
	if (ref $match_ref->{_source}{coreAuthor} eq "ARRAY"){
	    my $mult = 1;
	    foreach my $content (@{$match_ref->{_source}{coreAuthor}}){
		next if (defined $have_person_ref->{$content});
		
		$logger->debug("coreAuthor: $content");
		push @{$fields_ref->{'T0100'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult++,
		};
		
		push @{$fields_ref->{'PC0001'}}, {
		    content  => $content,
		};
		
		$have_person_ref->{$content} = 1;
	    }
	}
	else {
	    $logger->debug("coreAuthor single: ".$match_ref->{_source}{coreAuthor});
	    unless (defined $have_person_ref->{$match_ref->{_source}{coreAuthor}}){
		
		push @{$fields_ref->{'T0100'}}, {
		    content  => $match_ref->{_source}{coreAuthor},
		    subfield => '',
		    mult     => 1,
		};
		
		push @{$fields_ref->{'PC0001'}}, {
		    content  => $match_ref->{_source}{coreAuthor},
		};
		
		$have_person_ref->{$match_ref->{_source}{coreAuthor}} = 1;
		
	    }
	    
	}
    }
    
    if ($match_ref->{_source}{coreEditor}){
	if (ref $match_ref->{_source}{coreEditor} eq "ARRAY"){
	    my $mult = 1;
	    foreach my $content (@{$match_ref->{_source}{coreEditor}}){
		push @{$fields_ref->{'T0200'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult++,
		};
		
		push @{$fields_ref->{'PC0001'}}, {
		    content  => $content,
		};
	    }
	}
	else {
	    push @{$fields_ref->{'T0200'}}, {
		content  => $match_ref->{_source}{coreEditor},
		subfield => '',
		mult     => 1,
	    };
	    
	    push @{$fields_ref->{'PC0001'}}, {
		content  => $match_ref->{_source}{coreEditor},
	    };
	}
    }

    if ($match_ref->{_source}{contributor}){
	if (ref $match_ref->{_source}{contributor} eq "ARRAY"){
	    my $mult = 1;
	    foreach my $content (@{$match_ref->{_source}{contributor}}){
		push @{$fields_ref->{'T0201'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult++,
		};
		
		push @{$fields_ref->{'PC0001'}}, {
		    content  => $content,
		};
	    }
	}
	else {
	    push @{$fields_ref->{'T0201'}}, {
		content  => $match_ref->{_source}{contributor},
		subfield => '',
		mult     => 1,
	    };
	    
	    push @{$fields_ref->{'PC0001'}}, {
		content  => $match_ref->{_source}{contributor},
	    };
	}
    }
    
    if ($match_ref->{_source}{person}){
	if (ref $match_ref->{_source}{person} eq "ARRAY"){
	    my $mult = 1;
	    foreach my $content (@{$match_ref->{_source}{person}}){
		next if (defined $have_person_ref->{$content});
		
		push @{$fields_ref->{'T0101'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult++,
		};
		
		push @{$fields_ref->{'PC0001'}}, {
		    content  => $content,
		};
		
		$have_person_ref->{$content} = 1;
	    }
	}
	else {
	    unless (defined $have_person_ref->{$match_ref->{_source}{person}}){
		push @{$fields_ref->{'T0101'}}, {
		    content  => $match_ref->{_source}{person},
		    subfield => '',
		    mult     => 1,
		};
		
		push @{$fields_ref->{'PC0001'}}, {
		    content  => $match_ref->{_source}{person},
		};
		
		$have_person_ref->{$match_ref->{_source}{person}} = 1;
	    }
	}
    }

    # Schlagworte
    if ($match_ref->{_source}{topic}){
	if (ref $match_ref->{_source}{topic} eq "ARRAY"){
	    my $mult = 1;
	    foreach my $content (@{$match_ref->{_source}{topic}}){
		next if (defined $have_subject_ref->{$content});
		
		$logger->debug("topic: $content");
		push @{$fields_ref->{'T0710'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult++,
		};
		
		$have_subject_ref->{$content} = 1;
	    }
	}
	else {
	    $logger->debug("topic single: ".$match_ref->{_source}{topic});
	    unless (defined $have_subject_ref->{$match_ref->{_source}{topic}}){
		
		push @{$fields_ref->{'T0710'}}, {
		    content  => $match_ref->{_source}{topic},
		    subfield => '',
		    mult     => 1,
		};
		
		$have_subject_ref->{$match_ref->{_source}{topic}} = 1;
		
	    }
	    
	}
    }

    if ($match_ref->{_source}{topic_en}){
	if (ref $match_ref->{_source}{topic_en} eq "ARRAY"){
	    my $mult = 1;
	    foreach my $content (@{$match_ref->{_source}{topic_en}}){
		next if (defined $have_subject_ref->{$content});
		
		$logger->debug("topic_en: $content");
		push @{$fields_ref->{'T0710'}}, {
		    content  => $content,
		    subfield => '',
		    mult     => $mult++,
		};
		
		$have_subject_ref->{$content} = 1;
	    }
	}
	else {
	    $logger->debug("topic_en single: ".$match_ref->{_source}{topic_en});
	    unless (defined $have_subject_ref->{$match_ref->{_source}{topic_en}}){
		
		push @{$fields_ref->{'T0710'}}, {
		    content  => $match_ref->{_source}{topic_en},
		    subfield => '',
		    mult     => 1,
		};
		
		$have_subject_ref->{$match_ref->{_source}{topic_en}} = 1;
		
	    }
	    
	}
    }

    my $mult_url = 1;
    
    # URLs
    if ($match_ref->{_source}{links}){
	if (ref $match_ref->{_source}{links} eq "ARRAY"){

	    foreach my $content_ref (@{$match_ref->{_source}{links}}){
		
		push @{$fields_ref->{'T0662'}}, {
		    content  => $content_ref->{link},
		    subfield => '',
		    mult     => $mult_url,
		};

		push @{$fields_ref->{'T0663'}}, {
		    content  => $content_ref->{label},
		    subfield => '',
		    mult     => $mult_url,
		};


		if ($match_ref->{_source}{fulltext}){
		    push @{$fields_ref->{'T4120'}}, {
			content  => $content_ref->{link},
			subfield => 'f',
			mult     => $mult_url,
		    };
		}

		$mult_url++;
	    }
	}
    }

    if ($match_ref->{_source}{portal_url}){
	push @{$fields_ref->{'T0662'}}, {
	    content  => $match_ref->{_source}{portal_url},
	    subfield => '',
	    mult     => $mult_url,
	};
	
	push @{$fields_ref->{'T0663'}}, {
	    content  => "Portal URL",
	    subfield => '',
	    mult     => $mult_url,
	};
	
	$mult_url++;
    }
    
    
    return $fields_ref;
}

sub process_facets {
    my ($self,$results) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $ddatime   = new Benchmark;
    
    # Transformation Hash->Array zur Sortierung

    my $category_map_ref     = ();
    my $tmp_category_map_ref = $results->{aggregations};
                                
    foreach my $type (keys %{$tmp_category_map_ref}) {
        my $contents_ref = [] ;
        foreach my $item_ref (@{$tmp_category_map_ref->{$type}->{buckets}}) {
            push @{$contents_ref}, [
                $item_ref->{key},
                $item_ref->{doc_count},
            ];
        }
        
        if ($logger->is_debug){
            $logger->debug("Facet for $type ".YAML::Dump($contents_ref));
        }
        
        # Schwartz'ian Transform

	$type=~s/^facet_//;
	
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
    
    $logger->debug("Zeit fuer categorized drilldowns $drilldowntime");

    $self->{_facets} = $category_map_ref;
    
    return; 
}


sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $searchfield_mapping_ref = {
	'freesearch'              => '_all',
	    'mediatype'           => 'type', 	    
	    'mediatypestring'     => 'type',
	    'year'                => 'date', 	    
	    'yearstring'          => 'date', 	    
    };
    
    # Aufbau des elasticsearchquerystrings
    my @elasticsearchquerystrings = ();
    my $elasticsearchquerystring  = "";

    # Aufbau des elasticsearchfilterstrings
    my @elasticsearchfilterstrings = ();
    my $elasticsearchfilterstring  = "";

    my $ops_ref = {
        'AND'     => 'AND',
        'AND NOT' => 'NOT',
        'OR'      => 'OR',
    };

    my $query_ref        = {};
    
    my $must_query_ref   = [];
    my $should_query_ref = [];    
    
    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{val})?$searchquery->get_searchfield($field)->{val}:'';
        my $searchtermop     = (defined $searchquery->get_searchfield($field)->{bool} && defined $ops_ref->{$searchquery->get_searchfield($field)->{bool}})?$ops_ref->{$searchquery->get_searchfield($field)->{bool}}:'';
        if ($searchtermstring) {

	    # $searchtermstring = encode_utf8($searchtermstring);
	    
	    # Suchbegriff auf mehrere Felder verteilt
	    if ($field=~m/person/){
		if ($field =~m/string$/){
		    push @$should_query_ref, {
			match_phrase => {
			    person     => $searchtermstring,
			},
		    };
		    push @$should_query_ref, {
			match_phrase => {
			    coreAuthor => $searchtermstring,
			},
		    };
		}
		else {
		    push @$must_query_ref, {
			match => {
			    person     => $searchtermstring,
			    coreAuthor => $searchtermstring,
			},
		    };
		}		
	    }
	    elsif ($field=~m/corporatebody/){
		if ($field =~m/string$/){
		    push @$should_query_ref, {
			match_phrase => {
			    contributor => $searchtermstring,
			},
		    };
		    push @$should_query_ref, {
			match_phrase => {
			    coreEditor  => $searchtermstring,
			},
		    };
		}
		else {
		    push @$must_query_ref, {
			match => {
			    coreEditor  => $searchtermstring,
			    contributor => $searchtermstring,
			},
		    };
		}		
	    }
	    elsif ($field=~m/subject/){
		if ($field =~m/string$/){
		    push @$should_query_ref, {
			match_phrase => {
			    topic    => $searchtermstring,
			},
		    };
		    push @$should_query_ref, {
			match_phrase => {
			    topic_en => $searchtermstring,
			},
		    };
		}
		else {
		    push @$must_query_ref, {
			match => {
			    topic    => $searchtermstring,
			    topic_en => $searchtermstring,
			},
		    };
		}		
	    }
	    elsif ($field=~m/freesearch/){
		push @$must_query_ref, {
		    query_string => {
			query    => $searchtermstring,
			default_operator => $searchtermop,
			fields => ["_all","title^10","topic^7","abstract^3","source^3","title.partial^0.4","topic.partial^0.3","abstract.partial^0.2","content.partial^0.4","full_text^0.1"],
		    },
		};
	    }
	    else {	    
		if ($field =~m/string$/){
		    push @$must_query_ref, {
			match_phrase => {
			    $searchfield_mapping_ref->{$field} => $searchtermstring,
			},
		    };
		}
		else {
		    push @$must_query_ref, {
			match => {
			    $searchfield_mapping_ref->{$field} => $searchtermstring,
			},
		    };
		}
	    }
            # Innerhalb einer freien Suche wird Standardmaessig UND-Verknuepft
            # Nochmal explizites Setzen von +, weil sonst Wildcards innerhalb mehrerer
            # Suchterme ignoriert werden.

        }
    }

    if (@$should_query_ref){
	$query_ref->{should} = $should_query_ref;
    }

    if (@$must_query_ref){
	$query_ref->{must} = $must_query_ref;
    }
    
    # Filter

    my $filter_ref;

    if ($logger->is_debug){
        $logger->debug("All filters: ".YAML::Dump($searchquery->get_filter));
    }

    my $elasticsearch_filter_field_ref = $config->get('elasticsearch_filter_field');
    
    if (@{$searchquery->get_filter}){
        $filter_ref = [ ];
        foreach my $thisfilter_ref (@{$searchquery->get_filter}){
            my $field = $elasticsearch_filter_field_ref->{gesis}{$thisfilter_ref->{field}};
            my $term  = $thisfilter_ref->{term};

            
            $logger->debug("Facet: $field / Term: $term (Filter-Field: ".$thisfilter_ref->{field}.")");

	    push @$filter_ref, { "term" => {$field => $term}};
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


1;
__END__

=head1 NAME

 OpenBib::API::HTTP::Gesis - Objekt zur Interaktion mit HTTP zum ElasticSearch JSON API der Gesis

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib per HTTP über das JSON API von ElasticSearch auf einen Suchindex zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::API::HTTP::Gesis;

 my $es = new OpenBib::API::HTTP::Gesis;

 my $search_result_json = $es->search({ searchquery => $searchquery, queryoptions => $queryoptions });

 my $single_record_json = $es->get_record({ });

=head1 METHODS

=over 4

=item new({ userinfo => $userinfo, cxn_pool => $cxn_pool, nodes => $nodes_ref })

Anlegen eines neuen ElasticSearch-Objektes.

=item search({ searchquery => $searchquery, queryoptions => $queryoptions })

Liefert die ElasticSearch Antwort in JSON zurueck.

=item get_record({ })

Liefert die ElasticSearch Antwort in JSON zurueck.
=back

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
