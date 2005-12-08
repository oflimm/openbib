#####################################################################
#
#  OpenBib::SearchFrame
#
#  Dieses File ist (C) 2001-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::SearchFrame;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;

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
  
    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
  
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $sessionID = ($query->param('sessionID'))?$query->param('sessionID'):'';
    my @databases = ($query->param('database'))?$query->param('database'):();
    my $singleidn = $query->param('singleidn') || '';
    my $setmask   = $query->param('setmask') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';
  
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

    # Authorisierte Session?
    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
    my $showfs        = "1";
    my $showhst       = "1";
    my $showverf      = "1";
    my $showkor       = "1";
    my $showswt       = "1";
    my $shownotation  = "1";
    my $showisbn      = "1";
    my $showissn      = "1";
    my $showsign      = "1";
    my $showmart      = "0";
    my $showhststring = "1";
    my $showejahr     = "1";
  
    my $userprofiles  = "";

    # Wurde bereits ein Profil bei einer vorangegangenen Suche ausgewaehlt?
    my $idnresult=$sessiondbh->prepare("select profile from sessionprofile where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    my $result=$idnresult->fetchrow_hashref();
  
    my $prevprofile="";
  
    if (defined($result->{'profile'})) {
        $prevprofile = decode_utf8($result->{'profile'});
    }
  
    if ($userid) {
        my $targetresult=$userdbh->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($userid) or $logger->error($DBI::errstr);
    
        my $result=$targetresult->fetchrow_hashref();
    
        $showfs        = decode_utf8($result->{'fs'});
        $showhst       = decode_utf8($result->{'hst'});
        $showverf      = decode_utf8($result->{'verf'});
        $showkor       = decode_utf8($result->{'kor'});
        $showswt       = decode_utf8($result->{'swt'});
        $shownotation  = decode_utf8($result->{'notation'});
        $showisbn      = decode_utf8($result->{'isbn'});
        $showissn      = decode_utf8($result->{'issn'});
        $showsign      = decode_utf8($result->{'sign'});
        $showmart      = decode_utf8($result->{'mart'});
        $showhststring = decode_utf8($result->{'hststring'});
        $showejahr     = decode_utf8($result->{'ejahr'});

        $targetresult->finish();

        $targetresult=$userdbh->prepare("select profilid, profilename from userdbprofile where userid = ? order by profilename") or $logger->error($DBI::errstr);
        $targetresult->execute($userid) or $logger->error($DBI::errstr);
    
        while (my $res=$targetresult->fetchrow_hashref()) {
            my $profilid    = decode_utf8($res->{'profilid'});
            my $profilename = decode_utf8($res->{'profilename'});

            my $profselected="";
            if ($prevprofile eq "user$profilid") {
                $profselected="selected=\"selected\"";
            }

            $userprofiles.="<option value=\"user$profilid\" $profselected>- $profilename</option>";
        }

        if ($userprofiles){
            $userprofiles="<option value=\"\">Gespeicherte Katalogprofile:</option><option value=\"\">&nbsp;</option>".$userprofiles."<option value=\"\">&nbsp;</option>";
        }
    
        $targetresult=$userdbh->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($userid) or $logger->error($DBI::errstr);
    
        $result=$targetresult->fetchrow_hashref();
    
        $targetresult->finish();
    }
  
    # CGI-Uebergabe
  
    my $fs            = $query->param('fs')        || ''; # Freie Suche
    my $verf          = $query->param('verf')      || '';
    my $hst           = $query->param('hst')       || '';
    my $hststring     = $query->param('hststring') || '';
    my $swt           = $query->param('swt')       || '';
    my $kor           = $query->param('kor')       || '';
    my $sign          = $query->param('sign')      || '';
    my $isbn          = $query->param('isbn')      || '';
    my $issn          = $query->param('issn')      || '';
    my $notation      = $query->param('notation')  || '';
    my $ejahr         = $query->param('ejahr')     || '';
    my $mart          = $query->param('mart')      || '';

    my $boolverf      = ($query->param('boolverf'))?$query->param('boolverf'):"AND";
    my $boolhst       = ($query->param('boolhst'))?$query->param('boolhst'):"AND";
    my $boolswt       = ($query->param('boolswt'))?$query->param('boolswt'):"AND";
    my $boolkor       = ($query->param('boolkor'))?$query->param('boolkor'):"AND";
    my $boolnotation  = ($query->param('boolnotation'))?$query->param('boolnotation'):"AND";
    my $boolisbn      = ($query->param('boolisbn'))?$query->param('boolisbn'):"AND";
    my $boolissn      = ($query->param('boolissn'))?$query->param('boolissn'):"AND";
    my $boolsign      = ($query->param('boolsign'))?$query->param('boolsign'):"AND";
    my $boolejahr     = ($query->param('boolejahr'))?$query->param('boolejahr'):"AND";
    my $boolfs        = ($query->param('boolfs'))?$query->param('boolfs'):"AND";
    my $boolmart      = ($query->param('boolmart'))?$query->param('boolmart'):"AND";
    my $boolhststring = ($query->param('boolhststring'))?$query->param('boolhststring'):"AND";
  
    my $queryid       = $query->param('queryid') || '';
  
    # Assoziierten View zur Session aus Datenbank holen
    $idnresult=$sessiondbh->prepare("select viewinfo.description from sessionview,viewinfo where sessionview.sessionid = ? and sessionview.viewname=viewinfo.viewname") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    $result=$idnresult->fetchrow_hashref();
  
    my $viewdesc = decode_utf8($result->{'description'}) if (defined($result->{'description'}));

    $idnresult->finish();
  

    if ($setmask) {
        my $idnresult=$sessiondbh->prepare("update sessionmask set masktype = ? where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($setmask,$sessionID) or $logger->error($DBI::errstr);
        $idnresult->finish();
    }
    else {
        my $idnresult=$sessiondbh->prepare("select masktype from sessionmask where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
        my $result=$idnresult->fetchrow_hashref();
        $setmask = decode_utf8($result->{'masktype'});
    
        $idnresult->finish();
    }

    my $hits;
    if ($queryid ne "") {
        my $idnresult=$sessiondbh->prepare("select query,hits from queries where queryid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($queryid) or $logger->error($DBI::errstr);
    
        my $result=$idnresult->fetchrow_hashref();
        my $query = decode_utf8($result->{'query'});
    
        $query=~s/"/&quot;/g;

        $hits = decode_utf8($result->{'hits'});

        ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$boolhst,$boolswt,$boolkor,$boolnotation,$boolisbn,$boolsign,$boolejahr,$boolissn,$boolverf,$boolfs,$boolmart,$boolhststring)=split('\|\|',$query);

        $idnresult->finish();
    }

    # Wenn Datenbanken uebergeben wurden, dann werden diese eingetragen
    if ($#databases >= 0) {
        my $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

        foreach my $thisdb (@databases) {
            $idnresult=$sessiondbh->prepare("insert into dbchoice values (?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$thisdb) or $logger->error($DBI::errstr);
        }
        $idnresult->finish;
    }

    # Erzeugung der database-Input Tags fuer die suche
    my $dbinputtags="";

    $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

    my $dbcount=0;
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $dbname = decode_utf8($result->{'dbname'});
        $dbinputtags.="<input type=\"hidden\" name=\"database\" value=\"$dbname\" />\n";
        $dbcount++; 
    }

    $idnresult=$sessiondbh->prepare("select count(dbname) as rowcount from dbinfo where active=1") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    my $res    = $idnresult->fetchrow_hashref;
    my $alldbs = $res->{rowcount};

    $idnresult=$sessiondbh->prepare("select sum(count) from titcount,dbinfo where  titcount.dbname=dbinfo.dbname and dbinfo.active=1") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);

    my $alldbcount=$idnresult->fetchrow();

    $idnresult->finish();

    if ($dbcount != 0) {
        my $profselected="";
        if ($prevprofile eq "dbauswahl") {
            $profselected="selected=\"selected\"";
        }
        $dbcount="<option value=\"dbauswahl\" $profselected>Aktuelle Katalogauswahl ($dbcount Datenbanken)</option><option value=\"\">&nbsp;</option>";
    }
    else {
        $dbcount="";
    }

    # Ausgabe der vorhandenen queries
    $idnresult=$sessiondbh->prepare("select * from queries where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    my $anzahl=$idnresult->rows();

    my $prevqueries="";

    while (my $result=$idnresult->fetchrow_hashref()) {
        my $queryid = decode_utf8($result->{'queryid'});
        my $query   = decode_utf8($result->{'query'});
        my $hits    = decode_utf8($result->{'hits'});
        
        my ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$boolhst,$boolswt,$boolkor,$boolnotation,$boolisbn,$boolsign,$boolejahr,$boolissn,$boolverf,$boolfs,$boolmart,$boolhststring)=split('\|\|',$query);
        
        $prevqueries.="<OPTION value=\"$queryid\">";
        
        $prevqueries.="FS: $fs " if ($fs);
        $prevqueries.="AUT: $verf " if ($verf);
        $prevqueries.="HST: $hst " if ($hst);
        $prevqueries.="SWT: $swt " if ($swt);
        $prevqueries.="KOR: $kor " if ($kor);
        $prevqueries.="NOT: $notation " if ($notation);
        $prevqueries.="SIG: $sign " if ($sign);
        $prevqueries.="EJAHR: $ejahr " if ($ejahr);
        $prevqueries.="ISBN: $isbn " if ($isbn);
        $prevqueries.="ISSN: $issn " if ($issn);
        $prevqueries.="MART: $mart " if ($mart);
        $prevqueries.="HSTR: $hststring " if ($hststring);
        $prevqueries.="= Treffer: $hits";
        $prevqueries.="</OPTION>";
    }

    $idnresult->finish();

    # TT-Data erzeugen
    my $ttdata={
        view          => $view,
        stylesheet    => $stylesheet,
        viewdesc      => $viewdesc,
        sessionID     => $sessionID,
        dbinputtags   => $dbinputtags,
        alldbs        => $alldbs,
        dbcount       => $dbcount,
        alldbcount    => $alldbcount,
        userprofiles  => $userprofiles,
        prevprofile   => $prevprofile,
        showfs        => $showfs,
        showhst       => $showhst,
        showverf      => $showverf,
        showkor       => $showkor,
        showswt       => $showswt,
        shownotation  => $shownotation,
        showisbn      => $showisbn,
        showissn      => $showissn,
        showsign      => $showsign,
        showmart      => $showmart,
        showhststring => $showhststring,
        showejahr     => $showejahr,
	      
        fs            => $fs,
        hst           => $hst,
        hststring     => $hststring,
        verf          => $verf,
        kor           => $kor,
        swt           => $swt,
        notation      => $notation,
        isbn          => $isbn,
        issn          => $issn,
        sign          => $sign,
        mart          => $mart,
        ejahr         => $ejahr,
	       
        anzahl        => $anzahl,
        prevqueries   => $prevqueries,
        useragent     => $useragent,
        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config        => \%config,
    };
  
    if ($setmask eq "simple") {
        OpenBib::Common::Util::print_page($config{tt_searchframe_simple_tname},$ttdata,$r);
    }
    else {
        OpenBib::Common::Util::print_page($config{tt_searchframe_tname},$ttdata,$r);
    }
  
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
}

1;
