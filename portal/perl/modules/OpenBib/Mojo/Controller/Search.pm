###################################################################
#
#  OpenBib::Mojo::Controller::Search.pm
#
#  ehemals VirtualSearch.pm
#
#  Dieses File ist (C) 1997-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Search;

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
#use Mojo::AsyncAwait;

use Mojo::Promise;

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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

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

    $logger->debug("Content-Type $content_type");
    
    my $searchquery = OpenBib::SearchQuery->new({r => $r, view => $view, session => $session, config => $config});

    $self->stash('searchquery',$searchquery);

    # No Searchterms? Warning!

    unless ($searchquery->have_searchterms){
	return $self->print_warning($msg->maketext("Bitte geben Sie einen Suchbegriff ein."));
    }

    # Start der Ausgabe mit korrektem Header
    $self->res->code(200);
    $self->res->headers->content_type($content_type);
    
    $self->render_later;

    $logger->debug("Getting search header");
    my $header_p = $self->show_search_header_p();
    $logger->debug("Getting search header done");

    $logger->debug("Getting search result");
    my $searchresult_p = $self->show_search_result_p();
    $logger->debug("Getting search result done");
    
    $logger->debug("Getting search footer");
    my $footer_p = $self->show_search_footer_p();
    $logger->debug("Getting search footer done");

    $header_p->then(sub {
	my $content_header = shift;
	$self->write_chunk(encode_utf8($content_header)) if ($content_header);

	return $searchresult_p;
		    })->then(sub {
			my $content_searchresult = shift;
			$self->write_chunk(encode_utf8($content_searchresult));

			return $footer_p;
			})->then(sub {
			my $content_footer = shift;
			
			$self->write_chunk(encode_utf8($content_footer)) if ($content_footer);
			$self->finish;
			     }); #->catch(sub {
			#	 my $error = shift;
			#	 $logger->error($error);
			#	 $self->print_warning($error);
			#	       });
	
    $logger->debug("Getting search result");
#    $self->show_search_result();
    $logger->debug("Getting search result done");
    

    # Finalize with empty chunk

    
#     # Sequential search aka traditional meta search
#     if (defined $r->param('sm') && $r->param('sm') eq "seq"){
# 	$logger->debug("Getting search header");
# 	my $header = $self->show_search_header();
# 	$self->write_chunk($header);
# 	$logger->debug("Getting search header done");

# 	$logger->debug("Getting search result");
# 	$logger->debug("Starting sequential search");

# 	foreach my $database ($config->get_databases_of_searchprofile($searchquery->get_searchprofile)) {
# 	    my $seq_searchresult = await &show_search_single_catalogue($self,{database => $database, type => 'sequential'});
	    	    
# 	    $logger->debug("Result for db $database: $seq_searchresult XXX".YAML::Dump($seq_searchresult));
# #	    $self->write_chunk($seq_searchresult) if ($seq_searchresult);
# 	}
#         #$self->sequential_search();
# 	$logger->debug("Getting search result done");
	
# 	$logger->debug("Getting search footer");
# 	my $footer = $self->show_search_footer();
# 	$self->write_chunk($footer);
# 	$logger->debug("Getting search footer done");
# 	$self->finish;
#     }
#     # Joined search in one concatenated index
#     else {
# 	$logger->debug("Getting search header");
# 	my $header = $self->show_search_header();
# 	$self->write_chunk($header);
# 	$logger->debug("Getting search header done");
	
# 	$logger->debug("Getting search result");
# 	my $joined_searchresult = $self->show_search_single_catalogue({ type => 'joined'});
# 	$self->write_chunk($joined_searchresult);
# 	$logger->debug("Getting search result done");
	
# 	$logger->debug("Getting search footer");
# 	my $footer = $self->show_search_footer();
# 	$self->write_chunk($footer);
# 	$logger->debug("Getting search footer done");
# 	$self->finish;
#     }
    
}

sub show_search_header_p {
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
    my $searchquery    = $self->stash('searchquery');    
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $servername     = $self->stash('servername');
    my $path_prefix    = $self->stash('path_prefix');
    my $path           = $self->stash('path');
    my $representation = $self->stash('representation');
    my $content_type   = $self->stash('content_type') || $config->{'content_type_map_rev'}{$representation} || 'text/html';

    my $query          = $r;

    my $promise = Mojo::Promise->new;
    
    # CGI Args
    my $sb        = $r->param('sb') || $config->get_searchengine_of_view($view) || $config->{default_local_search_backend};

    $logger->debug("Using searchengine $sb");
    
    my $trefferliste  = $r->param('trefferliste')  || '';

    my $container = OpenBib::Container->instance;
    $container->register('query',$query);
    
    my $spelling_suggestion_ref = ($user->is_authenticated)?$user->get_spelling_suggestion():{};

    # Wildcard-Suche wird effektiv ueber Search->browse und nicht Search->search
    # realisiert!
    # if (!$searchquery->have_searchterms){
    # 	$logger->debug("Suchanfrage ohne Suchbegriffe -> Wildcard-Suche");
    # 	$searchquery->set_searchfield('freesearch','*','AND');
    # }

    # Wenn Wildcard-Suche, dann Einschraenkung der Facetten-Berechnung
    if ($searchquery->get_searchfield('freesearch')->{'val'} =~m/^\s*\*\s*$/){

	if($searchquery->single_db_in_searchprofile){
	    if (!$queryoptions->get_option('facets')){
		$logger->debug("Aktiviere alle Facetten");
		my $all_facets = join(',',keys %{$config->get('facets')});
		$queryoptions->set_option('facets',$all_facets);
	    }
	}
	else {
	    $logger->debug("Deaktiviere Facetten");
	    $queryoptions->set_option('facets','none');

	}
	$self->stash('qopts',$queryoptions);
    }
    
    if ($logger->is_debug){
        $logger->debug("_searchquery: ".YAML::Dump($searchquery->{_searchquery}));
    }
    
    # Loggen der Recherche-Art (1=simple, 2=complex)
    $session->log_event({
		type      => 20,
                content   => $searchquery->get_searchtype,
    });

    # Loggen des Recherche-Backends
    $session->log_event({
		type      => 21,
                content   => $sb,
    });

    $logger->debug("Searching backend $sb in searchprofile ".$searchquery->get_searchprofile);

    # Loggen des Recherche-Profils
    $session->log_event({
		type      => 23,
                content   => $searchquery->get_searchprofile,
    });

    # Recherche-Profil in Session speichern

    $session->set_profile($searchquery->get_searchprofile);
    
    #############################################################

    my $returncode = $self->enforce_year_restrictions($searchquery);

    if ($returncode){
        return $returncode;
    }
    
    my %trefferpage  = ();
    my %dbhits       = ();

    my $username  = "";
    my $password  = "";

    if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self"){
        ($username,$password)=$user->get_credentials();
    }

    # Hash im Loginname ersetzen
    $username =~s/#/\%23/;

    # Variablen fuer den Zugriff durch andere Methoden setzen
    $self->stash('username',$username);
    $self->stash('password',$password);
    
    # Array aus DB-Name und Titel-ID zur Navigation
    my @resultset   = ();
    
    my $fallbacksb    = "";
    
    my $atime=new Benchmark;
    
    my $starttemplatename=$self->get_start_templatename();

    # TT-Data erzeugen    
    my $startttdata={
        password       => $password,
        searchquery    => $searchquery,
        query          => $r,
        
        qopts          => $queryoptions->get_options,
        queryoptions   => $queryoptions,
        
        spelling_suggestion => $spelling_suggestion_ref,

        page           => $queryoptions->get_option('page'),
        sortorder      => $queryoptions->get_option('srto'),
        sorttype       => $queryoptions->get_option('srt'),
        
    };

    $startttdata = $self->add_default_ttdata($startttdata);

    $starttemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $view,
        profile      => $startttdata->{sysprofile},
        templatename => $starttemplatename,
    });

    my $content_header = "";
    
    # Ausgabe des ersten HTML-Bereichs
    my $starttemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        INCLUDE_PATH   => $config->{tt_include_path},
        #        ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT         => \$content_header,
    });
        
    $starttemplate->process($starttemplatename, $startttdata) || do {
        $logger->error($starttemplate->error());
        $self->res->code(400); # Server error
        return $promise->reject("Templating error for template $starttemplatename");

    };

#    $self->render_later(text => encode_utf8($content_header) );
#    $self->render_later(text => $content_header );

    #    $self->write_chunk(encode_utf8($content_header)) if ($content_header);
    return $promise->resolve($content_header);
}

sub show_search_single_catalogue_p {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;

    my $authority          = exists $arg_ref->{authority}
        ? $arg_ref->{authority}           : undef;

    my $type               = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'joined';
    
    my $config = $self->stash('config');

    my $promise = Mojo::Promise->new;

    my $searchresult = "";
    
    eval {
	my $result_ref = $self->search({database => $database});
	
	my $templatename = ($type eq "sequential")?$config->{tt_search_title_item_tname}:$config->{tt_search_title_combined_tname};
	
	$searchresult = $self->print_resultitem({templatename => $templatename, database => $database, result => $result_ref});

    };

    if ($@){
	$logger->error("Searchresult error: $@");
    
	
	return $promise->reject($@);
    }

    $logger->debug("Searchresult: $searchresult");
        
    return $promise->resolve($searchresult);
}

sub show_search_result_p {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $r              = $self->stash('r');

    my $promise = Mojo::Promise->new;
    
    # Alternativ: getrennte Suche uber alle Kataloge
    if (defined $r->param('sm') && $r->param('sm') eq "seq"){
        # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
        #

        return $self->sequential_search_p;

        ######################################################################
        #
        # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln
    }
    # Default: joined_search
    else {
        # BEGIN Anfrage an virtuelle (oder physikalisch zusammengefuegte)
        # Gesamtdatenbank aus allen ausgewaehlten Recherche-Datenbanken schicken und Ergebniss ausgeben
        #

        return $self->joined_search_p;

        ######################################################################
        #
        # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln
    }

    $promise->resolve;
}

sub show_search_footer_p {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $searchquery    = $self->stash('searchquery');
    my $queryoptions   = $self->stash('qopts');
    my $username       = $self->stash('username');
    my $password       = $self->stash('password');
    
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');

    my $promise = Mojo::Promise->new;
    
    # Jetzt update der Trefferinformationen, wenn keine ID
    $searchquery->save({sid => $session->{sid}});

    $logger->debug("Saving searchquery done");
    
    # TT-Data erzeugen
    my $endttdata={
        total_hits    => $self->stash('total_hits'),
        
        username      => $username,
        password      => $password,
        
        searchquery   => $searchquery,
        query         => $r,
        qopts         => $queryoptions->get_options,
        queryoptions  => $queryoptions,        
    };

    $endttdata = $self->add_default_ttdata($endttdata);

    # Ausgabe des letzten HTML-Bereichs
    my $endtemplatename=$self->get_end_templatename();
    
    $endtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $view,
        profile      => $endttdata->{sysprofile},
        templatename => $endtemplatename,
    });

    my $content_footer = "";
    
    my $endtemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        INCLUDE_PATH   => $config->{tt_include_path},
        #        ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT         => \$content_footer,
    });
    
    $endtemplate->process($endtemplatename, $endttdata) || do {
        $logger->error($endtemplate->error());
        $self->res->code(400); # server error
        return $promise->reject("Templating error for template $endtemplatename");;
    };

    $logger->debug("Template processed");
    
    # Wurde in allen Katalogen recherchiert?
    
    my $alldbcount = $config->get_number_of_dbs();

    my $searchquery_log_ref = {};

    my $searchquery_args = $searchquery->get_searchquery;
    
    foreach my $key (keys %{$searchquery_args}){
        $searchquery_log_ref->{$key} = $searchquery_args->{$key};
    }
        
    $searchquery_log_ref->{searchprofile} = $searchquery->get_searchprofile;
    
#    $searchquery_log_ref->{hits}   = $gesamttreffer;

    if ($logger->is_debug){
        $logger->debug("_searchquery: ".YAML::Dump($searchquery->{_searchquery}));
    }

    # Loggen des Queries
    $session->log_event({
        type      => 1,
        content   => $searchquery_log_ref,
        serialize => 1,
    });

#    $self->render(text => encode_utf8($content_footer) );
#    $self->render_later(text => $content_footer );
    
    #    $self->write_chunk(encode_utf8($content_footer)) if ($content_footer);
    return $promise->resolve($content_footer);
}

# Auf Grundlage der <form>-Struktur im Template searchform derzeit nicht verwendet
sub show_index {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');    
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $servername     = $self->stash('servername');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');    
    my $representation = $self->stash('representation') || '';

    # CGI Args
    my @databases     = ($r->param('db'))?$r->param('db'):();
    my $hitrange      = ($r->param('num' ))?$r->param('num'):50;
    my $page          = ($r->param('page' ))?$r->param('page'):1;
    my $sorttype      = ($r->param('srt' ))?$r->param('srt'):"person";
    my $sortorder     = ($r->param('srto'))?$r->param('srto'):'asc';
    my $defaultop     = ($r->param('dop'))?$r->param('dop'):'and';

    my $sortall       = ($r->param('sortall'))?$r->param('sortall'):'0';

    # Index zusammen mit Eingabefelder 
    my $verfindex     = $r->param('verfindex')     || '';
    my $korindex      = $r->param('korindex')      || '';
    my $swtindex      = $r->param('swtindex')      || '';
    my $notindex      = $r->param('notindex')      || '';

    # oder Index als separate Funktion
    my $indextype    = $r->param('indextype')     || ''; # (verfindex, korindex, swtindex oder notindex)
    my $indexterm    = $r->param('indexterm')     || '';
    my $searchindex  = $r->param('searchindex')     || '';
    
    my $profile       = $r->param('profile')        || '';
    my $trefferliste  = $r->param('trefferliste')  || '';
    my $st            = $r->param('st')            || '';    # Search type (1=simple,2=complex)    
    my $drilldown     = $r->param('dd')            || 0;     # Drill-Down?

    my $spelling_suggestion_ref = ($user->is_authenticated)?$user->get_spelling_suggestion():{};

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;
    my $searchquery = OpenBib::SearchQuery->new({r => $r, view => $view, session => $session});

    $self->stash('searchquery',$searchquery);
    
    my $sysprofile  = $config->get_profilename_of_view($view);

    @databases = $self->get_databases();

    my $content_type = $config->{content_type_map_rev}->{$representation};

    # BEGIN Index
    ####################################################################
    # Wenn ein kataloguebergreifender Index ausgewaehlt wurde
    ####################################################################

    my $normalizer = $self->stash('normalizer');

    my $contentreq = $normalizer->normalize({
        content   => $self->stash('dispatch_url_remainder'),
        searchreq => 1,
    });
    
    my $type = $self->stash('type');
    
    my $urlpart =
        ($type eq "aut"      )?"verf=$contentreq;verfindex=Index":
            ($type eq "kor"      )?"kor=$contentreq;korindex=Index":
                ($type eq "swt"      )?"swt=$contentreq;swtindex=Index":
                    ($type eq "notation" )?"notation=$contentreq;notindex=Index":undef;
    
    my $template =
        ($type eq "person"        )?$config->{"tt_search_person_tname"}:
            ($type eq "corporatebody" )?$config->{"tt_search_corporatebody_showkorindex_tname"}:
                ($type eq "subject"       )?$config->{"tt_search_subject_tname"}:
                    ($type eq "classification")?$config->{"tt_search_classification_tname"}:undef;
    
    $contentreq=~s/\+//g;
    $contentreq=~s/%2B//g;
    $contentreq=~s/%//g;
    
    if (!$contentreq) {
        return $self->print_warning($msg->maketext("F&uuml;r die Nutzung der Index-Funktion m&uuml;ssen Sie einen Begriff eingegeben"));
    }
    
    if ($#databases > 0 && length($contentreq) < 3) {
        return $self->print_warning($msg->maketext("Der Begriff muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche im Index ausgewählt wurde."));
    }
    
    my %index=();
    
    my @sortedindex=();
    
    my $atime=new Benchmark;
    
    foreach my $database (@databases) {
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $thisindex_ref=OpenBib::Search::Util::get_index({
            type       => $type,
            category   => 1,
            contentreq => $contentreq,
            dbh        => $dbh,
        });
        
        if ($logger->is_debug){
            $logger->debug("Index Ursprung ($database)".YAML::Dump($thisindex_ref));
        }
        
        # Umorganisierung der Daten Teil 1
        #
        # Hier werden die fuer eine Datenbank mit get_index ermittelten
        # Index-Items (AoH content,id,titcount) in einen Gesamt-Index
        # uebertragen (HoHoAoH) mit folgenden Schluesseln pro 'Ebene'
        # (1) <Indexbegriff>
        # {2} databases(Array), titcount(Skalar)
        # (3) dbname,dbdesc,id,titcount in Array databases
        foreach my $item_ref (@$thisindex_ref) {
            # Korrekte Initialisierung mit 0
            if (! exists $index{$item_ref->{content}}{titcount}) {
                $index{$item_ref->{content}}{titcount}=0;
            }
            
            push @{$index{$item_ref->{content}}{databases}}, {
                'dbname'   => $database,
                'dbdesc'   => $dbinfotable->get('dbnames')->{$database},
                'id'       => $item_ref->{id},
                'titcount' => $item_ref->{titcount},
            };
            
            $index{$item_ref->{content}}{titcount}=$index{$item_ref->{content}}{titcount}+$item_ref->{titcount};
        }
        $dbh->disconnect;
    }
    
    if ($logger->is_debug){
        $logger->debug("Index 1".YAML::Dump(\%index));
    }
    
    # Umorganisierung der Daten Teil 2
    #
    # Um die Begriffe sortieren zu koennen muss der HoHoAoH in ein
    # AoHoAoH umgewandelt werden.
    # Es werden folgende Schluessel pro 'Ebene' verwendet
    # {1} content(Skalar), databases(Array), titcount(Skalar)
    # (2) dbname,dbdesc,id,titcount in Array databases
    #
    # Ueber die Reihenfolge des ersten Arrays erfolgt die Sortierung
    foreach my $singlecontent (sort { uc($a) cmp uc($b) } keys %index) {
        push @sortedindex, { content   => $singlecontent,
                             titcount  => $index{$singlecontent}{titcount},
                             databases => $index{$singlecontent}{databases},
                         };
    }
    
    if ($logger->is_debug){
        $logger->debug("Index 2".YAML::Dump(\@sortedindex));
    }
    
    my $hits=$#sortedindex+1;
    
    my $databasestring="";
    foreach my $database (@databases){
        $databasestring.=";database=$database";
    }
    
    my $baseurl="http://$r->get_server_name$config->{virtualsearch_loc}?sessionID=$session->{ID};view=$view;$urlpart;profile=$profile;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder$databasestring";
    
    my @nav=();
    
    my $offset = $queryoptions->get_option('page')*$hitrange-$hitrange;
    
    if ($hitrange > 0) {
        $logger->debug("Navigation wird erzeugt: Hitrange: $hitrange Hits: $hits");
        
        for (my $i=0; $i <= $hits-1; $i+=$hitrange) {
            my $active=0;
            
            if ($i == $offset) {
                $active=1;
            }
            
            my $item={
                start  => $i+1,
                end    => ($i+$hitrange>$hits)?$hits:$i+$hitrange,
                url    => $baseurl.";hitrange=$hitrange;offset=$i",
                active => $active,
            };
            push @nav,$item;
        }
    }
    
    
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    # TT-Data erzeugen
    my $ttdata={
        qopts        => $queryoptions->get_options,
        queryoptions => $queryoptions,
        
        resulttime => $resulttime,
        contentreq => $contentreq,
        index      => \@sortedindex,
        nav        => \@nav,
        offset     => $offset,
        page       => $queryoptions->get_option('page'),
        hitrange   => $hitrange,
        baseurl    => $baseurl,
        profile    => $profile,
    };
    
    return $self->print_page($template,$ttdata);

    ####################################################################
    # ENDE Indizes
    #

}

sub gen_cloud {
    my ($arg_ref) = @_;

    # Set defaults
    my $term_ref            = exists $arg_ref->{term_ref}
        ? $arg_ref->{term_ref}            : undef;

    my $termcloud_ref = [];
    my $maxtermfreq = 0;
    my $mintermfreq = 999999999;

    foreach my $singleterm (keys %{$term_ref}) {
        if ($term_ref->{$singleterm} > $maxtermfreq){
            $maxtermfreq = $term_ref->{$singleterm};
        }
        if ($term_ref->{$singleterm} < $mintermfreq){
            $mintermfreq = $term_ref->{$singleterm};
        }
    }

    foreach my $singleterm (keys %{$term_ref}) {
        push @{$termcloud_ref}, {
            term => $singleterm,
            font => $term_ref->{$singleterm},
        };
    }

    if ($maxtermfreq-$mintermfreq > 0){
        for (my $i=0 ; $i < scalar (@$termcloud_ref) ; $i++){
	    $termcloud_ref->[$i]->{class} = int(($termcloud_ref->[$i]->{count}-$mintermfreq) / ($maxtermfreq-$mintermfreq) * 6);
	}
    }

    my $sortedtermcloud_ref;
    @{$sortedtermcloud_ref} = map { $_->[0] }
                    sort { $a->[1] cmp $b->[1] }
                        map { [$_, $_->{term}] }
                            @{$termcloud_ref};

    return $sortedtermcloud_ref;
}

sub gen_cloud_absolute {
    my ($arg_ref) = @_;

    # Set defaults
    my $term_ref            = exists $arg_ref->{term_ref}
        ? $arg_ref->{term_ref}            : undef;
    my $dbh                 = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;

    my $logger = get_logger ();
    my $atime=new Benchmark;
    
    my $termcloud_ref = [];
    my $maxtermfreq = 0;
    my $mintermfreq = 999999999;

    # Termfrequenzen sowie maximale Termfrequenz bestimmen
    foreach my $singleterm (keys %{$term_ref}) {
        if (length($singleterm) < 3){
            delete $term_ref->{$singleterm};
            next;
        }
        $term_ref->{$singleterm} = $dbh->get_termfreq($singleterm);
        if ($term_ref->{$singleterm} > $maxtermfreq){
            $maxtermfreq = $term_ref->{$singleterm};
        }
        if ($term_ref->{$singleterm} < $mintermfreq){
            $mintermfreq = $term_ref->{$singleterm};
        }
    }

    # Jetzt Fontgroessen bestimmen
    foreach my $singleterm (keys %{$term_ref}) {
        push @{$termcloud_ref}, {
            term  => $singleterm,
            count => $term_ref->{$singleterm},
        };
    }

    if ($maxtermfreq-$mintermfreq > 0){
        for (my $i=0 ; $i < scalar (@$termcloud_ref) ; $i++){
	    $termcloud_ref->[$i]->{class} = int(($termcloud_ref->[$i]->{count}-$mintermfreq) / ($maxtermfreq-$mintermfreq) * 6);
	}
    }
    
    my $sortedtermcloud_ref;
    @{$sortedtermcloud_ref} = map { $_->[0] }
                    sort { $a->[1] cmp $b->[1] }
                        map { [$_, $_->{term}] }
                            @{$termcloud_ref};

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    $logger->debug("Time: ".$resulttime);

    return $sortedtermcloud_ref;
}

sub xxxget_modified_querystring {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $exclude_array_ref    = exists $arg_ref->{exclude}
        ? $arg_ref->{exclude}        : [];
    
    my $change_ref           = exists $arg_ref->{change}
        ? $arg_ref->{change}         : {};


    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r              = $self->stash('r');

    $logger->debug("Modify Querystring");
    
    my $exclude_ref = {};
    
    foreach my $param (@{$exclude_array_ref}){
        $exclude_ref->{$param} = 1;
    }
    
    my @cgiparams = ();
    
    foreach my $param (keys %{$r->param}){
        $logger->debug("Processing $param");
        if (exists $arg_ref->{change}{$param}){
            push @cgiparams, "$param=".$arg_ref->{change}->{$param};
        }
        elsif (! exists $exclude_ref->{$param}){
            my @values = $r->param($param);
            if (@values){
                foreach my $value (@values){
                    push @cgiparams, "$param=$value";
                }
            }
            else {
                push @cgiparams, "$param=".$r->param($param);
            }
        }
    }
    
    return join('&',@cgiparams) if (@cgiparams);

    return 'blabla';
}

sub joined_search_p {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->stash('config');
    my $searchquery  = $self->stash('searchquery');
    my $session      = $self->stash('session');
    
    $logger->debug("Starting joined search");

    return $self->show_search_single_catalogue_p({ type => 'joined'});

#     r
#     $joined_searchresult->then(sub {
# 	my $content_searchresult = shift;
# 	$logger->debug("Promise searchresult: $content_searchresult");
# 	$self->write_chunk(encode_utf8($content_searchresult));
	
# 			       });

#     $logger->debug("Starting joined search done");    
# #    $self->write_chunk(encode_utf8($joined_searchresult));

#     # Etwaige Kataloge, die nicht lokal vorliegen und durch ein API angesprochen werden
#     # if (0 == 1){ # deaktiviert
#     # 	foreach my $database ($config->get_databases_of_searchprofile($searchquery->get_searchprofile)) {
#     # 	    my $system = $config->get_system_of_db($database);
	    
#     # 	    if ($system =~ /^Backend/){
#     # 		$self->stash('database',$database);
		
#     # 		$self->search({database => $database});
		
#     # 		my $seq_content_searchresult = $self->print_resultitem({templatename => $config->{tt_search_title_item_tname}});
		
#     # 		$writer->write(encode_utf8($seq_content_searchresult));
#     # 	    }
#     # 	}
#     # }
    
#     return; # $content_searchresult;
}

sub sequential_search_p {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config      = $self->stash('config');
    my $searchquery = $self->stash('searchquery');
    my $session     = $self->stash('session');

    ######################################################################
    # Schleife ueber alle Datenbanken 

    ######################################################################

    $logger->debug("Starting sequential search");

    my $promise = Mojo::Promise->new;

    # Array aus Promises fuer die Ergebnisse aller Recherchen
    my @all_searches = map { $self->show_search_single_catalogue_p({database => $_, type => 'sequential'}) } $config->get_databases_of_searchprofile($searchquery->get_searchprofile);

    my $searchresult = Mojo::Promise->all(@all_searches)->then(sub {
	my @searchresults = map { $_->[0] } @_;
	my $all_searchresults = join('',@searchresults);

	$logger->debug("Joined sequential results: $all_searchresults");
	return $all_searchresults;
	
					    });

    if ($logger->is_debug){
	$logger->debug("Sequential result ref: ".ref($searchresult));	
	$logger->debug("Sequential result: $searchresult");
    }
    
    $promise->resolve($searchresult);
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;

    my $authority          = exists $arg_ref->{authority}
        ? $arg_ref->{authority}           : undef;

    my $total_hits         = exists $arg_ref->{total_hits}
        ? $arg_ref->{total_hits}            : 0;
    
    my $r            = $self->stash('r');
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
    
    my $facets_ref = $searcher->get_facets;
    $searchquery->set_results($facets_ref->{8}) unless (defined $database); # Verteilung nach Datenbanken

    my $btime   = new Benchmark;
    $timeall    = timediff($btime,$atime);
    $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info($searcher->get_resultcount . " results found in $resulttime");
    
    $searchquery->set_hits($searcher->get_resultcount);
    
    if ($searcher->have_results) {

        $logger->debug("Results found #".$searcher->get_resultcount);
        
        $nav = Data::Pageset->new({
            'total_entries'    => $searcher->get_resultcount,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });
        
        $recordlist = $searcher->get_records();

    if ($logger->is_debug){
	$logger->debug("Titles in recordlist: ".$recordlist->get_size());
    }
    
	
    }
    else {
        $logger->debug("No results found #".$searcher->get_resultcount);
    }
    
    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation in
    # den einzeltreffern

    my $resultcount = $searcher->get_resultcount || 0 ;
    
    # $self->stash('searchtime',$resulttime);
    # $self->stash('nav',$nav);
    # $self->stash('facets',$facets_ref);
    # $self->stash('recordlist',$recordlist);
    # $self->stash('hits',$searcher->get_resultcount);
    # $self->stash('total_hits',$total_hits + $resultcount);

    return {
	searchtime => $resulttime,
	nav => $nav,
	facets => $facets_ref,
	recordlist => $recordlist,
	hits => $resultcount,
	total_hits => $total_hits + $resultcount,	    
    };
}

sub print_resultitem {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $templatename = exists $arg_ref->{templatename}
        ? $arg_ref->{templatename}        : undef;

    my $database     = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;

    my $result_ref   = exists $arg_ref->{result}
        ? $arg_ref->{result}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

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
#    my $database       = $self->stash('database') || '';
    my $viewname       = $self->stash('viewname') || '';        
    my $searchquery    = $self->stash('searchquery');

    # TT-Data erzeugen
    my $ttdata={
        database        => $database,
        viewname        => $viewname,
	
        searchquery     => $searchquery,
        
        qopts           => $queryoptions->get_options,
        queryoptions    => $queryoptions,
        
        query           => $r,

        gatt            => $self->stash('generic_attributes'),
        
        hits            => $result_ref->{'hits'},
        
        facets          => $result_ref->{'facets'},
        
        total_hits      => $result_ref->{'total_hits'},
        recordlist      => $result_ref->{'recordlist'},
        
        nav             => $result_ref->{'nav'},
        
#        lastquery       => $request->querystring,
        resulttime      => $result_ref->{'searchtime'},

	highlightquery  => \&highlightquery,
    };
    
    $ttdata = $self->add_default_ttdata($ttdata);

    my $content = "";

    $logger->debug("Trying template $templatename with view ".$ttdata->{view}." and database ".$ttdata->{database}." for representation $representation");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database, # Template ist fuer joined-search nicht datenbankabhaengig (=''), aber fuer sequential search
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $templatename,
    });

    $logger->debug("Cascaded template $templatename");
    # Start der Ausgabe mit korrektem Header
    # $r->content_type($ttdata->{content_type});
    
    # Es kann kein Datenbankabhaengiges Template geben
    
    my $itemtemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #                INCLUDE_PATH   => $config->{tt_include_path},
        #                ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT         => \$content,
    });            
    
    if ($logger->is_debug && defined $result_ref->{'recordlist'}){
	$logger->debug("Printing Result item");
    }
    
    $itemtemplate->process($templatename, $ttdata) || do {
        $logger->error("Process error for resultitem: ".$itemtemplate->error());
        $self->res->code(400); # server error
        return;
    };

    $logger->debug("Printed: $content");
    
    return $content;
}


sub dec2bin {
    my $str = unpack("B32", pack("N", shift));
    $str =~ s/^0+(?=\d)//;   # strip leading zeroes
    return $str;
}
sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}

sub enforce_year_restrictions {
    my $self = shift;
    my $searchquery = shift;

    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');

    if ($searchquery->get_searchfield('ejahr')->{norm}) {
        my ($ejtest)=$searchquery->get_searchfield('ejahr')->{norm}=~/.*(\d\d\d\d).*/;
        if (!$ejtest) {
            return $self->print_warning($msg->maketext("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein."));
        }
    }
    
    if ($searchquery->get_searchfield('ejahr')->{bool} eq "OR") {
        if ($searchquery->get_searchfield('ejahr')->{norm}) {
            return $self->print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."));
        }
    }
}

sub get_start_templatename {
    my $self = shift;
    
    my $config = $self->stash('config');
    
    return $config->{tt_search_title_start_tname};
}

sub get_end_templatename {
    my $self = shift;
    
    my $config = $self->stash('config');
    
    return $config->{tt_search_title_end_tname};
}

sub get_templatename_of_joined_search {
    my $self = shift;

    my $config         = $self->stash('config');
    
    return $config->{tt_search_title_combined_tname};
}

sub highlightquery {
    my ($searchquery,$content) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Highlight Query

    return $content unless ($searchquery && ref $searchquery eq "OpenBib::SearchQuery");

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
