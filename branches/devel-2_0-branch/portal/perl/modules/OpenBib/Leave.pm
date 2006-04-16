#####################################################################
#
#  OpenBib::Leave
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

package OpenBib::Leave;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;

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

    my $stylesheet = OpenBib::Common::Util::get_css_by_browsertype($r);
    my $sessionID  = $query->param('sessionID');
    my $lang       = $query->param('l')         || 'de';

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $userdbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd})
            or $logger->error_die($DBI::errstr);

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
  
    # Haben wir eine authentifizierte Session?
    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
    if ($userid) {
        # Authentifiziert-Status der Session loeschen
        my $userresult=$userdbh->prepare("delete from usersession where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        # Zwischengespeicherte Benutzerinformationen loeschen
        $userresult=$userdbh->prepare("update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        $userresult->finish();
    }
  
    # Zuallererst loeschen der Trefferliste fuer diese sessionID
    my $idnresult;

    $idnresult=$sessiondbh->prepare("delete from treffer where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    $idnresult=$sessiondbh->prepare("delete from queries where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    $idnresult=$sessiondbh->prepare("delete from searchresults where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    $idnresult=$sessiondbh->prepare("delete from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    $idnresult=$sessiondbh->prepare("delete from sessionmask where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    $idnresult=$sessiondbh->prepare("delete from sessionprofile where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    $idnresult->finish();
  
    # Kopieren ins sessionlog
  
    #  $idnresult=$sessiondbh->prepare("insert into sessionlog (sessionid,query,createtime) select session.sessionid,session.query,session.createtime from session where sessionid = ?)") or $logger->error($DBI::errstr);
    #  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    #  my $endtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());
  
    #  $idnresult=$sessiondbh->prepare("insert into sessionlog (endtime) values (?)  where sessionid = ?)") or $logger->error($DBI::errstr);
    #  $idnresult->execute($endtime,$sessionID) or $logger->error($DBI::errstr);
  
    #  $idnresult->finish();
  
    # Dann loeschen der Session in der Datenbank
  
    my $anzahlresult=$sessiondbh->prepare("delete from session where sessionid = ?") or $logger->error($DBI::errstr);
    $anzahlresult->execute($sessionID) or $logger->error($DBI::errstr);
    $anzahlresult->finish();
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        config     => \%config,
        msg        => $msg,
    };
  
    OpenBib::Common::Util::print_page($config{tt_leave_tname},$ttdata,$r);
  
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
}

1;
