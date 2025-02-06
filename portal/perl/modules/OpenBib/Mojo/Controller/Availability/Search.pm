####################################################################
#
#  OpenBib::Mojo::Controller::Search::Availability::Search.pm
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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
    my $config         = $self->stash('config');
    
    my $availability_search_ref = $config->get('availability_search');

    # Abfangen von Portalen ohne Verfuegbarkeitsrecherche
    unless (defined $availability_search_ref->{$view}){
	return $self->print_error("Für dieses Portal bieten wir keine Verfügbarkeitsrecherche an.")
    }
    
    $logger->debug("Verfuegbarkeitsrecherche exisitiert fuer diesen View");

    $self->SUPER::show_search;
}

sub show_search_result {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $view        = $self->stash('view');
    
    my $config      = $self->stash('config');
    my $searchquery = $self->stash('searchquery');
    my $session     = $self->stash('session');
    my $writer      = $self->stash('writer');

    ######################################################################
    # Schleife ueber alle Datenbanken 

    ######################################################################

    $logger->debug("Starting sequential search");

    my $content_searchresult = "";
    
    my $availability_search_ref = $config->get('availability_search');
    
    # Recherche ueber einzelne Datenbanken
    if (defined $availability_search_ref->{$view} && %{$availability_search_ref->{$view}}){

	my $searchquery = $self->stash('searchquery');

	my $type = "default";

	if ($searchquery->get_searchfield('mediatype')){
	    my $mediatype = $searchquery->get_searchfield('mediatype')->{val};
	    $type = $mediatype if (defined $availability_search_ref->{$view}{$mediatype});
	}
	
	foreach my $target_ref (@{$availability_search_ref->{$view}{$type}}) {
	    $self->stash('viewname',''); # Entfernen fuer dieses Target
	    $self->stash('database',''); # Entfernen fuer dieses Target
	    
	    if ($target_ref->{type} eq "database"){
		my $database = $target_ref->{name};
		
		$self->stash('database',$database);
		
		$self->rewrite_searchterms();
		
		$logger->debug("Searching in DB $database");
		
		$self->search({database => $database});
		
		$logger->debug("Searching in DB $database done");
	    }
	    elsif ($target_ref->{type} eq "view"){
		my $searchprofile_of_view = $config->get_searchprofile_of_view($target_ref->{name});
		
		$self->rewrite_searchterms();

		my $searchquery = $self->stash('searchquery');
		$searchquery->set_searchprofile($searchprofile_of_view);
		$self->stash('searchquery',$searchquery);

		$self->stash('viewname',$target_ref->{name});
		
		$self->search();
	    }
	    
	    my $seq_content_searchresult = $self->print_resultitem({templatename => $config->{tt_availability_search_item_tname}});
	    
	    $logger->debug("Result: $seq_content_searchresult");
	    $writer->write(encode_utf8($seq_content_searchresult));
	}
    }
    
    return; #   $content_searchresult;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;

    my $authority          = exists $arg_ref->{authority}
        ? $arg_ref->{authority}           : undef;

    my $query        = $self->query();
    my $view         = $self->stash('view');
    my $config       = $self->stash('config');
    my $queryoptions = $self->stash('qopts');
    my $searchquery  = $self->stash('searchquery');
    my $session      = $self->stash('session');

    # Keine Suche durchfuehren, wenn Suchparameter ajax != 0
    # Dann wird die Suche ueber die Include-Repraesentation in den Templates
    # getriggert
    return if ($queryoptions->get_option('ajax'));
	       
    my $atime=new Benchmark;
    my $timeall;
    
    my $recordlist;
    my $resulttime;
    my $nav;

    # Verfuegbarkeitsrecherche ist nicht auf die Kataloge des aufrufenden Views beschraenkt!
    
    my $search_args_ref = {};
    $search_args_ref->{options}      = $self->query2hashref;
    $search_args_ref->{database}     = $database if (defined $database);
    $search_args_ref->{view}         = $view if (defined $view);
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
    
    my $btime   = new Benchmark;
    $timeall    = timediff($btime,$atime);
    $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info($searcher->get_resultcount . " results found in $resulttime");
    
    $searchquery->set_hits($searcher->get_resultcount);
    
    if ($searcher->have_results) {

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
    
    $self->stash('searchtime',$resulttime);
    $self->stash('recordlist',$recordlist);
    $self->stash('hits',$searcher->get_resultcount);
    $self->stash('total_hits',$total_hits + $resultcount);

    return;
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
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
        
    my $searchquery   = $self->stash('searchquery');
    my $database      = $self->stash('database');
    my $searchprofile = $self->stash('searchprofile');
    
    my $new_searchquery = new OpenBib::SearchQuery;
    
    $new_searchquery->set_searchprofile($searchprofile);

    if ($database eq "eds"){
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
	    $logger->debug($new_searchquery->to_json);
	}
    }
    
    $self->stash('searchquery',$new_searchquery);

    return;
}

1;
