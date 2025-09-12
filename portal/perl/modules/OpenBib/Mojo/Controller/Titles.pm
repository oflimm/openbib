#####################################################################
#
#  OpenBib::Mojo::Controller::Titles.pm
#
#  Copyright 2009-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Titles;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);
use Date::Manip;
use URI::Escape qw(uri_escape uri_escape_utf8);
use Encode 'decode_utf8';
use XML::LibXML;

use OpenBib::Catalog;
use OpenBib::Catalog::Factory;
use OpenBib::Common::Util;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Search::Factory;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Util;
use OpenBib::SearchQuery;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Template::Utilities;
use OpenBib::Statistics;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_popular {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    
    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $dbinfotable    = $self->stash('dbinfo');
    
    my $statistics  = new OpenBib::Statistics();
    my $utils       = new OpenBib::Template::Utilities;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    my $profile       = $config->get_profilename_of_view($view);
    
    # TT-Data erzeugen
    my $ttdata={
        database      => $database,
        profile       => $profile,
        viewdesc      => $viewdesc,
        statistics    => $statistics,
        utils         => $utils,
    };

    my $templatename = "tt_titles_popular".(($database)?'_by_database':'')."_tname";
    return $self->print_page($config->{$templatename},$ttdata);
}

sub show_dbis_recommendations {
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
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $dbinfotable    = $self->stash('dbinfo');

    my $searchquery = OpenBib::SearchQuery->new({r => $r, view => $view});

    # TT-Data erzeugen
    my $ttdata={
        searchquery => $searchquery,
    };

    my $templatename = "tt_titles_dbis_recommendations_tname";
    return $self->print_page($config->{$templatename},$ttdata);
}

sub show_recent {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    
    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $dbinfotable    = $self->stash('dbinfo');
    
    my $statistics  = new OpenBib::Statistics();
    my $utils       = new OpenBib::Template::Utilities;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    my $profile       = $config->get_profilename_of_view($view);

    my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});
    
    my $recordlist_p = $catalog->get_recent_titles_p({
        limit    => 50,
						     });

    $recordlist_p->then(sub {
	my $recordlist = shift;

	return $recordlist->load_brief_records_p;
			})->then(sub {
			    my $recordlist = shift;
	
			    # TT-Data erzeugen
			    my $ttdata={
				database      => $database,
				recordlist    => $recordlist,
				profile       => $profile,
				viewdesc      => $viewdesc,
				statistics    => $statistics,
				utils         => $utils,
			    };
			    
			    my $templatename = "tt_titles_recent".(($database)?'_by_database':'')."_tname";
			    
			    return $self->print_page($config->{$templatename},$ttdata);
				 });
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $database       = $self->param('database');

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
    my $path_prefix    = $self->stash('path_prefix');
    my $representation = $self->stash('represenation');
    my $dbinfotable    = $self->stash('dbinfo');
    
    # CGI Args
    my $sb        = $r->param('sb')        || $config->{default_local_search_backend};

    # Katalog aktiv bzw. in View?
    unless ($config->database_defined_in_view({ database => $database, view => $view }) && $config->db_is_active($database)){
	return $self->print_warning("Der Katalog existiert nicht.");
    }

    my $search_args_ref = {};
    $search_args_ref->{options}      = $self->query2hashref;
    $search_args_ref->{database}     = $database if (defined $database);
    $search_args_ref->{sb}           = $sb if (defined $sb);
    $search_args_ref->{queryoptions} = $queryoptions if (defined $queryoptions);
    $search_args_ref->{config}       = $config if (defined $config);
    
    # Searcher erhaelt per default alle Query-Parameter uebergeben. So kann sich jedes
    # Backend - jenseits der Standard-Rechercheinformationen in OpenBib::SearchQuery
    # und OpenBib::QueryOptions - alle weiteren benoetigten Parameter individuell
    # heraussuchen.
    # Derzeit: Nur jeweils ein Parameter eines 'Parameternamens'
    
    my $searcher = OpenBib::Search::Factory->create_searcher($search_args_ref);

    # Browsing starten
    $searcher->browse;

    my $facets_ref = $searcher->get_facets;
    
    my $nav;
    my $recordlist = OpenBib::RecordList::Title->new;
    
    if ($searcher->have_results) {

        $logger->debug("Results found #".$searcher->get_resultcount);
        
        $nav = Data::Pageset->new({
            'total_entries'    => $searcher->get_resultcount,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });
        
        $recordlist = $searcher->get_records();
    }
    else {
        $logger->debug("No results found #".$searcher->get_resultcount);
    }
    
    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation in
    # den einzeltreffern

    $self->stash('nav',$nav);
    $self->stash('facets',$facets_ref);
    $self->stash('recordlist',$recordlist);
    $self->stash('hits',$searcher->get_resultcount);
    $self->stash('total_hits',$self->param('total_hits')+$searcher->get_resultcount);

    my $ttdata = {
        database    => $database,
        recordlist  => $recordlist,
        facets      => $self->stash('facets'),
        hits        => $self->stash('hits'),
        nav         => $self->stash('nav'),
    };
    
    return $self->print_page($config->{tt_titles_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $database       = $self->param('database');
    my $titleid        = $self->strip_suffix($self->decode_id($self->param('titleid')));

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
    my $path_prefix    = $self->stash('path_prefix');
    my $representation = $self->stash('represenation');
    my $dbinfotable    = $self->stash('dbinfo');

    # CGI Args
    my $stid          = $r->param('stid')              || '';
    my $callback      = $r->param('callback')  || '';
    my $queryid       = $r->param('queryid')   || '';
    my $format        = $r->param('format')    || 'full';
    my $no_log        = $r->param('no_log')    || '';
    my $flushcache    = $r->param('flush_cache')    || '';

    # Katalog aktiv bzw. in View?
    unless ($config->database_defined_in_view({ database => $database, view => $view }) && $config->db_is_active($database)){
	return $self->print_warning("Der Katalog existiert nicht.");
    }
    
    if ($user->{ID} && !$userid){
        my $args = "?l=".$self->stash('lang');

        return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/databases/id/$database/titles/id/".$self->decode_id($titleid)."$representation$args",303);
    }
    
    if ($userid && !$self->is_authenticated('user',$userid)){

        $logger->debug("Testing authorization for given userid $userid");
        return  $self->print_warning($msg->maketext("Zugriff verboten"));
    }

    # Flush from memcached
    if ($flushcache){
	my $memc_key = "record:title:full:$database:$titleid";
	$config->{memc}->delete($memc_key) if ($config->{memc});
    }
    
    $self->render_later;
    
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    
    $logger->debug("Vor");
    my $searchquery   = OpenBib::SearchQuery->new({r => $r, view => $view, session => $session, config => $config});

    my $authenticatordb = $user->get_targetdb_of_session($session->{ID});
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage -1 is ".timestr($timeall));
    }

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");

        $logger->debug("1");        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config});
	
	my $record_p   = $record->load_full_record_p;

	my $litlists_p = $user->get_litlists_of_tit_p({titleid => $titleid, dbname => $database, view => $view});
	    	
	$record_p->then(sub {

	    my $record = shift;

	    $logger->debug("3");        
	    # Literaturlisten finden
	    
	    # Anreicherung mit OLWS-Daten
	    if (defined $r->param('olws') && $r->param('olws') eq "Viewer"){
		if (defined $circinfotable->get($database) && defined $circinfotable->get($database)->{circcheckurl}){
		    $logger->debug("Endpoint: ".$circinfotable->get($database)->{circcheckurl});
		    my $soapresult;
		    eval {
			my $soap = SOAP::Lite
			    -> uri("urn:/Viewer")
			    -> proxy($circinfotable->get($database)->{circcheckurl});
			
			my $result = $soap->get_item_info(
			    SOAP::Data->name(parameter  =>\SOAP::Data->value(
						 SOAP::Data->name(collection => $circinfotable->get($database)->{circdb})->type('string'),
						 SOAP::Data->name(item       => $titleid)->type('string'))));
			
			unless ($result->fault) {
			    $soapresult=$result->result;
			}
			else {
			    if ($logger->is_debug){
				$logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
			    }
			}
		    };
		    
		    if ($@){
			$logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
		    }
		    
		    $record->{olws}=$soapresult;
		}
	    }
	    
	    
	    my $sysprofile= $config->get_profilename_of_view($view);
	    
	    if ($logger->is_debug){
		$logger->debug("Vor Enrichment:".YAML::Dump($record->get_fields));
	    }
	    
	    my $enriched_record_p = $record->enrich_content_p({ profilename => $sysprofile });
	    
	    return Mojo::Promise->all($enriched_record_p,$litlists_p);
			})->then(sub {
			    my $record = shift;
			    my $litlists_ref = shift;

			    $record = $record->[0];
			    
			    $logger->debug("1 - Ref Record: ".ref($record)." ".YAML::Dump($record));
    			    $logger->debug("1 - Ref Litlist: ".ref($litlists_ref)." ".YAML::Dump($litlists_ref));        	    
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 0 is ".timestr($timeall));
			    }
			    
			    my $poolname=$dbinfotable->get('dbnames')->{$database};
			    
			    # if ($queryid){
			    #     $searchquery->load({sid => $session->{sid}, queryid => $queryid});
			    # }
			    
			    my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
				session    => $session,
				database   => $database,
				titleid    => $titleid,
				view       => $view,
				session    => $session,
												});
			    
			    my $active_feeds = $config->get_activefeeds_of_db($database);
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 1 is ".timestr($timeall));
	    }
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 2 is ".timestr($timeall));
			    }
			    # TT-Data erzeugen
			    my $ttdata={
				database    => $database, # Zwingend wegen common/subtemplate
				userid      => $userid,
				poolname    => $poolname,
				prevurl     => $prevurl,
				nexturl     => $nexturl,
				#            qopts       => $queryoptions->get_options,
				queryid     => $searchquery->get_id,
				record      => $record,
				titleid      => $titleid,
				
				format      => $format,
				
				searchquery => $searchquery,
				activefeed  => $active_feeds,
				
				authenticatordb => $authenticatordb,
				
				litlists          => $litlists_ref,
				highlightquery    => \&highlightquery,
				sort_circulation => \&sort_circulation,
			    };
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 3 is ".timestr($timeall));
			    }
			    
			    # Log Event
			    
			    my $isbn;
			    
			    my $abstract_fields_ref = $record->to_abstract_fields;
			    
			    if (defined $abstract_fields_ref->{isbn} && $abstract_fields_ref->{isbn}){
				$isbn = $abstract_fields_ref->{isbn};
				$isbn =~s/ //g;
				$isbn =~s/-//g;
				$isbn =~s/X/x/g;
			    }
			    
			    if (!$no_log){
				$session->log_event({
				    type      => 10,
				    content   => {
					id       => $titleid,
					database => $database,
					isbn     => $isbn,
					#		    fields   => $abstract_fields_ref,
				    },
				    serialize => 1,
						    });
			    }
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time for show_record is ".timestr($timeall));
			    }
			    
			    return $self->print_page($config->{tt_titles_record_tname},$ttdata);
			    
				 });    
    }
    else {
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for show_record is ".timestr($timeall));
        }

        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }
}

sub redirect_to_bibsonomy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->decode_id($self->param('titleid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $msg            = $self->stash('msg');
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');
    my $dbinfotable    = $self->stash('dbinfo');
    
    if ($titleid && $database){
        my $record = OpenBib::Record::Title->new({id =>$titleid, database => $database, config => $config });

	my $record_p = $record->load_full_record_p;

	$record_p->then(sub {
	    my $title_as_bibtex_record = shift;
	    
	    my $title_as_bibtex = $title_as_bibtex_record->to_bibtex({utf8 => 1});
	    #        $title=~s/\n/ /g;
	    
	    $logger->debug("Title as BibTeX: $title_as_bibtex");
	    
	    my $bibsonomy_url = "http://www.bibsonomy.org/BibtexHandler?requTask=upload&url=".uri_escape_utf8("http://$servername$path_prefix/$config->{home_loc}")."&description=".uri_escape_utf8($config->get_viewdesc_from_viewname($view))."&encoding=UTF-8&selection=".uri_escape_utf8($title_as_bibtex);
	    
	    $logger->debug("Title as BibTeX: $title_as_bibtex");
	    
	    # my $redirect_url = "$path_prefix/$config->{redirect_loc}?type=510;url=".uri_escape_utf8($bibsonomy_url);
	    
	    $logger->debug($bibsonomy_url);
	    
	    $session->log_event({
		type      => 510,
		content   => $bibsonomy_url
				});
	    
	    # TODO GET?
	    $self->res->headers->content_type('text/html; charset=UTF-8');
	    return $self->redirect($bibsonomy_url);
				 });
    }
    else {
        return $self->print_warning($msg->maketext("Es wurden zuwenige Parameter übergeben."));
    }
}

sub show_availability {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->decode_id($self->param('titleid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');
    my $dbinfotable    = $self->stash('dbinfo');

    my $availability_status = 0;
    
    if ($titleid && $database){
        # Wenn Datenbank an Ausleihsystem gekoppelt, dann Medienstatus holen und auswerten
	my $thisdbinfo = $config->get_databaseinfo->single({ dbname => $database });
        if ($thisdbinfo && $thisdbinfo->get_column('circ')){
	    my $record;
	    my $sru_status_ref = [];

            # TT-Data erzeugen
            my $ttdata={
                database       => $database, # Zwingend wegen common/subtemplate
                titleid        => $titleid,
            };
	    
	    # Alma und SRU?
	    if ($thisdbinfo->get_column('circtype') eq "alma" && defined $config->get('alma')->{listitem_status} && $config->get('alma')->{listitem_status} eq "sru"){
		my $sru_status_p = $self->get_status_via_alma_sru_p({ titleid => $titleid, database => $database });
		$record = OpenBib::Record::Title->new({id => $titleid, database => $database, config => $config });

		$ttdata->{record} = $record;		
		
		$sru_status_p->then(sub {
		    my $sru_status_ref = shift;

		    $ttdata->{sru_status} = $sru_status_ref;
		    
		    return $self->print_page($config->{tt_titles_record_availability_tname},$ttdata);
				    });		

	    }
	    else {
		my $record = OpenBib::Record::Title->new({id => $titleid, database => $database, config => $config });

		my $circulation_p = $record->load_circulation_p;

		$circulation_p->then(sub {
		    my $circulation_ref = shift;
		    
		    $logger->debug("circulation_ref ".YAML::Dump($circulation_ref));
		    
		    $record->set_circulation($circulation_ref);
		    
		    $ttdata->{record} = $record;		

		    return $self->print_page($config->{tt_titles_record_availability_tname},$ttdata);
				});
		
	    }
	    

        }
    }

    return; # $self->render( text => '' );
}

sub show_record_fields {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $database       = $self->param('database');
    my $titleid        = $self->strip_suffix($self->decode_id($self->param('titleid')));

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
    my $path_prefix    = $self->stash('path_prefix');
    my $representation = $self->stash('represenation');
    my $dbinfotable    = $self->stash('dbinfo');

    # CGI Args
    my $stid          = $r->param('stid')              || '';
    my $callback      = $r->param('callback')  || '';
    my $queryid       = $r->param('queryid')   || '';
    my $format        = $r->param('format')    || 'full';
    my $no_log        = $r->param('no_log')    || '';
        
    if ($userid && !$self->is_authenticated('user',$userid)){
        $logger->debug("Testing authorization for given userid $userid");
        return;
    }

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    $logger->debug("Vor");
    my $searchquery   = OpenBib::SearchQuery->new({r => $r, view => $view, session => $session, config => $config});

    my $authenticatordb = $user->get_targetdb_of_session($session->{ID});
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage -1 is ".timestr($timeall));
    }

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");

        my $sysprofile= $config->get_profilename_of_view($view);
	
        $logger->debug("1");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config});

	my $record_p     = $record->load_full_record_p;

	$record_p->then(sub {
	    my $record = shift;
	    
        $logger->debug("2");        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 0 is ".timestr($timeall));
        }


        # if ($queryid){
        #     $searchquery->load({sid => $session->{sid}, queryid => $queryid});
        # }


        if ($logger->is_debug){
            $logger->debug("Vor Enrichment:".YAML::Dump($record->get_fields));
        }

	    	return $record->enrich_content_p({ profilename => $sysprofile });
			})->then(sub {
			    my $record = shift;
			    
			    my $poolname=$dbinfotable->get('dbnames')->{$database};
			    
			    my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
				session    => $session,
				database   => $database,
				titleid    => $titleid,
				view       => $view,
				session    => $session,
												});
			    
			    my $active_feeds = $config->get_activefeeds_of_db($database);
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 1 is ".timestr($timeall));
			    }
			    $logger->debug("3");        
			    
			    
			    if ($logger->is_debug){
				$logger->debug("Nach Enrichment:".YAML::Dump($record->get_fields));
			    }
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 2 is ".timestr($timeall));
			    }
			    
			    # TT-Data erzeugen
			    my $ttdata={
				database    => $database, # Zwingend wegen common/subtemplate
				userid      => $userid,
				poolname    => $poolname,
				prevurl     => $prevurl,
				nexturl     => $nexturl,
				#            qopts       => $queryoptions->get_options,
				queryid     => $searchquery->get_id,
				record      => $record,
				titleid      => $titleid,
				
				format      => $format,
				
				searchquery => $searchquery,
				activefeed  => $active_feeds,
				
				authenticatordb => $authenticatordb,
				
				highlightquery    => \&highlightquery,
			    };
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 3 is ".timestr($timeall));
			    }
			    
			    # Log Event
			    
			    my $isbn;
			    
			    if ($record->has_field("T0540") && $record->get_fields->{T0540}[0]{content}){
				$isbn = $record->get_fields->{T0540}[0]{content};
				$isbn =~s/ //g;
				$isbn =~s/-//g;
				$isbn =~s/X/x/g;
			    }
			    
			    if (!$no_log){
				$session->log_event({
				    type      => 10,
				    content   => {
					id       => $titleid,
					database => $database,
					isbn     => $isbn,
					fields   => $record->get_fields,
				    },
				    serialize => 1,
						    });
			    }
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time for show_record is ".timestr($timeall));
			    }
			    
			    return $self->print_page($config->{tt_titles_record_fields_tname},$ttdata);
				 });
    }
    else {
	if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for show_record is ".timestr($timeall));
        }
	
        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }
}

sub show_record_holdings {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $database       = $self->param('database');
    my $titleid        = $self->strip_suffix($self->decode_id($self->param('titleid')));

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
    my $path_prefix    = $self->stash('path_prefix');
    my $representation = $self->stash('represenation');
    my $dbinfotable    = $self->stash('dbinfo');

    # CGI Args
    my $stid          = $r->param('stid')              || '';
    my $callback      = $r->param('callback')  || '';
    my $queryid       = $r->param('queryid')   || '';
    my $format        = $r->param('format')    || 'full';
    my $no_log        = $r->param('no_log')    || '';


    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");

        $logger->debug("1");        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config});

        $logger->debug("2");        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 0 is ".timestr($timeall));
        }

	my $record_p = $record->load_full_record_p;

	$record_p->then(sub {
	    my $record = shift;
	    
	    my $sysprofile= $config->get_profilename_of_view($view);
	    
	    if ($logger->is_debug){
		$logger->debug("Vor Enrichment:".YAML::Dump($record->get_fields));
	    }

	    return $record->enrich_content_p({ profilename => $sysprofile });
			})->then(sub {
			    my $record = shift;

			    my $poolname=$dbinfotable->get('dbnames')->{$database};
			    
			    if ($logger->is_debug){
				$logger->debug("Nach Enrichment:".YAML::Dump($record->get_fields));
			    }
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time until stage 2 is ".timestr($timeall));
			    }
			    
			    # TT-Data erzeugen
			    my $ttdata={
				database    => $database, # Zwingend wegen common/subtemplate
				userid      => $userid,
				poolname    => $poolname,
				#            qopts       => $queryoptions->get_options,
				record      => $record,
				titleid      => $titleid,
			    };
			    
			    if ($config->{benchmark}) {
				$btime=new Benchmark;
				$timeall=timediff($btime,$atime);
				$logger->info("Total time for show_record is ".timestr($timeall));
			    }
			    
			    return $self->print_page($config->{tt_titles_record_holdings_tname},$ttdata);
				 });
    }
    else {
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for show_record is ".timestr($timeall));
        }

        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }
}

sub show_record_circulation {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->decode_id($self->param('titleid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');
    my $dbinfotable    = $self->stash('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config});

	my $record_p = $record->load_circulation_p;

	$record_p->then(sub {
	    my $record = shift;
	    
	    # TT-Data erzeugen
	    my $ttdata={
		database        => $database, # Zwingend wegen common/subtemplate
		record          => $record,
		titleid         => $titleid,
	    };
	    
	    return $self->print_page($config->{tt_titles_record_circulation_tname},$ttdata);
			});
    }

    return;
}

sub show_record_related_records {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->decode_id($self->param('titleid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');
    my $dbinfotable    = $self->stash('dbinfo');
    my $msg            = $self->stash('msg');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config });

	# Todo: Excluded locations via Filter
	my $enriched_record_p = $record->enrich_related_records_p({ viewname => $view });

	$enriched_record_p->then(sub {
	    my $record = shift;
	    
	    # TT-Data erzeugen
	    my $ttdata={
		database        => $database, # Zwingend wegen common/subtemplate
		record          => $record,
		titleid         => $titleid,
	    };
	    
	    return $self->print_page($config->{tt_titles_record_related_records_tname},$ttdata);
				  });
    }

    return $self->print_warning($msg->maketext("Keine valide Anfrage"));
}

sub show_record_similar_records {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->decode_id($self->param('titleid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');
    my $dbinfotable    = $self->stash('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config});

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
        };

        return $self->print_page($config->{tt_titles_record_similar_records_tname},$ttdata);
    }

    return;
}

sub show_record_same_records {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->decode_id($self->param('titleid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');
    my $dbinfotable    = $self->stash('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config });

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
        };

        return $self->print_page($config->{tt_titles_record_same_records_tname},$ttdata);
    }

    return;
}

sub highlightquery {
    my ($searchquery,$content) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Highlight Query

    return $content unless ($searchquery);
    
    my $term_ref = $searchquery->get_searchterms();

    return $content if (scalar(@$term_ref) <= 0);

    if ($logger->is_debug){
        $logger->debug("Terms: ".YAML::Dump($term_ref));
    }
    
    my $terms = join("|", grep /^\w{3,}/ ,@$term_ref);

    return $content if (!$terms);
    
    if ($logger->is_debug){
        $logger->debug("Term_ref: ".YAML::Dump($term_ref)."\nTerms: $terms");
        $logger->debug("Content vor: ".$content);
    }
    
    $content=~s/\b($terms)/<span class="ob-highlight_searchterm">$1<\/span>/ig unless ($content=~/http/);

    if ($logger->is_debug){
        $logger->debug("Content nach: ".$content);
    }
    
    return $content;
}

sub sort_circulation {
    my $array_ref = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return [] unless (ref $array_ref eq "ARRAY");
    
    # Schwartz'ian Transform
        
    my @sorted = map { $_->[0] }
    sort { $a->[1] cmp $b->[1] }
    map { [$_, sprintf("%s\t%s\t%s\t%s",$_->{department_id},$_->{department},$_->{storage},$_->{location_mark})] }
    @{$array_ref};
        
    return \@sorted;
}

sub get_status_via_alma_sru_p {
    my ($self,$arg_ref)=@_;
    
    # Set defaults
    my $titleid                = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}        : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sru_status_ref = [];

    unless ($titleid && $titleid =~m/^\d+$/){
	return Mojo::Promise->resolve($sru_status_ref);
    }

    my $config         = $self->stash('config');
    my $circ_config    = $config->load_alma_circulation_config;
    
    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout($config->get('alma')->{sru_timeout});
    
    my $url=$config->get('alma')->{'sru_baseurl'}."?version=1.2&operation=searchRetrieve&recordSchema=marcxml&query=alma.mms_id=$titleid&maximumRecords=1";

    $logger->debug("Request: $url");

    my $atime=new Benchmark;
    
    my $request = HTTP::Request->new('GET' => $url);
    
    my $response = $ua->request($request);

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    $resulttime = $resulttime * 1000.0; # to ms
    
    if ($resulttime > $config->get('alma')->{'sru_logging_threshold'}){
	$logger->error("Alma SRU call took $resulttime ms");
    }
    
    if ($logger->is_debug){
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success) {
	$logger->info($response->code . ' - ' . $response->message);
	return $sru_status_ref;
    }

    # recordData only
    my ($content) = $response->content =~m{<recordData>(.+?)</recordData>}sg;

    # delete namespace
    
    $content =~s{xmlns=".+?"}{}g;
    
    if ($logger->is_debug){
	$logger->debug("XML record: ".$content);
    }

    # Subfeld-Beschreibung des AVA-Feldes
    #
    # see: https://developers.exlibrisgroup.com/alma/apis/docs/bibs/R0VUIC9hbG1hd3MvdjEvYmlicy97bW1zX2lkfQ==/
    #
    # 0: Bib record ID
    # 8: Holdings ID
    # a: Institution Code
    # b: Library Code (*)
    # c: Location Name
    # d: Call number
    # e: Availability (available, unavailable, oder check_holdings) (*)
    # f: Total items
    # g: Non available items
    # h: Campus
    # j: Location code (*)
    # k: Call number type
    # p: Priority
    # q: Library name
    # t: Holdings Information
    # v: Calculated summary information
    #
    # Verwendete Subfelder sind mit (*) gekennzeichnet
    
    if ($content){
	my $parser = XML::LibXML->new();
	my $tree   = $parser->parse_string($content);
	my $root   = $tree->getDocumentElement;

	my @ava_nodes = $root->findnodes('/record/datafield[@tag="AVA"]');

	$logger->debug("# SRU AVA Nodes: ".$#ava_nodes);


	foreach my $ava_node (@ava_nodes){
	    my $library_code  = $ava_node->findvalue('subfield[@code="b"]');
	    my $location_code = $ava_node->findvalue('subfield[@code="j"]');
	    my $availability  = $ava_node->findvalue('subfield[@code="e"]');

	    my $this_circ_conf = {};
	    
	    if (defined $circ_config->{$library_code} && defined $circ_config->{$library_code}{$location_code}){
		$this_circ_conf = $circ_config->{$library_code}{$location_code};
	    }

	    my $availability_status = "unavailable";

	    if ($availability eq "available" && ($this_circ_conf->{loan} || $this_circ_conf->{order})){
		$availability_status = "loan";
	    }
	    # Unavailable bei Praesenzbibliotheken kann auch heissen, dass ein Buch in Erwerbung oder im Transfer ist.
	    elsif ($availability eq "unavailable" && !$this_circ_conf->{loan} && !$this_circ_conf->{order}){
		$availability_status = ""; # no status
	    }
	    elsif ($availability eq "available"){
		$availability_status = "presence";
	    }
	    elsif ($availability eq "check_holdings"){
		$availability_status = ""; # no status
	    }
	    
	    push @{$sru_status_ref}, {
		library_code        => $library_code,
		location_code       => $location_code,
		availability_status => $availability_status,
	    };
	}
    }
    
    if ($logger->is_debug){
	$logger->debug("SRU Status: ".YAML::Dump($sru_status_ref));
    }
    
    return Mojo::Promise->resolve($sru_status_ref);    
}

1;
