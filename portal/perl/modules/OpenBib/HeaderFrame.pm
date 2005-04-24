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

use Log::Log4perl qw(get_logger :levels);

use POSIX;

use Digest::MD5;
use DBI;

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
  
  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
  my $sessionID=$query->param('sessionID') || '';
  my $database=$query->param('database') || '';
  my $singleidn=$query->param('singleidn') || '';
  my $action=($query->param('action'))?$query->param('action'):'none';
  my $type=($query->param('type'))?$query->param('type'):'HTML';
  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen

  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  # Assoziierten View zur Session aus Datenbank holen
  
  my $idnresult=$sessiondbh->prepare("select viewname from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
  my $result=$idnresult->fetchrow_hashref();
  
  $idnresult->finish();

  my $view=$result->{'viewname'} || '';

  # Haben wir eine authentifizierte Session?
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  
  # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
  # die Session nicht authentifiziert ist

  # Dementsprechend einen LoginLink oder ein ProfilLink ausgeben

  my $anzahl="";

  # Wenn wir authentifiziert sind, dann

  my $username="";

  if ($userid){
    $username=OpenBib::Common::Util::get_username_for_userid($userdbh,$userid);

    # Anzahl Eintraege der privaten Merkliste bestimmen
    
    # Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
    
    my $idnresult=$userdbh->prepare("select * from treffer where userid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($userid) or $logger->error($DBI::errstr);
    $anzahl=$idnresult->rows();
    $idnresult->finish();
  }
  else {
    #  Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
  
    my $idnresult=$sessiondbh->prepare("select * from treffer where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    $anzahl=$idnresult->rows();
    $idnresult->finish();
  }

  $sessiondbh->disconnect();
  $userdbh->disconnect();

  my $template = Template->new({ 
				INCLUDE_PATH  => $config{tt_include_path},
				#    	    PRE_PROCESS   => 'config',
				OUTPUT        => $r,     # Output geht direkt an Apache Request
			       });

  # TT-Data erzeugen

  my $ttdata={
	      title      => 'KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
	      stylesheet   => $stylesheet,
	      view         => $view,
	      sessionID    => $sessionID,

	      username         => $username,
	      anzahl       => $anzahl,

	      show_foot_banner      => 0,

	      config       => \%config,
	     };
  
  # Dann Ausgabe des neuen Headers
  
  print $r->send_http_header("text/html");
  
  $template->process($config{tt_headerframe_tname}, $ttdata) || do { 
    $r->log_reason($template->error(), $r->filename);
    return SERVER_ERROR;
  };

  return OK;
}

1;
