####################################################################
#
#  OpenBib::VirtualSearch.pm
#
#  Dieses File ist (C) 1997-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::VirtualSearch;

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
use Search::Xapian;
use YAML ();

use OpenBib::Search::Util;
use OpenBib::VirtualSearch::Util;
use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Search::Local::Xapian;
use OpenBib::Template::Provider;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config = \%OpenBib::Config::config;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $userdbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    # CGI-Input auslesen
    my $serien        = decode_utf8($query->param('serien'))        || 0;
    my $enrich        = decode_utf8($query->param('enrich'))        || 1;

    my @databases     = ($query->param('database'))?$query->param('database'):();

    my $hitrange      = ($query->param('hitrange' ))?$query->param('hitrange'):20;
    my $offset        = ($query->param('offset'   ))?$query->param('offset'):1;
    my $maxhits       = ($query->param('maxhits'  ))?$query->param('maxhits'):500;
    my $sorttype      = ($query->param('sorttype' ))?$query->param('sorttype'):"author";
    my $sortorder     = ($query->param('sortorder'))?$query->param('sortorder'):'up';
    my $autoplus      = $query->param('autoplus')      || '';

    my $sortall       = ($query->param('sortall'))?$query->param('sortall'):'0';

    my $searchall     = $query->param('searchall')     || '';
    my $searchprofile = $query->param('searchprofile') || '';

    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $profil        = $query->param('profil')        || '';
    my $trefferliste  = $query->param('trefferliste')  || '';
    my $queryid       = $query->param('queryid')       || '';
    my $sb            = $query->param('sb')            || 'sql'; # Search backend
    my $drilldown     = $query->param('drilldown')     || 0;     # Drill-Down?

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if ($hitrange eq "alles") {
        $hitrange=-1;
    }
    
    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);

    my $targetcircinfo_ref
        = OpenBib::Common::Util::get_targetcircinfo($sessiondbh);

    my $searchquery_ref
        = OpenBib::Common::Util::get_searchquery($r);

    my $is_orgunit=0;

  ORGUNIT_SEARCH:
    foreach my $orgunit_ref (@{$config{orgunits}}){
        if ($orgunit_ref->{short} eq $profil){
            $is_orgunit=1;
            last ORGUNIT_SEARCH;
        }
    }
    
    $profil="" if (!$is_orgunit && $profil ne "dbauswahl" && !$profil=~/^user/ && $profil ne "alldbs");

    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        $sessiondbh->disconnect();
        $userdbh->disconnect();

        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

    # Authorisierter user?
    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
    $logger->info("Authorization: ", $sessionID, " ", ($userid)?$userid:'none');

    # BEGIN DB-Bestimmung
    ####################################################################
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    ####################################################################

    # Ueber view koennen bei Direkteinsprung in VirtualSearch die
    # entsprechenden Kataloge vorausgewaehlt werden
    if ($view && $#databases == -1) {
        my $idnresult=$sessiondbh->prepare("select dbname from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($view) or $logger->error($DBI::errstr);

        @databases=();
        my @idnres;
        while (@idnres=$idnresult->fetchrow) {
            push @databases, decode_utf8($idnres[0]);
        }
        $idnresult->finish();

    }

    if ($searchall) {
        my $idnresult=$sessiondbh->prepare("select dbname,description from dbinfo where active=1 order by orgunit,description") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        @databases=();
        my @idnres;
        while (@idnres=$idnresult->fetchrow) {
            push @databases, decode_utf8($idnres[0]);
        }
        $idnresult->finish();
    }
    elsif ($searchprofile || $verfindex || $korindex || $swtindex ) {
        if ($profil eq "dbauswahl") {
            # Eventuell bestehende Auswahl zuruecksetzen
            @databases=();

            my $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

            while (my $result=$idnresult->fetchrow_hashref()) {
                my $dbname = decode_utf8($result->{'dbname'});
                push @databases, $dbname;
            }
            $idnresult->finish();
        }
        # Wenn ein anderes Profil als 'dbauswahl' ausgewaehlt wuerde
        elsif ($profil) {
            # Eventuell bestehende Auswahl zuruecksetzen
            @databases=();

            # Benutzerspezifische Datenbankprofile
            if ($profil=~/^user(\d+)/) {
                my $profilid=$1;
	
                my $profilresult=$userdbh->prepare("select profildb.dbname from profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid = ? and userdbprofile.profilid=profildb.profilid order by dbname") or $logger->error($DBI::errstr);
                $profilresult->execute($userid,$profilid) or $logger->error($DBI::errstr);
	
                my @poolres;
                while (@poolres=$profilresult->fetchrow) {
                    push @databases, decode_utf8($poolres[0]);
                }
                $profilresult->finish();
	
            }
            elsif ($profil eq "alldbs") {
                # Alle Datenbanken
                my $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1 order by orgunit,dbname") or $logger->error($DBI::errstr);
                $idnresult->execute() or $logger->error($DBI::errstr);
	
                my @idnres;
                while (@idnres=$idnresult->fetchrow) {
                    push @databases, decode_utf8($idnres[0]);
                }
                $idnresult->finish();
            }
            else {
                my $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1 and orgunit = ? order by orgunit,dbname") or $logger->error($DBI::errstr);
                $idnresult->execute($profil) or $logger->error($DBI::errstr);
	
                my @idnres;
                while (@idnres=$idnresult->fetchrow) {
                    push @databases, decode_utf8($idnres[0]);
                }
                $idnresult->finish();
            }
        }
        # Kein Profil
        else {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben <b>In ausgewählten Katalogen suchen</b> angeklickt, obwohl sie keine [_1]Kataloge[_2] oder Suchprofile ausgewählt haben. Bitte wählen Sie die gewünschten Kataloge/Suchprofile aus oder betätigen Sie <b>In allen Katalogen suchen</a>.","<a href=\"$config{databasechoice_loc}?sessionID=$sessionID\" target=\"body\">","</a>"),$r,$msg);

            $sessiondbh->disconnect();
            $userdbh->disconnect();

            return OK;

        }

        # Wenn Profil aufgerufen wurde, dann abspeichern fuer Recherchemaske
        if ($profil) {
            my $idnresult=$sessiondbh->prepare("delete from sessionprofile where sessionid = ? ") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

            $idnresult=$sessiondbh->prepare("insert into sessionprofile values (?,?) ") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$profil) or $logger->error($DBI::errstr);
            $idnresult->finish();
        }
    }

    # BEGIN Index
    ####################################################################
    # Wenn ein kataloguebergreifender Index ausgewaehlt wurde
    ####################################################################

    if ($verfindex || $korindex || $swtindex) {
        my $contentreq =
            ($verfindex)?$searchquery_ref->{verf}{norm}:
            ($korindex )?$searchquery_ref->{kor }{norm}:
            ($swtindex )?$searchquery_ref->{swt }{norm}:undef;

        my $type =
            ($verfindex)?'aut':
            ($korindex )?'kor':
            ($swtindex )?'swt':undef;

        my $urlpart =
            ($verfindex)?"verf=$contentreq;verfindex=Index":
            ($korindex )?"kor=$contentreq;korindex=Index":
            ($swtindex )?"swt=$contentreq;swtindex=Index":undef;

        my $template =
            ($verfindex)?$config{"tt_virtualsearch_showverfindex_tname"}:
            ($korindex )?$config{"tt_virtualsearch_showkorindex_tname"}:
            ($swtindex )?$config{"tt_virtualsearch_showswtindex_tname"}:undef;
            
        $contentreq=~s/\+//g;
        $contentreq=~s/%2B//g;
        $contentreq=~s/%//g;

        if (!$contentreq) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keinen Begriff eingegeben"),$r,$msg);
            return OK;
        }

        if ($#databases > 0 && length($contentreq) < 3) {
            OpenBib::Common::Util::print_warning($msg->maketext("Der Begriff muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche ausgewählt wurde."),$r,$msg);
            return OK;
        }

        my %index=();

        my @sortedindex=();

        my $atime=new Benchmark;

        foreach my $database (@databases) {
            my $dbh
                = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
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
                    'dbdesc'   => $targetdbinfo_ref->{dbnames}{$database},
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
        
        my $hits=$#sortedindex;

        if ($hits > 200) {
            $hitrange=200;
        }

        my $baseurl="http://$config{servername}$config{virtualsearch_loc}?sessionID=$sessionID;view=$view;$urlpart;profil=$profil;maxhits=$maxhits;sorttype=$sorttype;sortorder=$sortorder";

        my @nav=();

        if ($hitrange > 0) {
            $logger->debug("Navigation wird erzeugt: Hitrange: $hitrange Hits: $hits");

            for (my $i=1; $i <= $hits; $i+=$hitrange) {
                my $active=0;
	
                if ($i == $offset) {
                    $active=1;
                }
	
                my $item={
                    start  => $i,
                    end    => ($i+$hitrange>$hits)?$hits+1:$i+$hitrange-1,
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
            sessionID  => $sessionID,
            resulttime => $resulttime,
            contentreq => $contentreq,
            index      => \@sortedindex,
            nav        => \@nav,
            offset     => $offset,
            hitrange   => $hitrange,
            baseurl    => $baseurl,
            profil     => $profil,
            config     => \%config,
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

    if ($searchquery_ref->{fs  }{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{verf}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{kor }{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{hst }{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{swt}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{notation}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{sign}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{isbn}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{issn}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{mart}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{hststring}{norm}) {
        $firstsql=1;
    }

    if ($searchquery_ref->{ejahr}{norm}){
        $firstsql=1;
    }
    
    if ($searchquery_ref->{ejahr}{norm}) {
        my ($ejtest)=$searchquery_ref->{ejahr}{norm}=~/.*(\d\d\d\d).*/;
        if (!$ejtest) {
            OpenBib::Common::Util::print_warning($msg->maketext("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein."),$r,$msg);

            $sessiondbh->disconnect();
            $userdbh->disconnect();

            return OK;
        }
    }

    if ($searchquery_ref->{ejahr}{bool} eq "OR") {
        if ($searchquery_ref->{ejahr}{norm}) {
            OpenBib::Common::Util::print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."),$r,$msg);

            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }
    }


    if ($searchquery_ref->{ejahr}{bool} eq "AND") {
        if ($searchquery_ref->{ejahr}{norm}) {
            if (!$firstsql) {
                OpenBib::Common::Util::print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."),$r,$msg);

                $sessiondbh->disconnect();
                $userdbh->disconnect();

                return OK;
            }
        }
    }

    if (!$firstsql) {
        OpenBib::Common::Util::print_warning($msg->maketext("Es wurde kein Suchkriterium eingegeben."),$r,$msg);

        $sessiondbh->disconnect();
        $userdbh->disconnect();

        return OK;
    }

    my %trefferpage  = ();
    my %dbhits       = ();

    my $loginname = "";
    my $password  = "";

    if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self"){
        ($loginname,$password)=OpenBib::Common::Util::get_cred_for_userid($userdbh,$userid);
    }

    # Hash im Loginname ersetzen
    $loginname =~s/#/\%23/;

    my $hostself="http://".$r->hostname.$r->uri;

    my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1,$msg);

    my $starttemplatename=$config{tt_virtualsearch_result_start_tname};
    if ($view && -e "$config{tt_include_path}/views/$view/$starttemplatename") {
        $starttemplatename="views/$view/$starttemplatename";
    }

    # Start der Ausgabe mit korrektem Header
    print $r->send_http_header("text/html");

    # Ausgabe des ersten HTML-Bereichs
    my $starttemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
#        ABSOLUTE       => 1,
        OUTPUT         => $r,
    });

    # TT-Data erzeugen

    my $startttdata={
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $sessionID,

        loginname      => $loginname,
        password       => $password,

        searchquery    => $searchquery_ref,
        queryargs      => $queryargs,
        sortselect     => $sortselect,
        thissortstring => $thissortstring,
        config         => \%config,
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
        
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$config{dbimodule}:dbname=$config{enrichmntdbname};host=$config{enrichmntdbhost};port=$config{enrichmntdbport}", $config{enrichmntdbuser}, $config{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

        my $sqlquerystring  = "select isbn from search where match (content) against (? in boolean mode) limit 2000";
        my $request         = $enrichdbh->prepare($sqlquerystring);
        $request->execute($searchquery_ref->{hst}{norm}." ".$searchquery_ref->{fs}{norm});
        while (my $res=$request->fetchrow_arrayref){
            push @{$enrichkeys_ref}, $res->[0];
        }

        $request->finish();
        $enrichdbh->disconnect();

        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von enrichkeys ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

        $logger->debug("Enrich-Keys: ".join(" ",@{$enrichkeys_ref}));
    }
    
    my $gesamttreffer=0;

    # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
    #
    ######################################################################
    # Schleife ueber alle Datenbanken 
    ######################################################################

    my @resultset=();
    foreach my $database (@databases) {
        
        if ($sb eq 'xapian'){
            # Xapian
            
            my $atime=new Benchmark;

            $logger->debug("Creating Xapian DB-Object for database $database");
            my $db = new Search::Xapian::Database ( $config{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
            my $qp = new Search::Xapian::QueryParser() || $logger->fatal("Couldn't open/create Xapian DB $!\n");
            
            my $querystring = lc($searchquery_ref->{fs}{norm});
            
            $querystring    = OpenBib::Common::Util::grundform({
                content  => $querystring,
            }),

            $qp->set_default_op(Search::Xapian::OP_AND);
            $qp->add_prefix('inauth'   ,'X1');
            $qp->add_prefix('intitle'  ,'X2');
            $qp->add_prefix('incorp'   ,'X3');
            $qp->add_prefix('insubj'   ,'X4');
            $qp->add_prefix('insys'    ,'X5');
            $qp->add_prefix('inyear'   ,'X7');
            $qp->add_prefix('inisbn'   ,'X8');
            $qp->add_prefix('inissn'   ,'X9');
            
            my $enq     = $db->enquire($qp->parse_query($querystring));

            my $thisquery = $enq->get_query()->get_description();
            $logger->info("Running query $thisquery");
            
            my @matches = $enq->matches(0,99999);
            
            my $fullresultcount = scalar(@matches);
            
            my $btime      = new Benchmark;
            my $timeall    = timediff($btime,$atime);
            my $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;
            
            $logger->info(scalar(@matches) . " results found in $resulttime");
            
            if (scalar(@matches) >= 1){
                
                my @outputbuffer=();
                
                my $rset=Search::Xapian::RSet->new() if ($drilldown && $fullresultcount > $maxhits);
                
                for (my $i=0; $i < $maxhits && defined $matches[$i]; $i++){
                    my $match=$matches[$i];
                    
                    $rset->add_document($match->get_docid) if ($drilldown && $fullresultcount > $maxhits);
                    my $document=$match->get_document();
                    my $titlistitem_raw=pack "H*", decode_utf8($document->get_data());
                    my $titlistitem_ref=Storable::thaw($titlistitem_raw);
                    
                    push @outputbuffer, $titlistitem_ref;
                }

                my $relevant_aut_ref;
                my $relevant_kor_ref;
                my $relevant_swt_ref;
                my $term_ref;
                my $drilldowntime;
                
                if ($drilldown && $fullresultcount > $maxhits ){
                    my $ddatime=new Benchmark;
                    my $eterms=$enq->get_eset(50,$rset);
                    
                    my $iter=$eterms->begin();
                    
                    $term_ref = {
                        aut => [],
                        kor => [],
                        hst => [],
                        all => [],
                    };
                    
                    while ($iter != $eterms->end()){
                        my $term   = $iter->get_termname();
                        my $weight = $iter->get_weight();
                        
                        if ($term=~/^X1(.+)$/){
                            push @{$term_ref->{aut}}, {
                                name   => $1,
                                weight => $weight,
                            };
                        }
                        elsif ($term=~/^X2(.+)$/){
                            $term=$1;
                            $term=~s/^(.)(.*)$/\u$1\l$2/;
                            push @{$term_ref->{hst}}, {
                                name   => $term,
                                weight => $weight,
                            };
                        } elsif ($term=~/^X3(.+)$/) {
                            push @{$term_ref->{kor}}, {
                                name   => $1,
                                weight => $weight,
                            };
                        } elsif ($term=~/^X4(.+)$/) {
                            push @{$term_ref->{swt}}, {
                                name   => $1,
                                weight => $weight,
                            };
                        } elsif ($term=~/^X7(.+)$/) {
                            push @{$term_ref->{ejahr}}, {
                                name   => $1,
                                weight => $weight,
                            };
                        } else {
                            $term=~s/^(.)(.*)$/\u$1\l$2/;
                            push @{$term_ref->{all}}, {
                                name   => $term,
                                weight => $weight,
                            };
                        }
                        
                        $iter++;
                    }

                    {
                        my $ddbtime       = new Benchmark;
                        my $ddtimeall     = timediff($ddbtime,$ddatime);
                        $logger->debug("ESet-Time: ".timestr($ddtimeall,"nop"));
                    }
                    
                    $logger->debug(YAML::Dump(\@outputbuffer));
                    
                    # Relavante Kategorieinhalte bestimmen
                    
                    $relevant_aut_ref = OpenBib::Search::Local::Xapian::get_relevant_terms({
                        categories     => ['P0100','P0101'],
                        type           => 'aut',
                        resultbuffer   => \@outputbuffer,
                        relevanttokens => $term_ref,
                    });
                    
                    $relevant_kor_ref = OpenBib::Search::Local::Xapian::get_relevant_terms({
                        categories     => ['C0200','C0201'],
                        type           => 'kor',
                        resultbuffer   => \@outputbuffer,
                        relevanttokens => $term_ref,
                    });
                    
                    $relevant_swt_ref = OpenBib::Search::Local::Xapian::get_relevant_terms({
                        categories     => ['T0710'],
                        type           => 'swt',
                        resultbuffer   => \@outputbuffer,
                        relevanttokens => $term_ref,
                    });
                    
                    my $ddbtime       = new Benchmark;
                    my $ddtimeall     = timediff($ddbtime,$ddatime);
                    $drilldowntime    = timestr($ddtimeall,"nop");
                    $drilldowntime    =~s/(\d+\.\d+) .*/$1/;
                }
                
                my @sortedoutputbuffer=();
                
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
            
                # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                foreach my $item_ref (@sortedoutputbuffer) {
                    push @resultset, { id       => $item_ref->{id},
                                       database => $item_ref->{database},
                                   };
                }
            
                my $treffer=$#sortedoutputbuffer+1;
            
                my $itemtemplatename=$config{tt_virtualsearch_result_item_tname};
                if ($view && -e "$config{tt_include_path}/views/$view/$itemtemplatename") {
                    $itemtemplatename="views/$view/$itemtemplatename";
                }
            
                my $itemtemplate = Template->new({
                    LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                        INCLUDE_PATH   => $config{tt_include_path},
                        ABSOLUTE       => 1,
                    }) ],
                    #                INCLUDE_PATH   => $config{tt_include_path},
                    #                ABSOLUTE       => 1,
                    OUTPUT         => $r,
                });
            
            
                # TT-Data erzeugen
                my $ttdata={
                    view            => $view,
                    sessionID       => $sessionID,
		  
                    dbinfo          => $targetdbinfo_ref->{dbinfo}{$database},

                    treffer         => $treffer,

                    fullresultcount => $fullresultcount,
                    resultlist      => \@sortedoutputbuffer,

                    qopts           => $queryoptions_ref,
                    drilldown       => $drilldown,
                    termfeedback    => $term_ref,
                    relevantaut     => $relevant_aut_ref,
                    relevantkor     => $relevant_kor_ref,
                    relevantswt     => $relevant_swt_ref,
                    lastquery       => $querystring,
                    sorttype        => $sorttype,
                    sortorder       => $sortorder,
                    resulttime      => $resulttime,
                    drilldowntime   => $drilldowntime,
                    config          => \%config,
                    msg             => $msg,
                };

                $itemtemplate->process($itemtemplatename, $ttdata) || do {
                    $r->log_reason($itemtemplate->error(), $r->filename);
                    return SERVER_ERROR;
                };

                $trefferpage{$database} = \@sortedoutputbuffer;
                $dbhits     {$database} = $treffer;
                $gesamttreffer          = $gesamttreffer+$treffer;

                undef $btime;
                undef $timeall;
            
            
            } 
        }
        elsif ($sb eq 'sql') {
            # SQL

            my $dbh
                = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                    or $logger->error_die($DBI::errstr);
            
            my $atime=new Benchmark;
            
            my $result_ref=OpenBib::Search::Util::initial_search_for_titidns({
                searchquery_ref => $searchquery_ref,

                serien          => $serien,
                dbh             => $dbh,
                maxhits         => $maxhits,

                enrich          => $enrich,
                enrichkeys_ref  => $enrichkeys_ref,
            });

            my @tidns           = @{$result_ref->{titidns_ref}};
            my $fullresultcount = $result_ref->{fullresultcount};

            # Wenn mindestens ein Treffer gefunden wurde
            if ($#tidns >= 0) {

                my $a2time;
            
                if ($config{benchmark}) {
                    $a2time=new Benchmark;
                }

                my @outputbuffer=();

                foreach my $idn (@tidns) {
                    push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                        titidn            => $idn,
                        dbh               => $dbh,
                        sessiondbh        => $sessiondbh,
                        database          => $database,
                        sessionID         => $sessionID,
                        targetdbinfo_ref  => $targetdbinfo_ref,
                    });
                }

                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;

                if ($config{benchmark}) {
                    my $b2time     = new Benchmark;
                    my $timeall2   = timediff($b2time,$a2time);

                    $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel (holen)       : ist ".timestr($timeall2));
                    $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel (suchen+holen): ist ".timestr($timeall));
                }

                my @sortedoutputbuffer=();

                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

                # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                foreach my $item_ref (@sortedoutputbuffer) {
                    push @resultset, { id       => $item_ref->{id},
                                       database => $item_ref->{database},
                                   };
                }
	    
                my $treffer=$#sortedoutputbuffer+1;

                my $itemtemplatename=$config{tt_virtualsearch_result_item_tname};
                if ($view && -e "$config{tt_include_path}/views/$view/$itemtemplatename") {
                    $itemtemplatename="views/$view/$itemtemplatename";
                }

                my $itemtemplate = Template->new({
                    LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                        INCLUDE_PATH   => $config{tt_include_path},
                        ABSOLUTE       => 1,
                    }) ],
                    #                INCLUDE_PATH   => $config{tt_include_path},
                    #                ABSOLUTE       => 1,
                    OUTPUT         => $r,
                });


                # TT-Data erzeugen
                my $ttdata={
                    view            => $view,
                    sessionID       => $sessionID,
		  
                    dbinfo          => $targetdbinfo_ref->{dbinfo}{$database},

                    treffer         => $treffer,

                    fullresultcount => $fullresultcount,
                    resultlist      => \@sortedoutputbuffer,
                    rating          => '',
                    bookinfo        => '',
                    sorttype        => $sorttype,
                    sortorder       => $sortorder,
                    resulttime      => $resulttime,
                    config          => \%config,
                    msg             => $msg,
                };

                $itemtemplate->process($itemtemplatename, $ttdata) || do {
                    $r->log_reason($itemtemplate->error(), $r->filename);
                    return SERVER_ERROR;
                };

                $trefferpage{$database} = \@sortedoutputbuffer;
                $dbhits     {$database} = $treffer;
                $gesamttreffer          = $gesamttreffer+$treffer;

                undef $btime;
                undef $timeall;

            }
            $dbh->disconnect;
            undef $atime;
        }

        # flush output buffer
        $r->rflush();
    }

    ######################################################################
    #
    # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln

#    $logger->info("InitialSearch: ", $sessionID, " ", $gesamttreffer, " fs=(", $fs, ") verf=(", $boolverf, "#", $verf, ") hst=(", $boolhst, "#", $hst, ") hststring=(", $boolhststring, "#", $hststring, ") swt=(", $boolswt, "#", $swt, ") kor=(", $boolkor, "#", $kor, ") sign=(", $boolsign, "#", $sign, ") isbn=(", $boolisbn, "#", $isbn, ") issn=(", $boolissn, "#", $issn, ") mart=(", $boolmart, "#", $mart, ") notation=(", $boolnotation, "#", $notation, ") ejahr=(", $boolejahr, "#", $ejahr, ") ejahrop=(", $ejahrop, ") databases=(",join(' ',sort @databases),") ");

    # Wenn etwas gefunden wurde, dann kann ein Resultset geschrieben werden.

    if ($gesamttreffer > 0) {
        $logger->debug("Resultset wird geschrieben: ".YAML::Dump(\@resultset));
        OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
    }

    ######################################################################
    # Bei einer SessionID von -1 wird effektiv keine Session verwendet
    ######################################################################

    if ($sessionID ne "-1") {
        # Jetzt update der Trefferinformationen

        my $dbasesstring=join("||",@databases);

        my $thisquerystring=unpack "H*", Storable::freeze($searchquery_ref);
        my $idnresult=$sessiondbh->prepare("select count(*) as rowcount from queries where query = ? and sessionid = ? and dbases = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($thisquerystring,$sessionID,$dbasesstring) or $logger->error($DBI::errstr);
        my $res  = $idnresult->fetchrow_hashref;
        my $rows = $res->{rowcount};

        my $queryalreadyexists=0;

        # Neuer Query
        if ($rows <= 0) {
            $idnresult=$sessiondbh->prepare("insert into queries (queryid,sessionid,query,hits,dbases) values (NULL,?,?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$thisquerystring,$gesamttreffer,$dbasesstring) or $logger->error($DBI::errstr);
        }
        # Query existiert schon
        else {
            $queryalreadyexists=1;
        }

        $idnresult=$sessiondbh->prepare("select queryid from queries where query = ? and sessionid = ? and dbases = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($thisquerystring,$sessionID,$dbasesstring) or $logger->error($DBI::errstr);

        my $queryid;
        while (my @idnres=$idnresult->fetchrow) {
            $queryid = decode_utf8($idnres[0]);
        }

        if ($queryalreadyexists == 0) {
            $idnresult=$sessiondbh->prepare("insert into searchresults values (?,?,?,?,?)") or $logger->error($DBI::errstr);

            foreach my $db (keys %trefferpage) {
                my $res=$trefferpage{$db};

                my $storableres=unpack "H*",Storable::freeze($res);

                $logger->debug("YAML-Dumped: ".YAML::Dump($res));
                my $num=$dbhits{$db};
                $idnresult->execute($sessionID,$db,$storableres,$num,$queryid) or $logger->error($DBI::errstr);
            }
        }

        $idnresult->finish();
    }

    # Ausgabe des letzten HTML-Bereichs
    my $endtemplatename=$config{tt_virtualsearch_result_end_tname};
    if ($view && -e "$config{tt_include_path}/views/$view/$endtemplatename") {
        $endtemplatename="views/$view/$endtemplatename";
    }

    my $endtemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
#        ABSOLUTE       => 1,
         OUTPUT         => $r,
    });

    # TT-Data erzeugen
    my $endttdata={
        view          => $view,
        sessionID     => $sessionID,

        gesamttreffer => $gesamttreffer,

        config        => \%config,
        msg           => $msg,
    };

    $endtemplate->process($endtemplatename, $endttdata) || do {
        $r->log_reason($endtemplate->error(), $r->filename);
        return SERVER_ERROR;
    };

    $sessiondbh->disconnect();
    $userdbh->disconnect();

    return OK;
}

1;
