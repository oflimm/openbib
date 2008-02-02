####################################################################
#
#  OpenBib::Handler::Apache::Connector::DigiBib.pm
#
#  Dieses File ist (C) 2003-2008 Oliver Flimm <flimm@openbib.org>
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

use Apache::Constants qw(:common);

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use DBI;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::VirtualSearch::Util;

sub handler {
    
    my $r=shift;
    
    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache::Request->instance($r);
    
    my $status=$query->parse;
    
    if ($status){
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session = OpenBib::Session->instance;

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
        if ($r->header_in('X-Forwarded-For') =~ /([^,\s]+)$/) {
            $r->connection->remote_ip($1);
        }
        
        # Loggen der Client-IP
        $session->log_event({
            type      => 102,
            content   => $r->connection->remote_ip,
        });
    }
    
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

    my $queryoptions_ref
        = $session->get_queryoptions($query);

    my $targetdbinfo_ref
        = $config->get_targetdbinfo();

    my $searchquery_ref
        = OpenBib::Common::Util::get_searchquery($r);

    # Autoplus einfuegen

    $searchquery_ref->{fs      }{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{fs      }{norm}) if ($searchquery_ref->{fs      }{norm});
    $searchquery_ref->{verf    }{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{verf    }{norm}) if ($searchquery_ref->{verf    }{norm});
    $searchquery_ref->{hst     }{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{hst     }{norm}) if ($searchquery_ref->{hst     }{norm});
    $searchquery_ref->{kor     }{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{kor     }{norm}) if ($searchquery_ref->{kor     }{norm});
    $searchquery_ref->{swt     }{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{swt     }{norm}) if ($searchquery_ref->{swt     }{norm});
    $searchquery_ref->{isbn    }{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{isbn    }{norm}) if ($searchquery_ref->{isbn    }{norm});
    $searchquery_ref->{issn    }{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{issn    }{norm}) if ($searchquery_ref->{issn    }{norm});
    $searchquery_ref->{gtquelle}{norm} = OpenBib::VirtualSearch::Util::conv2autoplus($searchquery_ref->{gtquelle}{norm}) if ($searchquery_ref->{gtquelle}{norm});

    if (!$sortorder){
        if ($sorttype eq "ejahr"){
            $sortorder="down";
        }
        else {
            $sortorder="up";
        }
    }
        
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    my @databases = $config->get_dbs_of_view($view);
    
    if ($tosearch eq "Trefferliste") {

        # Start der Ausgabe mit korrektem Header
        print $r->send_http_header("text/html");
        
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
                return OK;
            }
        }
        
        if ($searchquery_ref->{ejahr}{bool} eq "OR") {
            if ($searchquery_ref->{ejahr}{norm}) {
                return OK;
            }
        }
        
        
        if ($searchquery_ref->{ejahr}{bool} eq "AND") {
            if ($searchquery_ref->{ejahr}{norm}) {
                if (!$firstsql) {
                    return OK;
                }
            }
        }
        
        if (!$firstsql) {
            return OK;
        }
        
        
        my @ergebnisse;
                
        foreach my $database (@databases){
            my $dbh   = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

            my $result_ref=OpenBib::Search::Util::initial_search_for_titidns({
                searchquery_ref => $searchquery_ref,

                serien          => $serien,
                dbh             => $dbh,
                maxhits         => $maxhits,

                enrich          => 0,
                enrichkeys_ref  => [],
            });

            my @tidns           = @{$result_ref->{titidns_ref}};
            my $fullresultcount = $result_ref->{fullresultcount};
            
            if ($#tidns >= 0){

                my $recordlist = new OpenBib::RecordList::Title();
                my $record     = new OpenBib::Record::Title({database=>$database});

                foreach my $idn (@tidns) {
                    $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
                }
                
                $recordlist->sort({order=>$sortorder,type=>$sorttype});
                
                push @ergebnisse, @{$recordlist->to_list};
            }
        }

        
        # Dann den eigenen URL bestimmen
        my $myself="http://".$r->hostname.$r->uri."?".$r->args;
        
        $myself=~s/;/&/g;
        $myself=~s!:8008/!/!;
        
        my $treffercount=$#ergebnisse+1;

        # Wurde in allen Katalogen recherchiert?

        my $alldbcount = $config->get_number_of_dbs();

        my $searchquery_log_ref = $searchquery_ref;

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
        if ($view && -e "$config->{tt_include_path}/views/$view/$starttemplatename") {
            $starttemplatename="views/$view/$starttemplatename";
        }
                
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
        };
        
        $starttemplate->process($starttemplatename, $startttdata) || do {
            $r->log_reason($starttemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
        # Ausgabe flushen
        $r->rflush();

        $logger->debug(YAML::Dump(\@ergebnisse));
        
        my $liststart = ($offset<= $treffercount)?$offset-1:0;
        my $listend   = ($offset+$listlength-1 <= $treffercount)?$offset+$listlength-2:$treffercount-1;
        
        my $itemtemplatename=$config->{tt_connector_digibib_result_item_tname};
        if ($view && -e "$config->{tt_include_path}/views/$view/$itemtemplatename") {
            $itemtemplatename="views/$view/$itemtemplatename";
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
            targetdbinfo    => $targetdbinfo_ref,
            resultlist      => \@ergebnisse,#[$liststart..$listend],

            utf2iso      => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },

            config          => $config,
        };
        
        $itemtemplate->process($itemtemplatename, $ttdata) || do {
            $r->log_reason($itemtemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
        # Ausgabe des letzten HTML-Bereichs
        my $endtemplatename=$config->{tt_connector_digibib_result_end_tname};
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
        };
        
        $endtemplate->process($endtemplatename, $endttdata) || do {
            $r->log_reason($endtemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
    }
    elsif ($tosearch eq "Langanzeige"){
        
        print $r->send_http_header("text/html");
        
        my $dbh   = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

        my $record = OpenBib::Record::Title->new({database=>$database})
                      ->get_full_record({id=>$idn});

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
                    ->get_full_record({id=>$sbid});

                $has_sb=1;
            }
        }            

        # Ausgabe des letzten HTML-Bereichs
        my $templatename=$config->{tt_connector_digibib_showtitset_tname};
        if ($view && -e "$config->{tt_include_path}/views/$view/$templatename") {
            $templatename="views/$view/$templatename";
        }
        
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
            item         => $record->get_normdata,
            itemmex      => $record->get_mexdata,
            has_sb       => $has_sb,
            sbitem       => $sbrecord->get_normdata,
            sbitemmex    => $sbrecord->get_mexdata,
            targetdbinfo => $targetdbinfo_ref,
            database     => $database,

            utf2iso      => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },

        };
        
        $template->process($templatename, $ttdata) || do {
            $r->log_reason($template->error(), $r->filename);
            return SERVER_ERROR;
        };
  } 

  return OK;
}

1;
