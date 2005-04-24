####################################################################
#
#  OpenBib::DatabaseProfile
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

package OpenBib::DatabaseProfile;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use DBI;

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
  
  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  my @databases=($query->param('database'))?$query->param('database'):();
  my $action=($query->param('action'))?$query->param('action'):'';
  
  # CGI-Uebergabe
  
  my $newprofile=$query->param('newprofile') || '';
  my $profilid=$query->param('profilid') || '';
  
  my %checkeddb;
  
  my %fak=(
	   "1wiso", "Wirtschafts- u. Sozialwissenschaftliche Fakult&auml;t",
	   "2recht","Rechtswissenschaftliche Fakult&auml;t",
	   "3ezwheil","Erziehungswissenschaftliche u. Heilp&auml;dagogische Fakult&auml;t",
	   "4phil","Philosophische Fakult&auml;t",
	   "5matnat","Mathematisch-Naturwissenschaftliche Fakult&auml;t",
	   "0ungeb","Fakult&auml;tsungebunden"
	   );

  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
  }

  # Authorisierte Session?
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  unless($userid){
    OpenBib::Common::Util::print_warning("Sie haben sich nicht authentifiziert.",$r);
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
  }

  my $idnresult="";

  #####################################################################   
  # Anzeigen der Profilmanagement-Seite
  #####################################################################   

  if ($action eq "show" || $action eq "Profil anzeigen"){
    my $profilname="";
    
    if ($profilid){
      
      # Zuerst Profil-Description zur ID holen
      
      $idnresult=$userdbh->prepare("select profilename from userdbprofile where profilid = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($profilid) or $logger->error($DBI::errstr);
      
      my $result=$idnresult->fetchrow_hashref();
      
      $profilname=$result->{'profilename'};
      
      $idnresult=$userdbh->prepare("select dbname from profildb where profilid = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($profilid) or $logger->error($DBI::errstr);
      while (my $result=$idnresult->fetchrow_hashref()){
	my $dbname=$result->{'dbname'};
	$checkeddb{$dbname}="checked";    
      }
      $idnresult->finish();
    }
    
    my $profilemanagement="";
    
    my $profilselect="<select title=\"W&auml;hlen Sie ein anzuzeigendes oder zu l&ouml;schendes Profil aus\" name=\"profilid\">";
    my $profilresult=$userdbh->prepare("select profilid, profilename from userdbprofile where userid = ? order by profilename") or $logger->error($DBI::errstr);
    $profilresult->execute($userid) or $logger->error($DBI::errstr);
    while (my $res=$profilresult->fetchrow_hashref()){
      my $profilid=$res->{'profilid'};
      my $profilename=$res->{'profilename'};
      $profilselect.="<option value=\"$profilid\">$profilename</option>";
    } 
    $profilresult->finish();
    $profilselect.="</select>";
    
    
    $profilemanagement=<< "PROFIL";
<p>
<table width="100%">
<tr><th>Profilmanagement</th></tr>
<tr><td class="boxed">
<table>
<tr><td align=left><input type="text" title="Falls leer, so geben Sie hier bitte einen neuen Profilnamen ein" name="newprofile" value="$profilname" SIZE=30 MAXLENGTH=200></td><td align=left><INPUT type=submit title="Abspeicherung eines neuen oder bestehenden Profils" name="action" value="Profil speichern"></td><td></td><td width="90%">&nbsp;</td></tr>
<tr><td align=left>$profilselect</td><td align=left><INPUT type=submit title="Anzeige des ausgew&auml;hlten Profils" name="action" value="Profil anzeigen"></td><td><INPUT type=submit title="L&ouml;schung des ausgew&auml;hlten Profils " name="action" value="Profil l&ouml;schen"></td><td></td></tr>
<tr><td colspan="4"></td></tr>
<tr><td colspan="4" align=left>Definieren Sie oder bearbeiten Sie hier Ihre individuellen Katalogprofile. Diese werden gespeichert und stehen daher auch beim n&auml;chten Anmelden wieder zu Ihrer Verf&uuml;gung. Um ein hier definiertes Katalogprofil zu nutzen, w&auml;hlen Sie es in der Recherchemaske einfach unter <b>Suchprofil</b> aus und aktivieren zur Suche dann <b>In ausgew&auml;hlten Katalogen suchen</b>.
</td></tr>
</table>
</td></tr>
</table>
PROFIL

    OpenBib::Common::Util::print_simple_header("KUG: Datenbank-Profile",$r,$stylesheet);

    my $targettype=OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID);

    my $useraccountstring="";

    if ($targettype ne "self"){
      $useraccountstring="<li><a href=\"http://$config{servername}$config{circulation_loc}?sessionID=$sessionID;action=showcirc\">Benutzerkonto</a></li>";
    }

    print << "NAVI";
<ul id="tabbingmenu">
   <li><a href="http://$config{servername}$config{userprefs_loc}?sessionID=$sessionID&action=showfields" target="body">Grundeinstellungen</a></li>
   $useraccountstring
   <li><a class="active" href="http://$config{servername}$config{databaseprofile_loc}?sessionID=$sessionID&action=show" target="body">Katalogprofile</a></li>
</ul>

<div id="content">

<p>
<p>
NAVI



    if ($profilname){
      $profilemanagement.="<p>\nDerzeit angezeigtes Profil: <b>$profilname</b>\n<p>\n";
    }

    print << "HEAD";
<script language="JavaScript">
<!--

function update_fak(yourform, checked, fak) {
    for (var i = 0; i < yourform.elements.length; i++) {
         if (yourform.elements[i].id.indexOf(fak) != -1) {
              yourform.elements[i].checked = checked;
         }
    }
}

// -->
</script>

<FORM method="get" action="http://$config{servername}$config{databaseprofile_loc}">
<INPUT type=hidden name=hitrange value=-1>
<INPUT type=hidden name=sessionID value=$sessionID>

$profilemanagement
<p>
<table>

HEAD

    my $lastfakult="";
    my $count=0;
    
    my %stype;
    print "<TR><TD colspan=9 align=left bgcolor=lightblue><input type=\"checkbox\" name=\"fakult\" value=\"inst\" onclick=\"update_fak(this.form, this.checked,'inst')\" /><B>Alle Kataloge</B></TD></TR>\n";
  
    $idnresult=$sessiondbh->prepare("select * from dbinfo where active=1 order by faculty ASC, description ASC") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    
    while (my $result=$idnresult->fetchrow_hashref){
      
      my $fakult=$result->{'faculty'};
      my $name=$result->{'description'};
      my $systemtype=$result->{'system'};
      my $pool=$result->{'dbname'};
      my $sigel=$result->{'sigel'};
      
      # Spezielle Sigel umbiegen - Spaeter Eintrag des URLs in die DB geplant
      if ($sigel eq "301"){
	$sigel="ezw";
      }
      elsif ($sigel eq "998"){
	$sigel="bibfuehrer";
      }
      
      #    my ($dbid,$fakult,$name,$systemtype,$pool,$sigel)=@result;  
    
      
      if ($systemtype eq "a"){
	$stype{$pool}="yellow";
      }
      elsif ($systemtype eq "b"){
	$stype{$pool}="red";
      }
      elsif ($systemtype eq "l"){
	$stype{$pool}="green";
      }
      elsif ($systemtype eq "s"){
	$stype{$pool}="blue";
      }
      
      
      my $fakultpools="inst".substr($fakult,0,1);
      
      if ($fakult ne $lastfakult){
	
	# Tabelle aus vorherigen Durchgang muss geschlossen werden.
	
	if ($count%3 == 1){
	  print "  <TD></TD><TD></TD>\n  <TD></TD><TD></TD>\n</TR>\n";
	}
	elsif ($count%3 == 2){
	  print "  <TD></TD><TD></TD>\n</TR>\n";
	}
	# Ueberschriftszeilt mit Fakultaet ausgeben
	print "<TR><TD colspan=9></TD></TR>\n";
	print "<TR><TD colspan=9 align=left bgcolor=lightblue><input type=\"checkbox\" name=\"fakult\" value=\"$fakultpools\" onclick=\"update_fak(this.form, this.checked,'$fakultpools')\" id=\"inst\"/><B>".$fak{$fakult}."</B></TD></TR>\n";
	print "<TR><TD colspan=9></TD></TR>\n";
	# Wieder links mit Tabelle anfangen.
	
	$count=0;
      }
    
      $lastfakult=$fakult;
      
      my $checked="";
      
      if (defined $checkeddb{$pool}){
	$checked="checked";
      }
      if ($count%3 == 0){
	print "<TR>\n  <TD><INPUT type=checkbox name=database value=$pool id=\"$fakultpools\" $checked><TD bgcolor=".$stype{$pool}.">&nbsp;</TD><TD><a href=\"http://www.ub.uni-koeln.de/dezkat/bibinfo/$sigel.html\" target=_blank>$name</a></TD>\n";
      }
      elsif ($count%3 == 1) {
	print "  <TD><INPUT type=checkbox name=database value=$pool id=\"$fakultpools\" $checked><TD bgcolor=".$stype{$pool}.">&nbsp;</TD><TD><a href=\"http://www.ub.uni-koeln.de/dezkat/bibinfo/$sigel.html\" target=_blank>$name</a></TD>\n";
      }
      elsif ($count%3 == 2){
	print "  <TD><INPUT type=checkbox name=database value=$pool id=\"$fakultpools\" $checked><TD bgcolor=".$stype{$pool}.">&nbsp;</TD><TD><a href=\"http://www.ub.uni-koeln.de/dezkat/bibinfo/$sigel.html\" target=_blank>$name</a></TD>\n</TR>\n";
      }
      $count++;
    }
    
    $idnresult->finish();
    
    $sessiondbh->disconnect();
  
    
    if ($count%3 == 1){
      print "<TD></TD><TD></TD></TR>\n";
    }
    elsif ($count%3 == 2){
      print "<TD></TD></TR>\n";
    }
    
    print << "ENDE";
</TABLE>
</FORM>
</div>
<p>

ENDE
    OpenBib::Common::Util::print_footer();

  }

  #####################################################################   
  # Abspeichern eines Profils
  #####################################################################   

  elsif ($action eq "Profil speichern"){
    
    # Wurde ueberhaupt ein Profilname eingegeben?
    
    if (!$newprofile){
      OpenBib::Common::Util::print_warning("Sie haben keinen Profilnamen eingegeben!",$r);
      return OK;
    }

    my $profilresult=$userdbh->prepare("select profilid from userdbprofile where userid = ? and profilename = ?") or $logger->error($DBI::errstr);
    $profilresult->execute($userid,$newprofile) or $logger->error($DBI::errstr);
    
    my $numrows=$profilresult->rows;
    
    my $profilid="";
    
    # Wenn noch keine Profilid (=kein Profil diesen Namens)
    # existiert, dann wird eins erzeugt.
    
    if ($profilresult->rows <= 0){
      
      my $profilresult2=$userdbh->prepare("insert into userdbprofile values (NULL,?,?)") or $logger->error($DBI::errstr);
      
      $profilresult2->execute($newprofile,$userid) or $logger->error($DBI::errstr);
      $profilresult2=$userdbh->prepare("select profilid from userdbprofile where userid = ? and profilename = ?") or $logger->error($DBI::errstr);
      
      $profilresult2->execute($userid,$newprofile) or $logger->error($DBI::errstr);
      my $res=$profilresult2->fetchrow_hashref();
      $profilid=$res->{'profilid'};
      
      $profilresult2->finish();
    }
    else {
      my $res=$profilresult->fetchrow_hashref();
      $profilid=$res->{'profilid'};
    }
    
    # Jetzt habe ich eine profilid und kann Eintragen
    
    # Auswahl wird immer durch aktuelle ueberschrieben. 
    
    # Daher erst potentiell loeschen
    
    $profilresult=$userdbh->prepare("delete from profildb where profilid = ?") or $logger->error($DBI::errstr);
    
    $profilresult->execute($profilid) or $logger->error($DBI::errstr);
    

    my $database;
    foreach $database (@databases){
      
      # ... und dann eintragen
      
      my $profilresult=$userdbh->prepare("insert into profildb (profilid,dbname) values (?,?)") or $logger->error($DBI::errstr);
      
      $profilresult->execute($profilid,$database) or $logger->error($DBI::errstr);
      $profilresult->finish();
    }
    
    $r->internal_redirect("http://$config{servername}$config{databaseprofile_loc}?sessionID=$sessionID&action=show");

  }

  #####################################################################   
  # Loeschen eines Profils
  #####################################################################   

  elsif ($action eq "Profil löschen"){
    my $profilresult=$userdbh->prepare("delete from userdbprofile where userid = ? and profilid = ?") or $logger->error($DBI::errstr);
    $profilresult->execute($userid,$profilid) or $logger->error($DBI::errstr);
    
    $profilresult=$userdbh->prepare("delete from profildb where profilid = ?") or $logger->error($DBI::errstr);
    $profilresult->execute($profilid) or $logger->error($DBI::errstr);
    
    $profilresult->finish();
    
    $r->internal_redirect("http://$config{servername}$config{databaseprofile_loc}?sessionID=$sessionID&action=show");
    
  }

  #####################################################################   
  # ... andere Aktionen sind nicht erlaubt
  #####################################################################   

  else {
    OpenBib::Common::Util::print_warning("Keine g&uuml;ltige Aktion",$r);
  }

  $sessiondbh->disconnect();
  $userdbh->disconnect();
  
  return OK;
}

1;
