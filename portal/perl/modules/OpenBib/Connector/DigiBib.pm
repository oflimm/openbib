####################################################################
#
#  OpenBib::Connector::DigiBib.pm
#
#  Dieses File ist (C) 2003-2005 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Benchmark;
use DBI;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Config;
use OpenBib::Common::Util;
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

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    # CGI-Input auslesen
    #####################################################################
    #
    # Eingabeparamter
    #
    # Titelliste:
    #
    # verf       = Autor
    # hst        = Titel
    # swt        = Schlagwort
    # kor        = Koerperschaft
    # notation   = Notation
    # isbn       = ISBN
    # issn       = ISSN
    # sign       = Signatur
    # ejahr      = Erscheinungsjahr
    # maxhits    = Maximale Treffer pro Pool
    # listlength = Anzahl angezeigter Gesamttreffer
    # offset     = Offset zur Anzahl an Gesamttreffern
    # sorttype   = Sortierung (author, yearofpub, title)
    # bool1      = Boolscher Operator zu Titel
    # bool2      = Boolscher Operator zu Schlagwort
    # bool3      = Boolscher Operator zu Koerperschaft
    # bool4      = Boolscher Operator zu Notation
    # bool5      = Boolscher Operator zu ISBN
    # bool6      = Boolscher Operator zu Signatur
    # bool7      = Boolscher Operator zu Erscheinungsjahr (nur AND)
    # bool8      = Boolscher Operator zu ISSN
    # bool9      = Boolscher Operator zu Verfasser
    # tosearch   = Trefferliste
    #
    # Langanzeige:
    #
    # idn      = Titelidn
    # database = Datenbank
    # tosearch = Langanzeige

    my $fs       = $query->param('fs') || '';
    my $verf     = $query->param('verf');
    my $hst      = $query->param('hst');
    my $swt      = $query->param('swt');
    my $kor      = $query->param('kor');
    my $sign     = $query->param('sign');
    my $isbn     = $query->param('isbn');
    my $issn     = $query->param('issn');
    my $notation = $query->param('notation');

    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung

    if ($fs) {
        # Erst bereinigen
        $fs=~s/\+/ /gi;

        # Dann neu setzen
        $fs=~s/(\S+)/%2B$1/g;
    }

    if ($verf) {
        # Erst bereinigen
        $verf=~s/\+/ /gi;

        # Dann neu setzen
        $verf=~s/(\S+)/%2B$1/g;
    }

    if ($hst) {
        # Erst bereinigen
        $hst=~s/\+/ /gi;

        # Dann neu setzen
        $hst=~s/(\S+)/%2B$1/g;
    }

    if ($swt) {
        # Erst bereinigen
        $swt=~s/\+/ /gi;

        # Dann neu setzen
        $swt=~s/(\S+)/%2B$1/g;
    }

    if ($kor) {
        # Erst bereinigen
        $kor=~s/\+/ /gi;

        # Dann neu setzen
        $kor=~s/(\S+)/%2B$1/g;
    }

    if ($sign) {
        # Erst bereinigen
        $sign=~s/\+/ /gi;

        # Dann neu setzen
        $sign=~s/(\S+)/%2B$1/g;
    }

    if ($isbn) {
        # Erst bereinigen
        $isbn=~s/\+/ /gi;

        # Dann neu setzen
        $isbn=~s/(\S+)/%2B$1/g;
    }

    if ($issn) {
        # Erst bereinigen
        $issn=~s/\+/ /gi;

        # Dann neu setzen
        $issn=~s/(\S+)/%2B$1/g;
    }

    if ($notation) {
        # Erst bereinigen
        $notation=~s/\+/ /gi;

        # Dann neu setzen
        $notation=~s/(\S+)/%2B$1/g;
    }

    my $ejahr        = $query->param('ejahr');
    my $ejahrop      = $query->param('ejahrop');
    my $boolhst      = $query->param('bool1');
    my $boolswt      = $query->param('bool2');
    my $boolkor      = $query->param('bool3');
    my $boolnotation = $query->param('bool4');
    my $boolisbn     = $query->param('bool5');
    my $boolsign     = $query->param('bool6');
    my $boolejahr    = $query->param('bool7');
    my $boolissn     = $query->param('bool8');
    my $boolverf     = $query->param('bool9');
    my $idn          = $query->param('idn');
    my $database     = $query->param('database');
    my $maxhits      = ($query->param('maxhits'))?$query->param('maxhits'):200;
    my $offset       = ($query->param('offset'))?$query->param('offset'):1;
    my $listlength   = ($query->param('listlength'))?$query->param('listlength'):999999999;
    my $sorttype     = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortorder    = $query->param('sortorder');
    my $tosearch     = $query->param('tosearch');
    my $view         = ($query->param('view'))?$query->param('view'):'institute';

    if (!$sortorder) {
        if ($sorttype eq "ejahr") {
            $sortorder="down";
        } else {
            $sortorder="up";
        }
    }

    my $targetdbinfo_ref   = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);

    my @databases=();
    # Auswahl der Datenbanken entsprechend view
    if ($view) {
        my $idnresult=$sessiondbh->prepare("select dbname from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($view) or $logger->error($DBI::errstr);

        @databases=();
        my @idnres;
        while (@idnres=$idnresult->fetchrow) {
            push @databases, $idnres[0];
        }
        $idnresult->finish();
    }
    # sonst alle
    else {
        my $idnresult=$sessiondbh->prepare("select dbname,description from dbinfo where active=1 order by orgunit,description") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        @databases=();
        my @idnres;
        while (@idnres=$idnresult->fetchrow) {
            push @databases, $idnres[0];
        }
        $idnresult->finish();
    }

    if ($tosearch eq "Trefferliste") {
        my $starttemplatename=$config{tt_connector_digibib_result_start_tname};
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
#           INCLUDE_PATH   => $config{tt_include_path},
#           ABSOLUTE       => 1,
            OUTPUT         => $r,
        });
        
        # TT-Data erzeugen
        my $startttdata={
        };
        
        $starttemplate->process($starttemplatename, $startttdata) || do { 
            $r->log_reason($starttemplate->error(), $r->filename);
            return SERVER_ERROR;
        };
        
        # Ausgabe flushen
        $r->rflush();

        my $gesamttreffer=0;

        # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
        #
        ######################################################################
        # Schleife ueber alle Datenbanken 
        ######################################################################

        my @resultset=();
        foreach my $database (@databases) {
            my $dbh
                = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                    or $logger->error_die($DBI::errstr);
            
            my @tidns=OpenBib::Search::Util::initial_search_for_titidns({
                fs            => $fs,
                verf          => $verf,
                hst           => $hst,
                hststring     => $hststring,
                swt           => $swt,
                kor           => $kor,
                notation      => $notation,
                isbn          => $isbn,
                issn          => $issn,
                sign          => $sign,
                ejahr         => $ejahr,
                ejahrop       => $ejahrop,
                mart          => $mart,
                
                boolfs        => $boolfs,
                boolverf      => $boolverf,
                boolhst       => $boolhst,
                boolhststring => $boolhststring,
                boolswt       => $boolswt,
                boolkor       => $boolkor,
                boolnotation  => $boolnotation,
                boolisbn      => $boolisbn,
                boolissn      => $boolissn,
                boolsign      => $boolsign,
                boolejahr     => $boolejahr,
                boolmart      => $boolmart,
                
                dbh           => $dbh,
                maxhits       => $maxhits,
            });
            
            # Wenn mindestens ein Treffer gefunden wurde
            if ($#tidns >= 0) {
                my @outputbuffer=();
                
                my $atime=new Benchmark;
                
                foreach my $idn (@tidns) {
                    
                    # Zuerst in Resultset eintragen zur spaeteren Navigation
                    
                    push @resultset, { 'database' => $database,
                                       'idn'      => $idn
                                   };
                    
                    push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                        titidn            => $idn,
                        hint              => "none",
                        mode              => 5,
                        dbh               => $dbh,
                        sessiondbh        => $sessiondbh,
                        searchmultipleaut => 0,
                        searchmultiplekor => 0,
                        searchmultipleswt => 0,
                        searchmultiplenot => 0,
                        searchmultipletit => 0,
                        searchmode        => $searchmode,
                        hitrange          => $hitrange,
                        rating            => '',
                        bookinfo          => '',
                        sorttype          => $sorttype,
                        sortorder         => $sortorder,
                        database          => $database,
                        sessionID         => $sessionID,
                    });
                }
                
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                if ($config{benchmark}) {
                    $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
                }
                
                my @sortedoutputbuffer=();
                
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
                
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
#                    ABSOLUTE      => 1,
#                    INCLUDE_PATH  => $config{tt_include_path},
                    OUTPUT        => $r,
                });
                
                
                # TT-Data erzeugen
                my $ttdata={
                    view       => $view,
                    sessionID  => $sessionID,
                    
                    dbinfo     => $targetdbinfo_ref->{dbinfo}{$database},
                    
                    treffer    => $treffer,
                    
                    resultlist => \@sortedoutputbuffer,
                    
                    searchmode => $searchmode,
                    rating     => '',
                    bookinfo   => '',
                    sorttype   => $sorttype,
                    sortorder  => $sortorder,
                    
                    resulttime => $resulttime,
                    
                    utf2iso    => sub {
                        my $string=shift;
                        $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                        return $string;
                    },
                    
                    show_corporate_banner => 0,
                    show_foot_banner      => 1,
                    config     => \%config,
                };
                
                $itemtemplate->process($itemtemplatename, $ttdata) || do {
                    $r->log_reason($itemtemplate->error(), $r->filename);
                    return SERVER_ERROR;
                };
                
                $trefferpage{$database} = \@sortedoutputbuffer;
                $dbhits     {$database} = $treffer;
                $gesamttreffer          = $gesamttreffer+$treffer;
                
                undef $atime;
                undef $btime;
                undef $timeall;
                
            }
            $dbh->disconnect;
            $r->rflush();
        }
        
        my $jahr     = "";
        my $instname = "";
        my $link     = "";
        my $langurl  = "";
        my $year     = "";
        my $signatur = "";
        my $sigel    = "";

        my @ergebnisse;
        my $ergidx;

        my $suchstring.="&sessionID=-1&tosearch=In+ausgew%E4hlten+Katalogen+suchen&fs=&bool9=$bool9&verf=$verf&bool1=$bool1&hst=$hst&bool2=$bool2&swt=$swt&bool3=$bool3&kor=$kor&bool4=$bool4&notation=$notation&bool5=$bool5&isbn=$isbn&issn=$issn&bool8=$bool8&bool6=$bool6&sign=$sign&bool7=$bool7&ejahr=$ejahr&ejahrop=$ejahrop&maxhits=$maxhits&sorttype=$sorttype&sortorder=$sortorder";
    
        my $pool;
        foreach $pool (@databases) {
            $suchstring.="&"."database=$pool";
        }
    
        my $request=new HTTP::Request GET => "$trefferlistebefehlsurl?$suchstring";
    
        my $response=$ua->request($request);
    
        my $ergebnis=$response->content();
    
        # Parsen des Ergebnisse
    
        #  open(DEBUG,">/tmp/ergebnis2.dat");
        #  print DEBUG $suchstring."\n";
        #  print DEBUG $ergebnis;
        #  close(DEBUG);
    
        # Zuerst die Trefferzahl ermitteln
    
        my @seite=split("\n",$ergebnis);
        my $treffercount=0;
        my $zeile;
        while ($zeile <$#seite) {
            if ($seite[$zeile]=~/<strong>(\d+) Treffer<\/strong>/) {
                $treffercount+=$1;
            }
            $zeile++;
        }
    
        # Dann den eigenen URL bestimmen
    
        my $myself=$query->self_url();
    
        $myself=~s/;/&/g;
        $myself=~s!:8008/!/!;
    
        print << "META";
<LI><UL>
<LI> META
<LI> DB=KVIK
<LI> HITS=$treffercount
<LI> QUERY=$myself
</UL>

META

        # Und schliesslich die Treffer generieren
    
        my $location="";
    
        my $resultcount=0;
    
        while ($zeile <$#seite) {
            $hst="";
            $verf="";
            $jahr="";
            $idn="";
      
            if ($seite[$zeile]=~/<a href=.http.+?bibinfo.+?.html.*?>(.+?)<\/a>.+?Treffer/) {
                $instname=$1;
            }
      
            if ($seite[$zeile]=~/database=(inst\d\d\d).+?searchsingletit=(\d+)/) {
                $database=$1;
                $idn=$2;
	
                $resultcount++;
	
                if (($resultcount >= $offset) && ($resultcount < $offset+$listlength)) {
	  
                    $link=$dbases{$database};
	  
                    $langurl="database=$database&idn=$idn&tosearch=Langanzeige";
	  
                    if ($seite[$zeile]=~/<span id=\"rlauthor\">(.*?)<\/span>/) {
                        $verf=$1;
                    }

                    if ($seite[$zeile]=~/<span id=\"rltitle\">(.*?)<\/span>/) {
                        $hst=$1;
                    }
	  
                    if ($seite[$zeile]=~/<span id=\"rlyearofpub\">(.*?)<\/span>/) {
                        $year=$1;
                    }
	  
                    if ($seite[$zeile]=~/<span id=\"rlsignature\">(.*?)<\/span>/) {
                        $signatur=$1;
                    }
	  
                    $sigel=substr($database,4,3);
	  
                    if ($instname ne "") {
                        $location="<a href=\"$link\">38/$sigel</a> ($instname) ";
                    }
	  
                    if ($signatur ne "") {
                        $location.=": $signatur";
                    }
	  
                    print << "TITEL";
<LI><UL>
<LI> DB=KVIK
<LI> AU=$verf
<LI> TI=$hst
<LI> YR=$year
<LI> URL=$langurl
<LI> LO=$location
<LI> LNK=
</UL>

TITEL


                }               # Ende 'Fenster'
            }                   # Ende Trefferzeile
            $zeile++;
        }
    
    

        ######
    
        print << "FOOTTL";
</OL>

<!-- end result -->

</BODY>
</HTML>
FOOTTL

    } elsif ($tosearch eq "Langanzeige") {
    
        print $query->header;
        print << "HEADLA";
<HTML>
<HEAD>
<TITLE>Langanzeige</TITLE>
</HEAD>
<BODY>

<!-- begin result -->

<OL>

HEADLA

        # Hier wird jetzt der Satz ausgegeben
    
        ######
    
        my @ergebnisse;
        my $ergidx;
    
        my $suchstring.="sessionID=-1&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&showvbu=0&casesensitive=0&hitrange=20&sorttype=author&database=$database&dbms=mysql&searchsingletit=$idn";
    
        my $request=new HTTP::Request GET => "$langanzeigebefehlsurl?$suchstring";
    
        my $response=$ua->request($request);
    
        my $ergebnis=$response->content();
    
        # Parsen des Ergebnisse
    
        #  open(DEBUG,">/tmp/ergebnis.dat");
        #  print DEBUG $ergebnis;
        #  close(DEBUG);
    
        # Jetzt wird munter geparst

        my @verfasserarray=();
        my @korarray=();
        my @swtarray=();
        my @absarray=();
        my @isbnarray=();
        my @issnarray=();
        my @signarray=();
        my @urlarray=();

        my $hst="";
        my $verlag="";
        my $fussnote="";
        my $hstzusatz="";
        my $vorlverf="";
        my $verlagsort="";
        my $jahr="";
        my $zeitschriftentitel="";
        my $inverknidn="";
        my $seitenzahl="";
        my $umfang="";
        my $serie="";
        my $ausgabe="";
        my $dbname="";
        my $zusatz="";
        my $zitatangabe="";
        my $quelle="";
        my $abstract="";
        my $volltexturl="";
        my $autorlink="";
        my $titellink="";

        my @seite=split("\n",$ergebnis);
        my $zeile;
        while ($zeile <$#seite) {
            if ($seite[$zeile]=~/<strong>Verfasser<\/strong>.+Begriff in diesem Katalog suchen.>(.+?)<\/a><\/td><\/tr>$/) {
                push @verfasserarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>Person<\/strong>.+Begriff in diesem Katalog suchen.>(.+?)<\/a><\/td><\/tr>$/) {
                push @verfasserarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>K&ouml;rperschaft<\/strong>.+Begriff in diesem Katalog suchen.>(.+?)<\/a><\/td><\/tr>$/) {
                push @korarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>Urheber<\/strong>.+Begriff in diesem Katalog suchen.>(.+?)<\/a><\/td><\/tr>$/) {
                push @korarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>Schlagwort<\/strong>.+Begriff in diesem Katalog suchen.>(.+?)<\/a><\/td><\/tr>$/) {
                push @swtarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>Abstract<\/strong>.+?<td>(.+?)<\/td><\/tr>/) {
                push @absarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>URL<\/strong>.+?<td><a.+>(.+?)<\/a><\/td><\/tr>/) {
                push @urlarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>ISBN<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                push @isbnarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>ISSN<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                push @issnarray, $1;
            }
      
            if ($seite[$zeile]=~/<strong>Sachl.Ben.<\/strong>.+?<strong>(.+?)<\/strong><\/td><\/tr>$/) {
                $hst=$1;
            }
      
            if ($seite[$zeile]=~/<strong>HST<\/strong>.+?<strong>(.+?)<\/strong><\/td><\/tr>$/) {
                $hst=$1;
            }
      
            if ($seite[$zeile]=~/<strong>Verlag<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $verlag=$1;
            }
      
            if ($seite[$zeile]=~/<strong>Fu&szlig;note<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $fussnote=$1;
            }
      
            if ($seite[$zeile]=~/<strong>Zusatz<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $hstzusatz=$1;
            }
      
      
            if ($seite[$zeile]=~/<strong>Vorl.Verfasser<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $vorlverf=$1;
            }
      
            if ($seite[$zeile]=~/<strong>Verlagsort<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $verlagsort=$1;
            }
      
            if ($seite[$zeile]=~/<strong>Ersch. Jahr<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $jahr=$1;
            }
      
            if ($seite[$zeile]=~/<strong>IN unverkn<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $zeitschriftentitel=$1;
                if ($zeitschriftentitel=~/ ; (S\. *\d+.*)$/) {
                    $seitenzahl=$1;
                }
            }
      
      
            if ($seite[$zeile]=~/<strong>IN verkn<\/strong>.+?<td><a href=.*?singlegtf=(\d+).*?>(.*?)<.a> ; (.*)<\/td><\/tr>$/) {
                $inverknidn=$1;
                $zeitschriftentitel=$2;
                $zusatz=$3;
                if ($zusatz=~/.*?(S\. *\d+.*)$/) {
                    $seitenzahl=$1;
                }
            }
      
            if ($seite[$zeile]=~/<strong>Kollation<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $umfang=$1;
            }
      
      
            if ($seite[$zeile]=~/<strong>GTF<\/strong>.+?singlegtf.>(.+?)<\/a>(.*?)<\/td><\/tr>$/) {
                $serie=$1.$2;
            }
      
            if ($seite[$zeile]=~/<strong>GTM<\/strong>.+?singlegtm.>(.+?)<\/a>(.*?)<\/td><\/tr>$/) {
                $serie=$1.$2;
            }
      
            if ($seite[$zeile]=~/<strong>Ausgabe<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                $ausgabe=$1;
            }
      
            if ($seite[$zeile]=~/^<tr align=center><td><a href=.http:..www.ub.uni-koeln.de.dezkat.bibinfo.+?.html.><strong>(.+?)<\/strong>.*?<span id="rlsignature">(.*?)<\/span>/) {
                $dbname=$1;
                push @signarray, $2;
            }
      
      
            $zeile++;
        }
    
        my $link=$dbases{$database};
    
        my $sigel=substr($database,4,3);
        my $verf=join(" ; ",@verfasserarray);
        my $kor=join(" ; ",@korarray);
        my $swt=join(" ; ",@swtarray);
        my $isbn=join(" ; ",@isbnarray);
        my $issn=join(" ; ",@issnarray);
    
        my $signatur=join(" ; ",@signarray);
    
        if ($signatur ne "") {
            $signatur="<a href=\"$link\">38/$sigel</a> ($dbname): $signatur";
        }
    
        if ($hst && $hstzusatz) {
            $hst="$hst: $hstzusatz";
        }
    
        print << "LANGTITEL";
<LI><UL>
<LI> DB=KVIK
<LI> AU=$verf
<LI> RE=$vorlverf
<LI> TI=$hst
<LI> CO=$kor
<LI> KY=$swt
<LI> PB=$verlag
<LI> PBO=$verlagsort
<LI> AG=$ausgabe
<LI> UM=$umfang
<LI> SE=$serie
<LI> CT=$zitatangabe
<LI> ZT=$zeitschriftentitel
<LI> SZ=$seitenzahl
<LI> SO=$quelle
<LI> AB=$abstract
<LI> YR=$jahr
<LI> IB=$isbn
<LI> IS=$issn
<LI> LO=$signatur
<LI> FN=$fussnote
<LI> OLL=$volltexturl
<LI> AUH=$autorlink
<LI> TIH=$titellink
LANGTITEL

        if ($inverknidn) {
      
            my @verfasserarray=();
            my @korarray=();
            my @swtarray=();
            my @isbnarray=();
            my @issnarray=();
            my @signarray=();
      
            my $verlagsort="";
            my $verlag="";
            my $hst="";
            my $jahr="";
            my $umfang="";
            my $serie="";
      
            my @ergebnisse=();
            my $ergidx;
      
            my $suchstring.="sessionID=-1&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&showvbu=0&casesensitive=0&hitrange=20&sorttype=author&database=$database&dbms=mysql&searchsingletit=$inverknidn";
      
            my $request=new HTTP::Request GET => "$langanzeigebefehlsurl?$suchstring";
      
            my $response=$ua->request($request);
      
            my $ergebnis=$response->content();
      
            # Parsen des Ergebnisse
      
            #  open(DEBUG,">/tmp/ergebnis.dat");
            #  print DEBUG $ergebnis;
            #  close(DEBUG);
      
            # Jetzt wird munter geparst
      
            my @seite=split("\n",$ergebnis);
            my $zeile;
            while ($zeile <$#seite) {
                if ($seite[$zeile]=~/<strong>Verfasser<\/strong>.+?verf.>(.+?)<\/a><\/td><\/tr>$/) {
                    push @verfasserarray, $1;
                }
	
                if ($seite[$zeile]=~/<strong>Person<\/strong>.+?pers.>(.+?)<\/a><\/td><\/tr>$/) {
                    push @verfasserarray, $1;
                }
	
                if ($seite[$zeile]=~/<strong>K&ouml;rperschaft<\/strong>.+?kor.>(.+?)<\/a><\/td><\/tr>$/) {
                    push @korarray, $1;
                }
	
                if ($seite[$zeile]=~/<strong>Urheber<\/strong>.+?urh.>(.+?)<\/a><\/td><\/tr>$/) {
                    push @korarray, $1;
                }
	
                if ($seite[$zeile]=~/<strong>Schlagwort<\/strong>.+?swt.>(.+?)<\/a><\/td><\/tr>$/) {
                    push @swtarray, $1;
                }
	
                if ($seite[$zeile]=~/<strong>ISBN<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                    push @isbnarray, $1;
                }
	
                if ($seite[$zeile]=~/<strong>ISSN<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                    push @issnarray, $1;
                }
	
                if ($seite[$zeile]=~/<strong>Sachl.Ben.<\/strong>.+?<strong>(.+?)<\/strong><\/td><\/tr>$/) {
                    $hst=$1;
                }
	
                if ($seite[$zeile]=~/<strong>HST<\/strong>.+?<strong>(.+?)<\/strong><\/td><\/tr>$/) {
                    $hst=$1;
                }
	
                if ($seite[$zeile]=~/<strong>Verlag<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                    $verlag=$1;
                }
	
                if ($seite[$zeile]=~/<strong>Verlagsort<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                    $verlagsort=$1;
                }
	
                if ($seite[$zeile]=~/<strong>Ersch. Jahr<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                    $jahr=$1;
                }
	
                if ($seite[$zeile]=~/<strong>Kollation<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                    $umfang=$1;
                }
	
	
                if ($seite[$zeile]=~/<strong>GTF<\/strong>.+?singlegtf.>(.+?)<\/a>(.*?)<\/td><\/tr>$/) {
                    $serie=$1.$2;
                }
	
                if ($seite[$zeile]=~/<strong>GTM<\/strong>.+?singlegtm.>(.+?)<\/a>(.*?)<\/td><\/tr>$/) {
                    $serie=$1.$2;
                }
	
                if ($seite[$zeile]=~/<strong>Ausgabe<\/strong>.+?<td>(.+?)<\/td><\/tr>$/) {
                    $ausgabe=$1;
                }
	
                if ($seite[$zeile]=~/^<tr align=center><td><a href=.http:..www.ub.uni-koeln.de.dezkat.bibinfo.+?.html.><strong>(.+?)<\/strong><\/a><\/td><td>.*?<\/td><td>.*?<\/td><td><strong>(.*?)<\/strong><\/td>/) {
                    $dbname=$1;
                    push @signarray, $2;
                }
	
	
                $zeile++;
            }
      
            $sigel=substr($database,4,3);
            $verf=join(" ; ",@verfasserarray);
            $kor=join(" ; ",@korarray);
            $swt=join(" ; ",@swtarray);
            $isbn=join(" ; ",@isbnarray);
            $issn=join(" ; ",@issnarray);
            $signatur=join(" ; ",@signarray);
      
            print << "SBTITEL";
<LI> SBAU=$verf
<LI> SBTI=$hst
<LI> SBPB=$verlag
<LI> SBPBO=$verlagsort
<LI> SBSE=$serie
<LI> SBYR=$jahr
<LI> SBIB=$isbn
<LI> SBIS=$issn
SBTITEL

        }

        print << "ENDE";
</UL>
ENDE



        print << "FOOTLA";
</OL>

<!-- end result -->

</BODY>
</HTML>
FOOTLA

    }

    return OK;
}
