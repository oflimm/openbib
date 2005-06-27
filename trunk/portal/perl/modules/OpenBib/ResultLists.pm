####################################################################
#
#  OpenBib::ResultLists.pm
#
#  Dieses File ist (C) 2003-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::ResultLists;

use Apache::Constants qw(:common);

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use DBI;

use OpenBib::Common::Util;
use OpenBib::ResultLists::Util;
use OpenBib::Common::Stopwords;

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
  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  # CGI-Input auslesen
  
  my $sorttype=($query->param('sorttype'))?$query->param('sorttype'):"author";
  my $sortall=($query->param('sortall'))?$query->param('sortall'):'0';
  my $sortorder=($query->param('sortorder'))?$query->param('sortorder'):'up';
  my $trefferliste=$query->param('trefferliste') || '';
  my $autoplus=$query->param('autoplus') || '';
  my $queryid=$query->param('queryid') || '';
  my $view=$query->param('view') || '';

  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
    goto LEAVEPROG;
  }

  # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
  my $dbinforesult=$sessiondbh->prepare("select dbname,url,description from dbinfo") or $logger->error($DBI::errstr);
  $dbinforesult->execute() or $logger->error($DBI::errstr);
  
  my %dbases=();
  my %dbnames=();
  
  while (my $result=$dbinforesult->fetchrow_hashref()){
    my $dbname=$result->{'dbname'};
    my $url=$result->{'url'};
    my $description=$result->{'description'};
    
    # Wenn ein URL fuer die Datenbankinformation definiert ist, dann wird
    # damit verlinkt
    
    if ($url ne ""){
      $dbases{"$dbname"}="<a href=\"$url\" target=_blank>$description</a>";
    }
    else {
      $dbases{"$dbname"}="$description";
    }
    $dbnames{"$dbname"}=$description;
  }
  
  $dbinforesult->finish();

  # BEGIN Trefferliste
  #
  ####################################################################
  # Wenn die Trefferlistenfunktion ausgewaehlt wurde, dann ...
  ####################################################################
  
  if ($trefferliste){
    my $idnresult=$sessiondbh->prepare("select sessionid from searchresults where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    
    if ($idnresult->rows <= 0){
      OpenBib::Common::Util::print_warning("Derzeit existiert (noch) keine Trefferliste",$r);
      $idnresult->finish();
      goto LEAVEPROG;
    }
    
    ####################################################################
    # ... falls die Auswahlseite angezeigt werden soll
    ####################################################################
    
    if ($trefferliste eq "choice"){
      
      my @queryids=();
      my @querystrings=();
      my @queryhits=();
      
      $idnresult=$sessiondbh->prepare("select distinct searchresults.queryid,queries.query,queries.hits from searchresults,queries where searchresults.sessionid = ? and searchresults.queryid=queries.queryid order by queryid desc") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      
      while (my @res=$idnresult->fetchrow){
	push @queryids, $res[0];
	push @querystrings, $res[1];
	push @queryhits, $res[2];
      }
      
      my $thisqueryid="";
      my $thisqueryidx=0;
      
      if ($queryid eq ""){
	$thisqueryid=$queryids[0];
      }
      else{
	my $i=0;
	while ($i <= $#queryids){
	  if ($queryids[$i] eq "$queryid"){
	    $thisqueryidx=$i;
	  }
	  $i++
	}	
	$thisqueryid=$queryid;
      }
      
      my ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$bool1,$bool2,$bool3,$bool4,$bool5,$bool6,$bool7,$bool8,$bool9,$bool10,$bool11,$bool12)=split('\|\|',$querystrings[$thisqueryidx]);
      
      $idnresult=$sessiondbh->prepare("select dbname,hits from searchresults where sessionid = ? and queryid = ? order by hits desc") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$thisqueryid) or $logger->error($DBI::errstr);
      
      # Header mit allen Elementen ausgeben
      
      OpenBib::Common::Util::print_simple_header("Such-Client des Virtuellen Katalogs",$r);
      
      print << "HEADER";
<FORM METHOD="GET">

<ul id="tabbingmenu">
   <li><a class="active" href="$config{resultlists_loc}?sessionID=$sessionID;trefferliste=choice;view=$view">Trefferliste</a></li>
</ul>

<div id="content">

<p>
HEADER
      
      #      print "<h1>Direkt aus dem Cache</h1>";
      
      print "<table width=\"100%\"><tr>";
      
      #    print "Lastqueryid: $lastqueryid<p>";
      if ($queryid eq ""){
	print "<th>Aktuelle Recherche</th>";
      }   
      else {
	print "<th>Ausgew&auml;hlte Recherche</th>";
      }
      
      print "</tr><td class=\"boxedclear\"><table><tr><td colspan=\"2\">";
      
      print "(";
      print "&nbsp;FS: $fs " if ($fs);
      print "&nbsp;AUT: $verf " if ($verf);
      print "&nbsp;HST: $hst " if ($hst);
      print "&nbsp;SWT: $swt " if ($swt);
      print "&nbsp;KOR: $kor " if ($kor);
      print "&nbsp;NOT: $notation " if ($notation);
      print "&nbsp;SIG: $sign " if ($sign);
      print "&nbsp;EJAHR: $ejahr " if ($ejahr);
      print "&nbsp;ISBN: $isbn " if ($isbn);
      print "&nbsp;ISSN: $issn " if ($issn);
      print "&nbsp;MART: $mart " if ($mart);
      print "&nbsp;HSTR: $hststring " if ($hststring);
      
      #    print "= Treffer: $hits" if ($hits);
      print ")</td></tr><tr><td colspan=\"2\"></td></tr>";
      
      
      my $linecolor="aliceblue";
      my $hitcount=0;
      
      my $resultrow="";
      while (my @res=$idnresult->fetchrow){
	
	$resultrow.="<tr><td bgcolor=\"$linecolor\"><a href=\"$config{resultlists_loc}?sessionID=$sessionID&trefferliste=$res[0]&queryid=$thisqueryid\"><b>$dbnames{$res[0]}</b></a></td><td align=right>$res[1]</td></tr>\n";
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
	$hitcount+=$res[1];
      }
      
      
      print "<tr><td>Katalog</td><td>Treffer</td></tr>\n";
      
      print "<tr><td bgcolor=\"aliceblue\"><a href=\"$config{resultlists_loc}?sessionID=$sessionID&trefferliste=all&sortall=0&sorttype=author&queryid=$thisqueryid\"><b>Alle Treffer</b></a></td><td align=right>$hitcount</td></tr>\n";
      
      print "<tr><td bgcolor=\"white\">&nbsp;</td><td align=right>&nbsp;</td></tr>\n";
      
      print $resultrow;
      
      print "</table></td></tr></table>\n";
      
      $idnresult->finish();
      
      
      if ($queryid eq ""){

	# Weitere Trefferlisten zu alten Recherchen vorhanden?
	
	if ($#queryids > 0){
	  
	  
	  print "<form method=\"get\" action=\"$config{virtualsearch_loc}\">";
	  print "<input type=\"hidden\" name=\"sessionID\" value=\"$sessionID\">";
	  print "<input type=\"hidden\" name=\"trefferliste\" value=\"choice\">";
	  
	  print "<p><table width=\"100%\"><tr>";
	  print "<th>&Auml;ltere Recherchen</th></tr><tr><td class=\"boxedclear\">";
	  
	  print "<select name=\"queryid\">";
	  
	  my $i=1;
	  
	  while ($i <= $#queryids){
	    
	    my ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$bool1,$bool2,$bool3,$bool4,$bool5,$bool6,$bool7,$bool8,$bool9,$bool10,$bool11,$bool12)=split('\|\|',$querystrings[$i]);
	    
	    print "<OPTION value=\"".$queryids[$i]."\">";
	    print "(";
	    print "&nbsp;FS: $fs " if ($fs);
	    print "&nbsp;AUT: $verf " if ($verf);
	    print "&nbsp;HST: $hst " if ($hst);
	    print "&nbsp;SWT: $swt " if ($swt);
	    print "&nbsp;KOR: $kor " if ($kor);
	    print "&nbsp;NOT: $notation " if ($notation);
	    print "&nbsp;SIG: $sign " if ($sign);
	    print "&nbsp;EJAHR: $ejahr " if ($ejahr);
	    print "&nbsp;ISBN: $isbn " if ($isbn);
	    print "&nbsp;ISSN: $issn " if ($issn);
	    print "&nbsp;MART: $mart " if ($mart);
	    print "&nbsp;HSTR: $hststring " if ($hststring);
	    print "= Treffer: $queryhits[$i])" if ($queryhits[$i]);
	    print "</OPTION>\n";
	    
	    $i++;
	  }
	  print "</select>\n";
	  print "<input type=submit value=\"Auswahl\"></td></tr></table></form>";
	}
      }
      print "</table></div><p />";
      OpenBib::Common::Util::print_footer();
      
      goto LEAVEPROG;
      
    }
    
    ####################################################################
    # ... falls alle Treffer zu einer queryid angezeigt werden sollen
    ####################################################################
    
    elsif ($trefferliste eq "all"){
      
      # Erst am Ende der Anfangsrecherche wird die queryid erzeugt. Damit ist
      # sie noch nicht vorhanden, wenn am Anfang der Seite die Sortierungs-
      # funktionalitaet bereitgestellt wird. Wenn dann ohne queryid
      # die Trefferliste sortiert werden soll, dann muss zuerst die 
      # queryid bestimmt werden. Die betreffende ist die letzte zur aktuellen
      # sessionid
      
      if ($queryid eq ""){
	
	$idnresult=$sessiondbh->prepare("select max(queryid) from queries where sessionid = ?") or $logger->error($DBI::errstr);
	$idnresult->execute($sessionID) or $logger->error($DBI::errstr);
	
	my @res=$idnresult->fetchrow;
	$queryid=$res[0];
      }
      
      
      $idnresult=$sessiondbh->prepare("select searchresults.searchresult from searchresults, dbinfo where searchresults.dbname=dbinfo.dbname and sessionid = ? and queryid = ? order by dbinfo.faculty,searchresults.dbname") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$queryid) or $logger->error($DBI::errstr);
      
      # Header mit allen Elementen ausgeben
      
      OpenBib::Common::Util::print_simple_header("Such-Client des Virtuellen Katalogs",$r);
      
      print << "HEADER";

<ul id="tabbingmenu">
   <li><a class="active" href="$config{resultlists_loc}?sessionID=$sessionID;trefferliste=choice;view=$view">Trefferliste</a></li>
</ul>

<div id="content">

<FORM METHOD="GET">
<p>
HEADER
      
      OpenBib::Common::Util::print_sort_nav($r,'sortboth',1);      
      
      
      #print "<h1>Direkt aus dem Cache</h1>";
      print "<table>";
      
      #open(RES,">/tmp/res.dat");
      
      my @resultset=();
      
      if ($sortall == 1){
	
	my $idx=0;
	my @outputbuffer=();
	while (my @res=$idnresult->fetchrow){
	  my @splitresult=split("\n",$res[0]);
	  my $j=0;
	  
	  my $institut="";
	  
	  while ($j <= $#splitresult){
	    my $thisline=$splitresult[$j];
	    
	    if ($thisline =~/<tr bgcolor="lightblue"><td>&nbsp;<\/td><td>(<a.+?>.+?<\/a>)<\/td>/){
	      $institut=$1;
	    }
	    elsif ($thisline =~/<tr bgcolor="lightblue"><td>&nbsp;<\/td><td>(.+?)<\/td>/){
	      $institut=$1;
	    }
	    elsif ($thisline =~/<tr bgcolor="white"><td bgcolor="lightblue"><strong>\d+<\/strong><\/td><td colspan=2>(.+<\/td><\/tr>)/){
	      my $line=$1;
	      $outputbuffer[$idx++]="<td bgcolor=\"lightblue\">".$institut."</td><td>".$line; 	  
	      #print RES $outputbuffer[$idx-1];
	    }
	    elsif ($thisline =~/<tr bgcolor="aliceblue"><td bgcolor="lightblue"><strong>\d+<\/strong><\/td><td colspan=2>(.+<\/td><\/tr>)/){
	      my $line=$1;
	      $outputbuffer[$idx++]="<td bgcolor=\"lightblue\">".$institut."</td><td>".$line; 	  
	      #print RES $outputbuffer[$idx-1];
	    }
	    else {
	      #print RES $thisline."\n"; 
	    }
	    
	    $j++;
	  }
	  
	}
	
	my @sortedoutputbuffer=();
	
	OpenBib::ResultLists::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
	my $i=0;
	my $bgcolor="white";
	while ($i <= $#sortedoutputbuffer){
	  print "<tr bgcolor=\"$bgcolor\"><td bgcolor=\"lightblue\"><strong>".($i+1)."</strong></td>".$sortedoutputbuffer[$i]."\n";
	  
	  # Eintraege merken fuer Lastresultset
	  
	  my ($katkey)=$sortedoutputbuffer[$i]=~/searchsingletit=(\d+)/;
	  my ($resdatabase)=$sortedoutputbuffer[$i]=~/database=(\w+)/;
	  push @resultset, { 'database' => $resdatabase,
			     'idn' => $katkey
			   };
	  
	  $i++;
	  
	  if ($bgcolor eq "white"){
	    $bgcolor="aliceblue";
	  }
	  else {
	    $bgcolor="white";
	  }
	  
	}
	#close(RES);
	
      }
      elsif ($sortall == 0) {
	
	# Katalogoriertierte Sortierung
	
	#      open(RES,">/tmp/res.dat");
	while (my @res=$idnresult->fetchrow){
	  my @splitresult=split("\n",$res[0]);
	  my $j=0;
	  my $idx=0;
	  my @outputbuffer=();
	  while ($j <= $#splitresult){
	    my $thisline=$splitresult[$j];
	    
	    if ($thisline =~/<tr bgcolor="white"><td bgcolor="lightblue"><strong>\d+<\/strong><\/td>(<td colspan=2>.+<\/td><\/tr>)/){
	      my $line=$1;
	      $outputbuffer[$idx++]=$line; 	  
	      #	    print RES $outputbuffer[$idx-1];
	    }
	    elsif ($thisline =~/<tr bgcolor="aliceblue"><td bgcolor="lightblue"><strong>\d+<\/strong><\/td>(<td colspan=2>.+<\/td><\/tr>)/){
	      my $line=$1;
	      $outputbuffer[$idx++]=$line; 	  
	      #	    print RES $outputbuffer[$idx-1];
	    }
	    elsif ($thisline =~/<tr bgcolor="lightblue"><td>&nbsp;/){
	      print $thisline;
	    }
	    else {
	      #	    print RES $thisline."\n"; 
	    }
	    
	    
	    $j++;
	  }
	  
	  # Sortierung
	  
	  my @sortedoutputbuffer=();
	  
	  OpenBib::ResultLists::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	  
	  my $i=0;
	  my $bgcolor="white";
	  while ($i <= $#sortedoutputbuffer){
	    print "<tr bgcolor=\"$bgcolor\"><td bgcolor=\"lightblue\"><strong>".($i+1)."</strong></td>".$sortedoutputbuffer[$i]."\n";
	    
	    # Eintraege merken fuer Lastresultset
	    
	    my ($katkey)=$sortedoutputbuffer[$i]=~/searchsingletit=(\d+)/;
	    my ($resdatabase)=$sortedoutputbuffer[$i]=~/database=(\w+)/;
	    push @resultset, { 'database' => $resdatabase,
			       'idn' => $katkey
			     };
	    
	    $i++;
	    
	    if ($bgcolor eq "white"){
	      $bgcolor="aliceblue";
	    }
	    else {
	      $bgcolor="white";
	    }
	    
	  }
	  
	  print "<tr><td colspan=3>&nbsp;<td></tr>\n";
	  
	}
	
	#      close(RES);
	
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      
      $idnresult->finish();
      
      print "</table></div><p>";    
      OpenBib::Common::Util::print_footer();
      
      goto LEAVEPROG;
      
    }
    
    ####################################################################
    # ... falls die Treffer zu einer queryid aus einer Datenbank 
    # angezeigt werden sollen
    ####################################################################
    
    elsif ($dbases{$trefferliste} ne "") {
      
      my @resultset=();
      
      $idnresult=$sessiondbh->prepare("select searchresult from searchresults where sessionid = ? and dbname = ? and queryid = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$trefferliste,$queryid) or $logger->error($DBI::errstr);
      
      # Header mit allen Elementen ausgeben
      
      OpenBib::Common::Util::print_simple_header("Such-Client des Virtuellen Katalogs",$r);
      
      print << "HEADER";
<ul id="tabbingmenu">
   <li><a class="active" href="$config{resultlists_loc}?sessionID=$sessionID;trefferliste=choice;view=$view">Trefferliste</a></li>
</ul>

<div id="content">

<FORM METHOD="GET">

<p>
HEADER
      
      OpenBib::Common::Util::print_sort_nav($r,'sortsingle',1);
      
      #  print "<h1>Direkt aus dem Cache</h1>";
      print "<table>";
      
      # Katalogoriertierte Sortierung
      
      while (my @res=$idnresult->fetchrow){
	my @splitresult=split("\n",$res[0]);
	my $j=0;
	my $idx=0;
	my @outputbuffer=();
	while ($j <= $#splitresult){
	  my $thisline=$splitresult[$j];
	  
	  if ($thisline =~/<tr bgcolor="white"><td bgcolor="lightblue"><strong>\d+<\/strong><\/td>(<td colspan=2>.+<\/td><\/tr>)/){
	    my $line=$1;
	    $outputbuffer[$idx++]=$line; 	  
	    #	    print RES $outputbuffer[$idx-1];
	  }
	  elsif ($thisline =~/<tr bgcolor="aliceblue"><td bgcolor="lightblue"><strong>\d+<\/strong><\/td>(<td colspan=2>.+<\/td><\/tr>)/){
	    my $line=$1;
	    $outputbuffer[$idx++]=$line; 	  
	    #	    print RES $outputbuffer[$idx-1];
	  }
	  elsif ($thisline =~/<tr bgcolor="lightblue"><td>&nbsp;/){
	    print $thisline;
	  }
	  else {
	    #	    print RES $thisline."\n"; 
	  }
	  
	  
	  $j++;
	}
	
	# Sortierung
	
	my @sortedoutputbuffer=();
	
	OpenBib::ResultLists::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
	my $i=0;
	my $bgcolor="white";
	while ($i <= $#sortedoutputbuffer){
	  print "<tr bgcolor=\"$bgcolor\"><td bgcolor=\"lightblue\"><strong>".($i+1)."</strong></td>".$sortedoutputbuffer[$i]."\n";
	  
	  # Eintraege merken fuer Lastresultset
	  
	  my ($katkey)=$sortedoutputbuffer[$i]=~/searchsingletit=(\d+)/;
	  my ($resdatabase)=$sortedoutputbuffer[$i]=~/database=(\w+)/;
	  push @resultset, { 'database' => $resdatabase,
			     'idn' => $katkey
			   };
	    	  
	  $i++;
	  if ($bgcolor eq "white"){
	    $bgcolor="aliceblue";
	  }
	  else {
	    $bgcolor="white";
	  }
	  
	}
	
	print "<tr><td colspan=3>&nbsp;<td></tr>\n";
	
      }
      
      #    while (my @res=$idnresult->fetchrow){
      #      print $res[0]; 
      #    }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      $idnresult->finish();
      
      print "</table></div><p>";    
      OpenBib::Common::Util::print_footer();
      
      goto LEAVEPROG;
    }
    
  }
  
  ####################################################################
  # ENDE Trefferliste
  #

LEAVEPROG: sleep 0;

  $sessiondbh->disconnect();
  
  return OK;
}

1;
