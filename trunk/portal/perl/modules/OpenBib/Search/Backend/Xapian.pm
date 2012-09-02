#####################################################################
#
#  OpenBib::Search::Backend::Xapian
#
#  Dieses File ist (C) 2006-2012 Oliver Flimm <flimm@openbib.org>
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

use Apache2::Reload;
use Apache2::Request ();
use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $searchprofile   = exists $arg_ref->{searchprofile}
        ? $arg_ref->{searchprofile}           : undef;

    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;

    my $self = { };

    bless ($self, $class);

    # Entweder genau eine Datenbank via database oder (allgemeiner) ein Suchprofil via searchprofile mit einer oder mehr Datenbanken
    
    $self->{_searchprofile} = $searchprofile if ($searchprofile);
    $self->{_database}      = $database if ($database);
    
    return $self;
}

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

    $logger->debug(YAML::Dump($relevanttokens_ref->{$type}));

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
                        $cmpterm  = OpenBib::Common::Util::grundform({
                            category => $category,
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

    $logger->debug(YAML::Dump($fullterm_ref));
    return $fullterm_ref;
}

sub search {
    my ($self) = @_;

    # Set defaults search parameters
#    my $serien            = exists $arg_ref->{serien}
#        ? $arg_ref->{serien}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = OpenBib::Config->instance;
    my $searchquery  = OpenBib::SearchQuery->instance;
    my $queryoptions = OpenBib::QueryOptions->instance;

    # Used Parameters
    my $sorttype          = $queryoptions->get_option('srt');
    my $sortorder         = $queryoptions->get_option('srto');
    my $defaultop         = $queryoptions->get_option('dop');
    my $drilldown         = 1;

    # Pagination parameters
    my $page              = $queryoptions->get_option('page');
    my $num               = $queryoptions->get_option('num');
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $dbh;

    my $searchprofile = $searchquery->get_searchprofile;

    if ($searchprofile){
        my $profileindex_path = $config->{xapian_index_base_path}."/profile/".$searchprofile;
        
        if (-d $profileindex_path){
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
                $logger->debug("Adding Xapian DB-Object for database $database");
                
                if (!defined $dbh){
                    # Erstes Objekt erzeugen,
                    
                    $logger->debug("Creating Xapian DB-Object for database $database");                
                
                    eval {
                        $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
                    };
                    
                    if ($@){
                        $logger->error("Initializing with Database: $database - :".$@." not available");
                    }
                }
                else {
                    $logger->debug("Adding database $database");
                    
                    eval {
                        $dbh->add_database(new Search::Xapian::Database( $config->{xapian_index_base_path}."/".$database));
                    };
                    
                    if ($@){
                        $logger->error("Adding Database: $database - :".$@." not available");
                    }                        
                }
            }
        }
    }
    elsif ($self->{_database}){
        $logger->debug("Creating Xapian DB-Object for database $self->{_database}");
        
        eval {
            $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$self->{_database}) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
        };
        
        if ($@) {
            $logger->error("Database: $self->{_database} - :".$@);
            return;
        }

    }

    $self->{qp} = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");

    my @stopwords = ();
    if (exists $config->{stopword_filename} && -e $config->{stopword_filename}){
        open(SW,$config->{stopword_filename});
        while (my $stopword=<SW>){
            chomp $stopword ;
            $stopword = OpenBib::Common::Util::grundform({
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

    $logger->debug("Full querystring: $fullquerystring");
    
    my $default_op_ref = {
        'and' => "Search::Xapian::OP_AND",
        'or'  => "Search::Xapian::OP_OR",
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

    $self->{qp}->set_default_op($default_op_ref->{$defaultop});

    foreach my $prefix (keys %{$config->{xapian_search_prefix}}){
        $self->{qp}->add_prefix($prefix,$config->{xapian_search_prefix}{$prefix});
    }
    
    my $category_map_ref = {};
    my $enq       = $dbh->enquire($self->{qp}->parse_query($fullquerystring,Search::Xapian::FLAG_WILDCARD|Search::Xapian::FLAG_LOVEHATE|Search::Xapian::FLAG_BOOLEAN|Search::Xapian::FLAG_PHRASE));

    # Sorting
    if ($sorttype ne "relevance" || exists $config->{xapian_sorttype_value}{$sorttype}) { # default
        $sortorder = ($sortorder eq "asc")?0:1;
        $logger->debug("Set Sorting to type ".$config->{xapian_sorttype_value}{$sorttype}." / order ".$sortorder);

        $enq->set_sort_by_value($config->{xapian_sorttype_value}{$sorttype},$sortorder)
    }
    
    my $thisquery = $enq->get_query()->get_description();
        
    $logger->debug("Internal Xapian Query: $thisquery");
    
    my %decider_map   = ();
    my @decider_types = ();

    foreach my $drilldown_value (keys %{$config->{xapian_drilldown_value}}){
        push @decider_types, $config->{xapian_drilldown_value}{$drilldown_value};
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

    # Abkuerzung fuer Suchanfragen mit nur einem Begriff:
    #
    # Hier wird direkt die Begriffsfrequenz bestimmt.
    # Wenn diese die maximale Treffermengengroesse (maxmatch)
    # uebersteigt, dann werden
    # - drilldowns deaktiviert, da diese bei so unspezifischen
    #   Recherchen keine Hilfe bieten
    # - aber die korrekte Treffermengenzahl zurueck gegeben
    # Generell gilt aber auch hier: Es sind maximal maxmatch
    # Treffer ueber die Recherche zugreifbar!

    my $singletermcount = 0;
    if ($is_singleterm){
      $singletermcount = $dbh->get_termfreq($is_singleterm);

      if ($singletermcount > $maxmatch){
	$drilldown = "";
      }
    }

    my $rset = Search::Xapian::RSet->new();

    my $offset = $page*$num-$num;

    $logger->debug("Drilldown: $drilldown - Offset: $offset");
    
    my $mset = ($drilldown)?$enq->get_mset($offset,$num,$maxmatch,$rset,$decider_ref):$enq->get_mset($offset,$num,$maxmatch);

    $logger->debug("DB: $self->{_database}") if (defined $self->{_database});
    
    $logger->debug("Categories-Map: ".YAML::Dump(\%decider_map));

    $self->{_enq}         = $enq;

    if ($singletermcount > $maxmatch){
      $self->{resultcount} = $singletermcount;
    }
    else {
      $self->{resultcount} = $mset->get_matches_estimated;
    }

    my @matches = ();
    foreach my $match ($mset->items()) {
        push @matches, $match;
    }
    
#    my @this_matches      = splice(@matches,$offset,$num);
    $self->{_matches}     = \@matches;

    $logger->debug(YAML::Dump(\%decider_map));
    if ($singletermcount > $maxmatch){
      $self->{categories} = {};
    }
    else {
      $self->{categories}   = \%decider_map;
    }

    $logger->info("Running query ".$self->{_querystring}." with filters ".$self->{_filter});

    $logger->info("Found ".scalar(@matches)." matches in database $self->{_database}") if (defined $self->{_database});
    return;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = OpenBib::Config->instance;

    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;
    
    foreach my $match (@matches) {        
        my $document        = $match->get_document();
        my $titlistitem_ref = decode_json $document->get_data();

        $logger->debug("Record: ".$document->get_data() );
        $recordlist->add(new OpenBib::Record::Title({database => $titlistitem_ref->{database}, id => $titlistitem_ref->{id}})->set_brief_normdata_from_storable($titlistitem_ref));
    }

    return $recordlist;
}

sub matches {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug(YAML::Dump($self->{_matches}));
    return @{$self->{_matches}};
}

sub querystring {
    my $self=shift;
    return $self->{_querystring};
}

sub enq {
    my $self=shift;
    return $self->{_enq};
}

sub get_categorized_drilldown {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $ddatime   = new Benchmark;
    
    # Transformation Hash->Array zur Sortierung

    my $category_map_ref     = ();
    my $tmp_category_map_ref = $self->{categories};
                                
    foreach my $type (keys %{$tmp_category_map_ref}) {
        my $contents_ref = [] ;
        foreach my $content (keys %{$tmp_category_map_ref->{$type}}) {
            push @{$contents_ref}, [
                decode_utf8($content),
                $tmp_category_map_ref->{$type}{$content},
            ];
        }
        
        $logger->debug(YAML::Dump($contents_ref));
        
        # Schwartz'ian Transform
        
        @{$category_map_ref->{$type}} = map { $_->[0] }
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

    $logger->debug("Getting indexterms for id $id in database $database");
    my $config = OpenBib::Config->instance;

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

    $logger->debug(YAML::Dump(\@matches));
    
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

    my $config = OpenBib::Config->instance;

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

    my $config = OpenBib::Config->instance;

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
                if ($config->{searchfield}{$field}{type} eq "ft"){
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
            $searchtermstring_from = ($searchtermstring_from)?$searchtermstring_from:0;
            $searchtermstring_to   = ($searchtermstring_to)?$searchtermstring_to:9999;

            $searchtermstring_from = sprintf "%08d", $searchtermstring_from;
            $searchtermstring_to   = sprintf "%08d", $searchtermstring_to;

            
            $logger->debug("Adding Value range processor $searchtermstring_from .. $searchtermstring_to");
            
            my $vrp = new Search::Xapian::StringValueRangeProcessor($slot);
            $self->{qp}->add_valuerangeprocessor($vrp);
            push @xapianquerystrings, $searchtermstring_from."..".$searchtermstring_to;
        }
    }

    # Filter
    foreach my $filter_ref (@{$searchquery->get_filter}){
        push @xapianfilterstrings, "$filter_ref->{field}:$filter_ref->{norm}";
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

sub DESTROY {
    my $self=shift;

    return;
}

1;

