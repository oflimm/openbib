####################################################################
#
#  OpenBib::Mojo::Controller::Search::Availability::Search.pm
#
#  Dieses File ist (C) 2022-2025 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Mojo::Controller::Availability::Search;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Data::Pageset;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Storable ();
use String::Tokenizer;
use Search::Xapian;
use YAML ();

use Mojo::Promise;

use OpenBib::Container;
use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Factory;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Backend::ElasticSearch;
use OpenBib::Search::Backend::Z3950;
use OpenBib::Search::Backend::EZB;
use OpenBib::Search::Backend::DBIS;
use OpenBib::Search::Backend::BibSonomy;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Search';

sub show_search {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $servername     = $self->stash('servername');
    my $path_prefix    = $self->stash('path_prefix');
    my $path           = $self->stash('path');
    my $representation = $self->stash('representation');
    my $content_type   = $self->stash('content_type') || $config->{'content_type_map_rev'}{$representation} || 'text/html';

    my $availability_search_ref = $config->get('availability_search');

    # Abfangen von Portalen ohne Verfuegbarkeitsrecherche
    unless (defined $availability_search_ref->{$view}){
	return $self->print_error("Für dieses Portal bieten wir keine Verfügbarkeitsrecherche an.")
    }
    
    $logger->debug("Verfuegbarkeitsrecherche exisitiert fuer diesen View");

    $self->SUPER::show_search;
}

sub show_search_result_p {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $view        = $self->stash('view');
    
    my $config      = $self->stash('config');
    my $searchquery = $self->stash('searchquery');
    my $session     = $self->stash('session');
    my $writer      = $self->stash('writer');

    my $promise = Mojo::Promise->new;
    
    ######################################################################
    # Schleife ueber alle Datenbanken 

    ######################################################################

    $logger->debug("Starting sequential availability search");

    my $availability_search_ref = $config->get('availability_search');
    
    # Recherche ueber einzelne Datenbanken
    if (defined $availability_search_ref->{$view} && %{$availability_search_ref->{$view}}){

	my $searchquery = $self->stash('searchquery');

	my $type = "default";

	if ($searchquery->get_searchfield('mediatype')){
	    my $mediatype = $searchquery->get_searchfield('mediatype')->{val};
	    $type = $mediatype if (defined $availability_search_ref->{$view}{$mediatype});
	}

	# Array aus Promises fuer die Ergebnisse aller Recherchen	
	my @all_searches = ();
	
	foreach my $target_ref (@{$availability_search_ref->{$view}{$type}}) {
	    if ($target_ref->{type} eq "database"){
		my $this_searchquery = $self->rewrite_searchterms({ database => $target_ref->{name}});
		my $this_promise = $self->show_search_single_target_p({ database => $target_ref->{name}, searchquery => $this_searchquery, templatename => $config->{tt_availability_search_item_tname}});
		push @all_searches, $this_promise;
		
		$logger->debug("Adding DB ".$target_ref->{name});
	    }
	    elsif ($target_ref->{type} eq "view"){
		my $this_searchquery = $self->rewrite_searchterms({ viewname => $target_ref->{name}});
		my $this_promise = $self->show_search_single_target_p({ viewname => $target_ref->{name}, searchquery => $this_searchquery, templatename => $config->{tt_availability_search_item_tname}});
		push @all_searches, $this_promise;
		$logger->debug("Adding View ".$target_ref->{name});
	    }	    
	}
	
	return $promise->reject("No searchtargets") unless (@all_searches);
	
	return Mojo::Promise->all(@all_searches)->then(sub {
	    my @searchresults = map { $_->[0] } @_;
	    my $all_searchresults = join('',@searchresults);
	    
	    $logger->debug("Joined sequential results: $all_searchresults");
	    return $all_searchresults;
						       });	
    }
    
    return $promise->reject("Search error");
}

sub search_p {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;

    my $viewname           = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}            : undef;

    my $searchquery         = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}         : $self->stash('searchquery');
    
    my $authority          = exists $arg_ref->{authority}
        ? $arg_ref->{authority}           : undef;

    my $r            = $self->stash('r');
    my $view         = $self->stash('view');
    my $config       = $self->stash('config');
    my $queryoptions = $self->stash('qopts');
    my $session      = $self->stash('session');

    my $atime=new Benchmark;
    my $timeall;
    
    my $recordlist;
    my $resulttime;
    my $nav;

    # Verfuegbarkeitsrecherche ist nicht auf die Kataloge des aufrufenden Views beschraenkt!
    
    my $search_args_ref = {};
    $search_args_ref->{options}      = $self->query2hashref;
    $search_args_ref->{database}     = $database if (defined $database);
    $search_args_ref->{view}         = $viewname if (defined $viewname);
    $search_args_ref->{authority}    = $authority if (defined $authority);
    $search_args_ref->{searchquery}  = $searchquery if (defined $searchquery);
    $search_args_ref->{config}       = $config if (defined $config);
    $search_args_ref->{sessionID}    = $session->{ID} if (defined $session->{ID});    
    $search_args_ref->{queryoptions} = $queryoptions if (defined $queryoptions);

    # Searcher erhaelt per default alle Query-Parameter uebergeben. So kann sich jedes
    # Backend - jenseits der Standard-Rechercheinformationen in OpenBib::SearchQuery
    # und OpenBib::QueryOptions - alle weiteren benoetigten Parameter individuell
    # heraussuchen.
    # Derzeit: Nur jeweils ein Parameter eines 'Parameternamens'

    if ($config->{benchmark}) {
        my $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 1 is ".timestr($timeall));
    }

    $logger->debug("Args processed");
    
    my $searcher = OpenBib::Search::Factory->create_searcher($search_args_ref);

    # Recherche starten
    $searcher->search;

    if ($config->{benchmark}) {
        my $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 is ".timestr($timeall));
    }

    my $facets_ref = $searcher->get_facets;
    $searchquery->set_results($facets_ref->{8}) unless (defined $database); # Verteilung nach Datenbanken
    
    my $btime   = new Benchmark;
    $timeall    = timediff($btime,$atime);
    $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info($searcher->get_resultcount . " results found in $resulttime");
    
    $searchquery->set_hits($searcher->get_resultcount);
    
    if ($searcher->have_results) {

        $nav = Data::Pageset->new({
            'total_entries'    => $searcher->get_resultcount,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });
        	
        $logger->debug("Results found #".$searcher->get_resultcount);
                
        $recordlist = $searcher->get_records();

    }
    else {
        $logger->debug("No results found #".$searcher->get_resultcount);
    }
    
    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation in
    # den einzeltreffern

    my $total_hits  = $self->stash('total_hits') || 0 ;
    my $resultcount = $searcher->get_resultcount || 0 ;

    return Mojo::Promise->resolve({
	searchtime => $resulttime,
	nav => $nav,
	facets => $facets_ref,
	recordlist => $recordlist,
	hits => $resultcount,
	total_hits => $total_hits + $resultcount,	    
    });
}

sub get_start_templatename {
    my $self = shift;
    
    my $config = $self->stash('config');
    
    return $config->{tt_availability_search_start_tname};
}

sub get_end_templatename {
    my $self = shift;
    
    my $config = $self->stash('config');
    
    return $config->{tt_availability_search_end_tname};
}

sub rewrite_searchterms {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;

    my $viewname            = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}            : undef;
    
    my $searchquery   = $self->stash('searchquery');
    my $config        = $self->stash('config');
    
    my $new_searchquery = new OpenBib::SearchQuery;

    if ($viewname){
	my $profileid = $config->get_searchprofile_of_view($viewname);
	$new_searchquery->set_searchprofile($profileid);
    }
    
    if (defined $database && $database eq "eds"){
	$logger->debug("Trying to use EDS search params");

	my @src = ();
	if ($searchquery->get_searchfield('journal')){
	    push @src, $searchquery->get_searchfield('journal')->{val};
	}
	if ($searchquery->get_searchfield('volume')){
	    push @src, $searchquery->get_searchfield('volume')->{val};
	}
	if ($searchquery->get_searchfield('issue')){
	    push @src, $searchquery->get_searchfield('issue')->{val};
	}
	if ($searchquery->get_searchfield('pages')){
	    push @src, $searchquery->get_searchfield('pages')->{val};
	}

	if ($searchquery->get_searchfield('title')){
	    $new_searchquery->set_searchfield('title',$searchquery->get_searchfield('title')->{val});
	}
	
	if ($searchquery->get_searchfield('person')){
	    $new_searchquery->set_searchfield('person',$searchquery->get_searchfield('person')->{val});
	}

	if ($searchquery->get_searchfield('issn')){
	    $new_searchquery->set_searchfield('issn',$searchquery->get_searchfield('issn')->{val});
	}
	
	if (@src){
	    $new_searchquery->set_searchfield('source',join(' ',@src));
	}	
    }
    else {
	$logger->debug("Trying to restrict searchquery to issn/isbn (DB: $database / View: $viewname)");

	if ($searchquery->get_searchfield('journal') || $searchquery->get_searchfield('volume')){
	    if ($searchquery->get_searchfield('issn')){
		$new_searchquery->set_searchfield('issn',$searchquery->get_searchfield('issn')->{val});
	    }
	    else {
		$new_searchquery->set_searchfield('title',$searchquery->get_searchfield('journal')->{val});
	    }
	}
	elsif ($searchquery->get_searchfield('isbn') || $searchquery->get_searchfield('title')){
	    if ($searchquery->get_searchfield('isbn')){
		$new_searchquery->set_searchfield('isbn',$searchquery->get_searchfield('isbn')->{val});
	    }
	    else {
		$new_searchquery->set_searchfield('title',$searchquery->get_searchfield('title')->{val});
	    }
	}
	
	if ($logger->is_debug){
	    $logger->debug("Rewriting searchquery: ".$new_searchquery->to_json);
	}
    }

    return $new_searchquery;
}

sub show_search_single_target_p {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;

    my $viewname            = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}            : undef;

    my $searchquery         = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}         : $self->stash('searchquery');
    
    my $authority          = exists $arg_ref->{authority}
        ? $arg_ref->{authority}           : undef;
    
    my $templatename       = exists $arg_ref->{templatename}
        ? $arg_ref->{templatename}           : undef;

    my $type               = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'joined';
    
    my $config = $self->stash('config');

    my $promise = Mojo::Promise->new;

    my $searchresult = "";
    
    my $result_p = (defined $viewname)?$self->search_p({view => $viewname, searchquery => $searchquery}):$self->search_p({database => $database, searchquery => $searchquery});
    
    return $result_p->then(sub {
	my $result_ref = shift;
	
	if ($logger->is_debug){
	    $logger->debug("Searchresult result_ref: ".YAML::Dump($result_ref));
	}
	
	unless ($templatename) {
	    $templatename = ($type eq "sequential")?$config->{tt_search_title_item_tname}:$config->{tt_search_title_combined_tname} 
	}
	
	my $args_ref = {
	    templatename => $templatename,
	    result => $result_ref,
	};
	
	if ($database){
	    $args_ref->{database} = $database;
	}
	
	if ($viewname){
	    $args_ref->{viewname} = $viewname;
	}
	
	$searchresult = $self->print_resultitem($args_ref);
	
	$logger->debug("Searchresult: $searchresult");
	
	return $searchresult;
	
		    });
    
}

1;
