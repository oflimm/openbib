#####################################################################
#
#  OpenBib::DatabaseChoice
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

package OpenBib::DatabaseChoice;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

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
  
  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  my @databases=($query->param('database'))?$query->param('database'):();
  my $singleidn=$query->param('singleidn') || '';
  my $action=($query->param('action'))?$query->param('action'):'';
  
  # CGI-Uebergabe
  
  my $verf=$query->param('verf') || '';
  my $hst=$query->param('hst') || '';
  my $swt=$query->param('swt') || '';
  my $kor=$query->param('kor') || '';
  my $sign=$query->param('sign') || '';
  my $isbn=$query->param('isbn') || '';
  my $issn=$query->param('issn') || '';
  my $notation=$query->param('notation') || '';
  my $ejahr=$query->param('ejahr') || '';
  my $bool1=$query->param('bool1') || '';
  my $bool2=$query->param('bool2') || '';
  my $bool3=$query->param('bool3') || '';
  my $bool4=$query->param('bool4') || '';
  my $bool5=$query->param('bool5') || '';
  my $bool6=$query->param('bool6') || '';
  my $bool7=$query->param('bool7') || '';
  my $queryid=$query->param('queryid') || '';
  
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
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or die "could not connect";
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
      
    $sessiondbh->disconnect();
    $userdbh->disconnect();
      
    return OK;
  }
    
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);

  my $idnresult="";
  
  if ($sessionID ne ""){
    
    # Wenn Kataloge ausgewaehlt wurden
    if ($action eq "Kataloge auswählen"){
      
      # Zuerst die bestehende Auswahl loeschen
      
      $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid='$sessionID'");
      $idnresult->execute();
      
      # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
      my $database;
      foreach $database (@databases){
	$idnresult=$sessiondbh->prepare("insert into dbchoice (sessionid,dbname) values ('$sessionID','$database')");
	$idnresult->execute();
      }
      
      $idnresult->finish();
      
      $r->internal_redirect("http://$config{servername}$config{searchframe_loc}?sessionID=$sessionID");
      
    }
    
    # ... sonst anzeigen
    else {
      $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid='$sessionID'");
      $idnresult->execute();
      while (my $result=$idnresult->fetchrow_hashref()){
	my $dbname=$result->{'dbname'};
	$checkeddb{$dbname}="checked";
      }
      $idnresult->finish();
      
      OpenBib::Common::Util::print_simple_header("Datenbankauswahl",$r);
      
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

<FORM method="get" action="http://$config{servername}$config{databasechoice_loc}">
<INPUT type=hidden name=hitrange value=-1>
<INPUT type=hidden name=sessionID value=$sessionID>

<table BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
  <tr bgcolor="lightblue">
    <td  width="20">&nbsp;</td><td valign="middle" ALIGN=left height="32"><img src="/images/kvik/katalogauswahl.png" alt="Katalogauswahl"></td>
  </tr>
</table>
<p>
<table width="100%">
<tr><th>Hinweis</th></tr>
<tr><td class="boxedclear" style="font-size:9pt">
Auf dieser Seite k&ouml;nnen Sie einzelne Kataloge als Suchziel ausw&auml;hlen. Bei aktiviertem JavaScript reicht ein Klick auf das Schaltelement einer &uuml;bergeordneten hellblau hinterlegten Kategorie, um alle zugeh&ouml;rigen Kataloge automatisch auszuw&auml;hlen<p>
Nachdem Sie Ihre Auswahl getroffen haben aktivieren Sie bitte <b>Kataloge ausw&auml;hlen</b>. Sie springen dann auf die Rechercheseite und k&ouml;nnen Ihre Suchbegriffe eingeben. Ihre gerade getroffene Datenbankauswahl ist unter <b>Suchprofil</b> vorausgew&auml;hlt. Nun m&uuml;ssen Sie nur noch auf <b>In ausgew&auml;hlten Katalogen suchen</b> klicken, um in den ausgew&auml;hlten Datenbanken zu recherchieren.
</td></tr>
</table>
<p>
<INPUT type=submit name="action" value="Kataloge ausw&auml;hlen">&nbsp;<INPUT type=reset value="Urspr&uuml;ngliche Auswahl wiederherstellen">
<p>
<table>
HEAD

      my $lastfakult="";
      my $count=0;
      
      my %stype;
      print "<TR><TD colspan=9 align=left bgcolor=lightblue><input type=\"checkbox\" name=\"fakult\" value=\"inst\" onclick=\"update_fak(this.form, this.checked,'inst')\" /><B>Alle Kataloge</B></TD></TR>\n";
	    
      $idnresult=$sessiondbh->prepare("select * from dbinfo where active=1 order by faculty ASC, description ASC");
      $idnresult->execute();
	    
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
		<p>
		<INPUT type=submit name="action" value="Kataloge ausw&auml;hlen">&nbsp;<INPUT type=reset value="Urspr&uuml;ngliche Auswahl wiederherstellen">
		</FORM>
		<p>
ENDE
      OpenBib::Common::Util::print_footer();
    }
  }
  else {
    OpenBib::Common::Util::print_warning("Sie haben keine gueltige Session.",$r);
  }
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  
  return OK;
}

1;
