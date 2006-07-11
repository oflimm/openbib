####################################################################
#
#  OpenBib::Connector::DigiBib.pm
#
#  Dieses File ist (C) 2003-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Connector::DigiBib;

use Apache::Constants qw(:common);

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use DBI;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Search::Util;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    
    my $r=shift;
    
    # Log4perl logger erzeugen
    
    my $logger = get_logger();
    
    my $query=Apache::Request->new($r);
    
    my $status=$query->parse;
    
    if ($status){
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
    
    my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
    
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

    my $autoplus = 1;
    
    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
    my $hitrange   = 20;
    my $idn        = $query->param('idn');
    my $database   = $query->param('database');
    my $maxhits    = ($query->param('maxhits'))?$query->param('maxhits'):200;
    my $offset     = ($query->param('offset'))?$query->param('offset'):1;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):999999999;
    my $sorttype   = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortorder  = $query->param('sortorder');
    my $tosearch   = $query->param('tosearch');
    my $view       = $query->param('view') || 'institute';
    my $serien     = ($query->param('serien'))?$query->param('serien'):0;
    
    # Historisch begruendetes Kompatabilitaetsmapping
    $query->param('boolverf'      => $query->param('bool9'));
    $query->param('boolhst'       => $query->param('bool1'));
    $query->param('boolswt'       => $query->param('bool2'));
    $query->param('boolkor'       => $query->param('bool3'));
    $query->param('boolnotation'  => $query->param('bool4'));
    $query->param('boolisbn'      => $query->param('bool5'));
    $query->param('boolissn'      => $query->param('bool8'));
    $query->param('boolsign'      => $query->param('bool6'));
    $query->param('boolejahr'     => $query->param('bool7'));
    $query->param('boolfs'        => $query->param('bool10'));
    $query->param('boolmart'      => $query->param('bool11'));
    $query->param('boolhststring' => $query->param('bool12'));
    

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);

    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);

    my $searchquery_ref
        = OpenBib::Common::Util::get_searchquery($r);
                
    if (!$sortorder){
        if ($sorttype eq "ejahr"){
            $sortorder="down";
        }
        else {
            $sortorder="up";
        }
    }
        
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    
    my @databases=();
    
    my $dbinforesult=$sessiondbh->prepare("select dbname from viewdbs where viewname=? order by dbname") or die "Error -- $DBI::errstr";
    $dbinforesult->execute($view);
    
    while (my $result=$dbinforesult->fetchrow_hashref()){
        my $dbname=$result->{'dbname'};
        push @databases, $dbname;
    }
    
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
                $sessiondbh->disconnect();
                return OK;
            }
        }
        
        if ($searchquery_ref->{ejahr}{bool} eq "OR") {
            if ($searchquery_ref->{ejahr}{norm}) {
                $sessiondbh->disconnect();
                return OK;
            }
        }
        
        
        if ($searchquery_ref->{ejahr}{bool} eq "AND") {
            if ($searchquery_ref->{ejahr}{norm}) {
                if (!$firstsql) {
                    $sessiondbh->disconnect();
                    return OK;
                }
            }
        }
        
        if (!$firstsql) {
            $sessiondbh->disconnect();
            return OK;
        }
        
        
        my @ergebnisse;
                
        foreach my $database (@databases){
            my $dbh   = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);

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
                my @outputbuffer=();
                
                foreach my $idn (@tidns){
                    push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                        titidn            => $idn,
                        dbh               => $dbh,
                        sessiondbh        => $sessiondbh,
                        database          => $database,
                        sessionID         => -1,
                        targetdbinfo_ref  => $targetdbinfo_ref,
                    });
                }
                
                my @sortedoutputbuffer=();
                
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
                
                push @ergebnisse, @sortedoutputbuffer;
            }
        }

        
        # Dann den eigenen URL bestimmen
        my $myself="http://".$r->hostname.$r->uri."?".$r->args;
        
        $myself=~s/;/&/g;
        $myself=~s!:8008/!/!;
        
        my $treffercount=$#ergebnisse+1;

        my $starttemplatename=$config{tt_connector_digibib_result_start_tname};
        if ($view && -e "$config{tt_include_path}/views/$view/$starttemplatename") {
            $starttemplatename="views/$view/$starttemplatename";
        }
                
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
        
        my $itemtemplatename=$config{tt_connector_digibib_result_item_tname};
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
            targetdbinfo    => $targetdbinfo_ref,
            resultlist      => \@ergebnisse,#[$liststart..$listend],
            config          => \%config,
        };
        
        $itemtemplate->process($itemtemplatename, $ttdata) || do {
            $r->log_reason($itemtemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
        # Ausgabe des letzten HTML-Bereichs
        my $endtemplatename=$config{tt_connector_digibib_result_end_tname};
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
        };
        
        $endtemplate->process($endtemplatename, $endttdata) || do {
            $r->log_reason($endtemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
    }
    elsif ($tosearch eq "Langanzeige"){
        
        print $r->send_http_header("text/html");
        
        my $dbh   = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
        
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $idn,
            dbh                => $dbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => {},
            database           => $database,
        });
        

        # Quelle besetzt?

        my ($sbnormset,$sbmexnormset,$sbcircset);
        my $has_sb=0;
        
        if (exists $normset->{'T0590'}){

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
                ($sbnormset,$sbmexnormset,$sbcircset)=OpenBib::Search::Util::get_tit_set_by_idn({
                    titidn             => $sbid,
                    dbh                => $dbh,
                    targetdbinfo_ref   => $targetdbinfo_ref,
                    targetcircinfo_ref => {},
                    database           => $database,
                });                
                $has_sb=1;
            }
        }            

        # Ausgabe des letzten HTML-Bereichs
        my $templatename=$config{tt_connector_digibib_showtitset_tname};
        if ($view && -e "$config{tt_include_path}/views/$view/$templatename") {
            $templatename="views/$view/$templatename";
        }
        
        my $template = Template->new({
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
            #        INCLUDE_PATH   => $config{tt_include_path},
            #        ABSOLUTE       => 1,
            OUTPUT         => $r,
        });
        
        # TT-Data erzeugen
        my $ttdata={
            item         => $normset,
            itemmex      => $mexnormset,
            has_sb       => $has_sb,
            sbitem       => $sbnormset,
            sbitemmex    => $sbmexnormset,
            targetdbinfo => $targetdbinfo_ref,
        };
        
        $template->process($templatename, $ttdata) || do {
            $r->log_reason($template->error(), $r->filename);
            return SERVER_ERROR;
        };
  } 

  return OK;
}
