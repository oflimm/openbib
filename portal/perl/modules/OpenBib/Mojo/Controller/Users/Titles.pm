#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Titles.pm
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

package OpenBib::Mojo::Controller::Users::Titles;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);
use Date::Manip;
use URI::Escape qw(uri_escape uri_escape_utf8);
use Encode 'decode_utf8';

use OpenBib::Catalog;
use OpenBib::Search::Factory;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Util;
use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

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
    
    my $statistics  = new OpenBib::Statistics();
    my $utils       = new OpenBib::Template::Utilities;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    my $profile       = $config->get_profilename_of_view($view);

    my $catalog = new OpenBib::Catalog({ database => $database });
    
    my $recordlist = $catalog->get_recent_titles({
        limit    => 50,
    });

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

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $database       = $self->param('database');

    # Shared Args
    my $config         = $self->stash('config');

    $logger->debug("Showing Form for Title Record");
    
    if (!$self->is_authenticated('admin')){
        return;
    }

    my $ttdata={                #
        database => $database,
    };
    
    return $self->print_page($config->{tt_titles_form_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args

    $logger->debug("Creating Title Record");
            
    if (!$self->is_authenticated('admin')){
        return;
    }

    my $record = new OpenBib::Record::Title({ config => $config });
    $record->set_database($database);
    $record->set_from_psgi_request($r);

    # TODO: GET?
    $self->redirect("$path_prefix/$config->{titles_loc}/database/$database/new.html");

    return;
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
    
#     my $database_in_view = 0;

#     my @dbs_in_view = $config->get_viewdbs($view);

#     # Add 'special' databases of type api
#     push @dbs_in_view, $config->get_apidbs;
    
#     foreach my $dbname (@dbs_in_view){
#         if ($dbname eq $database){
#             $database_in_view = 1;
#             last;
#         }
#     }
    
#     # Databases with API are always considered
# #     foreach my $dbname ($config->get_apidbs){
# #         if ($dbname eq $database){
# #             $database_in_view = 1;
# #             last;
# #         }
# #     }
    
#     unless ($database_in_view || $user->is_admin){
# 	if ($logger->is_debug){
# 	    $logger->debug("Access denied for database $database. Viewdbs: ".YAML::Dump(@dbs_in_view));
# 	}
#         $self->header_add('Status' => 404); # NOT_FOUND
#         return;
#     }
    
#     if ($user->{ID} && !$userid){
#         my $args = "?l=".$self->stash('lang');

#         return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/title/database/$database/id/$titleid.$representation$args",'303 See Other');
#     }
    
    if ($userid && !$self->is_authenticated('user',$userid)){
        $logger->debug("Testing authorization for given userid $userid");
        return;
    }


    # Flush from memcached
    if ($flushcache){
	my $memc_key = "record:title:full:$database:$titleid";
	$config->{memc}->delete($memc_key) if ($config->{memc});
    }
        
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->new;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    my $searchquery   = OpenBib::SearchQuery->new({r => $r, view => $view, session => $session, config => $config});

    my $authenticatordb = $user->get_targetdb_of_session($session->{ID});

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid, config => $config})->load_full_record;

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

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 1 is ".timestr($timeall));
        }

        # Literaturlisten finden

        my $litlists_ref = $user->get_litlists_of_tit({titleid => $titleid, dbname => $database, view => $view});

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
                        $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
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
            qopts       => $queryoptions->get_options,
            queryid     => $searchquery->get_id,
            record      => $record,
            titleid      => $titleid,

            format      => $format,

            searchquery => $searchquery,
            activefeed  => $config->get_activefeeds_of_db($self->{database}),
            
            authenticatordb => $authenticatordb,
            
            litlists          => $litlists_ref,
            highlightquery    => \&highlightquery,
	    sort_circulation => \&sort_circulation,
        };

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
        
        return $self->print_page($config->{tt_titles_record_tname},$ttdata);

    }
    else {
        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for show_record is ".timestr($timeall));
    }

    $logger->debug("Done showing record");

    return;
}

sub show_record_searchindex {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->strip_suffix($self->decode_id($self->param('titleid')));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');

    my $searcher   = OpenBib::Search::Factory->create_searcher({database => $database, config => $config });

    my $terms_ref  = $searcher->get_indexterms({ database => $database, id => $titleid });
    my $values_ref = $searcher->get_values({ database => $database, id => $titleid });
    my $data_ref   = $searcher->get_data({ database => $database, id => $titleid });
    
    my $ttdata = {
        database => $database,
        titleid  => $titleid,
        terms    => $terms_ref,
        values   => $values_ref,
	data     => $data_ref,
    };
    
    return $self->print_page($config->{'tt_users_titles_record_searchindex_tname'},$ttdata);
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
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');

    if ($titleid && $database){
        my $title_as_bibtex = OpenBib::Record::Title->new({id =>$titleid, database => $database, config => $config })->load_full_record->to_bibtex({utf8 => 1});
        #        $title=~s/\n/ /g;

        $logger->debug("Title as BibTeX: $title_as_bibtex");

        my $bibsonomy_url = "http://www.bibsonomy.org/BibtexHandler?requTask=upload&url=".uri_escape_utf8("http://$servername$path_prefix/$config->{home_loc}")."&description=".uri_escape_utf8($config->get_viewdesc_from_viewname($view))."&encoding=UTF-8&selection=".uri_escape_utf8($title_as_bibtex);

        # my $redirect_url = "$path_prefix/$config->{redirect_loc}?type=510;url=".uri_escape_utf8($bibsonomy_url);
        
        $logger->debug($bibsonomy_url);

        $session->log_event({
            type      => 510,
            content   => $bibsonomy_url
        });

        # TODO Get?
        $self->res->headers->content_type('text/html; charset=UTF-8');
        $self->redirect($bibsonomy_url);
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


1;
