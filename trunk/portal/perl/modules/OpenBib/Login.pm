#####################################################################
#
#  OpenBib::Login
#
#  Dieses File ist (C) 2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Login;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use POSIX;
use Socket;

use Digest::MD5;
use DBI;

use Template;

use OpenBib::Login::Util;
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

  # Standardwerte festlegen

  my $action=($query->param('action'))?$query->param('action'):'none';
  my $code=($query->param('code'))?$query->param('code'):'1';
  my $targetid=($query->param('targetid'))?$query->param('targetid'):'none';
  my $loginname=($query->param('loginname'))?$query->param('loginname'):'';
  my $password=($query->param('password'))?$query->param('password'):'';
  my $sessionID=$query->param('sessionID');
  my $view=$query->param('view')||'';
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $idnresult=$sessiondbh->prepare("select sessionid from session where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
  # Wenn wir nichts gefunden haben, dann ist etwas faul
  
  if ($idnresult->rows <= 0 || $sessionID eq ""){
    OpenBib::Common::Util::print_warning("SessionID ist ung&uuml;lltig",$r);

    $idnresult->finish();
    
    $sessiondbh->disconnect();
    $userdbh->disconnect();

    return OK;
  }
  
  if ($action eq "login"){
    
    my $targetresult=$userdbh->prepare("select * from logintarget order by type,description") or $logger->error($DBI::errstr);
    
    $targetresult->execute() or $logger->error($DBI::errstr);
    
    my $targetselect="<select name=\"targetid\">";
    while (my $result=$targetresult->fetchrow_hashref()){
      my $targetid=$result->{'targetid'};
      my $description=$result->{'description'};
      
      $targetselect.="<option value=\"$targetid\">$description</option>";
      
    }
    $targetselect.="</select>";
    $targetresult->finish();
    
    # TT-Data erzeugen
    
    my $ttdata={
		title      => 'KUG: Authentifizierung',
		stylesheet => $stylesheet,
                sessionID  => $sessionID,
		view       => $view,
		targetselect => $targetselect,
		loginname  => $loginname,
		show_corporate_banner => 0,
		show_foot_banner => 1,
                show_testsystem_info => 0,
		invisible_links => 0,
		config     => \%config,
	       };
    
    OpenBib::Common::Util::print_page($config{tt_login_tname},$ttdata,$r);
    
  }
  elsif ($action eq "auth"){
    my $loginfailed=0;
    
    if ($loginname eq "" || $password eq ""){
      $loginfailed=1;
    }
    
    my $targetresult=$userdbh->prepare("select * from logintarget where targetid = ?") or $logger->error($DBI::errstr);
    
    $targetresult->execute($targetid) or $logger->error($DBI::errstr);
    
    my $hostname="";
    my $port="";
    my $user="";
    my $db="";
    my $description="";
    my $type="";
  
    while (my $result=$targetresult->fetchrow_hashref()){
      $hostname=$result->{'hostname'};
      $port=$result->{'port'};
      $user=$result->{'user'};
      $db=$result->{'db'};
      $description=$result->{'description'};
      $type=$result->{'type'};
    }

    $targetresult->finish();
    
    if ($type eq "olws"){
      
      my $ruserinfo=OpenBib::Login::Util::authenticate_olws_user($loginname,$password,$hostname,$db);
      
      my %userinfo=%$ruserinfo;
      
      if ($userinfo{'erfolgreich'} ne "1"){
	$loginfailed=2;
      }
      
      # Gegebenenfalls Benutzer lokal eintragen
      else {

	my $userid;

	my $userresult=$userdbh->prepare("select userid from user where loginname = ?") or $logger->error($DBI::errstr);
	
	$userresult->execute($loginname) or $logger->error($DBI::errstr);
	
	# Eintragen, wenn noch nicht existent
	
	if ($userresult->rows <= 0){

	  # Neuen Satz eintragen
	  $userresult=$userdbh->prepare("insert into user values (NULL,'',?,?,'','','','','','','','','')") or $logger->error($DBI::errstr);
	  
	  $userresult->execute($loginname,$password) or $logger->error($DBI::errstr);

	}
	else {
	  $userid=$userresult->{'userid'};
	}


	# Benuzerinformationen eintragen

	$userresult=$userdbh->prepare("update user set nachname = ?, vorname = ?, soll = ?, gut = ?, avanz = ?, bsanz = ?, vmanz = ?, gebdatum = ? where loginname = ?") or $logger->error($DBI::errstr);
	
	$userresult->execute($userinfo{'Nachname'},$userinfo{'Vorname'},$userinfo{'Soll'},$userinfo{'Guthaben'},$userinfo{'Avanz'},$userinfo{'Bsanz'},$userinfo{'Vmanz'},$userinfo{'Geburtsdatum'},$loginname) or $logger->error($DBI::errstr);
	$userresult->finish();
      }
    }
    elsif ($type eq "self"){
      
      my $result=OpenBib::Login::Util::authenticate_self_user($loginname,$password,$userdbh,$sessionID);
      
      if ($result <= 0){
	$loginfailed=2;
      }
    }
    
    if (!$loginfailed){
      # Jetzt wird die Session mit der Benutzerid assoziiert
      
      my $userresult=$userdbh->prepare("select userid from user where loginname = ?") or $logger->error($DBI::errstr);
      
      $userresult->execute($loginname) or $logger->error($DBI::errstr);
      
      my $res=$userresult->fetchrow_hashref();
      
      my $userid=$res->{'userid'};
      
      # Es darf keine Session assoziiert sein. Daher stumpf loeschen
      
      my $globalsessionID="$config{servername}:$sessionID";
      $userresult=$userdbh->prepare("delete from usersession where sessionid = ?") or $logger->error($DBI::errstr);
      
      $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
      
      $userresult=$userdbh->prepare("insert into usersession values (?,?)") or $logger->error($DBI::errstr);
      
      $userresult->execute($globalsessionID,$userid) or $logger->error($DBI::errstr);
      
      # Ueberpruefen, ob der Benutzer schon ein Suchprofil hat
      
      $userresult=$userdbh->prepare("select userid from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
      
      $userresult->execute($userid) or $logger->error($DBI::errstr);
      
      # Falls noch keins da ist, eintragen
      if ($userresult->rows <= 0){
	$userresult=$userdbh->prepare("insert into fieldchoice values (?,1,1,1,1,1,1,1,1,1,1,0,1)") or $logger->error($DBI::errstr);
	$userresult->execute($userid) or $logger->error($DBI::errstr);
	
      }
      
      # Jetzt wird die bestehende Trefferliste uebernommen.
      
      # Gehe ueber alle Eintraege der Trefferliste
      
      my $idnresult=$sessiondbh->prepare("select * from treffer where sessionid = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      
      # Es gibt etwas zu uebertragen
      
      if ($idnresult->rows > 0){
	
	while (my $res=$idnresult->fetchrow_hashref()){
	  my $dbname=$res->{'dbname'};
	  my $singleidn=$res->{'singleidn'};
	  
	  # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
	  
	  $userresult=$userdbh->prepare("select userid from treffer where userid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
	  
	  $userresult->execute($userid,$dbname,$singleidn) or $logger->error($DBI::errstr);
	  
	  if ($userresult->rows <= 0){
	    
	    $userresult=$userdbh->prepare("insert into treffer values (?,?,?)") or $logger->error($DBI::errstr);
	    
	    $userresult->execute($userid,$dbname,$singleidn) or $logger->error($DBI::errstr);
	  }
	}
      }

      $idnresult->finish();
      $userresult->finish();
    }
    

    # Und nun wird ein komplett neue Frameset aufgebaut
    
    my $headerframeurl="http://$config{servername}$config{headerframe_loc}?sessionID=$sessionID";
    my $searchframeurl="http://$config{servername}$config{userprefs_loc}?sessionID=$sessionID&action=showfields";
    
    my $toprows="140";
    
    if ($view ne ""){
      $headerframeurl.="&view=$view";
      $searchframeurl.="&view=$view";
      $toprows="175";
    }
    
    # Fehlerbehandlung
    
    if ($loginfailed){
      $searchframeurl="http://$config{servername}$config{login_loc}?sessionID=$sessionID&action=loginfailed&code=$loginfailed";
    }
    
    my $ttdata={
		toprows    => $toprows,
		headerframeurl => $headerframeurl,
		searchframeurl => $searchframeurl,
		config     => \%config,
	       };
    
    OpenBib::Common::Util::print_page($config{tt_startopac_tname},$ttdata,$r);
    
  }
  elsif ($action eq "loginfailed"){
    if ($code eq "1"){
      OpenBib::Common::Util::print_warning('Sie haben entweder kein Passwort oder keinen Loginnamen eingegeben',$r);
    }
    elsif ($code eq "2"){
      OpenBib::Common::Util::print_warning('Sie konnten mit Ihrem angegebenen Benutzernamen und Passwort nicht erfolgreich authentifiziert werden',$r);
    }
    else {
      OpenBib::Common::Util::print_warning('Falscher Fehler-Code',$r);
    }
    
  }

  $idnresult->finish();
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();

  return OK;
}

1;
