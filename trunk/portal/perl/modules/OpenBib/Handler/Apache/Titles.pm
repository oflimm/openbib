#####################################################################
#
#  OpenBib::Handler::Apache::Titles.pm
#
#  Copyright 2009-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Titles;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common REDIRECT);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Benchmark ':hireswallclock';
use CGI::Application::Plugin::Redirect;
use Log::Log4perl qw(get_logger :levels);
use Date::Manip;
use URI::Escape qw(uri_escape uri_escape_utf8);
use Encode 'decode_utf8';

use OpenBib::Catalog;
use OpenBib::Catalog::Factory;
use OpenBib::Search::Factory;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Util;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Template::Utilities;

use base 'OpenBib::Handler::Apache';

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
    $self->print_page($config->{$templatename},$ttdata);

    return Apache2::Const::OK;
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

    my $searchquery = OpenBib::SearchQuery->instance({r => $r, view => $view});

    # TT-Data erzeugen
    my $ttdata={
        searchquery => $searchquery,
    };

    my $templatename = "tt_titles_dbis_recommendations_tname";
    $self->print_page($config->{$templatename},$ttdata);

    return Apache2::Const::OK;
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

    $self->print_page($config->{$templatename},$ttdata);

    return Apache2::Const::OK;
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
    my $sb        = $query->param('sb')        || $config->{local_search_backend};


    # Searcher erhaelt per default alle Query-Parameter uebergeben. So kann sich jedes
    # Backend - jenseits der Standard-Rechercheinformationen in OpenBib::SearchQuery
    # und OpenBib::QueryOptions - alle weiteren benoetigten Parameter individuell
    # heraussuchen.
    # Derzeit: Nur jeweils ein Parameter eines 'Parameternamens'
    
    my $searcher = OpenBib::Search::Factory->create_searcher({database => $database, sb => $sb });

    # Browsing starten
    $searcher->browse;

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
    $self->param('recordlist',$recordlist);
    $self->param('hits',$searcher->get_resultcount);
    $self->param('total_hits',$self->param('total_hits')+$searcher->get_resultcount);

    my $ttdata = {
        database    => $database,
        recordlist  => $recordlist,
        hits        => $self->param('hits'),
        nav         => $self->param('nav'),
    };
    
    $self->print_page($config->{tt_titles_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $database       = $self->param('database');
    my $titleid        = $self->strip_suffix($self->param('titleid'));

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

        return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/title/database/$database/id/$titleid.$representation$args",'303 See Other');
    }
    
    if ($userid && !$self->is_authenticated('user',$userid)){
        $logger->debug("Testing authorization for given userid $userid");
        return;
    }

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $searchquery   = OpenBib::SearchQuery->instance({r => $r, view => $view});
    my $authenticatordb = $user->get_targetdb_of_session($session->{ID});
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage -1 is ".timestr($timeall));
    }

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid})->load_full_record;

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 0 is ".timestr($timeall));
        }

        my $poolname=$dbinfotable->{dbnames}{$database};

        if ($queryid){
            $searchquery->load({sid => $session->{sid}, queryid => $queryid});
        }

        my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
            session    => $session,
            database   => $database,
            titleid     => $titleid,
            view       => $view,
        });

        my $active_feeds = $config->get_activefeeds_of_db($database);
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 1 is ".timestr($timeall));
        }
        
        # Literaturlisten finden

        my $litlists_ref = $user->get_litlists_of_tit({titleid => $titleid, dbname => $database});

        # Anreicherung mit OLWS-Daten
        if (defined $query->param('olws') && $query->param('olws') eq "Viewer"){
            if (exists $circinfotable->{$database} && exists $circinfotable->{$database}{circcheckurl}){
                $logger->debug("Endpoint: ".$circinfotable->{$database}{circcheckurl});
                my $soapresult;
                eval {
                    my $soap = SOAP::Lite
                        -> uri("urn:/Viewer")
                            -> proxy($circinfotable->{$database}{circcheckurl});
                
                    my $result = $soap->get_item_info(
                        SOAP::Data->name(parameter  =>\SOAP::Data->value(
                            SOAP::Data->name(collection => $circinfotable->{$database}{circdb})->type('string'),
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

        $record->enrich_content({ profilename => $sysprofile });
        
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
        };

        $self->print_page($config->{tt_titles_record_tname},$ttdata);

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 3 is ".timestr($timeall));
        }

        # Log Event

        my $isbn;
        
        if (exists $record->get_fields->{T0540}[0]{content}){
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
                },
                serialize => 1,
            });
        }
    }
    else {
        $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for show_record is ".timestr($timeall));
    }

    $logger->debug("Done showing record");
    return Apache2::Const::OK;
}

sub redirect_to_bibsonomy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');
    
    if ($titleid && $database){
        my $title_as_bibtex = OpenBib::Record::Title->new({id =>$titleid, database => $database})->load_full_record->to_bibtex({utf8 => 1});
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

        $self->query->method('GET');
        $self->query->content_type('text/html; charset=UTF-8');
        $self->query->headers_out->add(Location => $bibsonomy_url);
        $self->query->status(Apache2::Const::REDIRECT);
    }

    return;
}

sub show_availability {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    my $availability_status = 0;
    
    if ($titleid && $database){
        # Wenn Datenbank an Ausleihsystem gekoppelt, dann Medienstatus hollen und auswerten
        if ($config->get_databaseinfo->single({ dbname => $database })->get_column('circ')){
            my $record = OpenBib::Record::Title->new({id =>$titleid, database => $database})->load_circulation;
            # TT-Data erzeugen
            my $ttdata={
                database    => $database, # Zwingend wegen common/subtemplate
                record      => $record,
                titleid     => $titleid,
            };

            $self->print_page($config->{tt_titles_record_availability_tname},$ttdata);
            return;
        }
    }

    return;
}

sub show_record_circulation {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid})->load_circulation;

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
        };

        $self->print_page($config->{tt_titles_record_circulation_tname},$ttdata);
        return;
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
    my $titleid        = $self->param('titleid');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid});

        my $sysprofile= $config->get_profilename_of_view($view);

        $record->enrich_related_records({ profilename => $sysprofile });

        my $related_records = $record->get_related_records;

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
            related_records => $related_records,
        };

        $self->print_page($config->{tt_titles_record_related_records_tname},$ttdata);
        return;
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
    my $titleid        = $self->param('titleid');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid});

        my $sysprofile= $config->get_profilename_of_view($view);

        $record->enrich_similar_records({ profilename => $sysprofile });

        my $similar_records = $record->get_similar_records;

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
            similar_records => $similar_records,
        };

        $self->print_page($config->{tt_titles_record_similar_records_tname},$ttdata);
        return;
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
    my $titleid        = $self->param('titleid');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');
    my $dbinfotable    = $self->param('dbinfo');

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid});

        my $sysprofile= $config->get_profilename_of_view($view);

        $record->enrich_same_records({ profilename => $sysprofile });

        my $same_records = $record->get_same_records;

        # TT-Data erzeugen
        my $ttdata={
            database        => $database, # Zwingend wegen common/subtemplate
            record          => $record,
            titleid         => $titleid,
            same_records    => $same_records,
        };

        $self->print_page($config->{tt_titles_record_same_records_tname},$ttdata);
        return;
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

1;
