#####################################################################
#
#  OpenBib::StartOpac
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

package OpenBib::StartOpac;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use POSIX;

use Digest::MD5;
use DBI;

use OpenBib::Common::Util();

use OpenBib::Config();

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {

  my $r=shift;

  my $query=Apache::Request->new($r);

  my $fs=$query->param('fs') || '';

  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  my $database=($query->param('database'))?$query->param('database'):'';
  my $view=($query->param('view'))?$query->param('view'):'';
  my $singleidn=$query->param('singleidn') || '';
  my $action=$query->param('action') || '';
  my $searchsingletit=$query->param('searchsingletit') || '';
  
  my $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh);

  
  # BEGIN View (Institutssicht)
  #
  ####################################################################
  # Wenn ein View aufgerufen wird, muss fuer die aktuelle Session
  # die Datenbankauswahl vorausgewaehlt und das Profil geaendert werden.
  ####################################################################
  
  
  if ($view ne ""){
    
    # 1. Gibt es diesen View?
    
    my $idnresult=$sessiondbh->prepare("select viewname from viewinfo where viewname='$view'");
    $idnresult->execute();
    my $anzahl=$idnresult->rows();
    
    if ($anzahl > 0){
      
      # 2. Datenbankauswahl setzen, aber nur, wenn der Benutzer selbst noch
      #    keine Auswahl getroffen hat
      
      $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid='$sessionID'");
      $idnresult->execute();
      my $anzahl=$idnresult->rows();
      
      # Wenn noch keine Datenbank ausgewaehlt wurde, dann setze die
      # Auswahl auf die zum View gehoerenden Datenbanken
      
      if ($anzahl == 0){
	$idnresult=$sessiondbh->prepare("select dbname from  viewdbs where viewname='$view'");
	$idnresult->execute();
	
	while (my $result=$idnresult->fetchrow_hashref()){
	  my $dbname=$result->{'dbname'};
	  my $idnresult2=$sessiondbh->prepare("insert into dbchoice (sessionid,dbname) values ('$sessionID','$dbname')");
	  $idnresult2->execute();
	  $idnresult2->finish();
	}
	
	
      }
      
      # 3. Assoziiere den View mit der Session (fuer Headframe/Merkliste);
      
      $idnresult=$sessiondbh->prepare("insert into sessionview values ('$sessionID','$view')");
      $idnresult->execute();
      
      
    }
    
    # Wenn es den View nicht gibt, dann wird gestartet wie ohne view
    else {
      $view="";
    }
    
    
    $idnresult->finish();
  }
  
  
  
  # Dann Ausgabe des neuen Headers
  
  my $headerframeurl="$config{headerframe_loc}?sessionID=$sessionID";
  my $searchframeurl="$config{searchframe_loc}?sessionID=$sessionID";
  
  my $toprows="140";
  
  if ($view ne ""){
    $headerframeurl.="&view=$view";
    $searchframeurl.="&view=$view";
    $toprows="175";
  }
  
  if ($searchsingletit ne '' && $database ne ''){
    $searchframeurl="$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&showvbu=0&casesensitive=0&hitrange=-1&database=$database&dbms=mysql&searchsingletit=$searchsingletit";
  }
  
  if ($fs ne ""){
    $searchframeurl="$config{virtualsearch_loc}?hitrange=-1&view=&sessionID=$sessionID&tosearch=In+allen+Katalogen+suchen&fs=$fs&bool9=AND&verf=&bool1=AND&hst=&bool2=AND&swt=&bool3=AND&kor=&bool4=AND&notation=&bool5=AND&isbn=&bool8=AND&issn=&bool6=AND&sign=&bool7=AND&ejahr=&ejahrop=%3D&maxhits=200&sorttype=author&sortorder=up&profil=";
  }

  print $r->send_http_header("text/html");

  print << "ENDE";
<HTML>
<link href="/images/openbib/favicon.ico" rel="shortcut icon">
<frameset rows="$toprows,*" frameborder=0>
<frame name="header" src="$headerframeurl" noresize >
<frame name="body" src="$searchframeurl">
</frameset>
</HTML>
ENDE

  $sessiondbh->disconnect();

  return OK;
}

1;
