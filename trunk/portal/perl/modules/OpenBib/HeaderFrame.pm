#####################################################################
#
#  OpenBib::HeaderFrame
#
#  Dies ist die Merkliste zum Katalog der BIBLIO-Distribution.
#
#  Dieses File ist (C) 2001-2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::HeaderFrame;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use POSIX;

use Digest::MD5;
use DBI;

use OpenBib::Common::Util;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
  my $r=shift;
  
  my $query=Apache::Request->new($r);
  
  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
  my $sessionID=$query->param('sessionID') || '';
  my $database=$query->param('database') || '';
  my $singleidn=$query->param('singleidn') || '';
  my $action=($query->param('action'))?$query->param('action'):'none';
  my $type=($query->param('type'))?$query->param('type'):'HTML';
  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen

  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or die "could not connect";
  
  # Assoziierten View zur Session aus Datenbank holen
  
  my $idnresult=$sessiondbh->prepare("select viewname from sessionview where sessionid='$sessionID'");
  $idnresult->execute();
  
  my $result=$idnresult->fetchrow_hashref();
  
  my $view=$result->{'viewname'} || '';
  
  my $viewdesc="";
  
  if ($view ne ""){
    $viewdesc="<tr><td colspan=3 align=left><img src=\"/images/openbib/views/$view.png\"></td></tr>";
  }

  # Haben wir eine authentifizierte Session?
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  
  # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
  # die Session nicht authentifiziert ist

  # Dementsprechend einen LoginLink oder ein ProfilLink ausgeben

  my $loginpreflink="<a href=\"$config{login_loc}?sessionID=$sessionID&view=$view&action=login\" target=\"body\">Login</a>&nbsp;&nbsp;";

  my $anzahl="";

  # Wenn wir authentifiziert sind, dann

  if ($userid){
    # Benutzerprofil-Link setzen
    
    $loginpreflink="<a href=\"$config{userprefs_loc}?sessionID=$sessionID&view=$view&action=showfields\" target=\"body\">Einstellungen</a>&nbsp;&nbsp;";
    
    # Anzahl Eintraege der privaten Merkliste bestimmen
    
    # Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
    
    my $idnresult=$userdbh->prepare("select * from treffer where userid=$userid");
    $idnresult->execute();
    $anzahl=$idnresult->rows();
    $idnresult->finish();
  }
  else {
    #  Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
  
    my $idnresult=$sessiondbh->prepare("select * from treffer where sessionid='$sessionID'");
    $idnresult->execute();
    $anzahl=$idnresult->rows();
    $idnresult->finish();
  }


  # Dann Ausgabe des neuen Headers
  
  OpenBib::Common::Util::print_simple_header("KUG - K&ouml;lner Universit&auml;tsGesamtkatalog",$r);

  print << "ENDE";
    <table  BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
	<tr>
	  <td ALIGN=LEFT>
	    <table><tr><td rowspan=2 valign=bottom><a target="_blank" href="http://kug.ub.uni-koeln.de/projekt/"><img SRC="/images/openbib/openbib-80pix.png" BORDER=0></a></td><td valign=bottom><img SRC="/images/openbib/koelner.virtueller-20pix.png" BORDER=0></td></tr><tr><td valign=top><img SRC="/images/openbib/institutsgesamtkatalog-20pix.png" BORDER=0></td></tr></table>
	    
	  </td>
	  
	  <td> &nbsp;&nbsp;</td>
	  
	  <td ALIGN=RIGHT>
	    <a target="_top" HREF="http://www.uni-koeln.de/"><img SRC="/images/openbib/gold.gif" height=95 BORDER=0></a>
	  </td>
	  
	</tr>

        $viewdesc

<tr><td align=left>&nbsp;&nbsp;<a href="$config{databasechoice_loc}?sessionID=$sessionID&view=$view" target="body">Katalogauswahl</a>&nbsp;&nbsp;<a href="$config{searchframe_loc}?sessionID=$sessionID&view=$view" target="body">Recherche</a>&nbsp;&nbsp;<a href="$config{virtualsearch_loc}?sessionID=$sessionID&trefferliste=choice&view=$view" target="body">Trefferliste</a>&nbsp;&nbsp;<a href="$config{managecollection_loc}?sessionID=$sessionID&action=show&view=$view" target="merkliste">Merkliste</a> [$anzahl]</td><td height=25>&nbsp;</td><td align=right>$loginpreflink<a href="/suchhilfe.html" target="body">Hilfe</a>&nbsp;&nbsp;<a href="$config{leave_loc}?sessionID=$sessionID&view=$view" target="_parent">Sitzung beenden</a>&nbsp;</td></tr>
    </table>
  </body>
</html>

ENDE

  $sessiondbh->disconnect();
  $userdbh->disconnect();

  return OK;
}

1;
