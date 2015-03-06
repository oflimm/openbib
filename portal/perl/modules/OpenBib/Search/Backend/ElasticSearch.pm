#####################################################################
#
#  OpenBib::Search::Backend::ElasticSearch
#
#  Dieses File ist (C) 2012-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Backend::ElasticSearch;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use ElasticSearch;
use ElasticSearch::SearchBuilder;
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::Search);

sub get_relevant_terms {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $category_ref       = exists $arg_ref->{categories}
        ? $arg_ref->{categories}        : undef;
    my $type               = exists $arg_ref->{type}
        ? $arg_ref->{type}              : undef;
    my $resultbuffer_ref   = exists $arg_ref->{resultbuffer}
        ? $arg_ref->{resultbuffer}      : undef;
    my $relevanttokens_ref = exists $arg_ref->{relevanttokens}
        ? $arg_ref->{relevanttokens}    : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $fulltermsem_ref={};
    my $fullterm_ref=[];

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($relevanttokens_ref->{$type}));
    }

    my $atime=new Benchmark;
    
    for (my $i=1; exists $relevanttokens_ref->{$type}[$i-1]{name} ; $i++){
        my $term=$relevanttokens_ref->{$type}[$i-1]{name};

        # Problematische Zeichen fuer Regexp herausfiltern
        $term=~s/\+//g;
        
        $logger->debug("Token: $term");
        foreach my $titlistitem_ref (@{$resultbuffer_ref}){
            foreach my $category (@{$category_ref}){
#                $logger->debug("Testing category $category");
                foreach my $thisterm_ref (@{$titlistitem_ref->{$category}}){
                    my $thisterm = $thisterm_ref->{content};
                    my $cmpterm;
                    if (exists $thisterm_ref->{contentnorm}){
                        $cmpterm  = $thisterm_ref->{contentnorm};
                    }
                    else {
                        $cmpterm  = OpenBib::Common::Util::normalize({
                            field => $category,
                            content  => $thisterm,
                        });
                    }
                    if ($cmpterm=~m/$term/i){
                        next if (exists $fulltermsem_ref->{$thisterm});
                        $fulltermsem_ref->{$thisterm}=1;
                        $logger->debug("Found $thisterm");

                        push @{$fullterm_ref}, $thisterm;
                    }
                }
            }
        }
    }

    my $btime       = new Benchmark;
    my $timeall     = timediff($btime,$atime);
    $logger->debug("Time: ".timestr($timeall,"nop"));

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($fullterm_ref));
    }
    
    return $fullterm_ref;
}

sub search {
    my ($self) = @_;

    # Set defaults search parameters
#    my $serien            = exists $arg_ref->{serien}
#        ? $arg_ref->{serien}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = OpenBib::Config->new;
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

    my $dbh;

    my $es = ElasticSearch->new(
        servers      => $config->{elasticsearch}->{servers},       # default '127.0.0.1:9200'
        transport    => $config->{elasticsearch}->{transport},     # default 'httplite'
        max_requests => $config->{elasticsearch}->{max_requests},  # default 10_000
        trace_calls  => $config->{elasticsearch}->{trace_calls},
        no_refresh   => $config->{elasticsearch}->{no_refesh},
    );

    my $searchprofile = $searchquery->get_searchprofile;

    my $index;
    
    if ($searchprofile){
        my $result = $es->index_exists(
            index => "profile_$searchprofile",
        );

        if ($result->{ok}){
            $index = "profile_$searchprofile"
        }
        else {
            my @index = ();
            foreach my $database ($config->get_databases_of_searchprofile($searchprofile)){
                push @index, $database if ($es->index_exists(
                    index => $database,
                ));
            }
            $index = \@index;
        }
    }
    elsif ($self->{_database}){
        $index = $self->{_database} if ($es->index_exists(
            index => $self->{_database},
        ));;
    }

    $self->parse_query($searchquery);

    if ($logger->is_debug){
        $logger->debug("Query:  ".YAML::Dump($self->{_query}));
        $logger->debug("Filter: ".YAML::Dump($self->{_filter}));
    }

    my $facets_ref = {};

    foreach my $facet (keys %{$config->{facets}}){
        $facets_ref->{$facet} = {
            terms => {
                field => "facet_$facet",
                size => 25,
            }
        };

#         my $thisfilterstring = $querystring->{filter}{"facet_$facet"};
#         if ($thisfilterstring){
#             push @{$facets_ref->{$facet}{facet_filter}}, { term => { "facet_$facet" =>  $thisfilterstring }};
#         }
    }

    # Facetten filtern

#     foreach my $filter (keys %{$querystring->{filter}}){
#         $facets_ref->{$filter}{facet_filter}{term} = {
#             "${filter}string" => $querystring->{filter}{$filter},
#         };
#     }    

    my $query_ref = $self->{_query};

    $query_ref->{'-filter'} = $self->{_filter};

    my $sort_ref = { };

    if ($sorttype eq "relevance"){
        $sort_ref->{_score} = {
            order => $sortorder,
        };
    }
    else {
        $sort_ref->{"sort_$sorttype"} = {
            order => $sortorder,
        };

    }
    
    my $results = $es->search(
        index  => $index,
        type   => 'title',
        queryb => $query_ref,
        facets => $facets_ref,
        sort   => $sort_ref, 
        from   => $from,
        size   => $num,
    );

    my @matches = ();
    foreach my $match (@{$results->{hits}->{hits}}){
        push @matches, {
            database => $match->{_index},
            id       => $match->{_id},
            listitem => $match->{_source}{listitem},
        };
    }

    # Facets
    $self->{categories} = $results->{facets};

    if ($logger->is_debug){
        $logger->debug("Results: ".YAML::Dump($results));
    }
    

    $self->{resultcount} = $results->{hits}->{total};

    $self->{_matches}     = \@matches;


    if ($logger->is_debug){
        $logger->info("Running query ".YAML::Dump($self->{_querystring})." with filters ".YAML::Dump($self->{_filter}));
    }

#    $logger->info("Found ".scalar(@matches)." matches in database $self->{_database}") if (defined $self->{_database});
    return;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = OpenBib::Config->new;

    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;

    if ($logger->is_debug){
        $logger->debug(YAML::Dump(\@matches));
    }

    foreach my $match (@matches) {
    
        $recordlist->add(OpenBib::Record::Title->new({database => $match->{database}, id => $match->{id}})->set_fields_from_storable($match->{listitem}));
    }

    return $recordlist;
}

sub get_facets {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $ddatime   = new Benchmark;
    
    # Transformation Hash->Array zur Sortierung

    my $type_map_ref = {
        database => 8,
        person => 3,
        corporatebody => 7,
        subject => 1,
        classification => 2,
        year => 5,
        mediatype => 4,
        tag => 9,
        litlist => 10,
        language => 6,
    };
    
    my $category_map_ref     = ();
    my $tmp_category_map_ref = $self->{categories};
                                
    foreach my $type (keys %{$tmp_category_map_ref}) {
        my $contents_ref = [] ;
        foreach my $item_ref (@{$tmp_category_map_ref->{$type}->{terms}}) {
            my $normcontent = OpenBib::Common::Util::normalize({
                content   => decode_utf8($item_ref->{term}),
                searchreq => 1,
            });
            
            $normcontent=~s/\W/_/g;
            push @{$contents_ref}, [
                decode_utf8($item_ref->{term}),
                $item_ref->{count},
                $normcontent,
            ];
        }
        
        if ($logger->is_debug){
            $logger->debug(YAML::Dump($contents_ref));
        }
        
        # Schwartz'ian Transform
        
        @{$category_map_ref->{$type_map_ref->{$type}}} = map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
                map { [$_, $_->[1]] }
                    @{$contents_ref};
    }

    my $ddbtime       = new Benchmark;
    my $ddtimeall     = timediff($ddbtime,$ddatime);
    my $drilldowntime    = timestr($ddtimeall,"nop");
    $drilldowntime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->debug("Zeit fuer categorized drilldowns $drilldowntime");

    return $category_map_ref;
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

    my $config = OpenBib::Config->new;

    my $dbh = undef;
    
    eval {
        $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
    };
    
    if ($@){
        $logger->error("Initializing with Database: $database - :".$@." not available");
        return [];
    }

    my $qp = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");

    # Explizites Setzen der Datenbank fuer FLAG_WILDCARD
    $qp->set_database($dbh);    
    $qp->add_prefix('id', 'Q');
    $qp->set_default_op(Search::Xapian::OP_AND);

    my $enq  = $dbh->enquire($qp->parse_query("id:$id"));

    my @matches = $enq->matches(0,10);

    my $indexterms_ref = [];
    
    if (scalar(@matches) == 1){
        my $docid         = $matches[0]->get_docid;;
        my $termlist_iter = $dbh->termlist_begin($docid);

        while ($termlist_iter != $dbh->termlist_end($docid)) {
            push @$indexterms_ref, $termlist_iter->get_termname;
            $termlist_iter++;
        }
    }
    
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

    my $config = OpenBib::Config->new;

    my $dbh = undef;
    
    eval {
        $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
    };
    
    if ($@){
        $logger->error("Initializing with Database: $database - :".$@." not available");
        return [];
    }

    my $qp = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");

    # Explizites Setzen der Datenbank fuer FLAG_WILDCARD
    $qp->set_database($dbh);    
    $qp->add_prefix('id', 'Q');
    $qp->set_default_op(Search::Xapian::OP_AND);

    my $enq  = $dbh->enquire($qp->parse_query("id:$id"));

    my @matches = $enq->matches(0,10);

    my $values_ref = {};
    
    if (scalar(@matches) == 1){
        my $docid         = $matches[0]->get_docid;;
        my $document      = $matches[0]->get_document;;
#        my $values_iter = $dbh->values_begin($docid);
        my $values_iter = $document->values_begin();

#        while ($values_iter != $dbh->values_end($docid)) {
        while ($values_iter ne $document->values_end()) {
            $values_ref->{$values_iter->get_valueno} = $values_iter->get_value;
            $values_iter++;
        }
    }
    
    return $values_ref;
}

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    # Aufbau des elasticsearchquerystrings
    my @elasticsearchquerystrings = ();
    my $elasticsearchquerystring  = "";

    # Aufbau des elasticsearchfilterstrings
    my @elasticsearchfilterstrings = ();
    my $elasticsearchfilterstring  = "";

    my $ops_ref = {
        'AND'     => 'AND ',
        'AND NOT' => 'NOT ',
        'OR'      => 'OR ',
    };

    my $query_ref = {};
    
    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{norm})?$searchquery->get_searchfield($field)->{norm}:'';
        my $searchtermop     = (defined $searchquery->get_searchfield($field)->{bool} && defined $ops_ref->{$searchquery->get_searchfield($field)->{bool}})?$ops_ref->{$searchquery->get_searchfield($field)->{bool}}:'';
        if ($searchtermstring) {
            # Freie Suche einfach uebernehmen
            if ($field eq "freesearch" && $searchtermstring) {
                my @searchterms = split('\s+',$searchtermstring);
                
#                  if (@searchterms > 1){
#                      push @{$query_ref->{freesearch}},'-and';
#                      push @{$query_ref->{freesearch}},@searchterms;
#                  }
#                  else {
#                      $query_ref->{freesearch} = $searchtermstring;
                #                  }
                
#                 foreach my $term (@searchterms){
#                     push @elasticsearchquerystrings, $config->{searchfield}{$field}{prefix}.":$term";
#                 }

                $query_ref->{freesearch} = $searchtermstring;
            }
            # Titelstring mit _ ersetzten
            elsif (($field eq "titlestring" || $field eq "mark") && $searchtermstring) {
                my @chars = split("",$searchtermstring);
                my $newsearchtermstring = "";
                foreach my $char (@chars){
                    if ($char ne "*"){
                        $char=~s/\W/_/g;
                    }
                    $newsearchtermstring.=$char;
                }

                $query_ref->{titlestring} = $newsearchtermstring;
            }
            # Sonst Operator und Prefix hinzufuegen
            elsif ($searchtermstring) {
                $query_ref->{$field} = $searchtermstring;
            }

            # Innerhalb einer freien Suche wird Standardmaessig UND-Verknuepft
            # Nochmal explizites Setzen von +, weil sonst Wildcards innerhalb mehrerer
            # Suchterme ignoriert werden.

        }
    }


     my $rev_searchfield_ref = {
         fper => "facet_person",
         fcln => "facet_classification",
         fsubj => "facet_subject",
         ftyp => "facet_mediatype",
         fyear => "facet_year",
         flang => "facet_language",
         fdb => "facet_database",
         ftag => "facet_tag",
         flitlist => "facet_litlist",
     };

#    my $rev_searchfield_ref = {};
#    
#    foreach my $searchfield (keys %{$config->{searchfield}}){
#        $rev_searchfield_ref->{$config->{searchfield}{$searchfield}{prefix}} = $searchfield;
#    }
    
    # Filter

    my $filter_ref;

    if ($logger->is_debug){
        $logger->debug("All filters: ".YAML::Dump($searchquery->get_filter));
    }
    
    if (@{$searchquery->get_filter}){
        $filter_ref = { };
        foreach my $thisfilter_ref (@{$searchquery->get_filter}){
            my $field = $rev_searchfield_ref->{$thisfilter_ref->{field}};
            my $term  = $thisfilter_ref->{term};
#            $term=~s/_/ /g;
            
            $logger->debug("Facet: $field / Term: $term / Ref: ".ref(${$filter_ref}{$field}));

            if (exists $filter_ref->{$field}){
                if (! ref($filter_ref->{$field})){
                    my $oldterm = $filter_ref->{$field};
                    $logger->debug("String -> Array: $oldterm");
                    $filter_ref->{$field}= [ '-and' ];
                    push @{$filter_ref->{$field}}, $oldterm;
                }
                $logger->debug("Add Array: $term");
                push @{$filter_ref->{$field}}, $term; #'"'.$term.'"';                    
            }
            else {
                $filter_ref->{$field} = $term; #'"'.$term.'"';
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

