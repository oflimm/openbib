#####################################################################
#
#  OpenBib::ManageCollection
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

package OpenBib::ManageCollection;

use Apache::Constants qw(:common M_GET);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;

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

  # Log4perl logger erzeugen

  my $logger = get_logger();

  my $query=Apache::Request->new($r);

  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

  my $befehlsurl="http://$config{servername}$config{search_loc}";

  my %endnote=(
	       'Verfasser' => '%A', # Author 
	       'Urheber' => '%C', # Corporate Author
	       'HST' => '%T', # Title of the article or book
	       '1' => '%S', # Title of the serie
	       '2' => '%J', # Journal containing the article
	       '3' => '%B', # Journal Title (refer: Book containing article)
	       '4' => '%R', # Report, paper, or thesis type
	       '5' => '%V', # Volume 
	       '6' => '%N', # Number with volume
	       '7' => '%E', # Editor of book containing article
	       '8' => '%P', # Page number(s)
	       'Verlag' => '%I', # Issuer. This is the publisher
	       'Verlagsort' => '%C', # City where published. This is the publishers address
	       'Ersch. Jahr' => '%D', # Date of publication
	       '11' => '%O', # Other information which is printed after the reference
	       '12' => '%K', # Keywords used by refer to help locate the reference
	       '13' => '%L', # Label used to number references when the -k flag of refer is used
	       '14' => '%X', # Abstract. This is not normally printed in a reference
	       '15' => '%W', # Where the item can be found (physical location of item)
	       'Kollation' => '%Z', # Pages in the entire document. Tib reserves this for special use
	       'Ausgabe' => '%7', # Edition 
	       '17' => '%Y', # Series Editor 
	       
	       );

  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen

  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);

  my $sessionID=$query->param('sessionID') || '';
  my $database=$query->param('database') || '';
  my $singleidn=$query->param('singleidn') || '';
  my $loeschen=$query->param('loeschen') || '';
  my $action=($query->param('action'))?$query->param('action'):'none';
  my $type=($query->param('type'))?$query->param('type'):'HTML';
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  
  # Haben wir eine authentifizierte Session?
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
  # die Session nicht authentifiziert ist

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

  # Assoziierten View zur Session aus Datenbank holen

  my $idnresult=$sessiondbh->prepare("select viewname from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

  my $result=$idnresult->fetchrow_hashref();
  
  my $view=$result->{'viewname'} || '';
  
  my $viewdesc="";
  
  if ($view ne ""){
    $viewdesc="<tr><td colspan=3 align=left><img src=\"/images/openbib/views/$view.png\"></td></tr>";
  }
  
  $idnresult->finish();
  
  #####################################################################
  # Einfuegen eines Titels ind die Merkliste

  if ($action eq "insert"){
    
    if ($userid){
      # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
      
      my $idnresult=$userdbh->prepare("select * from treffer where userid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($userid,$database,$singleidn) or $logger->error($DBI::errstr);
      my $anzahl=$idnresult->rows();
      $idnresult->finish();
      
      if ($anzahl == 0){
	# Zuerst Eintragen der Informationen
	
	my $idnresult=$userdbh->prepare("insert into treffer values (?,?,?)") or $logger->error($DBI::errstr);
	$idnresult->execute($userid,$database,$singleidn) or $logger->error($DBI::errstr);
	$idnresult->finish();
	
      }
    }
    # Anonyme Session
    else {
      
      # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
      
      my $idnresult=$sessiondbh->prepare("select * from treffer where sessionid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$database,$singleidn) or $logger->error($DBI::errstr);
      my $anzahl=$idnresult->rows();
      $idnresult->finish();
      
      if ($anzahl == 0){
	# Zuerst Eintragen der Informationen
	
	my $idnresult=$sessiondbh->prepare("insert into treffer values (?,?,?)") or $logger->error($DBI::errstr);
	$idnresult->execute($sessionID,$database,$singleidn) or $logger->error($DBI::errstr);
	$idnresult->finish();
	
      }
    }
    
    # Dann Ausgabe des neuen Headers via Redirect
    
    $r->internal_redirect("http://$config{servername}$config{headerframe_loc}?sessionID=$sessionID");
    
  }


  #####################################################################
  # Anzeigen des Inhalts der Merkliste

  elsif ($action eq "show"){

    if ($loeschen eq "Los"){
      
      my $loeschtit="";
      
      foreach $loeschtit ($query->param('loeschtit')){
	
	my ($loeschdb,$loeschidn)=split(":",$loeschtit);
	
	if ($userid){
	  my $idnresult=$userdbh->prepare("delete from treffer where userid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
	  $idnresult->execute($userid,$loeschdb,$loeschidn) or $logger->error($DBI::errstr);
	  $idnresult->finish();
	}
	else {
	  my $idnresult=$sessiondbh->prepare("delete from treffer where sessionid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
	  $idnresult->execute($sessionID,$loeschdb,$loeschidn) or $logger->error($DBI::errstr);
	  $idnresult->finish();
	}
	
      }
    }
    
    my $gesamttreffer="";  
    
    
    # Schleife ueber alle Treffer
    
    my $idnresult="";
    
    if ($userid){
      $idnresult=$userdbh->prepare("select * from treffer where userid = ? order by dbname") or $logger->error($DBI::errstr);
      $idnresult->execute($userid) or $logger->error($DBI::errstr);
    }
    else {
      $idnresult=$sessiondbh->prepare("select * from treffer where sessionid = ? order by dbname") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    }
    
    my $ua=new LWP::UserAgent;
    
    while (my $result=$idnresult->fetchrow_hashref()){
      $database=$result->{'dbname'};
      $singleidn=$result->{'singleidn'};
      
      $gesamttreffer=getTitleByType($gesamttreffer,$ua,$befehlsurl,$sessionID,$database,$singleidn,$type,\%endnote,\%dbases,1);
      
    }
    
    $idnresult->finish();
    
    if ($type eq "Text" || $type eq "EndNote"){
      $gesamttreffer="<pre>\n$gesamttreffer\n</pre>";
    }
    
    print $r->send_http_header("text/html");
    
    my $typetarget="";
    if ($type ne ""){
      $typetarget="&type=$type";
    }
    
    my $loeschauswahl="";
    if ($type eq "HTML"){
      $loeschauswahl="...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp<b>Ausgew&auml;hlte Titel l&ouml;schen</b>&nbsp;<input type=submit name=\"loeschen\" value=\"Los\">";
    }
    
    print << "ENDE2";
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<HTML>
  <HEAD>
    <meta http-equiv="pragma" content="no-cache">
    $stylesheet
    <link href="/images/openbib/favicon.ico" rel="shortcut icon">
    <TITLE>KUG - K&ouml;lner Universit&auml;tsGesamtkatalog</TITLE>
  </HEAD>
  <BODY BGCOLOR="#FFFFFF">
    <table  BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
	<tr>
	  <td ALIGN=LEFT>
	    <table><tr><td rowspan=2 valign=bottom><a target="_blank" href="http://kug.ub.uni-koeln.de/projekt/"><img SRC="/images/openbib/logo.png" BORDER=0></a></td><td valign=bottom><img SRC="/images/openbib/logozeile1.png" BORDER=0></td></tr><tr><td valign=top><img SRC="/images/openbib/logozeile2.png" BORDER=0></td></tr></table>
	    
	  </td>
	  
	  <td> &nbsp;&nbsp;</td>
	  
	  <td ALIGN=RIGHT>
	    <a target="_top" HREF="http://www.uni-koeln.de/"><img SRC="/images/openbib/logorechts.png" height=95 BORDER=0></a>
	  </td>
	</tr>

        $viewdesc

    </table>
<hr>

<form method="get" action="http://$config{servername}$config{managecollection_loc}">
<input type="hidden" name="sessionID" value="$sessionID">
<input type="hidden" name="action" value="show">

<table  BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
  <tr bgcolor="lightblue">
    <td width="20">&nbsp;</td>
    <td valign="middle" ALIGN=left height="32"><img src="/images/openbib/merkliste.png"></td>
      <td>&nbsp;</td>
      <td bgcolor=white align=right width=80>
        <a href=\"http://$config{servername}$config{managecollection_loc}?sessionID=$sessionID&action=mail$typetarget\" target=\"mail\" title=\"Als Mail verschicken\"><img src="/images/openbib/3d-file-blue-mailbox.png" height="29" alt="Als Mail verschicken" border=0></a>&nbsp;
        <a href=\"http://$config{servername}$config{managecollection_loc}?sessionID=$sessionID&action=save$typetarget\" target=\"save\" title=\"Abspeichern\"><img src="/images/openbib/3d-file-blue-disk35.png" height="29" alt="Abspeichern" border=0></a>&nbsp;
       </td>
  </tr>
</table>
<p>
<table width="100%">
<tr><th>Optionen</th></tr>
<tr><td class="boxed">
<b>Format:</b> <select name=type><option value="HTML">HTML</option><option value="Text">Text</option><option value="EndNote">EndNote</option></select>&nbsp;<input type=submit value="Los">&nbsp;&nbsp;&nbsp;&nbsp;<b>derzeit: $type</b>&nbsp;&nbsp;&nbsp;$loeschauswahl
</td><tr>
</table>
<p>
<table>
$gesamttreffer
</table>
<hr>
  </body>
</html>

ENDE2
    }

    #####################################################################
    # Abspeichern der Merkliste

  elsif ($action eq "save"){
    
    if ($singleidn){
      my $suchstring="sessionID=$sessionID&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&casesensitive=0&hitrange=-1&sorttype=author&database=$database&dbms=mysql&searchsingletit=$singleidn";
      
      my $gesamttreffer="";
      my $ua=new LWP::UserAgent;
      
      my $request=new HTTP::Request GET => "$befehlsurl?$suchstring";
      
      my $response=$ua->request($request);

      if ($response->is_success) {
	$logger->debug("Getting ", $response->content);
      }
      else {
	$logger->error("Getting ", $response->status_line);
      }
      
      my $ergebnis=$response->content();
      
      my ($treffer)=$ergebnis=~/^(<!-- Title begins here -->.+?^<!-- Title ends here -->)/ms;
      
      $gesamttreffer.="<hr>\n$treffer";
      
      # Herausfiltern der HTML-Tags der Titel
      
      $gesamttreffer=~s/<a.*?>//g;
      $gesamttreffer=~s/<td>&nbsp;/<td>/g;
      $gesamttreffer=~s/<\/a.*?>//g;
      $gesamttreffer=~s/<span.*?>G<\/span.*?>//g;
      
      print $r->header_out("Attachment" => "kugliste.html");
      print $r->header_out("Content-Type" => "text/html");
      print $r->send_http_header;
      
      print "<HTML>\n<HEAD><TITLE>Abgespeicherte Treffer</TITLE></HEAD>\n<BODY><h1>KUG-Trefferliste</h1><TABLE>\n";
      print $gesamttreffer;
      print "\n</TABLE>";
      
      OpenBib::Common::Util::print_footer();
    }
    else {
      # Schleife ueber alle Treffer
      
      my $idnresult="";
      
      if ($userid){
	$idnresult=$userdbh->prepare("select * from treffer where userid = ?") or $logger->error($DBI::errstr);
	$idnresult->execute($userid) or $logger->error($DBI::errstr);
      }
      else {
	$idnresult=$sessiondbh->prepare("select * from treffer where sessionid = ? order by dbname") or $logger->error($DBI::errstr);
	$idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      }  
      
      my $gesamttreffer="";
      my $ua=new LWP::UserAgent;
      
      while (my $result=$idnresult->fetchrow_hashref()){
	$database=$result->{'dbname'};
	$singleidn=$result->{'singleidn'};
	
	$gesamttreffer=getTitleByType($gesamttreffer,$ua,$befehlsurl,$sessionID,$database,$singleidn,$type,\%endnote,\%dbases,0);
	
      }
      
      if ($type eq "HTML"){
	
	print $r->header_out("Attachment" => "kugliste.html");
	print $r->header_out("Content-Type" => "text/html");
	print $r->send_http_header;
	
	print "<HTML>\n<HEAD><TITLE>Abgespeicherte Treffer</TITLE></HEAD>\n<BODY><h1>KUG-Trefferliste</h1><TABLE>\n";
	print $gesamttreffer;
	print "\n</TABLE>\n";
	
	OpenBib::Common::Util::print_footer();
      }
      else {
	print $r->header_out("Attachment" => "kugliste.txt");
	print $r->header_out("Content-Type" => "text/plain");
	print $r->send_http_header;
	
	print $gesamttreffer;
      }
      
    }
  }
  
  #####################################################################
  # Verschicken der Merkliste per Mail

  elsif ($action eq "mail"){

    # Weg mit der Singleidn - muss spaeter gefixed werden

    my $userresult=$userdbh->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);
    
    my $loginname="";
    
    if ($userresult->rows > 0){
      my $res=$userresult->fetchrow_hashref();
      $loginname=$res->{'loginname'};
    }
    
    OpenBib::Common::Util::print_simple_header("KUG - K&ouml;lner Universit&auml;tsGesamtkatalog",$r);

    print << "ENDE5";
    <table  BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
	<tr>
	  <td ALIGN=LEFT>
	    <table><tr><td rowspan=2 valign=bottom><a target="_blank" href="http://kug.ub.uni-koeln.de/projekt/"><img SRC="/images/openbib/logo.png" BORDER=0></a></td><td valign=bottom><img SRC="/images/openbib/logozeile1.png" BORDER=0></td></tr><tr><td valign=top><img SRC="/images/openbib/logozeile2.png" BORDER=0></td></tr></table>
	    
	  </td>
	  
	  <td> &nbsp;&nbsp;</td>
	  
	  <td ALIGN=RIGHT>
	    <a target="_top" HREF="http://www.uni-koeln.de/"><img SRC="/images/openbib/logorechts.png" height=95 BORDER=0></a>
	  </td>
	</tr>

        $viewdesc

    </table>
<hr>
<FORM method="post" action="http://$config{servername}$config{mailcollection_loc}" enctype="multipart/form-data">
<INPUT type=hidden name=sessionID value=$sessionID>
<INPUT type=hidden name=type value=$type>
<table>
<tr><td bgcolor="lightblue"><strong>Ihre Mailadresse</strong></td><td><input type=text name="email" VALUE="$loginname" SIZE=30 MAXLENGTH=200></td></tr>
<tr><td bgcolor="lightblue"><strong>Betreff</strong></td><td><input type=text name="subject" VALUE="" SIZE=30 MAXLENGTH=200></td></tr>
</table>
<p>
<input type=submit name=mail VALUE="Abschicken">&nbsp;<input type=reset value="Felder leeren">
<p>
ENDE5

    if ($singleidn){
      print "<INPUT type=hidden name=singleidn value=$singleidn>\n";
    }
    
    if ($database){
      print "<INPUT type=hidden name=database value=$database>\n";
    }
    
    print "<table>";
    
    if ($singleidn){
      
      my $suchstring="sessionID=$sessionID&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&casesensitive=0&hitrange=-1&sorttype=author&database=$database&dbms=mysql&searchsingletit=$singleidn";
      
      my $gesamttreffer="";
      my $ua=new LWP::UserAgent;
      
      my $request=new HTTP::Request GET => "$befehlsurl?$suchstring";
      
      my $response=$ua->request($request);

      if ($response->is_success) {
	$logger->debug("Getting ", $response->content);
      }
      else {
	$logger->error("Getting ", $response->status_line);
      }
      
      my $ergebnis=$response->content();
      
      my ($treffer)=$ergebnis=~/^(<!-- Title begins here -->.+?^<!-- Title ends here -->)/ms;
      
      #  ($treffer)=$ergebnis=~/^<table cellpadding=2>\n^<tr><td>(Kategorie)/ms;
      
      $gesamttreffer.="<hr>\n$treffer";
      
      # Herausfiltern der HTML-Tags der Titel
      
      $gesamttreffer=~s/<a.*?>//g;
      $gesamttreffer=~s/<td>&nbsp;/<td>/g;
      $gesamttreffer=~s/<\/a.*?>//g;
      $gesamttreffer=~s/<span.*?>G<\/span.*?>//g;

      print $gesamttreffer;
      
    }
    else {
      
      # Schleife ueber alle Treffer
      
      my $idnresult="";
      
      if ($userid){
	$idnresult=$userdbh->prepare("select * from treffer where userid = ?") or $logger->error($DBI::errstr);
	$idnresult->execute($userid) or $logger->error($DBI::errstr);
      }
      else {
	$idnresult=$sessiondbh->prepare("select * from treffer where sessionid = ? order by dbname") or $logger->error($DBI::errstr);
	$idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      }
      
      my $gesamttreffer="";
      my $ua=new LWP::UserAgent;
      
      while (my $result=$idnresult->fetchrow_hashref()){
	$database=$result->{'dbname'};
	$singleidn=$result->{'singleidn'};
	
	$gesamttreffer=getTitleByType($gesamttreffer,$ua,$befehlsurl,$sessionID,$database,$singleidn,$type,\%endnote,\%dbases,0);
	
      }
      
      if ($type eq "Text" || $type eq "EndNote"){
	$gesamttreffer="<pre>$gesamttreffer</pre>";
      }
      print $gesamttreffer;
      
    }
    
    
    print << "ENDE6";
</form>
</body>
</html>
ENDE6

  }

  #####################################################################
  # Ausdrucken der Merkliste (HTML) ueber Browser

  elsif ($action eq "print"){
    
    if ($singleidn){
      
      my $gesamttreffer="";
      my $ua=new LWP::UserAgent;
      
      $gesamttreffer=getTitleByType($gesamttreffer,$ua,$befehlsurl,$sessionID,$database,$singleidn,$type,\%endnote,\%dbases,0);
      
      OpenBib::Common::Util::print_simple_header("KUG - K&ouml;lner Universit&auml;tsGesamtkatalog",$r);
      
      print "<h1>Auszudruckender Titel</h1>\n";
      print $gesamttreffer;
      
      OpenBib::Common::Util::print_footer();
      
    }
    
  }
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  return OK;
}

#####################################################################
#####################################################################

#####################################################################
# Holen eines Titels per LWP, umwandlung in Type und Hinzufuegen
# zu $gesamttreffer

sub getTitleByType {
  my ($gesamttreffer,$ua,$befehlsurl,$sessionID,$database,$singleidn,$type,$endnoteref,$dbasesref,$checkbox)=@_;

  # Log4perl logger erzeugen

  my $logger = get_logger();

  my %endnote=%$endnoteref;
  my %dbases=%$dbasesref; 

  my $suchstring="sessionID=$sessionID&search=Mehrfachauswahl&searchmode=2&rating=0&bookinfo=0&showmexintit=1&casesensitive=0&hitrange=-1&sorttype=author&database=$database&dbms=mysql&searchsingletit=$singleidn";
  
  my $request=new HTTP::Request GET => "$befehlsurl?$suchstring";
  
  my $response=$ua->request($request);

  if ($response->is_success) {
    $logger->debug("Getting ", $response->content);
  }
  else {
    $logger->error("Getting ", $response->status_line);
  }
  
  my $ergebnis=$response->content();
  
  my ($treffer)=$ergebnis=~/^(<!-- Title begins here -->.+?^<!-- Title ends here -->)/ms;
  
  #  ($treffer)=$ergebnis=~/^<table cellpadding=2>\n^<tr><td>(Kategorie)/ms;
  
  # Herausfiltern der HTML-Tags der Titel
  
  $treffer=~s/<a .*?">//g;
  $treffer=~s/<.a>//g;
  $treffer=~s/<span .*?>G<.span>//g;
  $treffer=~s/<td>&nbsp;/<td>/g;
  
  if ($type eq "Text"){
    
    my @titelbuf=();
    
    # Treffer muss in Text umgewandelt werden
    
    $treffer=~s/^<.*?>$//g;
  
    my @trefferbuf=split("\n",$treffer);
    my $i=0;
    my $j=1;
    while ($i < $#trefferbuf){
      
      # Titelinformationen
      
      if ($trefferbuf[$i]=~/<tr><td.*?>(.+?)<.td><td>(.+?)<.td><.tr>/){
	my $kategorie=$1;
	my $inhalt=$2;

        $kategorie=sgml2umlaut($kategorie);
	
	$kategorie=~s/<.+?>//g;
	$inhalt=~s/<.+?>//g;
	while (length($kategorie) < 24){
	  $kategorie.=" ";
	}
	push @titelbuf, "$kategorie: $inhalt";
      }
      
      # Bestandsinformationen
      
      elsif ($trefferbuf[$i]=~/<tr.*?><td>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?rlsignature.*?>(.+?)<\/td><td.*?>(.+?)<\/td><\/tr>/){
	
	my $bibliothek=$1;
	my $standort=$2;
	my $signatur=$3;
	my $erschverl=$4;
	
	$bibliothek=~s/<.+?>//g;
	$standort=~s/<.+?>//g;
	$signatur=~s/<.+?>//g;
	$erschverl=~s/<.+?>//g;
	my $bestandsinfo= << "ENDE";
Besitzende Bibliothek $j : $bibliothek
Standort              $j : $standort
Lokale Signatur       $j : $signatur
Erscheinungsverlauf   $j : $erschverl
ENDE
              push @titelbuf, $bestandsinfo;
	$j++;
      }
      
      $i++;
    } 
    
    $treffer=join ("\n", @titelbuf);
    $gesamttreffer.="\n------------------------------------------\n$treffer";
  }
  elsif ($type eq "EndNote"){
    # Treffer muss in Text umgewandelt werden
    
    my @titelbuf=();
    
    $treffer=~s/^<.*?>$//g;
    
    my @trefferbuf=split("\n",$treffer);
    my $i=0;
    my $j=1;
    while ($i < $#trefferbuf){
      
      # Titelinformationen
      
      if ($trefferbuf[$i]=~/<tr><td.*?>(.+?)<.td><td>(.+?)<.td><.tr>/){
	my $kategorie=$1;
	my $inhalt=$2;
	
	$kategorie=~s/<.+?>//g;
	$inhalt=~s/<.+?>//g;
	
	if (defined($endnote{$kategorie})){
	  push @titelbuf, $endnote{$kategorie}." $inhalt";
	}
      }
      
      # Bestandsinformationen

      elsif ($trefferbuf[$i]=~/<tr.*?><td>(.+?)<\/td><td.*?>(.+?)<\/td><td.*?rlsignature.*?>(.+?)<\/td><td.*?>(.+?)<\/td><\/tr>/){      
	
	my $bibliothek=$1;
	my $standort=$2;
	my $signatur=$3;
	my $erschverl=$4;
	
	$bibliothek=~s/<.+?>//g;
	$standort=~s/<.+?>//g;
	$signatur=~s/<.+?>//g;
	$erschverl=~s/<.+?>//g;
	my $bestandsinfo="%W $bibliothek / $standort / $signatur / $erschverl";
	push @titelbuf, $bestandsinfo;
	$j++;
      }
      
      $i++;
    } 
    
    $treffer=join ("\n", @titelbuf);
    $gesamttreffer.="\n\n$treffer";
  }
  else {

    my $checkboxhtml="&nbsp;";
    if ($checkbox){
    $checkboxhtml="<input type=checkbox name=loeschtit value=\"".$database.":".$singleidn."\">";
  }

    $gesamttreffer.="<tr><td bgcolor=\"aliceblue\">$checkboxhtml</td><td bgcolor=\"aliceblue\">aus: ".$dbases{$database}."<td></tr><tr><td>&nbsp;</td><td>$treffer</td></tr>";
  }

  return $gesamttreffer;
}

sub sgml2umlaut {
  my ($line)=@_;
  
  $line=~s/&uuml;/ü/g; 
  $line=~s/&auml;/ä/g;
  $line=~s/&ouml;/ö/g;
  $line=~s/&Uuml;/Ü/g;
  $line=~s/&Auml;/Ä/g;
  $line=~s/&Ouml;/Ö/g;
  $line=~s/&szlig;/ß/g; 
  
  $line=~s/\&Eacute\;/É/g;	
  $line=~s/\&Egrave\;/È/g;	
  $line=~s/\&Ecirc\;/Ê/g;	
  $line=~s/\&Aacute\;/Á/g;	
  $line=~s/\&Agrave\;/À/g;	
  $line=~s/\&Acirc\;/Â/g;	
  $line=~s/\&Oacute\;/Ó/g;	
  $line=~s/\&Ograve\;/Ò/g;	
  $line=~s/\&Ocirc\;/Ô/g;	
  $line=~s/\&Uacute\;/Ú/g;	
  $line=~s/\&Ugrave\;/Ù/g;	
  $line=~s/\&Ucirc\;/Û/g;	
  $line=~s/\&Iacute\;/Í/g;     
  $line=~s/\&Igrave\;/Ì/g;	
  $line=~s/\&Icirc\;/Î/g;	
  $line=~s/\&Ntilde\;/Ñ/g;	
  $line=~s/\&Otilde\;/Õ/g;	
  $line=~s/\&Atilde\;/Ã/g;	
  
  $line=~s/\&eacute\;/é/g;	
  $line=~s/\&egrave\;/è/g;	
  $line=~s/\&ecirc\;/ê/g;	
  $line=~s/\&aacute\;/á/g;	
  $line=~s/\&agrave\;/à/g;	
  $line=~s/\&acirc\;/â/g;	
  $line=~s/\&oacute\;/ó/g;	
  $line=~s/\&ograve\;/ò/g;	
  $line=~s/\&ocirc\;/ô/g;	
  $line=~s/\&uacute\;/ú/g;	
  $line=~s/\&ugrave\;/ù/g;	
  $line=~s/\&ucirc\;/û/g;	
  $line=~s/\&iacute\;/í/g;     
  $line=~s/\&igrave\;/ì/g;	
  $line=~s/\&icirc\;/î/g;	
  $line=~s/\&ntilde\;/ñ/g;	
  $line=~s/\&otilde\;/õ/g;	
  $line=~s/\&atilde\;/ã/g;	
  
  return $line;		# 
}

1;
