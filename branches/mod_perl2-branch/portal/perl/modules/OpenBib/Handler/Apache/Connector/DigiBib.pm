####################################################################
#
#  OpenBib::Handler::Apache::Connector::DigiBib.pm
#
#  Dieses File ist (C) 2003-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::DigiBib;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Connection ();
use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Request();      # CGI-Handling (or require)
use Apache2::RequestIO (); # rflush, print
use Apache2::RequestRec ();

use Log::Log4perl qw(get_logger :levels);

use DBI;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::VirtualSearch::Util;

sub handler {
    
    my $r=shift;
    
    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);
    
    my $status=$query->parse;
    
    if ($status){
        $logger->error("Cannot parse Arguments");
    }

    my $session = OpenBib::Session->instance;

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle('de') || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # CGI-Input auslesen
    
    #####################################################################
    #
    # Eingabeparamter
    #
    # Titelliste:
    # verf  = Autor
    # hst   = Titel
    # swt   = Schlagwort
    # kor   = Koerperschaft
    # notation = Notation
    # isbn  = ISBN
    # issn  = ISSN
    # sign  = Signatur
    # ejahr = Erscheinungsjahr
    # maxhits = Maximale Treffer pro Pool
    # listlength = Anzahl angezeigter Gesamttreffer
    # offset = Offset zur Anzahl an Gesamttreffern
    # sorttype = Sortierung (author, yearofpub, title)
    # bool1 = Boolscher Operator zu Titel
    # bool2 = Boolscher Operator zu Schlagwort
    # bool3 = Boolscher Operator zu Koerperschaft
    # bool4 = Boolscher Operator zu Notation
    # bool5 = Boolscher Operator zu ISBN
    # bool6 = Boolscher Operator zu Signatur
    # bool7 = Boolscher Operator zu Erscheinungsjahr (derzeit effektiv nur AND)
    # bool8 = Boolscher Operator zu ISSN
    # bool9 = Boolscher Operator zu Verfasser
    # tosearch = Trefferliste
    #
    # Langanzeige:
    # 
    # idn = Titelidn
    # database = Datenbank
    # tosearch = Langanzeige

    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
    my $hitrange   = 20;
    my $idn        = $query->param('idn')        || '';
    my $database   = $query->param('database')   || '';
    my $maxhits    = $query->param('maxhits')    || 200;
    my $offset     = $query->param('offset')     || 1;
    my $listlength = $query->param('listlength') || 999999999;
    my $sorttype   = $query->param('sorttype')   || 'author';
    my $sortorder  = $query->param('sortorder')  || '';;
    my $tosearch   = $query->param('tosearch')   || '';
    my $view       = $query->param('view')       || 'institute';
    my $serien     = $query->param('serien')     || 0;
    my $sb         = $query->param('sb')         || 'xapian';

    # Loggen des Recherche-Einstiegs ueber Connector (1=DigiBib)

    # Wenn 'erste Trefferliste' oder Langtitelanzeige
    # Bei zurueckblaettern auf die erste Trefferliste wird eine weitere Session
    # geoeffnet und gezaeht. Die DigiBib-Zugriffsspezifikation des hbz ohne
    # eigene Sessions laesst jedoch keinen anderen Weg zu.
    
    if ($offset == 1){
        $session->log_event({
            type      => 22,
            content   => 1,
        });
        
        # Loggen der View-Auswahl
        $session->log_event({
            type      => 100,
            content   => $view,
        });
    
        my $useragent=$r->subprocess_env('HTTP_USER_AGENT') || '';
        
        # Loggen des Brower-Types
        $session->log_event({
            type      => 101,
            content   => $useragent,
        });

        # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
        # Client-IP setzen
        if ($r->headers_in('X-Forwarded-For') =~ /([^,\s]+)$/) {
            $r->connection->remote_ip($1);
        }
        
        # Loggen der Client-IP
        $session->log_event({
            type      => 102,
            content   => $r->connection->remote_ip,
        });
    }

    my $sysprofile   = $config->get_viewinfo($view)->{profilename};

    # Historisch begruendetes Kompatabilitaetsmapping
    
    $query->param('boolverf'      => $query->param('bool9'))  if ($query->param('bool9'));
    $query->param('boolhst'       => $query->param('bool1'))  if ($query->param('bool1'));
    $query->param('boolswt'       => $query->param('bool2'))  if ($query->param('bool2'));
    $query->param('boolkor'       => $query->param('bool3'))  if ($query->param('bool3'));
    $query->param('boolnotation'  => $query->param('bool4'))  if ($query->param('bool4'));
    $query->param('boolisbn'      => $query->param('bool5'))  if ($query->param('bool5'));
    $query->param('boolissn'      => $query->param('bool8'))  if ($query->param('bool8'));
    $query->param('boolsign'      => $query->param('bool6'))  if ($query->param('bool6'));
    $query->param('boolejahr'     => $query->param('bool7'))  if ($query->param('bool7'));
    $query->param('boolfs'        => $query->param('bool10')) if ($query->param('bool10'));
    $query->param('boolmart'      => $query->param('bool11')) if ($query->param('bool11'));
    $query->param('boolhststring' => $query->param('bool12')) if ($query->param('bool12'));

    if ($sb eq "sql"){
        # Automatische Und-Verknuepfung der Suchterme aktivieren
        $query->param('autoplus' => 1);
    }
    
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $searchquery = OpenBib::SearchQuery->instance;

    $searchquery->set_from_apache_request($r);

    # Bestimmung der Datenbanken, in denen gesucht werden soll
    my @databases = $config->get_dbs_of_view($view);

    my $treffercount = 0;
    
    if ($tosearch eq "Trefferliste") {
        
        my $fallbacksb = "";
        
        # Start der Ausgabe mit korrektem Header
        print $r->content_type("text/html");
        
        my @ergebnisse;
        my $recordlist;
        
        if ($sb eq "xapian"){
            $recordlist = new OpenBib::RecordList::Title();

            my $dbh;

            foreach my $database (@databases){
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
                    }                        
                }
            }

            if (!$fallbacksb){
                my $request = new OpenBib::Search::Local::Xapian();
                
                $request->initial_search({
                    serien          => $serien,
                    dbh             => $dbh,
                    database        => $database,
                    
                    enrich          => undef,
                    enrichkeys_ref  => undef,
                    dd_categorized  => 0,
                });
                
                $treffercount = $request->{resultcount};
                
                $logger->info($treffercount . " results found");
                
                if ($treffercount >= 1) {
                    my @matches = $request->matches;
                    my $i = 0; 
                    foreach my $match (@matches) {
                        last if ($i > $maxhits);
                        my $document        = $match->get_document();
                        my $titlistitem_raw = pack "H*", $document->get_data();
                        my $titlistitem_ref = Storable::thaw($titlistitem_raw);
                        
                        $recordlist->add(new OpenBib::Record::Title({database => $titlistitem_ref->{database}, id => $titlistitem_ref->{id}})->set_brief_normdata_from_storable($titlistitem_ref));
                        $i++;
                    }
                    
                    $recordlist->sort({order=>$sortorder,type=>$sorttype});
                    
                    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
                    push @ergebnisse, @{$recordlist->to_list};
                }
            }
        }            

        if ($sb eq "sql"  || $fallbacksb eq 'sql'){
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
                    return Apache2::Const::OK;
                }
            }
            
            if ($searchquery->get_searchfield('ejahr')->{bool} eq "OR") {
                if ($searchquery->get_searchfield('ejahr')->{norm}) {
                    OpenBib::Common::Util::print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."),$r,$msg);
                    return Apache2::Const::OK;
                }
            }
            
            
            if ($searchquery->get_searchfield('ejahr')->{bool} eq "AND") {
                if ($searchquery->get_searchfield('ejahr')->{norm}) {
                    if (!$firstsql) {
                        OpenBib::Common::Util::print_warning($msg->maketext("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung."),$r,$msg);
                        return Apache2::Const::OK;
                    }
                }
            }
            
            if (!$firstsql) {
                OpenBib::Common::Util::print_warning($msg->maketext("Es wurde kein Suchkriterium eingegeben."),$r,$msg);
                return Apache2::Const::OK;
            }
            
            foreach my $database (@databases){
                my ($recordlist,$fullresultcount) = OpenBib::Search::Util::initial_search_for_titidns({
                    serien          => $serien,
                    
                    database        => $database,
                    
                    hitrange        => $hitrange,
                    
                    maxhits         => $maxhits,
                    
                    enrich          => 0,
                    enrichkeys_ref  => [],
                });
                
                $logger->debug("Treffer-Ids in $database:".$recordlist->to_ids);
                
                # Wenn mindestens ein Treffer gefunden wurde
                if ($recordlist->get_size() > 0) {
                    # Kurztitelinformationen fuer RecordList laden
                    $recordlist->load_brief_records;
                    
                    $recordlist->sort({order=>$sortorder,type=>$sorttype});
                    
                    push @ergebnisse, @{$recordlist->to_list};
                }
            }

            $treffercount=$#ergebnisse+1;
        }
        
        # Dann den eigenen URL bestimmen
        my $myself="http://".$r->hostname.$r->uri."?".$r->args;
        
        $myself=~s/;/&/g;
        $myself=~s!:8008/!/!;
        
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

        $searchquery_log_ref->{hits}   = $treffercount;
        
        # Loggen des Queries
        $session->log_event({
            type      => 1,
            content   => $searchquery_log_ref,
            serialize => 1,
        });
        
        my $starttemplatename=$config->{tt_connector_digibib_result_start_tname};

        $starttemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
            database     => '', # Template nicht datenbankabhaengig
            view         => $view,
            profile      => $sysprofile,
            templatename => $starttemplatename,
        });

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
            treffercount   => $treffercount,
            myself         => $myself,
            sysprofile     => $sysprofile,
            view           => $view,
        };
        
        $starttemplate->process($starttemplatename, $startttdata) || do {
            $r->log_reason($starttemplate->error(), $r->filename);
            return Apache2::Const::SERVER_ERROR;
        };
        
        # Ausgabe flushen
        $r->rflush();

        $logger->debug(YAML::Dump(\@ergebnisse));
        
        my $liststart = ($offset<= $treffercount)?$offset-1:0;
        my $listend   = ($offset+$listlength-1 <= $treffercount)?$offset+$listlength-2:$treffercount-1;
        
        my $itemtemplatename=$config->{tt_connector_digibib_result_item_tname};

        $itemtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
            database     => '', # Template nicht datenbankabhaengig
            view         => $view,
            profile      => $sysprofile,
            templatename => $itemtemplatename,
        });

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
            dbinfo          => $dbinfotable,
            resultlist      => \@ergebnisse,#[$liststart..$listend],

            utf2iso      => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },

            view            => $view,
            sysprofile      => $sysprofile,
            config          => $config,
        };
        
        $itemtemplate->process($itemtemplatename, $ttdata) || do {
            $r->log_reason($itemtemplate->error(), $r->filename);
            return Apache2::Const::SERVER_ERROR;
        };
        
        # Ausgabe des letzten HTML-Bereichs
        my $endtemplatename=$config->{tt_connector_digibib_result_end_tname};

        $endtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
            database     => '', # Template nicht datenbankabhaengig
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
            view       => $view,
            sysprofile => $sysprofile,
        };
        
        $endtemplate->process($endtemplatename, $endttdata) || do {
            $r->log_reason($endtemplate->error(), $r->filename);
            return Apache2::Const::SERVER_ERROR;
        };
        
    }
    elsif ($tosearch eq "Langanzeige"){
        
        print $r->content_type("text/html");
        
        my $dbh   = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

        my $record = OpenBib::Record::Title->new({database=>$database})
                      ->load_full_record({id=>$idn});

        $session->log_event({
            type      => 10,
            content   => {
                id       => $idn,
                database => $database,
            },
            serialize => 1,
        });
        
        # Quelle besetzt?

        my $sbrecord;
        my $has_sb=0;
        
        if (exists $record->{normset}->{'T0590'}){

            $logger->debug("Satz hat 590");
            my $reqstring="select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($idn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my $res=$request->fetchrow_hashref;

            my $sbid=0;
            if (exists $res->{targetid}){
                $sbid=$res->{targetid};
            }

            $logger->debug("Sbid ist $sbid");
            if ($sbid){
                $sbrecord = OpenBib::Record::Title->new({database=>$database})
                    ->load_full_record({id=>$sbid});

                $has_sb=1;
            }
        }            

        # Ausgabe des letzten HTML-Bereichs
        my $templatename=$config->{tt_connector_digibib_showtitset_tname};

        $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
            database     => '', # Template nicht datenbankabhaengig
            view         => $view,
            profile      => $sysprofile,
            templatename => $templatename,
        });

        my $template = Template->new({
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
        my $ttdata={
            record       => $record,
            has_sb       => $has_sb,
            sbrecord     => $sbrecord,
            dbinfo       => $dbinfotable,
            database     => $database,

            utf2iso      => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },

            sysprofile   => $sysprofile,
            view         => $view,
            config       => $config,
        };
        
        $template->process($templatename, $ttdata) || do {
            $r->log_reason($template->error(), $r->filename);
            return Apache2::Const::SERVER_ERROR;
        };
  } 

  return Apache2::Const::OK;
}

1;
