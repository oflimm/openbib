#####################################################################
#
#  OpenBib::Common::Util
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

package OpenBib::Common::Util;

use strict;
use warnings;

use Apache::Constants qw(:common);

use Log::Log4perl qw(get_logger :levels);

use POSIX();

use Digest::MD5();
use DBI;

use OpenBib::Config;

use Template;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub init_new_session {
  my ($sessiondbh)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $sessionID="";

  my $havenewsessionID=0;
    
  while($havenewsessionID == 0){
    my $gmtime = localtime(time);
    my $md5digest=Digest::MD5->new();
    
    $md5digest->add($gmtime . rand('1024'). $$);
    
    $sessionID=$md5digest->hexdigest;
    
    # Nachschauen, ob es diese ID schon gibt
    
    my $idnresult=$sessiondbh->prepare("select count(sessionid) from session where sessionid='$sessionID'") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);

    my @idn=$idnresult->fetchrow_array();
    my $anzahl=$idn[0];
    
    # Wenn wir nichts gefunden haben, dann ist alles ok.
    if ($anzahl == 0 ){
      $havenewsessionID=1;
      
      my $createtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());
      
      # Eintrag in die Datenbank
      
      $idnresult=$sessiondbh->prepare("insert into session (sessionid,createtime) values ('$sessionID','$createtime')") or $logger->error($DBI::errstr);
      $idnresult->execute() or $logger->error($DBI::errstr);
    }
    
    $idnresult->finish();
  }
  
  return $sessionID;
}

sub session_is_valid {
  my ($sessiondbh,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  if ($sessionID eq "-1"){
    return 1;
  }

  my $idnresult=$sessiondbh->prepare("select count(sessionid) from session where sessionid='$sessionID'") or $logger->error($DBI::errstr);
  $idnresult->execute() or $logger->error($DBI::errstr);

  my @idn=$idnresult->fetchrow_array();
  my $anzahl=$idn[0];

  $idnresult->finish();

  if ($anzahl == 1){
    return 1;
  }

  return 0;
}

sub get_userid_of_session {
  my ($userdbh,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $userresult=$userdbh->prepare("select userid from usersession where sessionid='$config{servername}:$sessionID'") or $logger->error($DBI::errstr);

  $userresult->execute() or $logger->error($DBI::errstr);
  
  my $userid="";
  
  if ($userresult->rows > 0){
    my $res=$userresult->fetchrow_hashref();
    $userid=$res->{'userid'};
  }

  return $userid;
}

sub get_css_by_browsertype {
  my ($r)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $useragent=$r->subprocess_env('HTTP_USER_AGENT');

  my $stylesheet="";

  if ( $useragent=~/Mozilla.5.0/ || $useragent=~/MSIE 5/ || $useragent=~/MSIE 6/ || $useragent=~/Konqueror"/ ){
    $stylesheet= << "CSS";
<link rel="stylesheet" type="text/css" href="/styles/openbib.css" />
CSS
  }
  else {
    $stylesheet= << "CSS";
<link rel="stylesheet" type="text/css" href="/styles/openbib-simple.css" />
CSS
  }

  return $stylesheet;
}

#####################################################################
## get_sql_result(rreqarray,...): Suche anhand der in reqarray enthaltenen
##                                SQL-Statements, fasse die Ergebnisse zusammen
##                                und liefere sie zur"uck
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh
## $benchmark

sub get_sql_result {
  my ($rreqarray,$dbh,$benchmark)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my %metaidns;
  my @midns=();
  my $atime;
  my $btime;
  my $timeall;
  
  my @reqarray=@$rreqarray;
  
  my $i=0;    
  
  my $idnrequest;
  
  foreach $idnrequest (@reqarray){
    
    if ($benchmark){
      $atime=new Benchmark;
    }
    
    my $idnresult=$dbh->prepare("$idnrequest") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    
    my @idnres;
    while (@idnres=$idnresult->fetchrow){	    
      
      if (!$metaidns{$idnres[0]}){
	push @midns, $idnres[0];
      }
      $metaidns{$idnres[0]}=1;
    }
    $idnresult->finish();
    
    if ($benchmark){
      $btime=new Benchmark;
      $timeall=timediff($btime,$atime);
      print "Zeit fuer Idns zu : $idnrequest : ist ".timestr($timeall)."<p>\n";
      undef $atime;
      undef $btime;
      undef $timeall;
    }
  }
  
  return @midns;    
}

sub print_simple_header {
  my ($title,$r)=@_;
  
  my $stylesheet=get_css_by_browsertype($r);

  print $r->send_http_header("text/html");

  print << "HEADER";
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<HTML>
<HEAD>
  <meta http-equiv="pragma" content="no-cache">
  $stylesheet
  <link href="/images/openbib/favicon.ico" rel="shortcut icon">
  <TITLE>$title</title>
</HEAD>
<BODY BGCOLOR="#ffffff">
HEADER
  return;
}

sub print_extended_header {
  my ($title,$r)=@_;

  print_simple_header($title,$r);

  print << "HEADER";
    <table  BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
	<tr>
	  <td WIDTH=140 ALIGN=LEFT>
	    <table><tr><td rowspan=2 valign=bottom><img SRC="/images/openbib/logo.png" BORDER=0></td><td valign=bottom><img SRC="/images/openbib/logozeile1.png" BORDER=0></td></tr><tr><td valign=top><img SRC="/images/openbib/logozeile2.png" BORDER=0></td></tr></table>
	    
	  </td>
	  
	  <td height="42" valign="middle" WIDTH=40> &nbsp;&nbsp;</td>
	  
	  <td WIDTH=170 ALIGN=RIGHT>
	    <a target="_top" HREF="http://www.uni-koeln.de/"><img SRC="/images/openbib/logorechts.png" height=95 BORDER=0></a>
	  </td>
	</tr>
    </table>
<hr>
HEADER
  return;
}

sub print_footer {
  
  my $footer=<< "FOOTER";
<table BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
<tr><td class="boxedfull" align="left"><table BORDER=0 CELLSPACING=0 CELLPADDING=0 width=100%><tr><td
align="left"><b>KUG</b> ist ein Dienst der Universit&auml;ts- und
Stadtbibliothek K&ouml;ln</td><td>&nbsp;</td><td align="right"><a class="invisible" href="http://www.openbib.org/" target="_blank"><img src="/images/openbib/openbib-powered.png" alt="Powered by OpenBib" /></a></td></tr></table></td></tr>
</table>
<p />
<tt>KUG v1.1</tt>
</BODY>
</HTML>
FOOTER

  print STDOUT $footer;

  return;
}

sub print_warning {
  my ($warning,$r)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my $stylesheet=get_css_by_browsertype($r);
  
  my $template = Template->new({ 
				INCLUDE_PATH  => $config{tt_include_path},
				#    	    PRE_PROCESS   => 'config',
				OUTPUT        => $r,     # Output geht direkt an Apache Request
			       });
  
  # TT-Data erzeugen
  
  my $ttdata={
	      title      => 'Fehler: KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
	      stylesheet => $stylesheet,
	      
	      show_corporate_banner => 0,
	      show_foot_banner => 0,
	      invisible_links => 0,
	      
	      errmsg     => $warning,
	      config     => \%config,
	     };
  
  # Dann Ausgabe des neuen Headers
  
  print $r->send_http_header("text/html");
  
  $template->process($config{tt_error_tname}, $ttdata) || do { 
    $r->log_reason($template->error(), $r->filename);
    return SERVER_ERROR;
  };
  
  return;
}   

sub print_page {
  my ($templatename,$ttdata,$r)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my $stylesheet=get_css_by_browsertype($r);
  
  my $template = Template->new({ 
				INCLUDE_PATH  => $config{tt_include_path},
				#    	    PRE_PROCESS   => 'config',
				OUTPUT        => $r,     # Output geht direkt an Apache Request
			       });
  
  # Dann Ausgabe des neuen Headers
  
  print $r->send_http_header("text/html");
  
  $template->process($templatename, $ttdata) || do { 
    $r->log_reason($template->error(), $r->filename);
    return SERVER_ERROR;
  };
  
  return;
}   

sub print_sort_nav {
  my ($r,$nav,$usequerycache)=@_;

  my $myself=$r->uri;

  my $hostself="http://".$r->hostname.$r->uri;
  my $argself=$r->args;


  print "<p><form method=\"get\" action=\"$hostself\">\n";

  my $sorttype="";
  my $sortorder="";
  my $trefferliste="";
  my $sortall="";
  my $sessionID="";
  my $queryid="";

  my $fullargstring="";
  my $arg;
  foreach $arg (split ("&",$argself)){
    my ($key,$value)=split("=",$arg);
    if ($key ne "sortorder" && $key ne "sorttype" && $key ne "trefferliste" && $key ne "sortall" && $key ne "sessionID" && $key ne "queryid"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
    }
    elsif ($key eq "sortorder"){
      $sortorder=$value;
    }
    elsif ($key eq "sorttype"){
      $sorttype=$value;
    }
    elsif ($key eq "trefferliste"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $trefferliste=$value;
    }
    elsif ($key eq "sortall"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $sortall=$value;
    }
    elsif ($key eq "sessionID"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $sessionID=$value;
    }
    elsif ($key eq "queryid"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $queryid=$value;
    }

  }

  #Defaults setzen, falls Parameter nicht uebergeben

  $sortorder="up" unless ($sortorder);
  $sorttype="author" unless ($sorttype);

  # Bei der ersten Suche kann der 'trefferliste'-Parameter nicht
  # uebergeben werden. Daher wird er jetzt hier nachtraeglich gesetzt.

  if ($trefferliste eq ""){
    $trefferliste="all";
  }

  my $cacheargstring= << "CACHEARG";
<input type="hidden" name="trefferliste" value="$trefferliste">
<input type="hidden" name="sessionID" value="$sessionID">
<input type="hidden" name="queryid" value="$queryid">
CACHEARG

  if ($usequerycache){
    print $cacheargstring;
  }
  else {
    print $fullargstring;
  }

  my $navclick= << "NAVCLICK";
<table width="100%">
<tr><th>Optionen</th></tr>
<tr><td class="boxed">
<b>Sortierung:<b>&nbsp;<select name=sorttype><option value="author">nach Autor</option><option value="title">nach Titel</option><option value="yearofpub">nach Jahr</option><option value="publisher">nach Verlag</option><option value="signature">nach Signatur</option></select>&nbsp;<select name=sortorder><option value="up">aufsteigend</option><option value="down">absteigend</option></select>
NAVCLICK


  my %fullstring=('up','aufsteigend',
		  'down','absteigend',
		  'author','nach Autor/K&ouml;rperschaft',
		  'publisher','nach Verlag',
		  'signature','nach Signatur',
		  'title','nach Titel',
		  'yearofpub','nach Erscheinungsjahr'
		  );

  my $katalogtyp="pro Katalog";

  if ($sortall eq "1"){
    $katalogtyp="katalog&uuml;bergreifend";
  }

  my $aktuellstring="<b>derzeit:<b> ".$fullstring{$sorttype}." / ".$fullstring{$sortorder};

  $aktuellstring.=" / $katalogtyp" if ($nav);

  my $sortend="&nbsp;<input type=\"submit\" value=\"Los\"></form>&nbsp;&nbsp;&nbsp;$aktuellstring</td></tr></table><p>\n";

  if ($nav eq 'sortsingle'){
    print $navclick."<select name=\"sortall\"><option value=\"0\">pro Katalog</option></select>".$sortend;
  }
  elsif ($nav eq 'sortall'){
    print $navclick."<select name=\"sortall\"><option value=\"1\">katalog&uuml;bergreifend</option></select>".$sortend;
  }

  elsif ($nav eq 'sortboth'){
    print $navclick."<select name=\"sortall\"><option value=\"0\">pro Katalog</option><option value=\"1\">katalog&uuml;bergreifend</option></select>".$sortend;
  }
  else {
    print $navclick.$sortend;
  }

}

sub by_yearofpub {
  my $line1=0;
  my $line2=0;

  ($line1)=$a=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;
  ($line2)=$b=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;

  $line1=0 if ($line1 eq "");
  $line2=0 if ($line2 eq "");

  $line1 <=> $line2;
}

sub by_yearofpub_down {
  my $line1=0;
  my $line2=0;

  ($line1)=$a=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;
  ($line2)=$b=~m!<span id=.rlyearofpub.>.*?(\d\d\d\d).*?</span>!;

  $line1=0 if ($line1 eq "");
  $line2=0 if ($line2 eq "");

  $line2 <=> $line1;
}


sub by_publisher {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlpublisher.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlpublisher.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_publisher_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlpublisher.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlpublisher.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub by_signature {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlsignature.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlsignature.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_signature_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlsignature.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlsignature.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub by_author {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlauthor.>(.*?)</span>!;
  ($line2)=$b=~m!<span id=.rlauthor.>(.*?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_author_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rlauthor.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rlauthor.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub by_title {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rltitle.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rltitle.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line1 cmp $line2;
}

sub by_title_down {
  my $line1="";
  my $line2="";

  ($line1)=$a=~m!<span id=.rltitle.>(.+?)</span>!;
  ($line2)=$b=~m!<span id=.rltitle.>(.+?)</span>!;

  $line1=cleanrl($line1) if ($line1);
  $line2=cleanrl($line2) if ($line2);

  $line2 cmp $line1;
}

sub sort_buffer {
  my ($sorttype,$sortorder,$routputbuffer,$rsortedoutputbuffer)=@_;

  if ($sorttype eq "author" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_author @$routputbuffer;
  }
  elsif ($sorttype eq "author" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_author_down @$routputbuffer;
  }
  elsif ($sorttype eq "yearofpub" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_yearofpub @$routputbuffer;
  }
  elsif ($sorttype eq "yearofpub" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_yearofpub_down @$routputbuffer;
  }
  elsif ($sorttype eq "publisher" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_publisher @$routputbuffer;
  }
  elsif ($sorttype eq "publisher" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_publisher_down @$routputbuffer;
  }
  elsif ($sorttype eq "signature" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_signature @$routputbuffer;
  }
  elsif ($sorttype eq "signature" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_signature_down @$routputbuffer;
  }
  elsif ($sorttype eq "title" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_title @$routputbuffer;
  }
  elsif ($sorttype eq "title" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_title_down @$routputbuffer;
  }
  else {
    @$rsortedoutputbuffer=@$routputbuffer;
  }

  return;
}

sub cleanrl {
  my ($line)=@_;

  $line=~s/Ü/Ue/g;
  $line=~s/Ä/Ae/g;
  $line=~s/Ö/Oe/g;
  $line=lc($line);
  $line=~s/&(.)uml;/$1e/g;
  $line=~s/^ +//g;
  $line=~s/^¬//g;
  $line=~s/^"//g;
  $line=~s/^'//g;

  return $line;
}

sub updatelastresultset {
  my ($sessiondbh,$sessionID,$rresultset)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my @resultset=@$rresultset;

  my $resultsetstring=join("|",@resultset);

  my $sessionresult=$sessiondbh->prepare("update session set lastresultset='$resultsetstring' where sessionid='$sessionID'") or $logger->error($DBI::errstr);
  $sessionresult->execute() or $logger->error($DBI::errstr);
  $sessionresult->finish();

  return;
}


1;
__END__

=head1 NAME

 OpenBib::Common::Util - Gemeinsame Funktionen der OpenBib-Module

=head1 DESCRIPTION

 In OpenBib::Common::Util sind all jene Funktionen untergebracht, die 
 von mehr als einem mod_perl-Modul verwendet werden. Es sind dies 
 Funktionen aus den Bereichen Session- und User-Management, Ausgabe 
 von Webseiten oder deren Teilen und Interaktionen mit der 
 Katalog-Datenbank.

=head1 SYNOPSIS

 use OpenBib::Common::Util;

 # Stylesheet-Namen aus mod_perl Request-Object (Browser-Typ) bestimmen
 my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

 # eine neue Session erzeugen und Rueckgabe der $sessionID
 my $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh);

 # Ist die Session gueltig? Nein, dann Warnung und Ausstieg
 unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
   OpenBib::Search::Util::print_warning("Warnungstext",$r);
   exit;
 }

 # Ist die Session authentifiziert? Ja, dann Rueckgabe der positiven $userid,
 # sonst wird nichts zurueckgegeben 
 my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);

 # Ergebnisarray zu SQL-Anfragen (@requests) an DB-Handle $dbh fuellen
 my @resarr=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

 # Navigationsselement zwecks Sortierung einer Trefferliste ausgeben
 OpenBib::Common::Util::print_sort_nav($r,'',0);

 # Komplette Seite aus Template $templatename, Template-Daten $ttdata und
 # Request-Objekt $r bilden und ausgeben
 OpenBib::Common::Util::print_page($templatename,$ttdata,$r);

 # Einfachen Header mit Titel $title und Request-Objekt $r bilden und
 # ausgeben
 OpenBib::Common::Util::print_simple_header($title,$r);

 # Erweiterten Header mit Titel $title und Request-Objekt $r bilden und
 # zusaetzlich dem Bannerlogo ausgeben
 OpenBib::Common::Util::print_extended_header($title,$r);

 # Ausgabe des Footers
 OpenBib::Common::Util::print_footer();

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut





















































