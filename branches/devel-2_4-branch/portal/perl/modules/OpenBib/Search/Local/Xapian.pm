#####################################################################
#
#  OpenBib::Search::Local::Xapian
#
#  Dieses File ist (C) 2006-2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Local::Xapian;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Reload;
use Apache2::Request ();
use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Util;

sub new {
    my $class = shift;

    my $self = { };

    bless ($self, $class);

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

sub initial_search {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $serien            = exists $arg_ref->{serien}
        ? $arg_ref->{serien}        : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}           : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}      : undef;
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}      : undef;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}     : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}      : 50;
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : 0;
    my $dd_categorized    = exists $arg_ref->{dd_categorized}
        ? $arg_ref->{dd_categorized} : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;
    my $searchquery = OpenBib::SearchQuery->instance;
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $qp = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");

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
    $qp->set_stopper($stopper);
    
#    my $querystring    = $searchquery->get_searchfield('fs')->{norm};
    my $querystring    = $searchquery->to_xapian_querystring;

    my ($is_singleterm) = $querystring =~m/^(\w+)$/;

    # Explizites Setzen der Datenbank fuer FLAG_WILDCARD
    $qp->set_database($dbh);
    $qp->set_default_op(Search::Xapian::OP_AND);
    $qp->add_prefix('id'       ,'Q');

    $qp->add_prefix('aut'    ,'X1');
    $qp->add_prefix('tit'    ,'X2');
    $qp->add_prefix('corp'   ,'X3');
    $qp->add_prefix('subj'   ,'X4');
    $qp->add_prefix('sys'    ,'X5');
    $qp->add_prefix('year'   ,'X7');
    $qp->add_prefix('isbn'   ,'X8');
    $qp->add_prefix('issn'   ,'X9');

    # Drilldowns
    $qp->add_prefix('ddsubj'  ,'D1');
    $qp->add_prefix('ddnot'   ,'D2');
    $qp->add_prefix('ddper'   ,'D3');
    $qp->add_prefix('typ'     ,'D4');
    $qp->add_prefix('ddyear'  ,'D5');
    $qp->add_prefix('ddspr'   ,'D6');
    $qp->add_prefix('ddcorp'  ,'D7');
    $qp->add_prefix('db'      ,'D8');
    
    my $category_map_ref = {};
    my $enq       = $dbh->enquire($qp->parse_query($querystring,Search::Xapian::FLAG_WILDCARD|Search::Xapian::FLAG_LOVEHATE|Search::Xapian::FLAG_BOOLEAN));

    my $sorttype_map_ref = {
        "author"     => 20,
        "title"      => 21,
        "order"      => 22,
        "yearofpub"  => 23,
        "publisher"  => 24,
        "signature"  => 25,
        "popularity" => 26,
    };
    
    # Sorting
    if ($sorttype ne "relevance" || exists $sorttype_map_ref->{$sorttype}) { # default
        $sortorder = ($sortorder eq "up")?0:1;
        $logger->debug("Set Sorting to type ".$sorttype_map_ref->{$sorttype}." / order ".$sortorder);

        $enq->set_sort_by_value($sorttype_map_ref->{$sorttype},$sortorder)
    }
    
    my $thisquery = $enq->get_query()->get_description();
        
    $logger->debug("Internal Xapian Query: $thisquery");
    
    my %decider_map   = ();
    my @decider_types = ();

    push @decider_types, 1 if ($config->{drilldown_option}{categorized_swt});
    push @decider_types, 2 if ($config->{drilldown_option}{categorized_not});
    push @decider_types, 3 if ($config->{drilldown_option}{categorized_aut});
    push @decider_types, 4 if ($config->{drilldown_option}{categorized_mart});
    push @decider_types, 5 if ($config->{drilldown_option}{categorized_year});
    push @decider_types, 6 if ($config->{drilldown_option}{categorized_spr});
    push @decider_types, 7 if ($config->{drilldown_option}{categorized_kor});
    push @decider_types, 8;# if ($config->{drilldown_option}{categorized_database});

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
	$dd_categorized = "";
      }
    }

    my @matches   = ($dd_categorized)?$enq->matches(0,$maxmatch,$decider_ref):$enq->matches(0,$maxmatch);

    $logger->debug("DB: $database") if (defined $database);
    
    $logger->debug("Matches: ".YAML::Dump(\@matches));

    $logger->debug("Categories-Map: ".YAML::Dump(\%decider_map));

    $self->{_querystring} = $querystring;
    $self->{_enq}         = $enq;

    if ($singletermcount > $maxmatch){
      $self->{resultcount} = $singletermcount;
    }
    else {
      $self->{resultcount} = scalar(@matches);
    }

#    my @this_matches      = splice(@matches,$offset,$hitrange);
    $self->{_matches}     = \@matches;

    if ($singletermcount > $maxmatch){
      $self->{categories} = {};
    }
    else {
      $self->{categories}   = \%decider_map;
    }

    $logger->info("Running query ".$self->{_querystring});

    $logger->info("Found ".scalar(@matches)." matches in database $database") if (defined $database);
    return;
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
            my $normcontent = OpenBib::Common::Util::grundform({
                content   => decode_utf8($content),
                searchreq => 1,
            });
            
            $normcontent=~s/\W/_/g;
            push @{$contents_ref}, [
                decode_utf8($content),
                $tmp_category_map_ref->{$type}{$content},
                $normcontent,
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

sub DESTROY {
    my $self=shift;

    return;
}

1;

