#####################################################################
#
#  OpenBib::Handler::PSGI::Titles.pm
#
#  Copyright 2009-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Titles;

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

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_collection'         => 'show_collection',        
        'show_record'             => 'show_record',
        'show_popular'            => 'show_popular',
        'show_dbis_recommendations'  => 'show_dbis_recommendations',
        'show_recent'                => 'show_recent',
        'show_availability'          => 'show_availability',
        'show_record_related_records'       => 'show_record_related_records',
        'show_record_similar_records'       => 'show_record_similar_records',
        'show_record_same_records'          => 'show_record_same_records',
        'show_record_fields'                => 'show_record_fields',
        'show_record_holdings'              => 'show_record_holdings',
        'show_record_circulation'           => 'show_record_circulation',
        'redirect_to_bibsonomy'      => 'redirect_to_bibsonomy',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_popular {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    
    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $dbinfotable    = $self->param('dbinfo');
    
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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $dbinfotable    = $self->param('dbinfo');

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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $dbinfotable    = $self->param('dbinfo');
    
    my $statistics  = new OpenBib::Statistics();
    my $utils       = new OpenBib::Template::Utilities;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    my $profile       = $config->get_profilename_of_view($view);

    my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});
    
    my $recordlist = $catalog->get_recent_titles({
        limit    => 50,
    })->load_brief_records;

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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $representation = $self->param('represenation');
    my $dbinfotable    = $self->param('dbinfo');
    
    # CGI Args
    my $sb        = $query->param('sb')        || $config->{default_local_search_backend};


    my $search_args_ref = {};
    $search_args_ref->{options}      = OpenBib::Common::Util::query2hashref($query);
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

    $self->param('nav',$nav);
    $self->param('facets',$facets_ref);
    $self->param('recordlist',$recordlist);
    $self->param('hits',$searcher->get_resultcount);
    $self->param('total_hits',$self->param('total_hits')+$searcher->get_resultcount);

    my $ttdata = {
        database    => $database,
        recordlist  => $recordlist,
        facets      => $self->param('facets'),
        hits        => $self->param('hits'),
        nav         => $self->param('nav'),
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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $representation = $self->param('represenation');
    my $dbinfotable    = $self->param('dbinfo');

    # CGI Args
    my $stid          = $query->param('stid')              || '';
    my $callback      = $query->param('callback')  || '';
    my $queryid       = $query->param('queryid')   || '';
    my $format        = $query->param('format')    || 'full';
    my $no_log        = $query->param('no_log')    || '';
    
    if ($user->{ID} && !$userid){
        my $args = "?l=".$self->param('lang');

        return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/title/database/$database/id/".$self->decode_id($titleid)."$representation$args",303);
    }
    
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

        $logger->debug("1");        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config})->load_full_record;

        $logger->debug("2");        
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
        $logger->debug("3");        
        # Literaturlisten finden

        my $litlists_ref = $user->get_litlists_of_tit({titleid => $titleid, dbname => $database, view => $view});

        # Anreicherung mit OLWS-Daten
        if (defined $query->param('olws') && $query->param('olws') eq "Viewer"){
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
        
        $record->enrich_content({ profilename => $sysprofile });

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

        return $self->print_page($config->{tt_titles_record_tname},$ttdata);
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
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');
    
    if ($titleid && $database){
        my $title_as_bibtex = OpenBib::Record::Title->new({id =>$titleid, database => $database, config => $config })->load_full_record->to_bibtex({utf8 => 1});
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
        $self->header_add('Content-Type' => 'text/html; charset=UTF-8');
        return $self->redirect($bibsonomy_url);
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
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    my $availability_status = 0;
    
    if ($titleid && $database){
        # Wenn Datenbank an Ausleihsystem gekoppelt, dann Medienstatus holen und auswerten
	my $thisdbinfo = $config->get_databaseinfo->single({ dbname => $database });
        if ($thisdbinfo && $thisdbinfo->get_column('circ')){
	    my $record;
	    my $sru_status_ref = [];

	    # Alma und SRU?
	    if ($thisdbinfo->get_column('circtype') eq "alma" && defined $config->get('alma')->{listitem_status} && $config->get('alma')->{listitem_status} eq "sru"){
		$sru_status_ref = $self->get_status_via_alma_sru({ titleid => $titleid, database => $database });
		$record = OpenBib::Record::Title->new({id => $titleid, database => $database, config => $config });

	    }
	    else {
		$record = OpenBib::Record::Title->new({id => $titleid, database => $database, config => $config })->load_circulation;
	    }
	    
            # TT-Data erzeugen
            my $ttdata={
                database       => $database, # Zwingend wegen common/subtemplate
                record         => $record,
                titleid        => $titleid,
		sru_status     => $sru_status_ref,
            };

            return $self->print_page($config->{tt_titles_record_availability_tname},$ttdata);
        }
    }

    return;
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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $representation = $self->param('represenation');
    my $dbinfotable    = $self->param('dbinfo');

    # CGI Args
    my $stid          = $query->param('stid')              || '';
    my $callback      = $query->param('callback')  || '';
    my $queryid       = $query->param('queryid')   || '';
    my $format        = $query->param('format')    || 'full';
    my $no_log        = $query->param('no_log')    || '';
        
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

        $logger->debug("1");        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config})->load_full_record;

        $logger->debug("2");        
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
        $logger->debug("3");        

        my $sysprofile= $config->get_profilename_of_view($view);

        if ($logger->is_debug){
            $logger->debug("Vor Enrichment:".YAML::Dump($record->get_fields));
        }
        
        $record->enrich_content({ profilename => $sysprofile });

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
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $representation = $self->param('represenation');
    my $dbinfotable    = $self->param('dbinfo');

    # CGI Args
    my $stid          = $query->param('stid')              || '';
    my $callback      = $query->param('callback')  || '';
    my $queryid       = $query->param('queryid')   || '';
    my $format        = $query->param('format')    || 'full';
    my $no_log        = $query->param('no_log')    || '';


    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");

        $logger->debug("1");        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config})->load_full_record;

        $logger->debug("2");        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 0 is ".timestr($timeall));
        }

        my $poolname=$dbinfotable->get('dbnames')->{$database};

        my $sysprofile= $config->get_profilename_of_view($view);

        if ($logger->is_debug){
            $logger->debug("Vor Enrichment:".YAML::Dump($record->get_fields));
        }
        
        $record->enrich_content({ profilename => $sysprofile });

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
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config})->load_circulation;

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
        };

        return $self->print_page($config->{tt_titles_record_circulation_tname},$ttdata);
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
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config });

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
        };

        return $self->print_page($config->{tt_titles_record_related_records_tname},$ttdata);
    }

    return;
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
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

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
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

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

    # Schwartz'ian Transform
        
    my @sorted = map { $_->[0] }
    sort { $a->[1] cmp $b->[1] }
    map { [$_, sprintf("%03d:%s:%s:%s",$_->{department_id},$_->{department},$_->{storage},$_->{location_mark})] }
    @{$array_ref};
        
    return \@sorted;
}

sub get_status_via_alma_sru {
    my ($self,$arg_ref)=@_;
    
    # Set defaults
    my $titleid                = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}        : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sru_status_ref = [];

    unless ($titleid && $titleid =~m/^\d+$/){
	return $sru_status_ref;
    }

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    my $config         = $self->param('config');

    my $circ_config    = $config->load_alma_circulation_config;
    
    my $url=$config->get('alma')->{'sru_baseurl'}."?version=1.2&operation=searchRetrieve&recordSchema=marcxml&query=alma.mms_id=$titleid&maximumRecords=1";

    $logger->debug("Request: $url");

    my $request = HTTP::Request->new('GET' => $url);
    
    my $response = $ua->request($request);
    
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
    
    return $sru_status_ref;    
}

1;
