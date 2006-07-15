#####################################################################
#
#  OpenBib::SearchFrame
#
#  Dieses File ist (C) 2001-2006 Oliver Flimm <flimm@openbib.org>
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
use Storable ();
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }
  
    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
  
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $sessionID = ($query->param('sessionID'))?$query->param('sessionID'):'';
    my @databases = ($query->param('database'))?$query->param('database'):();
    my $singleidn = $query->param('singleidn') || '';
    my $setmask   = $query->param('setmask') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

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
  
    my $searchquery_ref
        = OpenBib::Common::Util::get_searchquery($r);
    
    my $queryid       = $query->param('queryid') || '';
  
    my $viewdesc      = $config->get_viewdesc_from_viewname($view);

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
        $searchquery_ref = Storable::thaw(pack "H*",$result->{'query'});
        $hits            = decode_utf8($result->{'hits'});
#        $query=~s/"/&quot;/g;

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

    my $alldbs     = $config->get_number_of_dbs();
    my $alldbcount = $config->get_number_of_titles();

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

    my @queries=();

    while (my $result=$idnresult->fetchrow_hashref()) {
        push @queries, {
            id          => decode_utf8($result->{queryid}),
            searchquery => Storable::thaw(pack "H*",$result->{query}),
            hits        => decode_utf8($result->{hits}),
        };
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

        searchquery   => $searchquery_ref,
	       
        anzahl        => $anzahl,
        queries       => \@queries,
        useragent     => $useragent,
        config        => $config,
        msg           => $msg,
    };
  
    if ($setmask eq "simple") {
        OpenBib::Common::Util::print_page($config->{tt_searchframe_simple_tname},$ttdata,$r);
    }
    else {
        OpenBib::Common::Util::print_page($config->{tt_searchframe_tname},$ttdata,$r);
    }
  
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
}

1;
