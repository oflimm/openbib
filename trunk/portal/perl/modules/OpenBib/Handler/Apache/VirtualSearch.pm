###################################################################
#
#  OpenBib::Handler::Apache::VirtualSearch.pm
#
#  Dieses File ist (C) 1997-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::VirtualSearch;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
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
use OpenBib::Search::Z3950;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    # CGI-Input auslesen
    my $serien        = decode_utf8($query->param('serien'))        || 0;
    my $enrich        = decode_utf8($query->param('enrich'))        || 0;

    my @databases     = ($query->param('database'))?$query->param('database'):();

    my $hitrange      = ($query->param('hitrange' ))?$query->param('hitrange'):50;
    my $offset        = ($query->param('offset'   ))?$query->param('offset'):0;
    my $sorttype      = ($query->param('sorttype' ))?$query->param('sorttype'):"author";
    my $sortorder     = ($query->param('sortorder'))?$query->param('sortorder'):'up';
    my $autoplus      = $query->param('autoplus')      || 1;
    my $combinedbs    = $query->param('combinedbs')    || 0;

    my $sortall       = ($query->param('sortall'))?$query->param('sortall'):'0';

    my $searchall     = $query->param('searchall')     || '';
    my $searchprofile = $query->param('searchprofile') || '';

    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';
    my $profil        = $query->param('profil')        || '';
    my $trefferliste  = $query->param('trefferliste')  || '';
    my $queryid       = $query->param('queryid')       || '';
    my $sb            = $query->param('sb')            || 'sql'; # Search backend
    my $st            = $query->param('st')            || '';    # Search type (1=simple,2=complex)    
    my $drilldown             = $query->param('drilldown')      || 0;     # Drill-Down?
    my $drilldown_cloud       = $query->param('dd_cloud')       || 0;     # Cloud?
    my $drilldown_categorized = $query->param('dd_categorized') || 0;     # Categorized?

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $searchquery = OpenBib::SearchQuery->instance;

    $searchquery->set_from_apache_request($r);

    my $is_orgunit=0;

  ORGUNIT_SEARCH:
    foreach my $orgunit_ref (@{$config->{orgunits}}){
        if ($orgunit_ref->{short} eq $profil){
            $is_orgunit=1;
            last ORGUNIT_SEARCH;
        }
    }
    
    $profil="" if (!$is_orgunit && $profil ne "dbauswahl" && !$profil=~/^user/ && $profil ne "alldbs");

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    # Loggen der Recherche-Art (1=simple, 2=complex)
    $session->log_event({
		type      => 20,
                content   => $st,
    });

    # Loggen des Recherche-Backends
    $session->log_event({
		type      => 21,
                content   => $sb,
    });

    # BEGIN DB-Bestimmung
    ####################################################################
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    ####################################################################

    # Wenn Datenbanken uebergeben werden, dann wird nur
    # in diesen gesucht.
    if ($#databases != -1) {
        $logger->debug("Selecting databases received via CGI");
        # Wenn Datenbanken explizit ueber das Suchformular uebergeben werden,
        # dann werden diese als neue Datenbankauswahl gesetzt
        
        # Zuerst die bestehende Auswahl loeschen
        $session->clear_dbchoice();
        
        # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
        foreach my $database (@databases) {
            $session->set_dbchoice($database);
        }
        
        # Neue Datenbankauswahl ist voreingestellt
        $session->set_profile('dbauswahl');
    }
    else {
        # Wenn nur ein View angegeben wird, aber keine Submit-Funktion (s.u.),
        # z.B. wenn direkt von extern fuer einen View eine Recherche gestartet werden soll,
        # dann wird in den Datenbanken des View recherchiert
        if ($view && !($searchall||$searchprofile||$verfindex||$korindex||$swtindex||$notindex)){
            $logger->debug("Selecting databases of view");
            @databases = $config->get_dbs_of_view($view);
        }
        
        else {
            if ($searchall) {
                if ($view){
                    $logger->debug("Selecting all active databases of views systemprofile");
                    @databases = $config->get_active_databases_of_systemprofile($view);
                }
                else {
                    $logger->debug("Selecting all active databases");
                    @databases = $config->get_active_databases();
                }
            }
            elsif ($searchprofile || $verfindex || $korindex || $swtindex || $notindex) {
                if ($profil eq "dbauswahl") {
                    $logger->debug("Selecting databases of users choice");
                    # Eventuell bestehende Auswahl zuruecksetzen
                    @databases = $session->get_dbchoice();
                }
                # Wenn ein anderes Profil als 'dbauswahl' ausgewaehlt wuerde
                elsif ($profil) {
                    $logger->debug("Selecting databases of userprofile");
                    # Eventuell bestehende Auswahl zuruecksetzen
                    @databases=();
                    
                    # Benutzerspezifische Datenbankprofile
                    if ($profil=~/^user(\d+)/) {
                        my $profilid=$1;

                        @databases = $user->get_profiledbs_of_profileid($profilid);
                    }
                    # oder alle
                    elsif ($profil eq "alldbs") {
                        # Alle Datenbanken
                        if ($view){
                            $logger->debug("Selecting all active databases of views systemprofile");
                            @databases = $config->get_active_databases_of_systemprofile($view);
                        }
                        else {
                            $logger->debug("Selecting all active databases");
                            @databases = $config->get_active_databases();
                        }
                    }
                    # ansonsten orgunit
                    else {
                        @databases = $config->get_active_databases_of_orgunit($profil);
                    }
                }
                # Kein Profil
                else {
                    OpenBib::Common::Util::print_warning($msg->maketext("Sie haben <b>In ausgewählten Katalogen suchen</b> angeklickt, obwohl sie keine [_1]Kataloge[_2] oder Suchprofile ausgewählt haben. Bitte wählen Sie die gewünschten Kataloge/Suchprofile aus oder betätigen Sie <b>In allen Katalogen suchen</a>.","<a href=\"$config->{databasechoice_loc}?sessionID=$session->{ID}\" target=\"body\">","</a>"),$r,$msg);
                    return OK;
                }
                
                # Wenn Profil aufgerufen wurde, dann abspeichern fuer Recherchemaske
                if ($profil) {
                    $session->set_profile($profil);
                }
            }
        }
    }

    my $queryalreadyexists = 0;
    
    # Abspeichern des Query und Generierung der Queryid
    if ($session->{ID} ne "-1") {
        ($queryalreadyexists,$queryid) = $session->get_queryid({
            databases   => \@databases,
            hitrange    => $hitrange,
        });
    }
    # BEGIN Index
    ####################################################################
    # Wenn ein kataloguebergreifender Index ausgewaehlt wurde
    ####################################################################

    $logger->debug(YAML::Dump($searchquery));
    if ($verfindex || $korindex || $swtindex || $notindex) {
        my $contentreq =
            ($verfindex)?$searchquery->get_searchfield('verf'    )->{norm}:
            ($korindex )?$searchquery->get_searchfield('kor'     )->{norm}:
            ($swtindex )?$searchquery->get_searchfield('swt'     )->{norm}:
            ($notindex )?$searchquery->get_searchfield('notation')->{norm}:undef;

        my $type =
            ($verfindex)?'aut':
            ($korindex )?'kor':
            ($swtindex )?'swt':
            ($notindex )?'notation':undef;

        my $urlpart =
            ($verfindex)?"verf=$contentreq;verfindex=Index":
            ($korindex )?"kor=$contentreq;korindex=Index":
            ($swtindex )?"swt=$contentreq;swtindex=Index":
            ($notindex )?"notation=$contentreq;notindex=Index":undef;

        my $template =
            ($verfindex)?$config->{"tt_virtualsearch_showverfindex_tname"}:
            ($korindex )?$config->{"tt_virtualsearch_showkorindex_tname"}:
            ($swtindex )?$config->{"tt_virtualsearch_showswtindex_tname"}:
            ($notindex )?$config->{"tt_virtualsearch_shownotindex_tname"}:undef;
            
        $contentreq=~s/\+//g;
        $contentreq=~s/%2B//g;
        $contentreq=~s/%//g;

        if (!$contentreq) {
            OpenBib::Common::Util::print_warning($msg->maketext("F&uuml;r die Nutzung der Index-Funktion m&uuml;ssen Sie einen Begriff eingegeben"),$r,$msg);
            return OK;
        }

        if ($#databases > 0 && length($contentreq) < 3) {
            OpenBib::Common::Util::print_warning($msg->maketext("Der Begriff muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche im Index ausgewählt wurde."),$r,$msg);
            return OK;
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
        
        my $baseurl="http://$config->{servername}$config->{virtualsearch_loc}?sessionID=$session->{ID};view=$view;$urlpart;profil=$profil;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder$databasestring";

        my @nav=();

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
            view       => $view,
            stylesheet => $stylesheet,		
            sessionID  => $session->{ID},

            qopts      => $queryoptions->get_options,
            
            resulttime => $resulttime,
            contentreq => $contentreq,
            index      => \@sortedindex,
            nav        => \@nav,
            offset     => $offset,
            hitrange   => $hitrange,
            baseurl    => $baseurl,
            profil     => $profil,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };

        OpenBib::Common::Util::print_page($template,$ttdata,$r);

        return OK;
    }

    ####################################################################
    # ENDE Indizes
    #


    # Folgende nicht erlaubte Anfragen werden sofort ausgesondert

    my $firstsql;

    if ($searchquery->get_searchfield('fs')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('verf')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('kor')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('hst')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('swt')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('notation')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('sign')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('isbn')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('issn')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('mart')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('hststring')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('inhalt')->{norm}) {
        $firstsql=1;
    }
    
    if ($searchquery->get_searchfield('gtquelle')->{norm}) {
        $firstsql=1;
    }

    if ($searchquery->get_searchfield('ejahr')->{norm}){
        $firstsql=1;
    }
    
    if ($searchquery->get_searchfield('ejahr')->{norm}) {
        my ($ejtest)=$searchquery->get_searchfield('ejahr')->{norm}=~/.*(\d\d\d\d).*/;
        if (!$ejtest) {
            OpenBib::Common::Util::print_warning($msg->maketext("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein."),$r,$msg);
            return OK;
        }
    }

    if ($searchquery->get_searchfield('ejahr')->{bool} eq "OR") {
        if ($searchquery->get_searchfield('ejahr')->{norm}) {
            OpenBib::Common::Util::print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."),$r,$msg);
            return OK;
        }
    }


    if ($searchquery->get_searchfield('ejahr')->{bool} eq "AND") {
        if ($searchquery->get_searchfield('ejahr')->{norm}) {
            if (!$firstsql) {
                OpenBib::Common::Util::print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."),$r,$msg);
                return OK;
            }
        }
    }

    if (!$firstsql) {
        OpenBib::Common::Util::print_warning($msg->maketext("Es wurde kein Suchkriterium eingegeben."),$r,$msg);
        return OK;
    }

    my %trefferpage  = ();
    my %dbhits       = ();

    my $loginname = "";
    my $password  = "";

    if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self"){
        ($loginname,$password)=$user->get_credentials();
    }

    # Hash im Loginname ersetzen
    $loginname =~s/#/\%23/;

    my $starttemplatename=$config->{tt_virtualsearch_result_start_tname};
    if ($view && -e "$config->{tt_include_path}/views/$view/$starttemplatename") {
        $starttemplatename="views/$view/$starttemplatename";
    }

    # Start der Ausgabe mit korrektem Header
    print $r->send_http_header("text/html");

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

    # TT-Data erzeugen

    my $startttdata={
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},

        loginname      => $loginname,
        password       => $password,

        searchquery    => $searchquery->get_searchquery,
        query          => $query,

        queryid        => $queryid,
        
        config         => $config,
        user           => $user,
        msg            => $msg,
    };

    $starttemplate->process($starttemplatename, $startttdata) || do {
        $r->log_reason($starttemplate->error(), $r->filename);
        return SERVER_ERROR;
    };

    # Ausgabe flushen
    $r->rflush();

    my $enrichkeys_ref=[];
    
    # Vorangestellte Recherche in der Datenbank zur Suchanreicherung
    if ($enrich){
        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

        my $sqlquerystring  = "select isbn from search where match (content) against (? in boolean mode) limit 2000";
        my $request         = $enrichdbh->prepare($sqlquerystring);
        $request->execute($searchquery->get_searchfield('hst')->{norm}." ".$searchquery->get_searchfield('fs')->{norm});
        while (my $res=$request->fetchrow_arrayref){
            push @{$enrichkeys_ref}, $res->[0];
        }

        $request->finish();
        $enrichdbh->disconnect();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von enrichkeys ist ".timestr($timeall));
        }

        $logger->debug("Enrich-Keys: ".join(" ",@{$enrichkeys_ref}));
    }
    
    my $gesamttreffer=0;

    # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
    #
    ######################################################################
    # Schleife ueber alle Datenbanken 
    ######################################################################

    my $atime=new Benchmark;

    # Array aus DB-Name und Titel-ID zur Navigation
    my @resultset  = ();
    my $fallbacksb = "";

#    my $cacherequest=$session->{dbh}->prepare("insert into searchresults values (?,?,?,?,?)") or $logger->error($DBI::errstr);

    if ($combinedbs){
        # Trefferliste
        my $recordlist;
        
        if ($sb eq 'xapian') {
            # Xapian

            $recordlist = new OpenBib::RecordList::Title();

            my $atime=new Benchmark;

            my $dbh;
            
            foreach my $database (@databases) {
                $logger->debug("Adding Xapian DB-Object for database $database");
                
                if (!defined $dbh){
                    # Erstes Objekt erzeugen,
                    
                    $logger->debug("Creating Xapian DB-Object for database $database");                
                    
                    eval {
                        $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
                    };
                    
                    if ($@){
                        $logger->error("Database: $database - :".$@);
                        $fallbacksb="sql";
                    }
                }
                else {
                    $logger->debug("Adding database $database");
                    
                    eval {
                        $dbh->add_database(new Search::Xapian::Database( $config->{xapian_index_base_path}."/".$database));
                    };
                    
                    if ($@){
                        $logger->error("Database: $database - :".$@);
                        $fallbacksb="sql";
                        last;
                    }                        
                }
            }
            
            # alles ok?, dann Recherche starten
            if (!$fallbacksb) {
                my $request = new OpenBib::Search::Local::Xapian();
                
                $request->initial_search({
                    serien          => $serien,
                    dbh             => $dbh,
                    
                    enrich          => $enrich,
                    enrichkeys_ref  => $enrichkeys_ref,
                    dd_categorized  => $drilldown_categorized,
                });
                
                my $fullresultcount = $request->{resultcount};
                
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                $logger->info($fullresultcount . " results found in $resulttime");
                
                my $category_map_ref = ();
                
                if ($fullresultcount >= 1) {
                    
                    my $rset=Search::Xapian::RSet->new() if ($drilldown && $drilldown_cloud);
                    my $mcount=0;
                    
                    foreach my $match ($request->matches) {
                        # Fuer Drilldowns (Tag-Cloud) werden die ersten
                        # 200 Treffer analysiert
                        last if ($drilldown && $drilldown_cloud && $mcount >= 200);
                        
                        $rset->add_document($match->get_docid) if ($drilldown && $drilldown_cloud);
                        # Es werden immer nur $hitrange Titelinformationen
                        # zur Ausgabe aus dem MSet herausgeholt
                        if ($mcount < $hitrange) {
                            my $document        = $match->get_document();
                            my $titlistitem_raw = pack "H*", $document->get_data();
                            my $titlistitem_ref = Storable::thaw($titlistitem_raw);
                            
                            $recordlist->add(new OpenBib::Record::Title({database => $titlistitem_ref->{database}, id => $titlistitem_ref->{id}})->set_brief_normdata_from_storable($titlistitem_ref));
                        }
                        $mcount++;
                    }
                    
                    my $termweight_ref={};
                    
                    my $drilldowntime;
                    
                    if ($drilldown) {
                        my $ddatime   = new Benchmark;
                        
                        if ($drilldown_categorized) {
                            # Transformation Hash->Array zur Sortierung
                            
                            my $tmp_category_map_ref = $request->{categories};
                            
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
                            
                        }
                        
                        if ($drilldown_cloud) {
                            my $esetrange = ($fullresultcount < 50)?$fullresultcount-1:200;
                            my $eterms    = $request->enq->get_eset($esetrange,$rset);
                            my $iter=$eterms->begin();
                            
                            while ($iter != $eterms->end()) {
                                my $term   = $iter->get_termname();
                                my $weight = $iter->get_weight();
                                
                                $logger->debug("Got relevant term $term with weight $weight");
                                my $thisterm = $term;
                                
                                if ($term=~/X\d+(.+)/) {
                                    $thisterm=$1;
                                }
                                
                                if (exists $termweight_ref->{$thisterm}) {
                                    $termweight_ref->{$thisterm}+=$weight;
                                }
                                else {
                                    $termweight_ref->{$thisterm}=$weight;
                                }
                                
                                $iter++;
                            }
                            
                            {
                                my $ddbtime       = new Benchmark;
                                my $ddtimeall     = timediff($ddbtime,$ddatime);
                                $logger->debug("ESet-Time: ".timestr($ddtimeall,"nop"));
                            }
                        }
                        
                        $logger->debug(YAML::Dump($recordlist->to_list));
                        
                        my $ddbtime       = new Benchmark;
                        my $ddtimeall     = timediff($ddbtime,$ddatime);
                        $drilldowntime    = timestr($ddtimeall,"nop");
                        $drilldowntime    =~s/(\d+\.\d+) .*/$1/;
                    }
                    
                    $recordlist->sort({order=>$sortorder,type=>$sorttype});
                    
                    
                    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                    push @resultset, @{$recordlist->to_ids};
                    
                    my $treffer=$recordlist->get_size();
                    
                    my $itemtemplatename=$config->{tt_virtualsearch_result_combined_tname};

                    if ($view && -e "$config->{tt_include_path}/views/$view/$itemtemplatename") {
                        $itemtemplatename="views/$view/$itemtemplatename";
                    }

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
                    
                    # TT-Data erzeugen
                    my $ttdata={
                        view            => $view,
                        sessionID       => $session->{ID},
                        
                        dbinfotable     => $dbinfotable,
                        
                        treffer         => $treffer,
                        
#                        database        => $database,
                        queryid         => $queryid,
                        
                        category_map    => $category_map_ref,
                        
                        fullresultcount => $fullresultcount,
                        recordlist      => $recordlist,
                        
                        qopts           => $queryoptions->get_options,
                        drilldown             => $drilldown,
                        drilldown_cloud       => $drilldown_cloud,
                        drilldown_categorized => $drilldown_categorized,
                        
                        cloud           => gen_cloud_absolute({dbh => $dbh, term_ref => $termweight_ref}),
                        
                        lastquery       => $request->querystring,
                        sorttype        => $sorttype,
                        sortorder       => $sortorder,
                        resulttime      => $resulttime,
                        drilldowntime   => $drilldowntime,
                        config          => $config,
                        user            => $user,
                        msg             => $msg,
                    };
                    
                    $itemtemplate->process($itemtemplatename, $ttdata) || do {
                        $r->log_reason($itemtemplate->error(), $r->filename);
                        return SERVER_ERROR;
                    };
                    
                    $trefferpage{'all'} = $recordlist;
                    $dbhits     {'all'} = $treffer;
                    $gesamttreffer      = $treffer;
                    
                    undef $btime;
                    undef $timeall;
                }
            }
        }
        
    }
    
    if (!$combinedbs || $fallbacksb){
        foreach my $database (@databases) {
            
            # Trefferliste
            my $recordlist;
            
            if ($config->get_system_of_db($database) eq "Z39.50"){
                my $atime=new Benchmark;
                
                # Beschraenkung der Treffer pro Datenbank auf 10, da Z39.50-Abragen
                # sehr langsam sind
                # $hitrange = 10;
                my $z3950dbh = new OpenBib::Search::Z3950($database);
                
                $z3950dbh->search;
                $z3950dbh->{rs}->option(elementSetName => "B");
                
                my $fullresultcount = $z3950dbh->{rs}->size();

                # Wenn mindestens ein Treffer gefunden wurde
                if ($fullresultcount >= 0) {
                
                    my $a2time;
                
                    if ($config->{benchmark}) {
                        $a2time=new Benchmark;
                    }

                    my $end=($fullresultcount < $z3950dbh->{hitrange})?$fullresultcount:$z3950dbh->{hitrange};
                
                    $recordlist = $z3950dbh->get_resultlist(0,$end);
                
                    my $btime      = new Benchmark;
                    my $timeall    = timediff($btime,$atime);
                    my $resulttime = timestr($timeall,"nop");
                    $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                    if ($config->{benchmark}) {
                        my $b2time     = new Benchmark;
                        my $timeall2   = timediff($b2time,$a2time);
                    
                        $logger->info("Zeit fuer : ".($recordlist->get_size())." Titel (holen)       : ist ".timestr($timeall2));
                        $logger->info("Zeit fuer : ".($recordlist->get_size())." Titel (suchen+holen): ist ".timestr($timeall));
                    }

                    $recordlist->sort({order=>$sortorder,type=>$sorttype});
                
                    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                    push @resultset, @{$recordlist->to_ids};
                
                    my $treffer=$recordlist->get_size();
                
                    my $itemtemplatename=$config->{tt_virtualsearch_result_item_tname};
                    if ($view && -e "$config->{tt_include_path}/views/$view/$itemtemplatename") {
                        $itemtemplatename="views/$view/$itemtemplatename";
                    }

                    # Database-Template ist spezifischer als View-Template und geht vor
                    if ($database && -e "$config->{tt_include_path}/database/$database/$itemtemplatename") {
                        $itemtemplatename="database/$database/$itemtemplatename";
                    }

                    my $itemtemplate = Template->new({
                        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                            INCLUDE_PATH   => $config->{tt_include_path},
                            ABSOLUTE       => 1,
                        }) ],
                        RECURSION      => 1,
                        OUTPUT         => $r,
                    });
                
                
                    # TT-Data erzeugen
                    my $ttdata={
                        view            => $view,
                        sessionID       => $session->{ID},
                        database        => $database,
                    
                        dbinfo          => $dbinfotable->{dbinfo}{$database},
                    
                        treffer         => $treffer,
                    
                        database        => $database,
                        queryid         => $queryid,
                        qopts           => $queryoptions->get_options,
                        fullresultcount => $fullresultcount,
                        recordlist      => $recordlist,
                    
                        sorttype        => $sorttype,
                        sortorder       => $sortorder,
                        resulttime      => $resulttime,
                        config          => $config,
                        user            => $user,
                        msg             => $msg,
                    };
                
                    $itemtemplate->process($itemtemplatename, $ttdata) || do {
                        $r->log_reason($itemtemplate->error(), $r->filename);
                        return SERVER_ERROR;
                    };
                
                    $trefferpage{$database} = $recordlist;
                    $dbhits     {$database} = $treffer;
                    $gesamttreffer          = $gesamttreffer+$treffer;
                
                    undef $btime;
                    undef $timeall;
                
                    # flush output buffer
                    $r->rflush();
                }
            } else {
                # Lokale Datenbaken
                my $fallbacksb=$sb;

                if ($sb eq 'xapian') {
                    # Xapian

                    $recordlist = new OpenBib::RecordList::Title();

                    my $atime=new Benchmark;

                    $logger->debug("Creating Xapian DB-Object for database $database");

                    my $dbh;
                    eval {
                        $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
                    };

                    if ($@) {
                        $logger->error("Database: $database - :".$@);
                        $fallbacksb="sql";
                    } else {
                        my $request = new OpenBib::Search::Local::Xapian();
                    
                        $request->initial_search({
                            serien          => $serien,
                            dbh             => $dbh,
                            database        => $database,
                        
                            enrich          => $enrich,
                            enrichkeys_ref  => $enrichkeys_ref,
                            dd_categorized  => $drilldown_categorized,
                        });

                        my $fullresultcount = $request->{resultcount};
                    
                        my $btime      = new Benchmark;
                        my $timeall    = timediff($btime,$atime);
                        my $resulttime = timestr($timeall,"nop");
                        $resulttime    =~s/(\d+\.\d+) .*/$1/;
                    
                        $logger->info($fullresultcount . " results found in $resulttime");

                        my $category_map_ref = ();

                        if ($fullresultcount >= 1) {

                            my $rset=Search::Xapian::RSet->new() if ($drilldown && $drilldown_cloud);
                            my $mcount=0;

                            foreach my $match ($request->matches) {
                                # Fuer Drilldowns (Tag-Cloud) werden die ersten
                                # 200 Treffer analysiert
                                last if ($drilldown && $drilldown_cloud && $mcount >= 200);

                                $rset->add_document($match->get_docid) if ($drilldown && $drilldown_cloud);
                                # Es werden immer nur $hitrange Titelinformationen
                                # zur Ausgabe aus dem MSet herausgeholt
                                if ($mcount < $hitrange) {
                                    my $document        = $match->get_document();
                                    my $titlistitem_raw = pack "H*", $document->get_data();
                                    my $titlistitem_ref = Storable::thaw($titlistitem_raw);

                                    $recordlist->add(new OpenBib::Record::Title({database => $titlistitem_ref->{database}, id => $titlistitem_ref->{id}})->set_brief_normdata_from_storable($titlistitem_ref));
                                }
                                $mcount++;
                            }
                        
                            my $termweight_ref={};
                        
                            my $drilldowntime;
                        
                            if ($drilldown) {
                                my $ddatime   = new Benchmark;
                            
                                if ($drilldown_categorized) {
                                # Transformation Hash->Array zur Sortierung
                                
                                    my $tmp_category_map_ref = $request->{categories};
                                
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

                                }

                                if ($drilldown_cloud) {
                                    my $esetrange = ($fullresultcount < 50)?$fullresultcount-1:200;
                                    my $eterms    = $request->enq->get_eset($esetrange,$rset);
                                    my $iter=$eterms->begin();
                                
                                    while ($iter != $eterms->end()) {
                                        my $term   = $iter->get_termname();
                                        my $weight = $iter->get_weight();
                                    
                                        $logger->debug("Got relevant term $term with weight $weight");
                                        my $thisterm = $term;
                                    
                                        if ($term=~/X\d+(.+)/) {
                                            $thisterm=$1;
                                        }

                                        if (exists $termweight_ref->{$thisterm}) {
                                            $termweight_ref->{$thisterm}+=$weight;
                                        } else {
                                            $termweight_ref->{$thisterm}=$weight;
                                        }
                                    
                                        $iter++;
                                    }

                                    {
                                        my $ddbtime       = new Benchmark;
                                        my $ddtimeall     = timediff($ddbtime,$ddatime);
                                        $logger->debug("ESet-Time: ".timestr($ddtimeall,"nop"));
                                    }
                                }
                            
                                $logger->debug(YAML::Dump($recordlist->to_list));

                                my $ddbtime       = new Benchmark;
                                my $ddtimeall     = timediff($ddbtime,$ddatime);
                                $drilldowntime    = timestr($ddtimeall,"nop");
                                $drilldowntime    =~s/(\d+\.\d+) .*/$1/;

                                $logger->debug("Zeit fuer Drilldowns $drilldowntime");
                            }

                            $recordlist->sort({order=>$sortorder,type=>$sorttype});

                        
                            # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                            push @resultset, @{$recordlist->to_ids};
                        
                            my $treffer=$recordlist->get_size();
                        
                            my $itemtemplatename=$config->{tt_virtualsearch_result_item_tname};
                            if ($view && -e "$config->{tt_include_path}/views/$view/$itemtemplatename") {
                                $itemtemplatename="views/$view/$itemtemplatename";
                            }

                            # Database-Template ist spezifischer als View-Template und geht vor
                            if ($database && -e "$config->{tt_include_path}/database/$database/$itemtemplatename") {
                                $itemtemplatename="database/$database/$itemtemplatename";
                            }

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
                        
                            # TT-Data erzeugen
                            my $ttdata={
                                view            => $view,
                                sessionID       => $session->{ID},
                            
                                dbinfo          => $dbinfotable->{dbinfo}{$database},
                            
                                treffer         => $treffer,
                            
                                database        => $database,
                                queryid         => $queryid,

                                category_map    => $category_map_ref,

                                fullresultcount => $fullresultcount,
                                recordlist      => $recordlist,
                            
                                qopts           => $queryoptions->get_options,
                                drilldown             => $drilldown,
                                drilldown_cloud       => $drilldown_cloud,
                                drilldown_categorized => $drilldown_categorized,

                                cloud           => gen_cloud_absolute({dbh => $dbh, term_ref => $termweight_ref}),

                                lastquery       => $request->querystring,
                                sorttype        => $sorttype,
                                sortorder       => $sortorder,
                                resulttime      => $resulttime,
                                drilldowntime   => $drilldowntime,
                                config          => $config,
                                user            => $user,
                                msg             => $msg,
                            };
                        
                            $itemtemplate->process($itemtemplatename, $ttdata) || do {
                                $r->log_reason($itemtemplate->error(), $r->filename);
                                return SERVER_ERROR;
                            };
                        
                            $trefferpage{$database} = $recordlist;
                            $dbhits     {$database} = $treffer;
                            $gesamttreffer          = $gesamttreffer+$treffer;
                        
                            undef $btime;
                            undef $timeall;

                            # flush output buffer
                            $r->rflush();
                        }
                    }
                }

                if ($sb eq 'sql' || $fallbacksb eq 'sql') {
                    # SQL
            
                    my $atime=new Benchmark;
            
                    my ($recordlist,$fullresultcount) = OpenBib::Search::Util::initial_search_for_titidns({
                        serien          => $serien,

                        database        => $database,

                        hitrange        => $hitrange,

                        enrich          => $enrich,
                        enrichkeys_ref  => $enrichkeys_ref,
                    });

                    $logger->debug("Treffer-Ids in $database:".$recordlist->to_ids);

                    # Wenn mindestens ein Treffer gefunden wurde
                    if ($recordlist->get_size() > 0) {

                        my $a2time;
            
                        if ($config->{benchmark}) {
                            $a2time=new Benchmark;
                        }

                        # Kurztitelinformationen fuer RecordList laden
                        $recordlist->load_brief_records;

                        my $btime      = new Benchmark;
                        my $timeall    = timediff($btime,$atime);
                        my $resulttime = timestr($timeall,"nop");
                        $resulttime    =~s/(\d+\.\d+) .*/$1/;

                        if ($config->{benchmark}) {
                            my $b2time     = new Benchmark;
                            my $timeall2   = timediff($b2time,$a2time);

                            $logger->info("Zeit fuer : ".($recordlist->get_size())." Titel (holen)       : ist ".timestr($timeall2));
                            $logger->info("Zeit fuer : ".($recordlist->get_size())." Titel (suchen+holen): ist ".timestr($timeall));
                        }

                        $recordlist->sort({order=>$sortorder,type=>$sorttype});

                        # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                        push @resultset, @{$recordlist->to_ids};
	    
                        my $treffer=$recordlist->get_size();

                        my $itemtemplatename=$config->{tt_virtualsearch_result_item_tname};
                        if ($view && -e "$config->{tt_include_path}/views/$view/$itemtemplatename") {
                            $itemtemplatename="views/$view/$itemtemplatename";
                        }

                        # Database-Template ist spezifischer als View-Template und geht vor
                        if ($database && -e "$config->{tt_include_path}/database/$database/$itemtemplatename") {
                            $itemtemplatename="database/$database/$itemtemplatename";
                        }

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


                        # TT-Data erzeugen
                        my $ttdata={
                            view            => $view,
                            sessionID       => $session->{ID},
		  
                            dbinfo          => $dbinfotable->{dbinfo}{$database},

                            treffer         => $treffer,

                            database        => $database,
                            queryid         => $queryid,
                            qopts           => $queryoptions->get_options,
                            fullresultcount => $fullresultcount,
                            recordlist      => $recordlist,

                            sorttype        => $sorttype,
                            sortorder       => $sortorder,
                            resulttime      => $resulttime,
                            config          => $config,
                            user            => $user,
                            msg             => $msg,
                        };

                        $itemtemplate->process($itemtemplatename, $ttdata) || do {
                            $r->log_reason($itemtemplate->error(), $r->filename);
                            return SERVER_ERROR;
                        };

                        $trefferpage{$database} = $recordlist;
                        $dbhits     {$database} = $treffer;
                        $gesamttreffer          = $gesamttreffer+$treffer;

                        undef $btime;
                        undef $timeall;

                        # flush output buffer
                        $r->rflush();
                    }
                }
            }
        }
        # Cachen des Ergebnisses
#        {
#            my $storableres=unpack "H*",Storable::freeze(\@resultlist);
#            $logger->debug("YAML-Dumped: ".YAML::Dump($res));
#            my $num=$#resultlist+1;
#            $cacherequest->execute($session->{ID},$database,$storableres,$num,$queryid) or $logger->error($DBI::errstr);
#        }
        
    }
#    $cacherequest->finish();
    

    if ($config->{benchmark}) {
        my $btime=new Benchmark;
        my $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung fuer Suche ueber alle Datenbanken ist ".timestr($timeall));
    }

    ######################################################################
    #
    # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln

#    $logger->info("InitialSearch: ", $session->{ID}, " ", $gesamttreffer, " fs=(", $fs, ") verf=(", $boolverf, "#", $verf, ") hst=(", $boolhst, "#", $hst, ") hststring=(", $boolhststring, "#", $hststring, ") gtquelle=(", $boolgtquelle, "#", $gtquelle, ") swt=(", $boolswt, "#", $swt, ") kor=(", $boolkor, "#", $kor, ") sign=(", $boolsign, "#", $sign, ") isbn=(", $boolisbn, "#", $isbn, ") issn=(", $boolissn, "#", $issn, ") mart=(", $boolmart, "#", $mart, ") notation=(", $boolnotation, "#", $notation, ") ejahr=(", $boolejahr, "#", $ejahr, ") ejahrop=(", $ejahrop, ") databases=(",join(' ',sort @databases),") ");

    # Wenn etwas gefunden wurde, dann kann ein Resultset geschrieben werden.

    if ($gesamttreffer > 0) {
        $logger->debug("Resultset wird geschrieben: ".YAML::Dump(\@resultset));
        $session->updatelastresultset(\@resultset);
    }

    ######################################################################
    # Bei einer SessionID von -1 wird effektiv keine Session verwendet
    ######################################################################

    if ($session->{ID} ne "-1") {
        # Neuer Query
        if (!$queryalreadyexists) {
            # Jetzt update der Trefferinformationen
            my $dbasesstring=join("||",sort @databases);
            my $thisquerystring=unpack "H*", Storable::freeze($searchquery->get_searchquery);

            # Wurde in allen Katalogen recherchiert?

            my $alldbcount = $config->get_number_of_dbs();

            my $searchquery_log_ref = $searchquery->get_searchquery;

            if ($#databases+1 == $alldbcount){
                $searchquery_log_ref->{alldbases} = 1;
                $logger->debug("Alle Datenbanken ausgewaehlt");
            }
            else {
                $searchquery_log_ref->{dbases} = \@databases;
            }

            $searchquery_log_ref->{hits}   = $gesamttreffer;

            # Loggen des Queries
            $session->log_event({
                type      => 1,
                content   => $searchquery_log_ref,
                serialize => 1,
            });

            $session->set_hits_of_query({
                queryid => $queryid,
                hits    => $gesamttreffer,
            });

            $session->set_all_searchresults({
                queryid  => $queryid,
                results  => \%trefferpage,
                dbhits   => \%dbhits,
                hitrange => $hitrange,
            });
        }
    }

    # Ausgabe des letzten HTML-Bereichs
    my $endtemplatename=$config->{tt_virtualsearch_result_end_tname};
    if ($view && -e "$config->{tt_include_path}/views/$view/$endtemplatename") {
        $endtemplatename="views/$view/$endtemplatename";
    }

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

    # TT-Data erzeugen
    my $endttdata={
        view          => $view,
        sessionID     => $session->{ID},

        gesamttreffer => $gesamttreffer,

        loginname     => $loginname,
        password      => $password,
        
        searchquery   => $searchquery->get_searchquery,
        query         => $query,
        queryid       => $queryid,

        config        => $config,
        user          => $user,
        msg           => $msg,
    };

    $endtemplate->process($endtemplatename, $endttdata) || do {
        $r->log_reason($endtemplate->error(), $r->filename);
        return SERVER_ERROR;
    };
    return OK;
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

1;
