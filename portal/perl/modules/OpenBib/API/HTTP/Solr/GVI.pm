#####################################################################
#
#  OpenBib::API::HTTP::Solr::GVI.pm
#
#  Objektorientiertes Interface zum Solr JSON-API des GVI
#
#  basiert auf OpenBib::API::HTTP::EDS
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

package OpenBib::API::HTTP::Solr::GVI;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use MARC::File::XML;
use MARC::Batch;
use MARC::Charset 'marc8_to_utf8';
use Storable;
use JSON::XS;
use URI::Escape;
use YAML ();

use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::API::HTTP::Solr);

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


    my $url = $config->get('solr')->{'gvi'}{'search_url'};

    my $header = ['Content-Type' => 'application/json; charset=UTF-8'];

    # Escape id
    $id=~s/\(/\\\(/g;
    $id=~s/\)/\\\)/g;
    
    my $json_query_ref = {
	'query' => { 'bool' => { 'must' => ["id:$id"]}},
#	'query' => { $id => { 'df' => 'id'}},

    };

    my $encoded_json = encode_utf8(encode_json($json_query_ref));

    $logger->debug("Solr JSON Query: $encoded_json");
    
    my $request = HTTP::Request->new('POST',$url,$header,$encoded_json);
    
    my $response = $ua->request($request);

    if ($logger->is_debug()){
	$logger->debug("Request URL: $url");
    }
    
    if ($logger->is_debug){
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success && $response->code != 400) {
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }

    my $json_result_ref = {};
    
    eval {
	$json_result_ref = decode_json $response->content;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
    }
    
    return $json_result_ref;
}

sub send_search_request {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $ua           = $self->get_client;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;
    
    # Used Parameters
    my $sorttype          = $queryoptions->get_option('srt');
    my $sortorder         = $queryoptions->get_option('srto');
    my $defaultop         = $queryoptions->get_option('dop');
    my $facets            = (defined $self->{_options}{facets})?$self->{_options}{facets}:$queryoptions->get_option('facets');
    my $gen_facets        = ($facets eq "none")?0:1;

    # Pagination parameters
    my $page              = $queryoptions->get_option('page');
    my $num               = $queryoptions->get_option('num');

    my $from              = ($page - 1)*$num;

    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    $logger->debug("srt: ".$sorttype);
    
    # Wenn srto in srt enthalten, dann aufteilen
    if ($sorttype =~m/^([^_]+)_([^_]+)$/){
        $sorttype=$1;
        $sortorder=$2;
        $logger->debug("srt Option split: srt = $1, srto = $2");
    }
    
    # Defaults from portal.yml
    my $current_facets_ref = $config->{facets};

    my $json_facets_ref = {};
    
    if ($gen_facets){
	if ($facets){
	    $current_facets_ref = {};
	    map { $current_facets_ref->{$_} = 1 } split(',',$facets);
	}
	
	foreach my $thisfacet (keys %$current_facets_ref){
	    if ($config->get('solr_facet_mapping')->{'gvi'}{$thisfacet}){
		my $gvi_facet = $config->get('solr_facet_mapping')->{'gvi'}{$thisfacet};
		$json_facets_ref->{$thisfacet} = {
		    'type' => 'terms',
			'field' => $gvi_facet,
			'limit' => 50
		};
	    }
	}
    }

    $logger->debug("Suche mit Facetten: ".YAML::Dump($json_facets_ref));

    my $url = $config->get('solr')->{'gvi'}{'search_url'};

    # search options
    my @search_options = ();

    $self->parse_query($searchquery);

    my $query_ref  = $self->get_query;
    my $filter_ref = $self->get_filter;
    
    if ($logger->is_debug()){
	$logger->debug("Request URL: $url");
    }

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $searchprofile = $searchquery->get_searchprofile;

    my @databases = ();
    
    if ($searchprofile){
	foreach my $database ($config->get_databases_of_searchprofile($searchprofile)){	    
	    push @databases, $database;	    
        }
    }
    elsif ($self->{_database}){
	push @databases, $self->{_database};
    }

    # Restrict search to catalogs by a filter
    #push @$filter_ref, "db:(".join(' OR ',@databases).")";
    
    my $header = ['Content-Type' => 'application/json; charset=UTF-8'];
    my $json_query_ref = {
	'query' => $query_ref,
	    'limit' => $num,
	    'offset' => $from,	    
    };

    # Filter hinzufuegen
    if (@$filter_ref){
    	$json_query_ref->{filter} = $filter_ref;
    }

    # Facetten aktivieren
    if (keys %$json_facets_ref){
    	$json_query_ref->{facet} = $json_facets_ref;
    }

    # # Sortierung
    # if ($sorttype ne "relevance") { # default
    # 	$json_query_ref->{sort} = "sort_$sorttype $sortorder";
    # }
    
    my $encoded_json = encode_utf8(encode_json($json_query_ref));

    $logger->debug("Solr JSON Query: $encoded_json");
    
    my $request = HTTP::Request->new('POST',$url,$header,$encoded_json);
    
    my $response = $ua->request($request);

  
    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $searchtime   = timestr($stimeall,"nop");
	$searchtime      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Zeit fuer Solr HTTP-Request $searchtime");
    }
    
    if (!$response->is_success && $response->code != 400) {
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }
    
    $logger->info('ok - '.$response->content);

    my $json_result_ref = {};
    
    eval {
	$json_result_ref = decode_json $response->content;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
    }
    
    return $json_result_ref;
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

    my $config       = $self->get_config;
    
    my $json_result_ref = $self->send_retrieve_request($arg_ref);

    my $record = new OpenBib::Record::Title({ database => $database, id => $id });

    my $fields_ref = ();

    # Gesamtresponse in response_source
    push @{$fields_ref->{'response_source'}}, {
	content => $json_result_ref
    };

    foreach my $match (@{$json_result_ref->{response}{docs}}){
	my $full_record = $match->{fullrecord};

	# Cleanup UTF8
	# see: https://blog.famzah.net/2010/07/01/filter-a-character-sequence-leaving-only-valid-utf-8-characters/
	$full_record =~ s/.*?((?:[\t\n\r\x20-\x7E])+|(?:\xD0[\x90-\xBF])+|(?:\xD1[\x80-\x8F])+|(?:\xC3[\x80-\xBF])+|).*?/$1/sg;

	$full_record = encode_utf8($full_record);

	my ($atime,$btime,$timeall);
	
	if ($config->{benchmark}) {
	    $atime=new Benchmark;
	}

	$logger->debug("Got $full_record");

	my $record_id = 0;
	if ($full_record){
	    eval {
		my $field_mult_ref = {};
		open(my $fh, "<", \$full_record);
		my $batch = MARC::Batch->new( 'XML', $fh );
		# Fallback to UTF8

		# Recover from errors
		$batch->strict_off();
		$batch->warnings_off();

		# Fallback to UTF8
		MARC::Charset->assume_unicode(1);
		# Ignore Encoding Errors
		MARC::Charset->ignore_errors(1);

		while (my $record = $batch->next() ){
		    my $encoding = $record->encoding();
		    
		    # Process all fields
		    foreach my $field ($record->fields()){
			my $field_nr = "T".$field->tag();
			$field_mult_ref->{$field_nr} = 1 unless (defined $field_mult_ref->{$field_nr});
			foreach my $subfield_ref ($field->subfields()){
			    my $content = $subfield_ref->[1];

			    if ($encoding eq "MARC-8"){
				$content = marc8_to_utf8($content);
			    }
			    else {
				$content = decode_utf8($content);	
			    }
			    
			    push @{$fields_ref->{$field_nr}}, {
				subfield => $subfield_ref->[0],
				content  => $content,
				mult     => $field_mult_ref->{$field_nr},
			    };
			}		    
			$field_mult_ref->{$field_nr} = $field_mult_ref->{$field_nr} + 1;
		    }
		}
		close $fh;

		if ($config->{benchmark}) {
		    my $stime        = new Benchmark;
		    my $stimeall     = timediff($stime,$atime);
		    my $parsetime   = timestr($stimeall,"nop");
		    $parsetime      =~s/(\d+\.\d+) .*/$1/;
		    
		    $logger->info("Zeit um Treffer zu parsen $parsetime");
		}
		
	    };
	    if ($@){
		$logger->error($@);
	    }

	    last;
	}
	# Gesamtresponse in response_source
	push @{$fields_ref->{'response_source'}}, {
	    content => $match
	};
    }
    
    $record->set_fields_from_storable($fields_ref);
    
    $record->set_holding([]);
    $record->set_circulation([]);
    
    return $record;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);

    my $config=$self->get_config;
    
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $json_result_ref = $self->send_search_request($arg_ref);

    if ($logger->is_debug){
	$logger->debug("GVI JSON Result".YAML::Dump($json_result_ref));
    }
    
    my @matches = $self->process_matches($json_result_ref);

    $self->process_facets($json_result_ref);
        
    my $resultcount = $json_result_ref->{response}{numFound};

    if ($logger->is_debug){
         $logger->info("Found ".$resultcount." titles");
    }
    
    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $searchtime   = timestr($stimeall,"nop");
	$searchtime      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Gesamtzeit fuer Solr-Suche $searchtime");
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

        my $id            = OpenBib::Common::Util::encode_id($match_ref->{id});
	my $fields_ref    = $match_ref->{fields};

        $recordlist->add(OpenBib::Record::Title->new({database => 'gvi', id => $id })->set_fields_from_storable($fields_ref));
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
    
    foreach my $match (@{$json_result_ref->{response}{docs}}){
	my $full_record = $match->{fullrecord};

	# Cleanup UTF8
	# see: https://blog.famzah.net/2010/07/01/filter-a-character-sequence-leaving-only-valid-utf-8-characters/
	$full_record =~ s/.*?((?:[\t\n\r\x20-\x7E])+|(?:\xD0[\x90-\xBF])+|(?:\xD1[\x80-\x8F])+|(?:\xC3[\x80-\xBF])+|).*?/$1/sg;

	$full_record = encode_utf8($full_record);

	my $fields_ref = {};

	my ($atime,$btime,$timeall);
	
	if ($config->{benchmark}) {
	    $atime=new Benchmark;
	}

	$logger->debug("Got $full_record");

	my $record_id = 0;
	if ($full_record){
	    eval {
		my $field_mult_ref = {};
		open(my $fh, "<", \$full_record);
		my $batch = MARC::Batch->new( 'XML', $fh );
		# Fallback to UTF8

		# Recover from errors
		$batch->strict_off();
		$batch->warnings_off();

		# Fallback to UTF8
		MARC::Charset->assume_unicode(1);
		# Ignore Encoding Errors
		MARC::Charset->ignore_errors(1);

		while (my $record = $batch->next() ){
		    my $encoding = $record->encoding();
		    
		    # Process all fields
		    foreach my $field ($record->fields()){
			my $field_nr = "T".$field->tag();
			$field_mult_ref->{$field_nr} = 1 unless (defined $field_mult_ref->{$field_nr});
			foreach my $subfield_ref ($field->subfields()){
			    my $content = $subfield_ref->[1];

			    if ($encoding eq "MARC-8"){
				$content = marc8_to_utf8($content);
			    }
			    else {
				$content = decode_utf8($content);	
			    }
			    
			    push @{$fields_ref->{$field_nr}}, {
				subfield => $subfield_ref->[0],
				content  => $content,
				mult     => $field_mult_ref->{$field_nr},
			    };
			}		    
			$field_mult_ref->{$field_nr} = $field_mult_ref->{$field_nr} + 1;
		    }
		}
		close $fh;
	    };
	    if ($@){
		$logger->error($@);
	    }
	}
	# Gesamtresponse in response_source
	push @{$fields_ref->{'response_source'}}, {
	    content => $match
	};

	if ($logger->is_debug){
	    $logger->debug("Felder ".YAML::Dump($fields_ref));
	}
	
        push @matches, {
            database => 'gvi',
            id       => $match->{id},
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

    my $category_map_ref     = ();
    
    # Transformation Hash->Array zur Sortierung

    $logger->debug("Start processing facets: ".YAML::Dump($json_result_ref->{facets}));

    delete $json_result_ref->{facets}{count};
    
    foreach my $type (keys %{$json_result_ref->{facets}}){
	
	my $solr_facet_ref = $json_result_ref->{facets}{$type};
	
        my $contents_ref = [] ;
        foreach my $item_ref (@{$solr_facet_ref->{buckets}}) {
            push @{$contents_ref}, [
                $item_ref->{val},
                $item_ref->{count},
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

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $query_count = 1;
    
    my $query_ref = {};

    foreach my $field (keys %{$config->{searchfield}}){
	next unless (defined $config->get('solr_searchfield_mapping')->{gvi}{$field});

	my $gvi_searchfield = $config->get('solr_searchfield_mapping')->{gvi}{$field};
	
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{val})?$searchquery->get_searchfield($field)->{val}:'';
        my $bool             = (defined $searchquery->get_searchfield($field)->{bool})?$searchquery->get_searchfield($field)->{bool}:'AND';

	if ($gvi_searchfield && $searchtermstring){
	    push @{$query_ref->{'bool'}{'must'}},     $gvi_searchfield.":".$searchtermstring if ($bool eq "AND");
	    push @{$query_ref->{'bool'}{'must_not'}}, $gvi_searchfield.":".$searchtermstring if ($bool eq "AND NOT");
	    push @{$query_ref->{'bool'}{'should'}},   $gvi_searchfield.":".$searchtermstring if ($bool eq "OR");
	    $query_count++;
	}
    }

    # No Filters for now

    my $filter_count = 1;
    
    my $filter_ref = [];

    if ($logger->is_debug){
        $logger->debug("All filters: ".YAML::Dump($searchquery->get_filter));
    }

    my $solr_filter_field_ref = $config->get('solr_filter_field')->{'gvi'};
    
    if (@{$searchquery->get_filter}){
        $filter_ref = [ ];
        foreach my $thisfilter_ref (@{$searchquery->get_filter}){
            my $field = $solr_filter_field_ref->{$thisfilter_ref->{field}};
            my $term  = $thisfilter_ref->{term};
#            $term=~s/_/ /g;
            
            $logger->debug("Filter: $field / Term: $term (Filter-Field: ".$thisfilter_ref->{field}.")");

	    if ($field && $term){
		push @$filter_ref, "$field:$term";
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


1;
__END__

=head1 NAME

 OpenBib::API::HTTP::Solr::GVI - Objekt zur Interaktion mit dem Solr JSON API des GVI

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib über das JSON API von Solr auf einen Suchindex GVI zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::API::HTTP::Solr::GVI;

 my $solr = new OpenBib::API::HTTP::Solr::GVI;

 my $search_result_json = $solr->search({ searchquery => $searchquery, queryoptions => $queryoptions });

 my $single_record_json = $solr->get_record({ });

=head1 METHODS

=over 4

=item new({ api_key => $api_key, api_user => $api_user })

Anlegen eines neuen Solr-Objektes.

=item search({ searchquery => $searchquery, queryoptions => $queryoptions })

Liefert die Solr Antwort in JSON zurueck.

=item get_record({ })

Liefert die Solr Antwort in JSON zurueck.
=back

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
