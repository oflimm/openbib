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
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or die "could not connect";
  
  my $idnresult=$sessiondbh->prepare("select sessionid from session where sessionid='$sessionID'") or die "Error -- $DBI::errstr";
  $idnresult->execute();
  
  # Wenn wir nichts gefunden haben, dann ist etwas faul
  
  if ($idnresult->rows <= 0 || $sessionID eq ""){
    OpenBib::Common::Util::print_warning("SessionID ist ung&uuml;lltig",$r);
    exit;
  }
  
  if ($action eq "login"){
    
    my $targetresult=$userdbh->prepare("select * from logintarget order by type,description") or die "Error -- $DBI::errstr";
    
    $targetresult->execute();
    
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
    
    my $targetresult=$userdbh->prepare("select * from logintarget where targetid='$targetid'") or die "Error -- $DBI::errstr";
    
    $targetresult->execute();
    
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
    
    if ($type eq "slnp"){
      
      my $ruserinfo=OpenBib::Login::Util::authenticate_slnp_user($loginname,$password,$hostname,$port,$user,$db);
      
      my %userinfo=%$ruserinfo;
      
      if ($userinfo{'erfolgreich'} ne "1"){
	$loginfailed=2;
      }
      
      # Gegebenenfalls Benutzer lokal eintragen
      else {
	my $userresult=$userdbh->prepare("select userid from user where loginname='$loginname'") or die "Error -- $DBI::errstr";
	
	$userresult->execute();
	
	# Eintragen, wenn noch nicht existent
	
	if ($userresult->rows <= 0){
	  $userresult=$userdbh->prepare("insert into user values (NULL,'','$loginname','$password','')") or die "Error -- $DBI::errstr";
	  
	  $userresult->execute();
	  
	}
	
	#      my $res=$userresult->fetchrow_hashref();
	
	#      $userid=$res->{'userid'};
	
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
      
      my $userresult=$userdbh->prepare("select userid from user where loginname='$loginname'") or die "Error -- $DBI::errstr";
      
      $userresult->execute();
      
      my $res=$userresult->fetchrow_hashref();
      
      my $userid=$res->{'userid'};
      
      # Es darf keine Session assoziiert sein. Daher stumpf loeschen
      
      $userresult=$userdbh->prepare("delete from usersession where sessionid='$config{servername}:$sessionID'") or die "Error -- $DBI::errstr";
      
      $userresult->execute();
      
      $userresult=$userdbh->prepare("insert into usersession values ('$config{servername}:$sessionID','$userid')") or die "Error -- $DBI::errstr";
      
      $userresult->execute();
      
      # Ueberpruefen, ob der Benutzer schon ein Suchprofil hat
      
      $userresult=$userdbh->prepare("select userid from fieldchoice  where userid=$userid") or die "Error -- $DBI::errstr";
      
      $userresult->execute();
      
      # Falls noch keins da ist, eintragen
      if ($userresult->rows <= 0){
	$userresult=$userdbh->prepare("insert into fieldchoice values ($userid,1,1,1,1,1,1,1,1,1,1,1)") or die "Error -- $DBI::errstr";
	$userresult->execute();
	
      }
      
      # Jetzt wird die bestehende Trefferliste uebernommen.
      
      # Gehe ueber alle Eintraege der Trefferliste
      
      my $idnresult=$sessiondbh->prepare("select * from treffer where sessionid='$sessionID'");
      $idnresult->execute();
      
      # Es gibt etwas zu uebertragen
      
      if ($idnresult->rows > 0){
	
	while (my $res=$idnresult->fetchrow_hashref()){
	  my $dbname=$res->{'dbname'};
	  my $singleidn=$res->{'singleidn'};
	  
	  # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
	  
	  $userresult=$userdbh->prepare("select userid from treffer where userid=$userid and dbname='$dbname' and singleidn=$singleidn");
	  
	  $userresult->execute();
	  
	  if ($userresult->rows <= 0){
	    
	    $userresult=$userdbh->prepare("insert into treffer values ($userid,'$dbname',$singleidn)");
	    
	    $userresult->execute();
	  }
	}
      }
      
      
      $idnresult->finish();
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
      OpenBib::Common::Util::print_warning('Sie konnten mit Ihrem angegebenen Benutzernamen und Passwort nicht erfolgreicht authentifiziert werden',$r);
    }
    else {
    OpenBib::Common::Util::print_warning('Falscher Fehler-Code',$r);
  }
    
  }

  $sessiondbh->disconnect();
  $userdbh->disconnect();

  return OK;
}

1;
