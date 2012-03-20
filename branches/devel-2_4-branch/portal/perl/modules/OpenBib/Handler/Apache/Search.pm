###################################################################
#
#  OpenBib::Handler::Apache::Search.pm
#
#  ehemals VirtualSearch.pm
#
#  Dieses File ist (C) 1997-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Search;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestIO (); # rflush, print
use Apache2::RequestRec ();
use Benchmark ':hireswallclock';
use Data::Pageset;
use DBI;
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Storable ();
use String::Tokenizer;
use Search::Xapian;
use YAML ();

use OpenBib::Search::Util;
use OpenBib::VirtualSearch::Util;
use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Local::Xapian;
use OpenBib::Search::Local::ElasticSearch;
use OpenBib::Search::Z3950;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_search');
    $self->run_modes(
        'show_search'   => 'show_search',
        'show_index'    => 'show_index',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_search {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->param('r');
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $servername     = $self->param('servername');
    my $path_prefix    = $self->param('path_prefix');
    my $path           = $self->param('path');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    
    # CGI Args
    my $sb        = $query->param('sb')        || $config->{local_search_backend};
    
    # TODO: Warum hier und nicht in SearchQuery? Erstmal weg
#    my $serien        = decode_utf8($query->param('serien'))        || 0;

    # Folgende Parameter wind bereis im QueryOptions-Objekt enthalten ($self->param('qopts')
#     my $hitrange      = ($query->param('num' ))?$query->param('num'):50;
#     my $page          = ($query->param('page' ))?$query->param('page'):1;
#     my $listtype      = ($query->param('lt' ))?$query->param('lt'):"cover";
#     my $sorttype      = ($query->param('srt' ))?$query->param('srt'):"person";
#     my $sortorder     = ($query->param('srto'))?$query->param('srto'):'asc';
#     my $defaultop     = ($query->param('dop'))?$query->param('dop'):'and';
#     my $joindbs       = $query->param('jn') || $query->param('combinedbs')    || 1;

#    my $sortall       = ($query->param('sortall'))?$query->param('sortall'):'0';

    # Parameter bereits in SearchQuery Objekt
    
#     # Index zusammen mit Eingabefelder 
#     my $verfindex     = $query->param('verfindex')     || '';
#     my $korindex      = $query->param('korindex')      || '';
#     my $swtindex      = $query->param('swtindex')      || '';
#     my $notindex      = $query->param('notindex')      || '';

#     # oder Index als separate Funktion
#     my $indextype    = $query->param('indextype')      || ''; # (verfindex, korindex, swtindex oder notindex)
#     my $indexterm    = $query->param('indexterm')      || '';
#     my $searchindex  = $query->param('searchindex')    || '';
    
#    my $profile       = $query->param('profile')       || '';
    my $trefferliste  = $query->param('trefferliste')  || '';
    my $queryid       = $query->param('queryid')       || '';


    #     my $st            = $query->param('st')            || '';    # Search type (1=simple,2=complex)    
#     my $drilldown     = $query->param('dd')            || 1;     # Drill-Down?
    
    my $spelling_suggestion_ref = ($user->is_authenticated)?$user->get_spelling_suggestion():{};

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $searchquery = OpenBib::SearchQuery->instance({r => $r, view => $view});
    
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

    # BEGIN Index
    ####################################################################
    # Wenn ein kataloguebergreifender Index ausgewaehlt wurde
    ####################################################################

    if ($searchquery->is_indexsearch){
        $self->search_index;
    }

    ####################################################################
    # ENDE Indizes
    #

    #############################################################

    if ($searchquery->get_searchfield('ejahr')->{norm}) {
        my ($ejtest)=$searchquery->get_searchfield('ejahr')->{norm}=~/.*(\d\d\d\d).*/;
        if (!$ejtest) {
            $self->print_warning($msg->maketext("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein."));
            return Apache2::Const::OK;
        }
    }

    if ($searchquery->get_searchfield('ejahr')->{bool} eq "OR") {
        if ($searchquery->get_searchfield('ejahr')->{norm}) {
            $self->print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."));
            return Apache2::Const::OK;
        }
    }


    if (!$searchquery->have_searchterms) {
        $self->print_warning($msg->maketext("Es wurde kein Suchkriterium eingegeben."));
        return Apache2::Const::OK;
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

    # Array aus DB-Name und Titel-ID zur Navigation
    my @resultset   = ();
    
    my $fallbacksb    = "";
    my $gesamttreffer = 0;

    my $atime=new Benchmark;
    
    my $starttemplatename=$config->{tt_search_title_start_tname};

        # TT-Data erzeugen
    
    my $startttdata={
        password       => $password,
        searchquery    => $searchquery,
        queryid        => $queryid,
        query          => $query,
        
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

    $logger->debug("Content-Type $content_type");
    # Start der Ausgabe mit korrektem Header
    $r->content_type("$content_type");
    
    # Ausgabe des ersten HTML-Bereichs
    my $starttemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        INCLUDE_PATH   => $config->{tt_include_path},
        #        ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT         => $r,
    });
        
    $starttemplate->process($starttemplatename, $startttdata) || do {
        $r->log_error($starttemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
    
    # Ausgabe flushen
    eval {
        $r->rflush();
    };

    if($@) {
        $logger->error("Flush-Error");
    }

    # Kombinierte Suche ueber alle Kataloge

    if ($queryoptions->get_option('jn')){
        # BEGIN Anfrage an virtuelle (oder physikalisch zusammengefuegte)
        # Gesamtdatenbank aus allen ausgewaehlten Recherche-Datenbanken schicken und Ergebniss ausgeben
        #

        $self->joined_search({sb => $sb});

        ######################################################################
        #
        # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln
    }
    # Alternativ: getrennte Suche uber alle Kataloge
    else {
        # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
        #

        $self->sequential_search({sb => $sb});

        ######################################################################
        #
        # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln
    }

    # TT-Data erzeugen
    my $endttdata={
        gesamttreffer => $gesamttreffer,
        
        username      => $username,
        password      => $password,
        
        searchquery   => $searchquery,
        query         => $query,
        queryid       => $queryid,
        qopts         => $queryoptions->get_options,
        queryoptions  => $queryoptions,        
    };

    $endttdata = $self->add_default_ttdata($endttdata);

    # Ausgabe des letzten HTML-Bereichs
    my $endtemplatename=$config->{tt_search_title_end_tname};
    
    $endtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $view,
        profile      => $endttdata->{sysprofile},
        templatename => $endtemplatename,
    });
    
    my $endtemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        INCLUDE_PATH   => $config->{tt_include_path},
        #        ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT         => $r,
    });
    
    $endtemplate->process($endtemplatename, $endttdata) || do {
        $r->log_error($endtemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
    
    # Wenn etwas gefunden wurde, dann kann ein Resultset geschrieben werden.

    if ($gesamttreffer > 0) {
        $logger->debug("Resultset wird geschrieben: ".YAML::Dump(\@resultset));
        $session->updatelastresultset(\@resultset);
    }

    # Jetzt update der Trefferinformationen, wenn keine ID
    $searchquery->save({sessionID => $session->{ID}}); 
    
    # Wurde in allen Katalogen recherchiert?
    
    my $alldbcount = $config->get_number_of_dbs();
    
    my $searchquery_log_ref = $searchquery->get_searchquery;
        
    $searchquery_log_ref->{searchprofile} = $searchquery->get_searchprofile;
    
    $searchquery_log_ref->{hits}   = $gesamttreffer;
    
    # Loggen des Queries
    $session->log_event({
        type      => 1,
        content   => $searchquery_log_ref,
        serialize => 1,
    });

    return Apache2::Const::OK;
}

# Auf Grundlage der <form>-Struktur im Template searchform derzeit nicht verwendet
sub show_index {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $servername     = $self->param('servername');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $representation = $self->param('representation') || '';

    # CGI Args
    my @databases     = ($query->param('db'))?$query->param('db'):();
    my $hitrange      = ($query->param('num' ))?$query->param('num'):50;
    my $page          = ($query->param('page' ))?$query->param('page'):1;
    my $sorttype      = ($query->param('srt' ))?$query->param('srt'):"person";
    my $sortorder     = ($query->param('srto'))?$query->param('srto'):'asc';
    my $defaultop     = ($query->param('dop'))?$query->param('dop'):'and';
    my $joindbs       = $query->param('jn') || $query->param('combinedbs')    || 1;

    my $sortall       = ($query->param('sortall'))?$query->param('sortall'):'0';

    # Index zusammen mit Eingabefelder 
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';

    # oder Index als separate Funktion
    my $indextype    = $query->param('indextype')     || ''; # (verfindex, korindex, swtindex oder notindex)
    my $indexterm    = $query->param('indexterm')     || '';
    my $searchindex  = $query->param('searchindex')     || '';
    
    my $profile       = $query->param('profile')        || '';
    my $trefferliste  = $query->param('trefferliste')  || '';
    my $queryid       = $query->param('queryid')       || '';
    my $st            = $query->param('st')            || '';    # Search type (1=simple,2=complex)    
    my $drilldown     = $query->param('dd')            || 0;     # Drill-Down?

    my $spelling_suggestion_ref = ($user->is_authenticated)?$user->get_spelling_suggestion():{};

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $searchquery = OpenBib::SearchQuery->instance;

    my $sysprofile  = $config->get_profilename_of_view($view);

    @databases = $self->get_databases();

    my $content_type = $config->{content_type_map_rev}->{$representation};

    # BEGIN Index
    ####################################################################
    # Wenn ein kataloguebergreifender Index ausgewaehlt wurde
    ####################################################################

    my $contentreq = OpenBib::Common::Util::grundform({
        content   => $self->param('dispatch_url_remainder'),
        searchreq => 1,
    });
    
    my $type = $self->param('type');
    
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
        $self->print_warning($msg->maketext("F&uuml;r die Nutzung der Index-Funktion m&uuml;ssen Sie einen Begriff eingegeben"));
        return Apache2::Const::OK;
    }
    
    if ($#databases > 0 && length($contentreq) < 3) {
        $self->print_warning($msg->maketext("Der Begriff muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche im Index ausgewählt wurde."));
        return Apache2::Const::OK;
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
        
        $logger->debug("Index Ursprung ($database)".YAML::Dump($thisindex_ref));
        
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
                'dbdesc'   => $dbinfotable->{dbnames}{$database},
                'id'       => $item_ref->{id},
                'titcount' => $item_ref->{titcount},
            };
            
            $index{$item_ref->{content}}{titcount}=$index{$item_ref->{content}}{titcount}+$item_ref->{titcount};
        }
        $dbh->disconnect;
    }
    
    $logger->debug("Index 1".YAML::Dump(\%index));
    
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
    
    $logger->debug("Index 2".YAML::Dump(\@sortedindex));
    
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
    
    $self->print_page($template,$ttdata);
    
    return Apache2::Const::OK;

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

    my $query          = $self->query();

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Modify Querystring");
    
    my $exclude_ref = {};
    
    foreach my $param (@{$exclude_array_ref}){
        $exclude_ref->{$param} = 1;
    }
    
    my @cgiparams = ();
    
    foreach my $param (keys %{$query->param}){
        $logger->debug("Processing $param");
        if (exists $arg_ref->{change}{$param}){
            push @cgiparams, "$param=".$arg_ref->{change}->{$param};
        }
        elsif (! exists $exclude_ref->{$param}){
            my @values = $query->param($param);
            if (@values){
                foreach my $value (@values){
                    push @cgiparams, "$param=$value";
                }
            }
            else {
                push @cgiparams, "$param=".$query->param($param);
            }
        }
    }
    
    return join(";",@cgiparams) if (@cgiparams);

    return 'blabla';
}

sub joined_search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $recordlist;
    
    if    ($arg_ref->{sb} eq "xapian"){
        $self->search_xapian($arg_ref);
    }
    elsif ($arg_ref->{sb} eq "elasticsearch"){
        $self->search_elasticsearch($arg_ref);
    }

    $self->print_resultitem({templatename => $config->{tt_search_title_combined_tname}});
}

sub sequential_search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config      = OpenBib::Config->instance;
    my $searchquery = OpenBib::SearchQuery->instance;

    ######################################################################
    # Schleife ueber alle Datenbanken 
    ######################################################################

    foreach my $database ($config->get_databases_of_searchprofile($searchquery->get_searchprofile)) {
        # Trefferliste
        my $recordlist;

        if ($config->get_system_of_db($database) eq "Z39.50"){
            $self->search_z3950({ database => $database });
        }
        elsif ($arg_ref->{sb} eq "xapian"){
            $self->search_xapian({ database => $database });
        }
        elsif ($arg_ref->{sb} eq "elasticsearch"){
            $self->search_elasticsearch({ database => $database });
        }
        
        $self->print_resultitem({templatename => $config->{tt_search_title_item_tname}});
    }

    return;
}

sub search_xapian {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $searchquery  = OpenBib::SearchQuery->instance;
    my $queryoptions = OpenBib::QueryOptions->instance;


    my $atime=new Benchmark;
    my $timeall;
    
    my $recordlist;
    my $category_map_ref = ();
    my $resulttime;
    my $nav;

    my $request_args = {};

    if ($arg_ref->{database}){
        $request_args->{database} = $arg_ref->{database};
    }

    if ($arg_ref->{searchprofile}){
        $request_args->{searchprofile} = $arg_ref->{searchprofile};
    }

    # Recherche starten
    my $request = new OpenBib::Search::Local::Xapian($request_args);
    
    $request->initial_search();
    
    my $btime      = new Benchmark;
    $timeall    = timediff($btime,$atime);
    $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info($request->get_resultcount . " results found in $resulttime");
    
    $searchquery->set_hits($request->get_resultcount);
    
    if ($request->have_results) {
        $nav = Data::Pageset->new({
            'total_entries'    => $request->get_resultcount,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });
        
        $recordlist = $request->get_records();
        
#        if ($queryoptions->get_option('dd')) {
            $category_map_ref = $request->get_categorized_drilldown;
            $searchquery->set_results($category_map_ref->{8}); # Verteilung nach Datenbanken
#        }

    }
    
    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation in
    # den einzeltreffern

    $self->param('searchtime',$resulttime);
    $self->param('nav',$nav);
    $self->param('recordlist',$recordlist);
    $self->param('facets',$category_map_ref);
    $self->param('hits',$request->get_resultcount);
    $self->param('total_hits',$self->param('total_hits')+$request->get_resultcount);

    return;
}


sub search_elasticsearch {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $searchquery  = OpenBib::SearchQuery->instance;
    my $queryoptions = OpenBib::QueryOptions->instance;


    my $atime=new Benchmark;
    my $timeall;
    
    my $recordlist;
    my $category_map_ref = ();
    my $resulttime;
    my $nav;

    my $request_args = {};
    
    if ($arg_ref->{database}){
        $request_args->{database} = $arg_ref->{database};
    }

    if ($arg_ref->{searchprofile}){
        $request_args->{searchprofile} = $arg_ref->{searchprofile};
    }

    # Recherche starten
    my $request = new OpenBib::Search::Local::ElasticSearch($request_args);

    $request->initial_search();
    
    my $btime      = new Benchmark;
    $timeall    = timediff($btime,$atime);
    $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info($request->get_resultcount . " results found in $resulttime");
    
    $searchquery->set_hits($request->get_resultcount);
    
    if ($request->have_results) {
        $nav = Data::Pageset->new({
            'total_entries'    => $request->get_resultcount,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });
        
        $recordlist = $request->get_records();
        
#        if ($queryoptions->get_option('dd')) {
            $category_map_ref = $request->get_categorized_drilldown;
            $searchquery->set_results($category_map_ref->{8}); # Verteilung nach Datenbanken
#        }

    }
    
    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation in
    # den einzeltreffern

    $self->param('searchtime',$resulttime);
    $self->param('nav',$nav);
    $self->param('recordlist',$recordlist);
    $self->param('facets',$category_map_ref);
    $self->param('hits',$request->get_resultcount);
    $self->param('total_hits',$self->param('total_hits')+$request->get_resultcount);

    return;
}

sub search_z3950 {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $searchquery  = OpenBib::SearchQuery->instance;
    my $queryoptions = OpenBib::QueryOptions->instance;

    my $atime=new Benchmark;
    my $timeall;
    my $resulttime;
    my $recordlist;
    my $nav;

    my $database = $arg_ref->{database};

    return unless ($database);
    
    # Beschraenkung der Treffer pro Datenbank auf 10, da Z39.50-Abragen
    # sehr langsam sind
    # $hitrange = 10;
    my $z3950dbh = new OpenBib::Search::Z3950($database);
    
    $z3950dbh->search;

    my $btime      = new Benchmark;
    $timeall    = timediff($btime,$atime);
    $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    $z3950dbh->{rs}->option(elementSetName => "B");
    
    my $fullresultcount = $z3950dbh->{rs}->size();
    
    # Wenn mindestens ein Treffer gefunden wurde
    if ($fullresultcount >= 0) {
        
        my $a2time;
        
        if ($config->{benchmark}) {
            $a2time=new Benchmark;
        }
        
        my $end=($fullresultcount < $z3950dbh->{hitrange})?$fullresultcount:$z3950dbh->{hitrange};

        $nav = Data::Pageset->new({
            'total_entries'    => $fullresultcount,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });

        my $start_range = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num') + 1;
        my $end_range   = $queryoptions->get_option('page')*$queryoptions->get_option('num');
        if ($end_range >= $fullresultcount){
            $end_range       = $fullresultcount;
        }
        
        $recordlist = $z3950dbh->get_resultlist($start_range-1,$end_range);
        
        if ($config->{benchmark}) {
            my $b2time     = new Benchmark;
            my $timeall2   = timediff($b2time,$a2time);
            
            $logger->info("Zeit fuer : ".($recordlist->get_size())." Titel (holen)       : ist ".timestr($timeall2));
            $logger->info("Zeit fuer : ".($recordlist->get_size())." Titel (suchen+holen): ist ".timestr($timeall));
        }
        
        $recordlist->sort({order=>$queryoptions->get_option('srto'),type=>$queryoptions->get_option('srt')});
        
        $searchquery->set_hits($fullresultcount);
    }
    
    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation in
    # den einzeltreffern

    $self->param('searchtime',$resulttime);
    $self->param('nav',$nav);
    $self->param('recordlist',$recordlist);
    $self->param('facets',{});
    $self->param('hits',$fullresultcount);
    $self->param('total_hits',$self->param('total_hits')+$fullresultcount);

    return;
}


sub print_resultitem {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $templatename = exists $arg_ref->{templatename}
        ? $arg_ref->{templatename}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $r              = $self->param('r');
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $servername     = $self->param('servername');
    my $path_prefix    = $self->param('path_prefix');
    my $path           = $self->param('path');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $config->{'content_type_map_rev'}{$representation} || 'text/html';

    my $searchquery  = OpenBib::SearchQuery->instance;
    my $dbinfotable  = OpenBib::Config::DatabaseInfoTable->instance;

    # TT-Data erzeugen
    my $ttdata={
        dbinfo          => $dbinfotable,
        
        searchquery     => $searchquery,
        
        qopts           => $queryoptions->get_options,
        queryoptions    => $queryoptions,

        
        query           => $query,
        
        treffer         => $self->param('hits'),
        
        category_map    => $self->param('facets'),
        
        fullresultcount => $self->param('total_hits'),
        recordlist      => $self->param('recordlist'),
        
        nav             => $self->param('nav'),
        
#        lastquery       => $request->querystring,
        resulttime      => $self->param('searchtime'),
    };
    
    $ttdata = $self->add_default_ttdata($ttdata);

    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $templatename,
    });
    
    # Start der Ausgabe mit korrektem Header
    $r->content_type($ttdata->{content_type});
    
    # Es kann kein Datenbankabhaengiges Template geben
    
    my $itemtemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #                INCLUDE_PATH   => $config->{tt_include_path},
        #                ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT         => $r,
    });            
    
    
    $logger->debug("Printing Combined Result");
    
    $itemtemplate->process($templatename, $ttdata) || do {
        $r->log_error($itemtemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
}

sub search_index {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

        # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->param('r');
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $servername     = $self->param('servername');
    my $path_prefix    = $self->param('path_prefix');
    my $path           = $self->param('path');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $config->{'content_type_map_rev'}{$representation} || 'text/html';

    my $profile       = $query->param('profile')       || '';

    # Index zusammen mit Eingabefelder 
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';

    # oder Index als separate Funktion
    my $indextype    = $query->param('indextype')     || ''; # (verfindex, korindex, swtindex oder notindex)
    my $indexterm    = $query->param('indexterm')     || '';
    my $searchindex  = $query->param('searchindex')     || '';

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $searchquery = OpenBib::SearchQuery->instance;

    my $searchprofile = $self->get_searchprofile();

    
    my $contentreq =
        ($searchindex)?$searchquery->get_searchfield('indexterm' )->{norm}:
            
            ($verfindex)?$searchquery->get_searchfield('verf'         )->{norm}:
                ($korindex )?$searchquery->get_searchfield('kor'          )->{norm}:
                    ($swtindex )?$searchquery->get_searchfield('swt'          )->{norm}:
                        ($notindex )?$searchquery->get_searchfield('notation'     )->{norm}:undef;
    
    my $type =
        ($indextype)?$indextype:
        ($verfindex)?'aut':
            ($korindex )?'kor':
                ($swtindex )?'swt':
                    ($notindex )?'notation':undef;
    
    my $urlpart =
        ($type eq "aut"      )?"verf=$contentreq;verfindex=Index":
            ($type eq "kor"      )?"kor=$contentreq;korindex=Index":
                ($type eq "swt"      )?"swt=$contentreq;swtindex=Index":
                    ($type eq "notation" )?"notation=$contentreq;notindex=Index":undef;
    
    my $template =
        ($type eq "aut"      )?$config->{"tt_search_person_tname"}:
            ($type eq "kor"      )?$config->{"tt_search_corporatebody_tname"}:
                ($type eq "swt"      )?$config->{"tt_search_subject_tname"}:
                    ($type eq "notation" )?$config->{"tt_search_classification_tname"}:undef;
    
    $contentreq=~s/\+//g;
    $contentreq=~s/%2B//g;
    $contentreq=~s/%//g;
    
    if (!$contentreq) {
        $self->print_warning($msg->maketext("F&uuml;r die Nutzung der Index-Funktion m&uuml;ssen Sie einen Begriff eingegeben"));
        return Apache2::Const::OK;
    }
    
    if (length($contentreq) < 3) {
        my @databases = $config->get_databases_of_searchprofile($searchprofile);
        if ($#databases > 0){
            $self->print_warning($msg->maketext("Der Begriff muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche im Index ausgewählt wurde."));
            return Apache2::Const::OK;
        }
    }
    
    my %index=();
    
    my @sortedindex=();
    
    my $atime=new Benchmark;
    
    foreach my $database ($config->get_databases_of_searchprofile($searchprofile)) {
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $thisindex_ref=OpenBib::Search::Util::get_index({
            type       => $type,
            category   => 1,
            contentreq => $contentreq,
            dbh        => $dbh,
        });
        
        $logger->debug("Index Ursprung ($database)".YAML::Dump($thisindex_ref));
        
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
                'dbdesc'   => $dbinfotable->{dbnames}{$database},
                'id'       => $item_ref->{id},
                'titcount' => $item_ref->{titcount},
            };
            
            $index{$item_ref->{content}}{titcount}=$index{$item_ref->{content}}{titcount}+$item_ref->{titcount};
        }
        $dbh->disconnect;
    }
    
    $logger->debug("Index 1".YAML::Dump(\%index));
    
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
    
    $logger->debug("Index 2".YAML::Dump(\@sortedindex));
    
    my $hits=$#sortedindex+1;
    
    my $databasestring="";
    foreach my $database ($config->get_databases_of_searchprofile($searchprofile)){
        $databasestring.=";database=$database";
    }
    
    my $baseurl="$path_prefix/$config->{search_loc}?$urlpart;profile=$profile;hitrange=$queryoptions->get_option('num');sorttype=$queryoptions->get_option('srt');sortorder=$queryoptions->get_option('srto')$databasestring";
    
    my @nav=();
    
    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');
    
    if ($queryoptions->get_option('num') > 0) {
        $logger->debug("Navigation wird erzeugt: Hitrange: $queryoptions->get_option('num') Hits: $hits");
        
        for (my $i=0; $i <= $hits-1; $i+=$queryoptions->get_option('num')) {
            my $active=0;
            
            if ($i == $offset) {
                $active=1;
            }
            
            my $item={
                start  => $i+1,
                end    => ($i+$queryoptions->get_option('num')>$hits)?$hits:$i+$queryoptions->get_option('num'),
                url    => $baseurl.";hitrange=$queryoptions->get_option('num');offset=$i",
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
        servername   => $servername,
        lang         => $lang,
        qopts        => $queryoptions->get_options,
        queryoptions => $queryoptions,
        
        resulttime => $resulttime,
        contentreq => $contentreq,
        index      => \@sortedindex,
        nav        => \@nav,
        offset     => $offset,
        baseurl    => $baseurl,
    };

    $ttdata = $self->add_default_ttdata($ttdata);
    
    $self->print_page($template,$ttdata,$r);
    
    return Apache2::Const::OK;
}

1;
