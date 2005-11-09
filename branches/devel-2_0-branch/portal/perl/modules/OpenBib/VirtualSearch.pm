####################################################################
#
#  OpenBib::VirtualSearch.pm
#
#  Dieses File ist (C) 1997-2005 Oliver Flimm <flimm@openbib.org>
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
use Apache::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use YAML ();

use OpenBib::Search::Util;
use OpenBib::VirtualSearch::Util;
use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Template::Provider;

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

    # Standardwerte festlegen
    my $searchmode=2;

    # CGI-Input auslesen
    my $fs            = $query->param('fs')            || '';
    my $verf          = $query->param('verf')          || '';
    my $hst           = $query->param('hst')           || '';
    my $hststring     = $query->param('hststring')     || '';
    my $swt           = $query->param('swt')           || '';
    my $kor           = $query->param('kor')           || '';
    my $sign          = $query->param('sign')          || '';
    my $isbn          = $query->param('isbn')          || '';
    my $issn          = $query->param('issn')          || '';
    my $mart          = $query->param('mart')          || '';
    my $notation      = $query->param('notation')      || '';
    my $ejahr         = $query->param('ejahr')         || '';
    my $ejahrop       = $query->param('ejahrop')       || '=';
    my @databases     = ($query->param('database'))?$query->param('database'):();

    my $hitrange      = ($query->param('hitrange'))?$query->param('hitrange'):20;
    my $offset        = ($query->param('offset'))?$query->param('offset'):1;
    my $maxhits       = ($query->param('maxhits'))?$query->param('maxhits'):500;
    my $sorttype      = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortorder     = ($query->param('sortorder'))?$query->param('sortorder'):'up';
    my $autoplus      = $query->param('autoplus')      || '';
    my $lang          = $query->param('l')             || 'de';

    my $sortall       = ($query->param('sortall'))?$query->param('sortall'):'0';

    my $searchall     = $query->param('searchall')     || '';
    my $searchprofile = $query->param('searchprofile') || '';

    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';
    my $profil        = $query->param('profil')        || '';
    my $trefferliste  = $query->param('trefferliste')  || '';
    my $queryid       = $query->param('queryid')       || '';

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    #####################################################################
    ## boolX: Verkn"upfung der Eingabefelder (leere Felder werden ignoriert)
    ##        AND  - Und-Verkn"upfung
    ##        OR   - Oder-Verkn"upfung
    ##        NOT  - Und Nicht-Verknuepfung
    my $boolverf      = ($query->param('boolverf'))     ?$query->param('boolverf')
        :"AND";
    my $boolhst       = ($query->param('boolhst'))      ?$query->param('boolhst')
        :"AND";
    my $boolswt       = ($query->param('boolswt'))      ?$query->param('boolswt')
        :"AND";
    my $boolkor       = ($query->param('boolkor'))      ?$query->param('boolkor')
        :"AND";
    my $boolnotation  = ($query->param('boolnotation')) ?$query->param('boolnotation')
        :"AND";
    my $boolisbn      = ($query->param('boolisbn'))     ?$query->param('boolisbn')
        :"AND";
    my $boolissn      = ($query->param('boolissn'))     ?$query->param('boolissn')
        :"AND";
    my $boolsign      = ($query->param('boolsign'))     ?$query->param('boolsign')
        :"AND";
    my $boolejahr     = ($query->param('boolejahr'))    ?$query->param('boolejahr')
        :"AND" ;
    my $boolfs        = ($query->param('boolfs'))       ?$query->param('boolfs')
        :"AND";
    my $boolmart      = ($query->param('boolmart'))     ?$query->param('boolmart')
        :"AND";
    my $boolhststring = ($query->param('boolhststring'))?$query->param('boolhststring')
        :"AND";


    # Sicherheits-Checks

    if ($boolverf ne "AND" && $boolverf ne "OR" && $boolverf ne "NOT") {
        $boolverf      = "AND";
    }

    if ($boolhst ne "AND" && $boolhst ne "OR" && $boolhst ne "NOT") {
        $boolhst       = "AND";
    }

    if ($boolswt ne "AND" && $boolswt ne "OR" && $boolswt ne "NOT") {
        $boolswt       = "AND";
    }

    if ($boolkor ne "AND" && $boolkor ne "OR" && $boolkor ne "NOT") {
        $boolkor       = "AND";
    }

    if ($boolnotation ne "AND" && $boolnotation ne "OR" && $boolnotation ne "NOT") {
        $boolnotation  = "AND";
    }

    if ($boolisbn ne "AND" && $boolisbn ne "OR" && $boolisbn ne "NOT") {
        $boolisbn      = "AND";
    }

    if ($boolissn ne "AND" && $boolissn ne "OR" && $boolissn ne "NOT") {
        $boolissn      = "AND";
    }

    if ($boolsign ne "AND" && $boolsign ne "OR" && $boolsign ne "NOT") {
        $boolsign      = "AND";
    }

    if ($boolejahr ne "AND") {
        $boolejahr     = "AND";
    }

    if ($boolfs ne "AND" && $boolfs ne "OR" && $boolfs ne "NOT") {
        $boolfs        = "AND";
    }

    if ($boolmart ne "AND" && $boolmart ne "OR" && $boolmart ne "NOT") {
        $boolmart      = "AND";
    }

    if ($boolhststring ne "AND" && $boolhststring ne "OR" && $boolhststring ne "NOT") {
        $boolhststring = "AND";
    }

    $boolverf      = "AND NOT" if ($boolverf      eq "NOT");
    $boolhst       = "AND NOT" if ($boolhst       eq "NOT");
    $boolswt       = "AND NOT" if ($boolswt       eq "NOT");
    $boolkor       = "AND NOT" if ($boolkor       eq "NOT");
    $boolnotation  = "AND NOT" if ($boolnotation  eq "NOT");
    $boolisbn      = "AND NOT" if ($boolisbn      eq "NOT");
    $boolissn      = "AND NOT" if ($boolissn      eq "NOT");
    $boolsign      = "AND NOT" if ($boolsign      eq "NOT");
    $boolfs        = "AND NOT" if ($boolfs        eq "NOT");
    $boolmart      = "AND NOT" if ($boolmart      eq "NOT");
    $boolhststring = "AND NOT" if ($boolhststring eq "NOT");

    # Filter: ISBN und ISSN

    # Entfernung der Minus-Zeichen bei der ISBN
    $fs   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
    $isbn =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;

    # Entfernung der Minus-Zeichen bei der ISSN
    $fs   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)/$1$2$3$4$5$6$7$8/g;
    $issn =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)/$1$2$3$4$5$6$7$8/g;

    # Filter Rest
    $fs        = OpenBib::VirtualSearch::Util::cleansearchterm($fs);
    $verf      = OpenBib::VirtualSearch::Util::cleansearchterm($verf);
    $hst       = OpenBib::VirtualSearch::Util::cleansearchterm($hst);
    $hststring = OpenBib::VirtualSearch::Util::cleansearchterm($hststring);

    # Bei hststring zusaetzlich normieren durch Weglassung des ersten
    # Stopwortes
    $hststring = OpenBib::Common::Stopwords::strip_first_stopword($hststring);
    $swt       = OpenBib::VirtualSearch::Util::cleansearchterm($swt);
    $kor       = OpenBib::VirtualSearch::Util::cleansearchterm($kor);
    $sign      = OpenBib::VirtualSearch::Util::cleansearchterm($sign);
    $isbn      = OpenBib::VirtualSearch::Util::cleansearchterm($isbn);
    $issn      = OpenBib::VirtualSearch::Util::cleansearchterm($issn);
    $mart      = OpenBib::VirtualSearch::Util::cleansearchterm($mart);
    $notation  = OpenBib::VirtualSearch::Util::cleansearchterm($notation);
    $ejahr     = OpenBib::VirtualSearch::Util::cleansearchterm($ejahr);
    $ejahrop   = OpenBib::VirtualSearch::Util::cleansearchterm($ejahrop);

    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
    if ($autoplus eq "1") {
        $fs   = OpenBib::VirtualSearch::Util::conv2autoplus($fs) if ($fs);
        $verf = OpenBib::VirtualSearch::Util::conv2autoplus($verf) if ($verf);
        $hst  = OpenBib::VirtualSearch::Util::conv2autoplus($hst) if ($hst);
        $kor  = OpenBib::VirtualSearch::Util::conv2autoplus($kor) if ($kor);
        $swt  = OpenBib::VirtualSearch::Util::conv2autoplus($swt) if ($swt);
        $isbn = OpenBib::VirtualSearch::Util::conv2autoplus($isbn) if ($isbn);
        $issn = OpenBib::VirtualSearch::Util::conv2autoplus($issn) if ($issn);
    }

    if ($hitrange eq "alles") {
        $hitrange=-1;
    }

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$r);

    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);

    my $targetcircinfo_ref
        = OpenBib::Common::Util::get_targetcircinfo($sessiondbh);

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
        OpenBib::Common::Util::print_warning("Ungültige Session",$r);

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
        my $idnresult=$sessiondbh->prepare("select dbname,description from dbinfo where active=1 order by faculty,description") or $logger->error($DBI::errstr);
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
                my $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1 order by faculty,dbname") or $logger->error($DBI::errstr);
                $idnresult->execute() or $logger->error($DBI::errstr);
	
                my @idnres;
                while (@idnres=$idnresult->fetchrow) {
                    push @databases, decode_utf8($idnres[0]);
                }
                $idnresult->finish();
            }
            else {
                my $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1 and faculty = ? order by faculty,dbname") or $logger->error($DBI::errstr);
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
            OpenBib::Common::Util::print_warning("Sie haben \"In ausgewählten Katalogen suchen\" angeklickt, obwohl sie keine <a href=\"$config{databasechoice_loc}?sessionID=$sessionID\" target=\"body\">Kataloge</a> oder Suchprofile ausgewählt haben. Bitte wählen Sie die gewünschten Kataloge/Suchprofile aus oder betätigen Sie \"In allen Katalogen suchen\".",$r);

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

    # BEGIN Indizes
    ####################################################################
    # Wenn ein kataloguebergreifender Verfasserindex ausgewaehlt wurde
    ####################################################################

    if ($verfindex) {
        $verf=~s/\+//g;
        $verf=~s/%2B//g;
        $verf=~s/%//g;

        if (!$verf) {
            OpenBib::Common::Util::print_warning("Sie haben keinen Verfasser eingegeben",$r);
            return OK;
        }

        if ($#databases > 0 && length($verf) < 3 ) {
            OpenBib::Common::Util::print_warning("Der Verfasseranfang muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche ausgewählt wurde.",$r);
            return OK;
        }

        my %verfindex=();

        my @sortedindex=();

        foreach my $database (@databases) {
            my $dbh
                = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                    or $logger->error_die($DBI::errstr);
            my $thisindex_ref=OpenBib::Search::Util::get_index_by_verf($verf,$dbh);

            # Umorganisierung der Daten Teil 1
            foreach my $item_ref (@$thisindex_ref) {
                # Korrekte Initialisierung mit 0
                if (! $verfindex{$item_ref->{verf}}{titanzahl}) {
                    $verfindex{$item_ref->{verf}}{titanzahl}=0;
                }
	
                my $verfdb={
                    'dbname'    => $database,
                    'dbdesc'    => $targetdbinfo_ref->{dbnames}{$database},
                    'verfidn'   => $item_ref->{verfidn},
                    'titanzahl' => $item_ref->{titanzahl},
                };

                push @{$verfindex{$item_ref->{verf}}{databases}}, $verfdb;
                $verfindex{$item_ref->{verf}}{titanzahl}=$verfindex{$item_ref->{verf}}{titanzahl}+$item_ref->{titanzahl};
            }
            $dbh->disconnect;
        }

        # Umorganisierung der Daten Teil 2
        foreach my $singleverf (sort { uc($a) cmp uc($b) } keys %verfindex) {
            push @sortedindex, { verf      => $singleverf,
                                 titanzahl => $verfindex{$singleverf}{titanzahl},
                                 databases => $verfindex{$singleverf}{databases},
                             };
        }

        $logger->debug("Verfasserindex".YAML::Dump(\@sortedindex));

        my $hits=$#sortedindex;

        if ($hits > 200) {
            $hitrange=200;
        }

        my $baseurl="http://$config{servername}$config{virtualsearch_loc}?sessionID=$sessionID;view=$view;verf=$verf;verfindex=Index;profil=$profil;maxhits=$maxhits;sorttype=$sorttype;sortorder=$sortorder";

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

        # TT-Data erzeugen
        my $ttdata={
            lang       => $lang,
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,
		
            searchmode => $searchmode,
	
            verf       => $verf,
            verfindex  => \@sortedindex,

            nav        => \@nav,
            offset     => $offset,
            hitrange   => $hitrange,

            baseurl    => $baseurl,

            profil     => $profil,

            utf2iso    => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },
		
            show_corporate_banner => 0,
            show_foot_banner      => 1,
            config     => \%config,
        };

        OpenBib::Common::Util::print_page($config{tt_virtualsearch_showverfindex_tname},$ttdata,$r);

        return OK;
    }

    # BEGIN Koerperschaften
    ####################################################################
    # Wenn ein kataloguebergreifender Koerperschaftsindex ausgewaehlt wurde
    ####################################################################

    if ($korindex) {
        $kor=~s/\+//g;
        $kor=~s/%2B//g;
        $kor=~s/%//g;

        if (!$kor) {
            OpenBib::Common::Util::print_warning("Sie haben keine Körperschaft eingegeben",$r);
            return OK;
        }

        if ($#databases > 0 && length($kor) < 3 ) {
            OpenBib::Common::Util::print_warning("Der Körperschaftsanfang muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche ausgewählt wurde.",$r);
            return OK;
        }

        my %korindex=();

        my @sortedindex=();

        foreach my $database (@databases) {
            my $dbh
                = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                    or $logger->error_die($DBI::errstr);
            my $thisindex_ref=OpenBib::Search::Util::get_index_by_kor($kor,$dbh);

            # Umorganisierung der Daten Teil 1

            foreach my $item_ref (@$thisindex_ref) {
                # Korrekte Initialisierung mit 0
                if (! $korindex{$item_ref->{kor}}{titanzahl}) {
                    $korindex{$item_ref->{kor}}{titanzahl}=0;
                }
	
                my $kordb={
                    'dbname'    => $database,
                    'dbdesc'    => $targetdbinfo_ref->{dbnames}{$database},
                    'koridn'    => $item_ref->{koridn},
                    'titanzahl' => $item_ref->{titanzahl},
                };

                push @{$korindex{$item_ref->{kor}}{databases}}, $kordb;
                $korindex{$item_ref->{kor}}{titanzahl}=$korindex{$item_ref->{kor}}{titanzahl}+$item_ref->{titanzahl};
            }
            $dbh->disconnect;
        }

        # Umorganisierung der Daten Teil 2
        foreach my $singlekor (sort { uc($a) cmp uc($b) } keys %korindex) {
            push @sortedindex, { kor       => $singlekor,
                                 titanzahl => $korindex{$singlekor}{titanzahl},
                                 databases => $korindex{$singlekor}{databases},
                             };
        }

        my $hits=$#sortedindex;

        if ($hits > 200) {
            $hitrange=200;
        }

        my $baseurl="http://$config{servername}$config{virtualsearch_loc}?sessionID=$sessionID;view=$view;kor=$kor;korindex=Index;profil=$profil;maxhits=$maxhits;sorttype=$sorttype;sortorder=$sortorder";

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

        # TT-Data erzeugen
        my $ttdata={
            lang       => $lang,
            view       => $view,
            stylesheet => $stylesheet,		
            sessionID  => $sessionID,
		
            searchmode => $searchmode,
	
            kor        => $kor,
            korindex   => \@sortedindex,

            nav        => \@nav,
            offset     => $offset,
            hitrange   => $hitrange,

            baseurl    => $baseurl,

            profil     => $profil,

            utf2iso    => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },
		
            show_corporate_banner => 0,
            show_foot_banner      => 1,
            config     => \%config,
        };

        OpenBib::Common::Util::print_page($config{tt_virtualsearch_showkorindex_tname},$ttdata,$r);

        return OK;
    }


    # BEGIN Schlagworte
    # (derzeit nicht unterstuetzt)
    ####################################################################
    # Wenn ein kataloguebergreifender Schlagwortindex ausgewaehlt wurde
    ####################################################################

    if ($swtindex) {
        $swt=~s/\+//g;
        $swt=~s/%2B//g;
        $swt=~s/%//g;

        if (!$swt) {
            OpenBib::Common::Util::print_warning("Sie haben kein Schlagwort eingegeben",$r);
            return OK;
        }

        if ($#databases > 0 && length($swt) < 3) {
            OpenBib::Common::Util::print_warning("Der Schlagwortanfang muss mindestens 3 Zeichen umfassen, wenn mehr als eine Datenbank zur Suche ausgewählt wurde.",$r);
            return OK;
        }

        my %swtindex=();

        my @sortedindex=();

        foreach my $database (@databases) {
            my $dbh
                = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
                    or $logger->error_die($DBI::errstr);
            my $thisindex_ref=OpenBib::Search::Util::get_index_by_swt($swt,$dbh);

            # Umorganisierung der Daten Teil 1
            foreach my $item_ref (@$thisindex_ref) {
                # Korrekte Initialisierung mit 0
                if (! $swtindex{$item_ref->{swt}}{titanzahl}) {
                    $swtindex{$item_ref->{swt}}{titanzahl}=0;
                }

                my $swtdb={
                    'dbname'    => $database,
                    'dbdesc'    => $targetdbinfo_ref->{dbnames}{$database},
                    'swtidn'    => $item_ref->{swtidn},
                    'titanzahl' => $item_ref->{titanzahl},
                };

                push @{$swtindex{$item_ref->{swt}}{databases}}, $swtdb;
                $swtindex{$item_ref->{swt}}{titanzahl}=$swtindex{$item_ref->{swt}}{titanzahl}+$item_ref->{titanzahl};
            }
            $dbh->disconnect;
        }

        # Umorganisierung der Daten Teil 2
        foreach my $singleswt (sort { uc($a) cmp uc($b) } keys %swtindex) {
            push @sortedindex, { swt       => $singleswt,
                                 titanzahl => $swtindex{$singleswt}{titanzahl},
                                 databases => $swtindex{$singleswt}{databases},
                             };
        }

        my $hits=$#sortedindex;

        if ($hits > 200) {
            $hitrange=200;
        }

        my $baseurl="http://$config{servername}$config{virtualsearch_loc}?sessionID=$sessionID;view=$view;swt=$swt;swtindex=Index;profil=$profil;maxhits=$maxhits;sorttype=$sorttype;sortorder=$sortorder";

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

        # TT-Data erzeugen
        my $ttdata={
            lang       => $lang,
            view       => $view,
            stylesheet => $stylesheet,		
            sessionID  => $sessionID,
		
            searchmode => $searchmode,
	
            swt        => $swt,
            swtindex   => \@sortedindex,

            nav        => \@nav,
            offset     => $offset,
            hitrange   => $hitrange,

            baseurl    => $baseurl,

            profil     => $profil,

            utf2iso    => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },
		
            show_corporate_banner => 0,
            show_foot_banner => 1,
            config     => \%config,
        };

        OpenBib::Common::Util::print_page($config{tt_virtualsearch_showswtindex_tname},$ttdata,$r);

        return OK;
    }

    ####################################################################
    # ENDE Indizes
    #


    # Folgende nicht erlaubte Anfragen werden sofort ausgesondert

    my $firstsql;

    if ($fs) {
        $firstsql=1;
    }

    if ($verf) {
        $firstsql=1;
    }

    if ($kor) {
        $firstsql=1;
    }

    if ($hst) {
        $firstsql=1;
    }

    if ($swt) {
        $firstsql=1;
    }

    if ($notation) {
        $firstsql=1;
    }

    if ($sign) {
        $firstsql=1;
    }

    if ($isbn) {
        $firstsql=1;
    }

    if ($issn) {
        $firstsql=1;
    }

    if ($mart) {
        $firstsql=1;
    }

    if ($hststring) {
        $firstsql=1;
    }

    if ($ejahr) {
        my ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
        if (!$ejtest) {
            OpenBib::Common::Util::print_warning("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein.",$r);

            $sessiondbh->disconnect();
            $userdbh->disconnect();

            return OK;
        }
    }

    if ($boolejahr eq "OR") {
        if ($ejahr) {
            OpenBib::Common::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung.",$r);

            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }
    }


    if ($boolejahr eq "AND") {
        if ($ejahr) {
            if (!$firstsql) {
                OpenBib::Common::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der
UND-Verknüpfung und mindestens einem weiteren angegebenen Suchbegriff möglich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verständnis für diese Einschränkung.",$r);

                $sessiondbh->disconnect();
                $userdbh->disconnect();

                return OK;
            }
        }
    }

    if (!$firstsql) {
        OpenBib::Common::Util::print_warning("Es wurde kein Suchkriterium eingegeben.",$r);

        $sessiondbh->disconnect();
        $userdbh->disconnect();

        return OK;
    }

    my %trefferpage = ();
    my %dbhits      = ();

    my $loginname = "";
    my $password  = "";

    if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self"){
        ($loginname,$password)=OpenBib::Common::Util::get_cred_for_userid($userdbh,$userid);
    }

    # Hash im Loginname ersetzen
    $loginname =~s/#/\%23/;

    $verf      =~s/%2B(\w+)/$1/g;
    $hst       =~s/%2B(\w+)/$1/g;
    $kor       =~s/%2B(\w+)/$1/g;
    $ejahr     =~s/%2B(\w+)/$1/g;
    $isbn      =~s/%2B(\w+)/$1/g;
    $issn      =~s/%2B(\w+)/$1/g;

    my $hostself="http://".$r->hostname.$r->uri;

    my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1);

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
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
        ABSOLUTE       => 1,
        OUTPUT         => $r,
    });

    # TT-Data erzeugen
    my $startttdata={
        lang           => $lang,
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $sessionID,

        loginname      => $loginname,
        password       => $password,

        verf           => OpenBib::VirtualSearch::Util::externalsearchterm($verf),
        hst            => OpenBib::VirtualSearch::Util::externalsearchterm($hst),
        kor            => OpenBib::VirtualSearch::Util::externalsearchterm($kor),
        ejahr          => OpenBib::VirtualSearch::Util::externalsearchterm($ejahr),
        isbn           => OpenBib::VirtualSearch::Util::externalsearchterm($isbn),
        issn           => OpenBib::VirtualSearch::Util::externalsearchterm($issn),
        queryargs      => $queryargs,
        sortselect     => $sortselect,
        thissortstring => $thissortstring,

        utf2iso        => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
            return $string;
        },

        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config         => \%config,
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
                    targetdbinfo_ref  => $targetdbinfo_ref,
                });
            }

            my $btime      = new Benchmark;
            my $timeall    = timediff($btime,$atime);
            my $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;

            if ($config{benchmark}) {
                $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
            }

#            my @sortedoutputbuffer=();
            my @sortedoutputbuffer=@outputbuffer;

#            OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

            my $treffer=$#sortedoutputbuffer+1;

            my $itemtemplatename=$config{tt_virtualsearch_result_item_tname};
            if ($view && -e "$config{tt_include_path}/views/$view/$itemtemplatename") {
                $itemtemplatename="views/$view/$itemtemplatename";
            }

            my $itemtemplate = Template->new({
                LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                    INCLUDE_PATH   => $config{tt_include_path},
                }) ],
#                INCLUDE_PATH   => $config{tt_include_path},
                ABSOLUTE       => 1,
                OUTPUT         => $r,
            });


            # TT-Data erzeugen
            my $ttdata={
                lang       => $lang,
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

    ######################################################################
    #
    # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln

    $logger->info("InitialSearch: ", $sessionID, " ", $gesamttreffer, " fs=(", $fs, ") verf=(", $boolverf, "#", $verf, ") hst=(", $boolhst, "#", $hst, ") hststring=(", $boolhststring, "#", $hststring, ") swt=(", $boolswt, "#", $swt, ") kor=(", $boolkor, "#", $kor, ") sign=(", $boolsign, "#", $sign, ") isbn=(", $boolisbn, "#", $isbn, ") issn=(", $boolissn, "#", $issn, ") mart=(", $boolmart, "#", $mart, ") notation=(", $boolnotation, "#", $notation, ") ejahr=(", $boolejahr, "#", $ejahr, ") ejahrop=(", $ejahrop, ") databases=(",join(' ',sort @databases),") ");

    # Wenn etwas gefunden wurde, dann kann ein Resultset geschrieben werden.

    if ($gesamttreffer > 0) {
        OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
    }

    ######################################################################
    # Bei einer SessionID von -1 wird effektiv keine Session verwendet
    ######################################################################

    if ($sessionID ne "-1") {
        # Jetzt update der Trefferinformationen

        # Plus-Zeichen fuer Abspeicherung wieder hinzufuegen...!
        $fs       =~s/%2B/\+/g;
        $verf     =~s/%2B/\+/g;
        $hst      =~s/%2B/\+/g;
        $swt      =~s/%2B/\+/g;
        $kor      =~s/%2B/\+/g;
        $notation =~s/%2B/\+/g;
        $sign     =~s/%2B/\+/g;
        $isbn     =~s/%2B/\+/g;
        $issn     =~s/%2B/\+/g;
        $ejahr    =~s/%2B/\+/g;

        my $dbasesstring=join("||",@databases);

        my $thisquerystring="$fs||$verf||$hst||$swt||$kor||$sign||$isbn||$issn||$notation||$mart||$ejahr||$hststring||$boolhst||$boolswt||$boolkor||$boolnotation||$boolisbn||$boolsign||$boolejahr||$boolissn||$boolverf||$boolfs||$boolmart||$boolhststring";
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

                my $yamlres=YAML::Dump($res);

                $logger->debug("YAML-Dumped: $yamlres");
                my $num=$dbhits{$db};
                $idnresult->execute($sessionID,$db,$yamlres,$num,$queryid) or $logger->error($DBI::errstr);
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
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
        ABSOLUTE       => 1,
        OUTPUT         => $r,
    });

    # TT-Data erzeugen
    my $endttdata={
        lang          => $lang,
        view          => $view,
        sessionID     => $sessionID,

        gesamttreffer => $gesamttreffer,

        utf2iso       => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
            return $string;
        },

        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config        => \%config,
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
