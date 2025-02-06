####################################################################
#
#  OpenBib::Mojo::Controller::Search::SeparateFacets.pm
#
#  Dieses File ist (C) 2003-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Search::SeparateFacets;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable ();
use Template;
use YAML();

use OpenBib::Common::Stopwords;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;

    my $authority          = exists $arg_ref->{authority}
        ? $arg_ref->{authority}           : undef;

    # Dispatched Args
    my $view         = $self->stash('view');
    
    # Shared Args
    my $r            = $self->stash('r');
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

    # Besteht das Suchprofil nur aus einer Datenbank, dann den Datenbanknamen setzen.
    # So koennen per API angesteuerte Backends gemeinsam mit anderen Profilen ueber den zugehoerigen searchprofile-Parameter
    # angesteuert werden (OpenBib::Search::Factory)
    if ($database){
	# Nur Kataloge im View sind erlaubt
	my @in_restricted_dbs = $config->restrict_databases_to_view({ databases => [ $database ], view => $view });
	unless (@in_restricted_dbs){
	    $logger->error("Blocked access to db $database being not in view $view");
	    $database = undef;
	}
    }
    elsif (!$database && $searchquery && $searchquery->get_searchprofile){
	my @databases = $config->get_databases_of_searchprofile($searchquery->get_searchprofile);
	
	if (scalar @databases == 1){
	    $database = $databases[0];
	}
    }
    
    my $search_args_ref = {};
    $search_args_ref->{options}      = $self->query2hashref;
    $search_args_ref->{database}     = $database if (defined $database);
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
    
    
    $self->stash('searchtime',$resulttime);
    $self->stash('facets',$facets_ref);
    $self->stash('hits',$searcher->get_resultcount);

    my $ttdate = {};
    
    return $self->print_page($config->{tt_search_separate_facets_tname},$ttdata);
}

1;
