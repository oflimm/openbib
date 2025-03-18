#####################################################################
#
#  OpenBib::Search::Backend::Xapian
#
#  Dieses File ist (C) 2006-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Backend::Xapian;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian qw(:qpflags);
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;
use OpenBib::Normalizer;

use base qw(OpenBib::Search);

sub get_relevant_terms {
    my ($self,$arg_ref) = @_;
    
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

    my $normalizer = $self->{_normalizer};
    
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
                        $cmpterm  = $normalizer->normalize({
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

    if ($logger->is_debug){
        $logger->debug("Time: ".timestr($timeall,"nop"));
    }

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($fullterm_ref));
    }
    
    return $fullterm_ref;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Set defaults search parameters
    my $options_ref          = exists $arg_ref->{options}
        ? $arg_ref->{options}        : {};

        
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;
    my $normalizer   = $self->{_normalizer};

    # Used Parameters
    my $sorttype          = (defined $self->{_options}{srt})?$self->{_options}{srt}:$queryoptions->get_option('srt');
    my $sortorder         = (defined $self->{_options}{srto})?$self->{_options}{srto}:$queryoptions->get_option('srto');
    my $defaultop         = (defined $self->{_options}{dop})?$self->{_options}{dop}:
        ($queryoptions->get_option('dop'))?$queryoptions->get_option('dop'):'and';
    my $facets            = (defined $self->{_options}{facets})?$self->{_options}{facets}:$queryoptions->get_option('facets');
    my $gen_facets        = ($facets eq "none")?0:1;
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    if ($logger->is_debug){
        $logger->debug("Options: ".YAML::Dump($options_ref));
    }

    $logger->debug("srt: ".$sorttype);
    
    # Wenn srto in srt enthalten, dann aufteilen
    if ($sorttype =~m/^([^_]+)_([^_]+)$/){
        $sorttype=$1;
        $sortorder=$2;
        $logger->debug("srt Option split: srt = $1, srto = $2");
    }
    
    # Pagination parameters
    my $page              = (defined $self->{_options}{page})?$self->{_options}{page}:$queryoptions->get_option('page');
    my $num               = (defined $self->{_options}{num})?$self->{_options}{num}:$queryoptions->get_option('num');
    my $collapse          = (defined $self->{_options}{clp})?$self->{_options}{clp}:$queryoptions->get_option('clp');
    
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Defaults from portal.yml
    my $current_facets_ref = $config->{facets};

    if ($facets){
        $current_facets_ref = {};
        map { $current_facets_ref->{$_} = 1 } split(',',$facets);
    }

    my $apidb_map = $config->get_apidb_map;
    
    if ($logger->is_debug){
        $logger->debug("Facets CGI Parameter: $facets");
        $logger->debug("Generate Facets: ".YAML::Dump($current_facets_ref));
    }
    
    my $dbh;

    my $searchprofile = $searchquery->get_searchprofile;

    $logger->debug("Performing Authority Search") if ($self->{_authority});
    
    if ($searchprofile){
        my $profileindex_path = $config->{xapian_index_base_path}."/_searchprofile/".$searchprofile;

        if ($self->{_authority}){
            $profileindex_path .="_authority";
        }
        
        if (-d $profileindex_path || -e $profileindex_path){
            $logger->debug("Adding Xapian DB-Object for profile $searchprofile with path $profileindex_path");
            
            eval {
                $dbh = new Search::Xapian::Database ( $profileindex_path ) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
            };
            
            if ($@){
                $logger->error("Initializing with Profile: $searchprofile - :".$@." not available");
            }
            
        }        
        else {
            foreach my $database ($config->get_databases_of_searchprofile($searchprofile)) {

		if (defined $apidb_map->{$database} && $apidb_map->{$database}){
		    $logger->debug("Ignoring database $database of type api");
		    next;
		}
		
                $logger->debug("Adding Xapian DB-Object for searchindex $database");
                
                if (!defined $dbh){
                    # Erstes Objekt erzeugen,
                    
                    $logger->debug("Creating Xapian DB-Object for database $database");                

                    my $databaseindex_path = $config->{xapian_index_base_path}."/".$database;
                    
                    if ($self->{_authority}){
                        $databaseindex_path .="_authority";
                    }

                    $logger->debug("Initializing Xapian Index using path $databaseindex_path");
                    
                    eval {
                        $dbh = new Search::Xapian::Database ( $databaseindex_path) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
                    };
                    
                    if ($@){
                        $logger->error("Initializing with searchindex: $database - :".$@." not available");
                    }
                }
                else {
                    $logger->debug("Adding searchindex $database");

                    my $databaseindex_path = $config->{xapian_index_base_path}."/".$database;
                    
                    if ($self->{_authority}){
                        $databaseindex_path .="_authority";
                    }

                    $logger->debug("Adding Xapian Index using path $databaseindex_path");
                    
                    eval {
                        $dbh->add_database(new Search::Xapian::Database( $databaseindex_path));
                    };
                    
                    if ($@){
                        $logger->error("Adding searchindex: $database - :".$@." not available");
                    }                        
                }
            }
        }
    }
    elsif ($self->{_database}){
        $logger->debug("Creating Xapian DB-Object for database $self->{_database}");

        my $databaseindex_path = $config->{xapian_index_base_path}."/".$self->{_database};
        
        if ($self->{_authority}){
            $databaseindex_path .="_authority";
        }

        $logger->debug("Using Xapian Index using path $databaseindex_path");
        
        eval {
            $dbh = new Search::Xapian::Database ( $databaseindex_path) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
        };
        
        if ($@) {
            $logger->error("Database: $self->{_database} - :".$@);
            return;
        }

    }

    $self->{qp} = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");

    unless ($dbh){
        $logger->fatal("No searchindex for searchprofile $searchprofile");
        return;
    }

    my @stopwords = ();
    if (exists $config->{stopword_filename} && -e $config->{stopword_filename}){
        open(SW,$config->{stopword_filename});
        while (my $stopword=<SW>){
            chomp $stopword ;
            $stopword = $normalizer->normalize({
                content  => $stopword,
            });
            push @stopwords, $stopword;
        }
        close(SW);
    }

    my $stopper = new Search::Xapian::SimpleStopper(@stopwords);
    $self->{qp}->set_stopper($stopper);
    
    $self->parse_query($searchquery);

    my $fullquerystring = $self->{_querystring}." ".$self->{_filter};
    
    my ($is_singleterm) = $fullquerystring =~m/^(\w+)$/;

    $logger->debug("Full querystring: '$fullquerystring'");
        
    if ($fullquerystring=~/^\*\s*$/){
	return $self->browse($arg_ref);
    }
    
    my $default_op_ref = {
        'and' => Search::Xapian::OP_AND,
        'or'  => Search::Xapian::OP_OR,
        'AND' => Search::Xapian::OP_AND,
        'OR'  => Search::Xapian::OP_OR,
    };
    
    # Explizites Setzen der Datenbank fuer FLAG_WILDCARD
    # Explizites Setzen der Datenbank fuer FLAG_WILDCARD
    eval {
        $self->{qp}->set_database($dbh);
    };

    if ($@){
        $logger->error("Error setting dbh $dbh :".$@);
        return [];
    }

    if ($defaultop ne "or"){
        $self->{qp}->set_default_op($default_op_ref->{$defaultop});
        if ($logger->is_debug){
            $logger->debug("Setting default op $defaultop to ".$default_op_ref->{$defaultop});
            $logger->debug("Got default op ".$self->{qp}->get_default_op);
        }
    }
    
    foreach my $searchfield (keys %{$config->{xapian_search}}){
        if ($config->{xapian_search}{$searchfield}{type} eq "boolean"){
            $self->{qp}->add_boolean_prefix($searchfield,$config->{xapian_search}{$searchfield}{prefix});
        }
        else {
            $self->{qp}->add_prefix($searchfield,$config->{xapian_search}{$searchfield}{prefix});
        }
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 1 is ".timestr($timeall));
    }

    my $category_map_ref = {};
    my $enq       = $dbh->enquire($self->{qp}->parse_query($fullquerystring,Search::Xapian::FLAG_WILDCARD|Search::Xapian::FLAG_LOVEHATE|Search::Xapian::FLAG_BOOLEAN|Search::Xapian::FLAG_PHRASE));
#    my $enq       = $dbh->enquire($self->{qp}->parse_query($fullquerystring,FLAG_WILDCARD|FLAG_BOOLEAN|FLAG_PHRASE));

    $logger->debug("Original sorting type: $sorttype");
    
    # Sorting
    if ($sorttype ne "relevance" || exists $config->{xapian_sorttype_value}{$sorttype}) { # default
        $sortorder = ($sortorder eq "asc")?0:1;

	$logger->debug("Original sorting order: $sortorder");
	
        $logger->debug("Set Sorting to type ".$config->{xapian_sorttype_value}{$sorttype}." / order ".$sortorder);
        # Sortierung nach Zaehlung: Erst nach Zaehlung, dann Titel
        if ($sorttype ne "title"){
            my $sorter = new Search::Xapian::MultiValueSorter;
            $sorter->add($config->{xapian_sorttype_value}{$sorttype},$sortorder);
            $sorter->add($config->{xapian_sorttype_value}{title},0);
            $enq->set_sort_by_key($sorter)
        }
        else {
            $enq->set_sort_by_value($config->{xapian_sorttype_value}{$sorttype},$sortorder);
        }
    }

    # Collapsing
    if ($collapse){
	$logger->debug("Setting collapse key $collapse");
        $enq->set_collapse_key($config->{xapian_collapse_value}{$collapse},1);
    }
    
    my $thisquery = $enq->get_query()->get_description();
        
    $logger->debug("Internal Xapian Query: $thisquery");
    
    my %decider_map   = ();
    my @decider_types = ();

    
    foreach my $single_facet (keys %{$config->{xapian_facet_value}}){
        if (defined $current_facets_ref->{$single_facet} && $current_facets_ref->{$single_facet}){
            push @decider_types, $config->{xapian_facet_value}{$single_facet};
        }
    }

    my $spy_ref = {};
    
    foreach my $spy_num (@decider_types){
	$spy_ref->{$spy_num} =  Search::Xapian::ValueCountMatchSpy->new($spy_num);
	$enq->add_matchspy($spy_ref->{$spy_num});
    }

    # my $decider_ref = sub {
    #   foreach my $value (@decider_types){
    # 	my $mvalues = $_[0]->get_value($value);
    # 	foreach my $mvalue (split("\t",$mvalues)){
    # 	  $decider_map{$value}{$mvalue}+=1;
    # 	}
    #   }
    #   return 1;
    # };

    my $maxmatch=$config->{xapian_option}{maxmatch};

    # Abkuerzung fuer Suchanfragen mit nur einem Begriff:
    #
    # Hier wird direkt die Begriffsfrequenz bestimmt.
    # Wenn diese die maximale Treffermengengroesse (maxmatch)
    # uebersteigt, dann werden
    # - facets deaktiviert, da diese bei so unspezifischen
    #   Recherchen keine Hilfe bieten
    # - aber die korrekte Treffermengenzahl zurueck gegeben
    # Generell gilt aber auch hier: Es sind maximal maxmatch
    # Treffer ueber die Recherche zugreifbar!

    my $singletermcount = 0;
    if ($is_singleterm){
      $singletermcount = $dbh->get_termfreq($is_singleterm);

      if ($singletermcount > $maxmatch){
	$gen_facets = 0;
      }
    }

    my $rset = Search::Xapian::RSet->new();

    $logger->debug("Page: $page - Num: $num");
    
    my $offset = $page*$num-$num;
  
    $logger->debug("Facets: $gen_facets - Offset: $offset");

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 is ".timestr($timeall));
    }

    if ($logger->is_debug){
        $logger->debug("DB: $self->{_database}") if (defined $self->{_database});
        $logger->debug("Categories-Map: ".YAML::Dump(\%decider_map));
    }

#    my $mset = ($gen_facets)?$enq->get_mset($offset,$num,$maxmatch,$rset,$decider_ref):$enq->get_mset($offset,$num,$maxmatch);
    my $mset = $enq->get_mset($offset,$num,$maxmatch);

    $self->{_enq}         = $enq;

    my $resultcount = $mset->get_matches_estimated;    
    my $lower_bound = $mset->get_matches_lower_bound;
    my $upper_bound = $mset->get_matches_upper_bound;

    if ($logger->is_debug){
	$logger->debug("Counts: result $resultcount - lower $lower_bound - upper $upper_bound");
    }

    if ($lower_bound > $maxmatch){
	$resultcount = $upper_bound;
    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 3 is ".timestr($timeall));
    }
    
    $self->{resultcount} = $resultcount;

    my @matches = ();
    foreach my $match ($mset->items()) {
        push @matches, $match;
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 4 is ".timestr($timeall));
    }
    
#    my @this_matches      = splice(@matches,$offset,$num);
    $self->{_matches}     = \@matches;

    if ($logger->is_debug){
        $logger->debug("Matches: ".YAML::Dump($self->{_matches}));
        $logger->debug("Decider map: ".YAML::Dump(\%decider_map));
    }    
    
    if ($singletermcount > $maxmatch){
	$self->{categories} = {};
    }
    else {
	foreach my $value (keys %$spy_ref){
	    foreach my $this_spy ($spy_ref->{$value}){
		my $end = $this_spy->values_end();
		for (my $facet_value = $this_spy->values_begin(); $facet_value != $end; $facet_value++) {
		    my $mvalues    = $facet_value->get_termname();
		    my $valuecount = $facet_value->get_termfreq();
		    
		    foreach my $mvalue (split("\t",$mvalues)){
			$decider_map{$value}{$mvalue}+=$valuecount;
		    }
		}
	    }
	}
	
	$self->{categories}   = \%decider_map;
    }

    if ($logger->is_info){
	$logger->info("Running query ".$self->{_querystring}." with filters ".$self->{_filter});
	
	$logger->info("Found ".scalar(@matches)." matches in database $self->{_database}") if (defined $self->{_database});
    }
    
    return;
}

sub browse {
    my ($self,$arg_ref) = @_;

    # Set defaults search parameters
    my $options_ref          = exists $arg_ref->{options}
        ? $arg_ref->{options}        : {};

    # Set defaults search parameters
#    my $serien            = exists $arg_ref->{serien}
#        ? $arg_ref->{serien}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;

    # Used Parameters
    my $sorttype          = (defined $self->{_options}{srt})?$self->{_options}{srt}:$queryoptions->get_option('srt');
    my $sortorder         = (defined $self->{_options}{srto})?$self->{_options}{srto}:$queryoptions->get_option('srto');
    my $defaultop         = (defined $self->{_options}{dop})?$self->{_options}{dop}:$queryoptions->get_option('dop');
    my $facets            = (defined $self->{_options}{facets})?$self->{_options}{facets}:$queryoptions->get_option('facets');
    my $gen_facets        = ($facets && $facets ne "none")?1:0;

    if ($logger->is_debug){
        $logger->debug("Options: ".YAML::Dump($options_ref));
    }

    $logger->debug("srt: ".$sorttype);
    
    # Wenn srto in srt enthalten, dann aufteilen
    if ($sorttype =~m/^([^_]+)_([^_]+)$/){
        $sorttype=$1;
        $sortorder=$2;
        $logger->debug("srt Option split: srt = $1, srto = $2");
    }
    
    # Pagination parameters
    my $page              = (defined $self->{_options}{page})?$self->{_options}{page}:$queryoptions->get_option('page');
    my $num               = (defined $self->{_options}{num})?$self->{_options}{num}:$queryoptions->get_option('num');
    my $collapse          = (defined $self->{_options}{clp})?$self->{_options}{clp}:$queryoptions->get_option('clp');
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Defaults from portal.yml
    my $current_facets_ref = $config->{facets};

    if ($facets && $facets ne "all"){
        $current_facets_ref = {};
        map { $current_facets_ref->{$_} = 1 } split(',',$facets);
    }

    my $apidb_map = $config->get_apidb_map;
    
    my $dbh;

    my $searchprofile = $searchquery->get_searchprofile;

    $logger->debug("Performing Authority Search") if ($self->{_authority});
    
    if ($searchprofile){
        my $profileindex_path = $config->{xapian_index_base_path}."/_searchprofile/".$searchprofile;

        if ($self->{_authority}){
            $profileindex_path .="_authority";
        }
        
        if (-d $profileindex_path || -e $profileindex_path){
            $logger->debug("Adding Xapian DB-Object for profile $searchprofile with path $profileindex_path");
            
            eval {
                $dbh = new Search::Xapian::Database ( $profileindex_path ) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
            };
            
            if ($@){
                $logger->error("Initializing with Profile: $searchprofile - :".$@." not available");
            }
            
        }        
        else {
            foreach my $database ($config->get_databases_of_searchprofile($searchprofile)) {

		if (defined $apidb_map->{$database} && $apidb_map->{$database}){
		    $logger->debug("Ignoring database $database of type api");
		    next;
		}
		
                $logger->debug("Adding Xapian DB-Object for searchindex $database");
                
                if (!defined $dbh){
                    # Erstes Objekt erzeugen,
                    
                    $logger->debug("Creating Xapian DB-Object for database $database");                

                    my $databaseindex_path = $config->{xapian_index_base_path}."/".$database;
                    
                    if ($self->{_authority}){
                        $databaseindex_path .="_authority";
                    }

                    $logger->debug("Initializing Xapian Index using path $databaseindex_path");
                    
                    eval {
                        $dbh = new Search::Xapian::Database ( $databaseindex_path) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
                    };
                    
                    if ($@){
                        $logger->error("Initializing with searchindex: $database - :".$@." not available");
                    }
                }
                else {
                    $logger->debug("Adding searchindex $database");

                    my $databaseindex_path = $config->{xapian_index_base_path}."/".$database;
                    
                    if ($self->{_authority}){
                        $databaseindex_path .="_authority";
                    }

                    $logger->debug("Adding Xapian Index using path $databaseindex_path");
                    
                    eval {
                        $dbh->add_database(new Search::Xapian::Database( $databaseindex_path));
                    };
                    
                    if ($@){
                        $logger->error("Adding searchindex: $database - :".$@." not available");
                    }                        
                }
            }
        }
    }
    elsif ($self->{_database}){
        $logger->debug("Creating Xapian DB-Object for database $self->{_database}");

        my $databaseindex_path = $config->{xapian_index_base_path}."/".$self->{_database};
        
        if ($self->{_authority}){
            $databaseindex_path .="_authority";
        }

        $logger->debug("Using Xapian Index using path $databaseindex_path");
        
        eval {
            $dbh = new Search::Xapian::Database ( $databaseindex_path) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
        };
        
        if ($@) {
            $logger->error("Database: $self->{_database} - :".$@);
            return;
        }

    }

    $self->{qp} = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");

    unless ($dbh){
        $logger->fatal("No searchindex for database $self->{_database}");
        return;
    }

    # Explizites Setzen der Datenbank fuer FLAG_WILDCARD
    # Explizites Setzen der Datenbank fuer FLAG_WILDCARD
    eval {
        $self->{qp}->set_database($dbh);
    };

    if ($@){
        $logger->error("Error setting dbh $dbh :".$@);
        return [];
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 1 is ".timestr($timeall));
    }

    my $category_map_ref = {};

    my $matchall = Search::Xapian::Query->new("");

    if ($logger->is_debug){
        $logger->debug("Matchall Query ".$matchall->get_description);
    }
    
    my $enq       = $dbh->enquire($matchall);

    # Sorting
    if ($sorttype ne "relevance" || exists $config->{xapian_sorttype_value}{$sorttype}) { # default
        $sortorder = ($sortorder eq "asc")?0:1;

        $logger->debug("Set Sorting to type ".$config->{xapian_sorttype_value}{$sorttype}." / order ".$sortorder);
        # Sortierung nach Zaehlung: Erst nach Zaehlung, dann Titel
        if ($sorttype eq "order"){
            my $sorter = new Search::Xapian::MultiValueSorter;
            $sorter->add($config->{xapian_sorttype_value}{$sorttype},$sortorder);
            $sorter->add($config->{xapian_sorttype_value}{title},0);
            $enq->set_sort_by_key($sorter)
        }
        else {
            $enq->set_sort_by_value($config->{xapian_sorttype_value}{$sorttype},$sortorder);
        }
    }
    
    my $thisquery = $enq->get_query()->get_description();
        
    $logger->debug("Internal Xapian Query: $thisquery");
    
    my %decider_map   = ();
    my @decider_types = ();

    foreach my $single_facet (keys %{$config->{xapian_facet_value}}){
        if (defined $current_facets_ref->{$single_facet} && $current_facets_ref->{$single_facet}){
            push @decider_types, $config->{xapian_facet_value}{$single_facet};
        }
    }

    my $decider_ref = sub {
      foreach my $value (@decider_types){
	my $mvalues = $_[0]->get_value($value);
	foreach my $mvalue (split("\t",$mvalues)){
	  $decider_map{$value}{$mvalue}+=1;
	}
      }
      return 1;
    };

    my $maxmatch=$config->{xapian_option}{maxmatch};

    my $offset = $page*$num-$num;

    my $rset = Search::Xapian::RSet->new();

    $logger->debug("Facets: $gen_facets - Offset: $offset");

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 is ".timestr($timeall));
    }

    my $mset = ($gen_facets)?$enq->get_mset($offset,$num,$maxmatch,$rset,$decider_ref):$enq->get_mset($offset,$num,$maxmatch);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 3 is ".timestr($timeall));
    }
    
    $logger->debug("DB: $self->{_database}") if (defined $self->{_database});
    
    if ($logger->is_debug){
        $logger->debug("Categories-Map: ".YAML::Dump(\%decider_map));
    }

    $self->{_enq}         = $enq;

    $self->{resultcount} = $mset->get_matches_estimated;

    my @matches = ();
    foreach my $match ($mset->items()) {
        push @matches, $match;
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 4 is ".timestr($timeall));
    }

#    my @this_matches      = splice(@matches,$offset,$num);
    $self->{_matches}     = \@matches;

    $self->{categories}   = \%decider_map;

    $logger->info("Found ".scalar(@matches)." matches in database $self->{_database}") if (defined $self->{_database});
    return;
}


sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;

    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;
    
    foreach my $match (@matches) {        
        my $document        = $match->get_document();
        my $titlistitem_ref = decode_json $document->get_data();

        my $id            = $titlistitem_ref->{id};
        my $database      = $titlistitem_ref->{database};
        my $locations_ref = $titlistitem_ref->{locations};
        delete $titlistitem_ref->{id};
        delete $titlistitem_ref->{database};
        delete $titlistitem_ref->{locations};

        if ($logger->is_debug){
            $logger->debug("Record: ".decode_utf8($document->get_data()) );
        }
        
        $recordlist->add(new OpenBib::Record::Title({database => $database, id => $id, locations => $locations_ref})->set_fields_from_storable($titlistitem_ref));
    }

    if ($logger->is_debug){
	$logger->debug("Result-Recordlist: ".YAML::Dump($recordlist->to_ids))
    }

    return $recordlist;
}


sub get_records_as_json {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;

    my @matches = $self->matches;

    my $records_ref = [];
    
    foreach my $match (@matches) {        
        my $document        = $match->get_document();
        my $titlistitem_ref = decode_json $document->get_data();

        push @$records_ref, $titlistitem_ref;
    }

    return $records_ref;
}

sub get_facets {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $cutoff            = (defined $self->{_options}{cutoff})?$self->{_options}{cutoff}:0;

    $logger->debug("Getting facets with cutoff $cutoff");
    
    my $ddatime   = new Benchmark;
    
    # Transformation Hash->Array zur Sortierung

    my $facets_ref     = ();
    my $tmp_category_map_ref = $self->{categories};

    my %facet_rev_map = ();

    foreach my $facet (keys %{$config->{xapian_facet_value}}){
        $facet_rev_map{$config->{xapian_facet_value}{$facet}} = $facet;
    }
    
    foreach my $type (keys %{$tmp_category_map_ref}) {
        my $contents_ref = [] ;
        foreach my $content (keys %{$tmp_category_map_ref->{$type}}) {
            push @{$contents_ref}, [
                decode_utf8($content),
                $tmp_category_map_ref->{$type}{$content},
            ];
        }
        
        if ($logger->is_debug){
            $logger->debug(YAML::Dump($contents_ref));
        }
        
        # Schwartz'ian Transform
        
        my @sorted = map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
                map { [$_, $_->[1]] }
                    @{$contents_ref};

	if ($cutoff){
	    $logger->debug("Cutting Facets values: $cutoff");
	    @sorted = splice(@sorted,0,$cutoff);
	}

	@{$facets_ref->{$facet_rev_map{$type}}} = @sorted;

    }

    my $ddbtime       = new Benchmark;
    my $ddtimeall     = timediff($ddbtime,$ddatime);
    my $facettime    = timestr($ddtimeall,"nop");
    $facettime    =~s/(\d+\.\d+) .*/$1/;

    if ($logger->is_debug){
        $logger->debug("Facets: ".YAML::Dump($facets_ref));
        $logger->debug("Zeit fuer faceting $facettime");
    }

    $self->{_facets} = $facets_ref;
    
    return $facets_ref;
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

    $logger->debug("Getting indexterms for id $id in database $database");
    my $config       = $self->get_config;
    my $normalizer   = $self->{_normalizer};

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

    $id = $normalizer->normalize({ content => $id, type => 'id'});
    
    my $enq  = $dbh->enquire("Q$id"); #$qp->parse_query("id:$id"));

    my $thisquery = $enq->get_query()->get_description();
        
    $logger->debug("Internal Xapian Query: $thisquery");

    my @matches = $enq->matches(0,10);

    if ($logger->is_debug){
        $logger->debug(YAML::Dump(\@matches));
    }
    
    my $indexterms_ref = [];
    
    if (scalar(@matches) > 0){
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

    my $config       = $self->get_config;
    my $normalizer   = $self->{_normalizer};

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
    eval {
        $qp->set_database($dbh);
    };

    if ($@){
        $logger->error("Error setting database $database :".$@);
        return [];
    }
    
    $qp->add_prefix('id', 'Q');
    $qp->set_default_op(Search::Xapian::OP_AND);

    $id = $normalizer->normalize({ content => $id, type => 'id'});

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
            if ($values_iter->get_valueno == 23){ # sortable serialize year
                $values_ref->{$values_iter->get_valueno} = Search::Xapian::sortable_unserialise($values_iter->get_value);
            }
            else {
                $values_ref->{$values_iter->get_valueno} = $values_iter->get_value;
            }
            $values_iter++;
        }
    }
    
    return $values_ref;
}

sub get_data {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}      : undef;
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $normalizer   = $self->{_normalizer};

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
    eval {
        $qp->set_database($dbh);
    };

    if ($@){
        $logger->error("Error setting database $database :".$@);
        return [];
    }
    
    $qp->add_prefix('id', 'Q');
    $qp->set_default_op(Search::Xapian::OP_AND);

    $id = $normalizer->normalize({ content => $id, type => 'id'});
    
    my $enq  = $dbh->enquire($qp->parse_query("id:$id"));

    my @matches = $enq->matches(0,10);

    my $data;
    
    if (scalar(@matches) == 1){
        my $docid         = $matches[0]->get_docid;;
        my $document      = $matches[0]->get_document;;
	
	$data = $document->get_data;
    }
    
    return $data;
}

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $queryoptions = $self->get_queryoptions;
    my $normalizer   = $self->{_normalizer};
    
    # Used Parameters
    # Keinen Value range Prozessor?
    my $novrp = $queryoptions->get_option('novrp');

    # Aufbau des xapianquerystrings
    my @xapianquerystrings = ();
    my $xapianquerystring  = "";

    # Aufbau des xapianfilterstrings
    my @xapianfilterstrings = ();
    my $xapianfilterstring  = "";

    my $ops_ref = {
        'AND'     => 'AND ',
        'AND NOT' => 'NOT ',
        'OR'      => 'OR ',
    };

    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{norm})?$searchquery->get_searchfield($field)->{norm}:'';
        my $searchtermop     = (defined $searchquery->get_searchfield($field)->{bool} && defined $ops_ref->{$searchquery->get_searchfield($field)->{bool}})?$ops_ref->{$searchquery->get_searchfield($field)->{bool}}:'';
        if ($searchtermstring) {
            # Freie Suche einfach uebernehmen
            if ($field eq "freesearch" && $searchtermstring) {
#                 my @searchterms = split('\s+',$searchtermstring);
                
#                 # Inhalte von @searchterms mit Suchprefix bestuecken
#                 foreach my $searchterm (@searchterms){                    
#                     $searchterm="+".$searchtermstring if ($searchtermstring=~/^\w/);
#                 }
#                 $searchtermstring = "(".join(' ',@searchterms).")";

                push @xapianquerystrings, $searchtermstring;
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
                    
                $searchtermstring=$searchtermop.$config->{searchfield}{$field}{prefix}.":$newsearchtermstring";
                push @xapianquerystrings, $searchtermstring;                
            }
            # Sonst Operator und Prefix hinzufuegen
            elsif ($searchtermstring) {
                if ($config->{searchfield}{$field}{type} eq "ft" && $searchtermstring =~m/\s+/){
                    $searchtermstring = "($searchtermstring)";
                }
                
                $searchtermstring=$searchtermop.$config->{searchfield}{$field}{prefix}.":$searchtermstring";
                push @xapianquerystrings, $searchtermstring;                
            }

            # Innerhalb einer freien Suche wird Standardmaessig UND-Verknuepft
            # Nochmal explizites Setzen von +, weil sonst Wildcards innerhalb mehrerer
            # Suchterme ignoriert werden.

        }
    }

    # Ranges fuer Integer-Felder
    foreach my $field (keys %{$config->{searchfield}}){

        # Achtung: Bisher nur ein einziges Suchfeld: year
        next unless ($config->{searchfield}{$field}{type} eq "integer");
        
        my $searchtermstring_from = (defined $searchquery->get_searchfield("${field}_from")->{norm})?$searchquery->get_searchfield("${field}_from")->{norm}:'';
        my $searchtermstring_to   = (defined $searchquery->get_searchfield("${field}_to")->{norm})?$searchquery->get_searchfield("${field}_to")->{norm}:'';
        my $searchtermop_from     = (defined $searchquery->get_searchfield("${field}_from")->{bool} && defined $ops_ref->{$searchquery->get_searchfield("${field}_from")->{bool}})?$ops_ref->{$searchquery->get_searchfield("${field}_from")->{bool}}:'';
        my $searchtermop_to       = (defined $searchquery->get_searchfield("${field}_to")->{bool} && defined $ops_ref->{$searchquery->get_searchfield("${field}_to")->{bool}})?$ops_ref->{$searchquery->get_searchfield("${field}_to")->{bool}}:'';

        my $slot = $config->{xapian_sorttype_value}{$field};
        
        if ($searchtermstring_from || $searchtermstring_to) {
            $searchtermstring_from = ($searchtermstring_from)?$searchtermstring_from:-9999;
            $searchtermstring_to   = ($searchtermstring_to)?$searchtermstring_to:9999;

            # push @xapianquerystrings, $searchtermstring_from."..".$searchtermstring_to;

            if ($novrp){
                $logger->debug("From $searchtermstring_from to $searchtermstring_to");
                my $idx=$searchtermstring_from;
                while ($idx<=$searchtermstring_to){
                    $logger->debug("Adding $idx");
                    push @xapianquerystrings, "+".$config->{searchfield}{$field}{prefix}.":$idx";
                    $idx++;
                }
            }
            else {
                #$searchtermstring_from = sprintf "%08d", $searchtermstring_from;
                #$searchtermstring_to   = sprintf "%08d", $searchtermstring_to;

                $logger->debug("Adding Value range processor $searchtermstring_from .. $searchtermstring_to");
                
                my $vrp = new Search::Xapian::NumberValueRangeProcessor($slot);
                $self->{qp}->add_valuerangeprocessor($vrp);
                push @xapianquerystrings, $searchtermstring_from."..".$searchtermstring_to;
            }


        }
    }

    # Filter
    foreach my $filter_ref (@{$searchquery->get_filter}){
        push @xapianfilterstrings, "$filter_ref->{field}:$filter_ref->{norm}";
    }

    # Sucheinschraenkung auf Standort(e)
    my $view          = $searchquery->{view};
    my @viewlocations = ();

    if ($view && defined $config->{searchfield}{'locationstring'}){
	@viewlocations = $config->get_viewlocations($view);

	
	if (@viewlocations){

	    if ($logger->is_debug){
		$logger->debug("Viewlocations".YAML::Dump(\@viewlocations)."\n#: ".scalar(@viewlocations));
	    }
	    my $prefix = $config->{searchfield}{'locationstring'}{prefix};

	    @viewlocations = map { "$prefix:".$normalizer->normalize({
                content   => $_,
                type      => 'string',
            }) } @viewlocations;

	    if ($#viewlocations == 0){
		push @xapianquerystrings, $viewlocations[0];
	    }
	    else {
		push @xapianquerystrings, "(".join(' OR ',@viewlocations).")";
	    }
	}	
    }
    
    $xapianquerystring  = join(" ",@xapianquerystrings);
    $xapianfilterstring = join(" ",@xapianfilterstrings);

    $xapianquerystring=~s/^AND //;
    $xapianquerystring=~s/^OR //;
    $xapianquerystring=~s/^NOT //;

#    $xapianquerystring=~s/^OR /FALSE OR /;
#    $xapianquerystring=~s/^NOT /TRUE NOT /;
    
    $logger->debug("Xapian-Querystring: $xapianquerystring - Xapian-Filterstring: $xapianfilterstring");
    $self->{_querystring} = $xapianquerystring;
    $self->{_filter}      = $xapianfilterstring;

    return $self;
}

sub get_number_of_documents {
    my ($self,$database)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;

    $database = (defined $database)?$database:
    (defined $self->{_database})?$self->{_database}:undef;

    return -1 unless $database;
    
    my $dbh = undef;
    
    eval {
        $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
    };
    
    if ($@){
        $logger->error("Initializing with Database: $database - :".$@." not available");
        return [];
    }

    
    return $dbh->get_doccount;
}       
    

1;

