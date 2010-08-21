###################################################################
#
#  OpenBib::Handler::Apache::Search.pm
#
#  ehemals VirtualSearch.pm
#
#  Dieses File ist (C) 1997-2010 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Search::Z3950;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'search'       => 'search_databases',
        'index'        => 'search_index',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub search_databases {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    
    # CGI Args
    my $serien        = decode_utf8($query->param('serien'))        || 0;
    my @databases     = ($query->param('db'))?$query->param('db'):();
    my $hitrange      = ($query->param('num' ))?$query->param('num'):50;
    my $page          = ($query->param('page' ))?$query->param('page'):1;
    my $listtype      = ($query->param('lt' ))?$query->param('lt'):"author";
    my $sorttype      = ($query->param('srt' ))?$query->param('srt'):"author";
    my $sortorder     = ($query->param('srto'))?$query->param('srto'):'up';
    my $defaultop     = ($query->param('dop'))?$query->param('dop'):'and';
    my $combinedbs    = $query->param('combinedbs')    || 0;

    my $sortall       = ($query->param('sortall'))?$query->param('sortall'):'0';

    my $searchall     = $query->param('searchall')     || '';
    my $searchprofile = $query->param('searchprofile') || '';

    # Index zusammen mit Eingabefelder 
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';

    # oder Index als separate Funktion
    my $indextype    = $query->param('indextype')     || ''; # (verfindex, korindex, swtindex oder notindex)
    my $indexterm    = $query->param('indexterm')     || '';
    my $searchindex  = $query->param('searchindex')     || '';
    
    my $profil        = $query->param('profil')        || '';
    my $trefferliste  = $query->param('trefferliste')  || '';
    my $queryid       = $query->param('queryid')       || '';
    my $st            = $query->param('st')            || '';    # Search type (1=simple,2=complex)    
    my $drilldown     = $query->param('dd')            || 0;     # Drill-Down?
    
    my $spelling_suggestion_ref = ($user->is_authenticated)?$user->get_spelling_suggestion():{};

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $searchquery = OpenBib::SearchQuery->instance;
    
    my $is_orgunit=0;

    my $sb = $config->{local_search_backend};
    
  ORGUNIT_SEARCH:
    foreach my $orgunit_ref (@{$config->{orgunits}}){
        if ($orgunit_ref->{short} eq $profil){
            $is_orgunit=1;
            last ORGUNIT_SEARCH;
        }
    }
    
    $profil="" if (!$is_orgunit && $profil ne "dbauswahl" && !$profil=~/^user/ && $profil ne "alldbs");

    # Loggen der Recherche-Art (1=simple, 2=complex)
    $session->log_event({
		type      => 20,
                content   => $st,
    });

    # Loggen des Recherche-Backends
    $session->log_event({
		type      => 21,
                content   => 'xapian',
    });

    my $sysprofile   = $config->get_viewinfo($view)->{profilename};

    @databases       = $self->get_databases();
    
    my $queryalreadyexists = 0;

    if ($queryid){
        $logger->debug("Query exists for SessionID $session->{ID} -> $queryid: Loading");
        $searchquery->load({sessionID => $session->{ID}, queryid => $queryid});
        @databases = @{$searchquery->get_databases};
        
        $queryalreadyexists = 1;
    }
    else {
        $searchquery->set_from_apache_request($r,\@databases);
        
        # Abspeichern des Query und Generierung der Queryid
        if ($session->{ID} ne "-1") {
            ($queryalreadyexists,$queryid) = $session->get_queryid({
                databases   => \@databases,
                hitrange    => $hitrange,
            });
        }
    }

#     if ($searchindex){
#         my $redirecturl = "";

#         if ($indextype eq "aut"){
#             $redirecturl = "$config->{base_loc}/$view/$config->{handler}{index_loc}{name}/person/$indexterm";
#         }
#         if ($indextype eq "kor"){
#             $redirecturl = "$config->{base_loc}/$view/$config->{handler}{index_loc}{name}/corporatebody/$indexterm";
#         }        
#         if ($indextype eq "swt"){
#             $redirecturl = "$config->{base_loc}/$view/$config->{handler}{index_loc}{name}/subject/$indexterm";
#         }
#         if ($indextype eq "notation"){
#             $redirecturl = "$config->{base_loc}/$view/$config->{handler}{index_loc}{name}/classification/$indexterm";
#         }

#         $logger->debug("Redirecting to $redirecturl");

#         $self->header_props( uri => $redirecturl);
#         $self->header_type('redirect');
#         return '';
#     }

    # BEGIN Index
    ####################################################################
    # Wenn ein kataloguebergreifender Index ausgewaehlt wurde
    ####################################################################

    $logger->debug(YAML::Dump($searchquery));
    if ($searchindex || $verfindex || $korindex || $swtindex || $notindex) {
        
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
            OpenBib::Common::Util::print_warning($msg->maketext("F&uuml;r die Nutzung der Index-Funktion m&uuml;ssen Sie einen Begriff eingegeben"),$r,$msg);
            return Apache2::Const::OK;
        }

        if ($#databases > 0 && length($contentreq) < 3) {
            OpenBib::Common::Util::print_warning($msg->maketext("Der Begriff muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche im Index ausgewählt wurde."),$r,$msg);
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
        
        my $baseurl="http://$config->{servername}$config->{virtualsearch_loc}?sessionID=$session->{ID};view=$view;$urlpart;profil=$profil;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder$databasestring";

        my @nav=();

        my $offset = $page*$hitrange-$hitrange;
    
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
            page       => $page,
            hitrange   => $hitrange,
            baseurl    => $baseurl,
            profil     => $profil,
            sysprofile => $sysprofile,
            config     => $config,
            user       => $user,
            msg        => $msg,

            decode_utf8    => sub {
                my $string=shift;
                return decode_utf8($string);
            },
        };

        OpenBib::Common::Util::print_page($template,$ttdata,$r);

        return Apache2::Const::OK;
    }

    ####################################################################
    # ENDE Indizes
    #

    #############################################################

    if ($searchquery->get_searchfield('ejahr')->{norm}) {
        my ($ejtest)=$searchquery->get_searchfield('ejahr')->{norm}=~/.*(\d\d\d\d).*/;
        if (!$ejtest) {
            OpenBib::Common::Util::print_warning($msg->maketext("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein."),$r,$msg);
            return Apache2::Const::OK;
        }
    }

    if ($searchquery->get_searchfield('ejahr')->{bool} eq "OR") {
        if ($searchquery->get_searchfield('ejahr')->{norm}) {
            OpenBib::Common::Util::print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."),$r,$msg);
            return Apache2::Const::OK;
        }
    }


    if (!$searchquery->have_searchterms) {
        OpenBib::Common::Util::print_warning($msg->maketext("Es wurde kein Suchkriterium eingegeben."),$r,$msg);
        return Apache2::Const::OK;
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

    # Array aus DB-Name und Titel-ID zur Navigation
    my @resultset   = ();
    
    my $fallbacksb    = "";
    my $gesamttreffer = 0;

    my $atime=new Benchmark;
    
    my $starttemplatename=$config->{tt_search_title_start_tname};
    
    $starttemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $view,
        profile      => $sysprofile,
        templatename => $starttemplatename,
    });
    
    # Start der Ausgabe mit korrektem Header
    $r->content_type("text/html");
    
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
        sq             => $searchquery,
        
        queryid        => $queryid,
        query          => $query,
        
        qopts          => $queryoptions->get_options,
        
        spelling_suggestion => $spelling_suggestion_ref,

        hitrange       => $hitrange,
        page           => $page,
        sortorder      => $sortorder,
        sorttype       => $sorttype,
        
        sysprofile     => $sysprofile,
        config         => $config,
        user           => $user,
        msg            => $msg,

        decode_utf8    => sub {
            my $string=shift;
            return decode_utf8($string);
        },
    };
        
    $starttemplate->process($starttemplatename, $startttdata) || do {
        $r->log_error($starttemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
    
    # Ausgabe flushen
    eval {
        $r->rflush(); 
    };
    
    if($@) { 
        $logger->error("Flush-Error") 
    }
    
    # Kombinierte Suche ueber alle Kataloge

    if ($combinedbs){
        # Trefferliste
        my $recordlist;
        
        if ($sb eq 'xapian') {
            # Xapian

            $recordlist = new OpenBib::RecordList::Title();

            my $atime=new Benchmark;
            my $category_map_ref = ();
            my $fullresultcount;
            my $resulttime;
            my $request;
            my $timeall;
            
            my $dbh;
            my $nav;
            
            foreach my $database (@databases) {
                $logger->debug("Adding Xapian DB-Object for database $database");
                
                if (!defined $dbh){
                    # Erstes Objekt erzeugen,
                    
                    $logger->debug("Creating Xapian DB-Object for database $database");                
                    
                    eval {
                        $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");
                    };
                    
                    if ($@){
                        $logger->error("Initializing with Database: $database - :".$@." not available");
                    }
                }
                else {
                    $logger->debug("Adding database $database");
                    
                    eval {
                        $dbh->add_database(new Search::Xapian::Database( $config->{xapian_index_base_path}."/".$database));
                    };
                    
                    if ($@){
                        $logger->error("Adding Database: $database - :".$@." not available");
                    }                        
                }
            }

            #$dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/view_kug") || $logger->fatal("Couldn't open/create Xapian DB $!\n");

            # Recherche starten
            $request = new OpenBib::Search::Local::Xapian();
                
            $request->initial_search({
                serien          => $serien,
                dbh             => $dbh,
                
                sortorder       => $sortorder,
                sorttype        => $sorttype,

                hitrange        => $hitrange,
                page            => $page,
                defaultop       => $defaultop,

                drilldown       => $drilldown,
            });
            
            $fullresultcount = $request->{resultcount};
            
            my $btime      = new Benchmark;
            $timeall    = timediff($btime,$atime);
            $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;
            
            $logger->info($fullresultcount . " results found in $resulttime");
            
            if ($fullresultcount >= 1) {
                $nav = Data::Pageset->new({
                    'total_entries'    => $fullresultcount,
                    'entries_per_page' => $hitrange,
                    'current_page'     => $page,
                    'mode'             => 'slide',
                });
                
                my @matches = $request->matches;
                foreach my $match (@matches) {
                    my $document        = $match->get_document();

                    my $titlistitem_ref;
                    
                    if ($config->{internal_serialize_type} eq "packed_storable"){
                        $titlistitem_ref = Storable::thaw(pack "H*", $document->get_data());
                    }
                    elsif ($config->{internal_serialize_type} eq "json"){
                        $titlistitem_ref = decode_json $document->get_data();
                    }
                    else {
                        $titlistitem_ref = Storable::thaw(pack "H*", $document->get_data());
                    }
                    
                    $recordlist->add(new OpenBib::Record::Title({database => $titlistitem_ref->{database}, id => $titlistitem_ref->{id}})->set_brief_normdata_from_storable($titlistitem_ref));
                }
                
                if ($drilldown) {
                    $category_map_ref = $request->get_categorized_drilldown;
                }
            }

            # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation in
            # den einzeltreffern
            push @resultset, @{$recordlist->to_ids};
            
            my $treffer=$fullresultcount;
            
            my $itemtemplatename=$config->{tt_search_title_combined_tname};
            
            $itemtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
                database     => '', # Template ist nicht datenbankabhaengig
                view         => $view,
                profile      => $sysprofile,
                templatename => $itemtemplatename,
            });
            
            # Start der Ausgabe mit korrektem Header
            $r->content_type("text/html");
            
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
                
                searchall       => $searchall,
                
                dbinfo          => $dbinfotable,
                
                searchquery     => $searchquery,
                
                qopts           => $queryoptions->get_options,
                
                query           => $query,
                
                treffer         => $treffer,
                
                queryid         => $queryid,
                
                category_map    => $category_map_ref,
                
                fullresultcount => $fullresultcount,
                recordlist      => $recordlist,
                
                nav             => $nav,
                
                combinedbs      => $combinedbs,
                
                drilldown             => $drilldown,
                
                page           => $page,
                hitrange       => $hitrange,
                
                lastquery       => $request->querystring,
                sorttype        => $sorttype,
                sortorder       => $sortorder,
                defaultop       => $defaultop,
                resulttime      => $resulttime,
                sysprofile      => $sysprofile,
                config          => $config,
                user            => $user,
                msg             => $msg,
            };
            
            $logger->debug("Printing Combined Result");
            
            $itemtemplate->process($itemtemplatename, $ttdata) || do {
                $r->log_error($itemtemplate->error(), $r->filename);
                return Apache2::Const::SERVER_ERROR;
            };
            
            $trefferpage{'combined'} = $recordlist;
            $dbhits     {'combined'} = $treffer;
            $gesamttreffer      = $treffer;

            decode_utf8    => sub {
                my $string=shift;
                return decode_utf8($string);
            },            
        }
    }
    # Alternativ: getrennte Suche uber alle Kataloge
    else {
        # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
        #
        ######################################################################
        # Schleife ueber alle Datenbanken 
        ######################################################################
        
        my $atime=new Benchmark;
        
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
                
                    my $treffer=$fullresultcount;

                    my $itemtemplatename=$config->{tt_search_title_item_tname};
                    
                    $itemtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
                        database     => $database,
                        view         => $view,
                        profile      => $sysprofile,
                        templatename => $itemtemplatename,
                    });

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
                        
                        dbinfo          => $dbinfotable,
                        
                        treffer         => $treffer,

                        searchquery     => $searchquery,

                        database        => $database,
                        queryid         => $queryid,
                        qopts           => $queryoptions->get_options,
                        fullresultcount => $fullresultcount,
                        recordlist      => $recordlist,
                        
                        sorttype        => $sorttype,
                        sortorder       => $sortorder,
                        resulttime      => $resulttime,
                        sysprofile      => $sysprofile,
                        config          => $config,
                        user            => $user,
                        msg             => $msg,

                        decode_utf8    => sub {
                            my $string=shift;
                            return decode_utf8($string);
                        },

                    };
                    
                    $itemtemplate->process($itemtemplatename, $ttdata) || do {
                        $r->log_error($itemtemplate->error(), $r->filename);
                        return Apache2::Const::SERVER_ERROR;
                    };
                    
                    $trefferpage{$database} = $recordlist;
                    $dbhits     {$database} = $treffer;
                    $gesamttreffer          = $gesamttreffer+$treffer;
                    
                    undef $btime;
                    undef $timeall;
                    
                    # flush output buffer
		    eval {
		      $r->rflush(); 
		    };
		    
		    if($@) { 
		      $logger->error("Flush-Error") 
		    }		    
                }
            }
            else {
                # Lokale Datenbaken
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
                    }
                    else { 
                       my $request = new OpenBib::Search::Local::Xapian();
                    
                        $request->initial_search({
                            serien          => $serien,
                            dbh             => $dbh,
                            database        => $database,

                            defaultop       => $defaultop,
                            sortorder       => $sortorder,
                            sorttype        => $sorttype,

                            hitrange        => $hitrange,
                            page            => $page,

                            drilldown       => $drilldown,
                        });

                        my $fullresultcount = $request->{resultcount};
                    
                        my $btime      = new Benchmark;
                        my $timeall    = timediff($btime,$atime);
                        my $resulttime = timestr($timeall,"nop");
                        $resulttime    =~s/(\d+\.\d+) .*/$1/;
                    
                        $logger->info($fullresultcount . " results found in $resulttime");

                        my $category_map_ref = ();

                        if ($fullresultcount >= 1) {
                            my $nav = Data::Pageset->new({
                                'total_entries'    => $fullresultcount,
                                'entries_per_page' => $hitrange,
                                'current_page'     => $page,
                                'mode'             => 'slide',
                            });

                            my @matches = $request->matches;
                            foreach my $match (@matches) {
                                # Es werden immer nur $hitrange Titelinformationen
                                # zur Ausgabe aus dem MSet herausgeholt
                                my $document        = $match->get_document();

                                my $titlistitem_ref;
                                
                                if ($config->{internal_serialize_type} eq "packed_storable"){
                                    $titlistitem_ref = Storable::thaw(pack "H*", $document->get_data());
                                }
                                elsif ($config->{internal_serialize_type} eq "json"){
                                    $titlistitem_ref = decode_json $document->get_data();
                                }
                                else {
                                    $titlistitem_ref = Storable::thaw(pack "H*", $document->get_data());
                                }
                                
                                $recordlist->add(new OpenBib::Record::Title({database => $titlistitem_ref->{database}, id => $titlistitem_ref->{id}})->set_brief_normdata_from_storable($titlistitem_ref));
                            }
                        
                            my $termweight_ref={};
                        
                            if ($drilldown) {
                                $category_map_ref = $request->get_categorized_drilldown;
                            }

                            # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                            push @resultset, @{$recordlist->to_ids};
                        
                            my $treffer=$fullresultcount;

                            my $itemtemplatename=$config->{tt_search_title_item_tname};

                            $itemtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
                                database     => $database,
                                view         => $view,
                                profile      => $sysprofile,
                                templatename => $itemtemplatename,
                            });

                            $logger->debug("Using Template $itemtemplatename");
                            
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

                                dbinfo          => $dbinfotable,
                            
                                treffer         => $treffer,
                            
                                database        => $database,
                                queryid         => $queryid,

                                searchquery     => $searchquery,

                                category_map    => $category_map_ref,

                                fullresultcount => $fullresultcount,
                                recordlist      => $recordlist,

                                qopts           => $queryoptions->get_options,
                                drilldown       => $drilldown,

                                cloud           => gen_cloud_absolute({dbh => $dbh, term_ref => $termweight_ref}),

                                nav             => $nav,

                                page            => $page,
                                hitrange        => $hitrange,
                                lastquery       => $request->querystring,
                                sorttype        => $sorttype,
                                sortorder       => $sortorder,
                                resulttime      => $resulttime,
                                sysprofile      => $sysprofile,
                                config          => $config,
                                user            => $user,
                                msg             => $msg,

                                decode_utf8    => sub {
                                    my $string=shift;
                                    return decode_utf8($string);
                                },

                            };
                        
                            $itemtemplate->process($itemtemplatename, $ttdata) || do {
                                $r->log_error($itemtemplate->error(), $r->filename);
                                return Apache2::Const::SERVER_ERROR;
                            };
                        
                            $trefferpage{$database} = $recordlist;
                            $dbhits     {$database} = $treffer;
                            $gesamttreffer          = $gesamttreffer+$treffer;
                        
                            undef $btime;
                            undef $timeall;

                            # flush output buffer
                            eval {
                                $logger->error("Flushing");
                                $r->rflush();
			    };

			    if($@) { 
                                $logger->error("Flush-Error");
			    }
                        }
                    }
                }
            }
        }

        if ($config->{benchmark}) {
            my $btime=new Benchmark;
            my $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung fuer Suche ueber alle Datenbanken ist ".timestr($timeall));
        }
        
        ######################################################################
        #
        # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln
        
        #    $logger->info("InitialSearch: ", $session->{ID}, " ", $gesamttreffer, " fs=(", $fs, ") verf=(", $boolverf, "#", $verf, ") hst=(", $boolhst, "#", $hst, ") hststring=(", $boolhststring, "#", $hststring, ") gtquelle=(", $boolgtquelle, "#", $gtquelle, ") swt=(", $boolswt, "#", $swt, ") kor=(", $boolkor, "#", $kor, ") sign=(", $boolsign, "#", $sign, ") isbn=(", $boolisbn, "#", $isbn, ") issn=(", $boolissn, "#", $issn, ") mart=(", $boolmart, "#", $mart, ") notation=(", $boolnotation, "#", $notation, ") ejahr=(", $boolejahr, "#", $ejahr, ") ejahrop=(", $ejahrop, ") databases=(",join(' ',sort @databases),") ");
                
    }
    
    # Ausgabe des letzten HTML-Bereichs
    my $endtemplatename=$config->{tt_search_title_end_tname};
    
    $endtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '', # Template ist nicht datenbankabhaengig
        view         => $view,
        profile      => $sysprofile,
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
        qopts         => $queryoptions->get_options,
        
        sysprofile    => $sysprofile,
        config        => $config,
        user          => $user,
        msg           => $msg,

        decode_utf8    => sub {
            my $string=shift;
            return decode_utf8($string);
        },
    };
    
    $endtemplate->process($endtemplatename, $endttdata) || do {
        $r->log_error($endtemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
    
    # Wenn etwas gefunden wurde, dann kann ein Resultset geschrieben werden.

    if ($gesamttreffer > 0) {
        $logger->debug("Resultset wird geschrieben: ".YAML::Dump(\@resultset));
        $session->updatelastresultset(\@resultset);
    }

    ######################################################################
    # Bei einer SessionID von -1 wird effektiv keine Session verwendet
    ######################################################################

    # Neuer Query
    if (!$queryalreadyexists) {

        # Jetzt update der Trefferinformationen
        $searchquery->save({sessionID => $session->{ID}, queryid => $queryid});

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
        }) unless ($combinedbs);

    }
    
    return Apache2::Const::OK;
}

# Auf Grundlage der <form>-Struktur im Template searchmask derzeit nicht verwendet
sub search_index {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    

    # CGI Args
    my @databases     = ($query->param('db'))?$query->param('db'):();
    my $hitrange      = ($query->param('num' ))?$query->param('num'):50;
    my $page          = ($query->param('page' ))?$query->param('page'):1;
    my $sorttype      = ($query->param('srt' ))?$query->param('srt'):"author";
    my $sortorder     = ($query->param('srto'))?$query->param('srto'):'up';
    my $defaultop     = ($query->param('dop'))?$query->param('dop'):'and';
    my $combinedbs    = $query->param('combinedbs')    || 0;

    my $sortall       = ($query->param('sortall'))?$query->param('sortall'):'0';

    my $searchall     = $query->param('searchall')     || '';
    my $searchprofile = $query->param('searchprofile') || '';

    # Index zusammen mit Eingabefelder 
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';

    # oder Index als separate Funktion
    my $indextype    = $query->param('indextype')     || ''; # (verfindex, korindex, swtindex oder notindex)
    my $indexterm    = $query->param('indexterm')     || '';
    my $searchindex  = $query->param('searchindex')     || '';
    
    my $profil        = $query->param('profil')        || '';
    my $trefferliste  = $query->param('trefferliste')  || '';
    my $queryid       = $query->param('queryid')       || '';
    my $st            = $query->param('st')            || '';    # Search type (1=simple,2=complex)    
    my $drilldown     = $query->param('dd')            || 0;     # Drill-Down?

    my $spelling_suggestion_ref = ($user->is_authenticated)?$user->get_spelling_suggestion():{};

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $searchquery = OpenBib::SearchQuery->instance;

    my $sysprofile   = $config->get_viewinfo($view)->{profilename};

    @databases = $self->get_databases();
    
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
        OpenBib::Common::Util::print_warning($msg->maketext("F&uuml;r die Nutzung der Index-Funktion m&uuml;ssen Sie einen Begriff eingegeben"),$r,$msg);
        return Apache2::Const::OK;
    }
    
    if ($#databases > 0 && length($contentreq) < 3) {
        OpenBib::Common::Util::print_warning($msg->maketext("Der Begriff muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche im Index ausgewählt wurde."),$r,$msg);
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
    
    my $baseurl="http://$config->{servername}$config->{virtualsearch_loc}?sessionID=$session->{ID};view=$view;$urlpart;profil=$profil;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder$databasestring";
    
    my @nav=();
    
    my $offset = $page*$hitrange-$hitrange;
    
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
        page       => $page,
        hitrange   => $hitrange,
        baseurl    => $baseurl,
        profil     => $profil,
        sysprofile => $sysprofile,
        config     => $config,
        user       => $user,
        msg        => $msg,

        decode_utf8    => sub {
            my $string=shift;
            return decode_utf8($string);
        },
    };
    
    OpenBib::Common::Util::print_page($template,$ttdata,$r);
    
    return Apache2::Const::OK;

    ####################################################################
    # ENDE Indizes
    #

}

sub get_databases {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');

    # CGI Args
    my @databases     = ($query->param('db'))?$query->param('db'):();
    my $queryid       = $query->param('queryid')       || '';
    my $searchall     = $query->param('searchall')     || '';
    my $searchprofile = $query->param('searchprofile') || '';
    my $searchindex   = $query->param('searchindex')   || '';

    my $profil        = $query->param('profil')        || '';

    # Index zusammen mit Eingabefelder 
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $notindex      = $query->param('notindex')      || '';

    my $searchquery = OpenBib::SearchQuery->instance;

    my $is_orgunit  = 0;
  ORGUNIT_SEARCH:
    foreach my $orgunit_ref (@{$config->{orgunits}}){
        if ($orgunit_ref->{short} eq $profil){
            $is_orgunit=1;
            last ORGUNIT_SEARCH;
        }
    }
    
    $profil="" if (!$is_orgunit && $profil ne "dbauswahl" && !$profil=~/^user/ && $profil ne "alldbs");

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
        # Wenn eine Queryid uebergeben wurde, dann werden *immer* die damit
        # assoziierten Datenbanken verwendet
        if ($queryid){
            my $databases_ref = $searchquery->get_databases;
            @databases = @{$databases_ref};
        }
        # Wenn nur ein View angegeben wird, aber keine Submit-Funktion (s.u.),
        # z.B. wenn direkt von extern fuer einen View eine Recherche gestartet werden soll,
        # dann wird in den Datenbanken des View recherchiert
        elsif ($view && !($searchall||$searchprofile||$searchindex||$verfindex||$korindex||$swtindex||$notindex)){
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
            elsif ($searchprofile || $searchindex || $verfindex || $korindex || $swtindex || $notindex) {
                if ($profil eq "dbauswahl") {
                    $logger->debug("Selecting databases of users choice");
                    # Eventuell bestehende Auswahl zuruecksetzen
                    @databases = $session->get_dbchoice();
                }
                # Wenn ein anderes Profil als 'dbauswahl' ausgewaehlt wuerde
                elsif ($profil) {
                    $logger->debug("Selecting databases of Profile $profil");
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
                    OpenBib::Common::Util::print_warning($msg->maketext("Sie haben <b>In ausgewählten Katalogen suchen</b> angeklickt, obwohl sie keine [_1]Kataloge[_2] oder Suchprofile ausgewählt haben. Bitte wählen Sie die gewünschten Kataloge/Suchprofile aus oder betätigen Sie <b>In allen Katalogen suchen</a>.","<a href=\"$config->{base_loc}/$view/$config->{handler}{databasechoice_loc}{name}\" target=\"body\">","</a>"),$r,$msg);
                    return Apache2::Const::OK;
                }
                
                # Wenn Profil aufgerufen wurde, dann abspeichern fuer Recherchemaske
                if ($profil) {
                    $session->set_profile($profil);
                }
            }
        }
    }

    # Dublette Datenbanken filtern
    my %seen_dbases = ();
    @databases = grep { ! $seen_dbases{$_} ++ } @databases;

    return @databases;
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
