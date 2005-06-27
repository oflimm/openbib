#####################################################################
#
#  OpenBib::VirtualSearch::Util
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

package OpenBib::VirtualSearch::Util;

use strict;
use warnings;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub number_of_swts {
  my ($rstring)=@_;

  my @rst=split("\n",$rstring);

  my $line;
  foreach $line (@rst){
    
    # Wir haben mehrere Treffer, wenn eine Auswahlliste erscheint
    if ($line=~m/Es wurden (\d+) Schlagworte in dieser Datenbank gefunden/){
      my $number=$1;
#      print "Nummer : $number";
      return $number;
    }
  }
  return "false";
}

sub extract_swtlines {
  my ($rstring)=@_;
  my @linebuf;

  my @rst=split("\n",$rstring);

  my $line;
  my $lidx;
  foreach $line (@rst){

    # Wir haben mehrere Treffer, wenn eine Auswahlliste erscheint
    if ($line=~m/^.tr.(.td..a href=.*?.\/a..\/td..td.\d+.\/td.).\/tr./){
      my $swtstring=$1;
      $linebuf[$lidx++]=$swtstring;
    }
  }

  return @linebuf;   
}

sub is_multiple_tit {
  my ($rstring)=@_;

  my @rst=split("\n",$rstring);

  my $line;
  foreach $line (@rst){
    
    # Wir haben mehrere Treffer, wenn eine Auswahlliste erscheint
    if ($line=~m/^Titlelist begins here/){
      return "yes";
    }
  }
  return "false";
}

sub extract_singletit_from_multiple {
  my ($rstring,$hitrange,$rdbases,$sorttype)=@_;
  my @mtit;
  my @rst=split("\n",$rstring); 
  my $titidx=0;
  my %dbases=%$rdbases;
  my $line;
  foreach $line (@rst){

    # Extrahiere wichtige Titelinformationen und konstruiere daraus eigene
    # Eintr"age
    if ($line=~m/^(.tr bgcolor=.+?.).td..input type=.checkbox. name=.searchmultipletit.*?..td..td.(.+?)database=(\w+)(.*..td...tr.)/){
      
      $line="<td colspan=2>".$2."sorttype=$sorttype&database=".$3.$4;
      if ($hitrange > 0){
	$line=~s/hitrange=-1/hitrange=$hitrange/;
      }
      $mtit[$titidx++]=$line;
    }
    elsif ($line=~m/^.tr..td bgcolor=lightblue..a href=/){
      $mtit[$titidx++]=$line;
    }
  }
  return @mtit;
}

sub is_single_tit {
  my ($rstring,$befehlsurl,$database,$hitrange,$sessionID,$sorttype)=@_;
  
  my $singletit;
  my $ast;
  my $hst;
  my $sachlben;
  my $idn;
  my $verlag;
  my $erschjahr;
  my $retval;
  
  my @rst=split("\n",$rstring); 

  my $line;

  my @verfasserarray=();
  my @signaturarray=();

  foreach $line (@rst){

    # Global Search eliminieren

    $line=~s/\<a href.*?virtual-biblio-search.pl.*?bsp.//;
    # Bei R"uckgabe von 'Gefundener Titel' gab es nur einen Treffer
    if ($line=~m/^<!-- Title begins here -->/){
      $singletit=1;
    }
    
    # Extrahiere den HST aus dem einen Titelsatz
    if ($line=~m/^.*.strong.HST..strong...td..td..strong.(.*)..strong...td...tr./){
      $hst=$1;
    }

    # Extrahiere den AST aus dem einen Titelsatz
    if ($line=~m/^.*.strong.Ansetzungssachtitel..strong...td..td.(.*)..td...tr./){
      $ast=$1;
    }
    
    # Extrahiere die Sachl.Ben. aus dem einen Titelsatz
    if ($line=~m/^.*.strong.Sachl.Ben...strong...td..td..strong.(.*)..strong...td...tr./){
      $sachlben=$1;
    }

    # Extrahiere die Verfasser aus dem einen Titelsatz
    if ($line=~m/^.+?Verfasser.+?\<a href.*?\>.*?\<.a\>.*?\<a href.*?\>(.*?)\<.a\>/){
      push @verfasserarray, $1;
    }

    # Extrahiere die Person aus dem einen Titelsatz
    if ($line=~m/^.+?>Person.+?\<a href.*?\>.*?\<.a\>.*?\<a href.*?\>(.*)\<.a\>/){
      push @verfasserarray, $1;
    }

    # Extrahiere den Urheber aus dem einen Titelsatz
    if ($line=~m/^.+?Urheber.+?\<a href.*?\>.*?\<.a\>.*?\<a href.*?\>(.*)\<.a\>/){
      push @verfasserarray, $1;
    }

    # Extrahiere die Koerperschaft aus dem einen Titelsatz
    if ($line=~m/^.+?K.+?rperschaft.+?\<a href.*?\>.*?\<.a\>.*?\<a href.*?\>(.*)\<.a\>/){
      push @verfasserarray, $1;
    }
    
    # Extrahiere die Identnummer aus dem einen Titelsatz
    if ($line=~m/^.tr.*Ident-Nr.*.td.(\d+).*tr./){
      $idn=$1;
    }

    # Extrahiere den Datenbanknamen aus dem einen Titelsatz
#    if ($line=~m/^Schlagwortindex..input type=hidden name=database value=(\w+)./){
    if ($line=~m/^Schlagwortindex.+?database=(\w+?)&amp;/){
      $database=$1;
    }
    
    # Extrahiere den Verlag aus dem einen Titelsatz
    if ($line=~m/^.tr..td bgcolor=.lightblue...strong.Verlag..strong...td..td.(.+)..td...tr./){
      $verlag=$1;
    }
    
    # Extrahiere das Erscheinungsjahr aus dem einen Titelsatz
    if ($line=~m/^.tr..td bgcolor=.lightblue...strong.Ersch. Jahr..strong...td..td.(.+)..td...tr./){
      $erschjahr=$1;
    }

    # Extrahiere die Signatur aus dem einen Titelsatz
#    if ($line=~m/^<tr align=center..td..a href=.http:.+?..strong..+?..strong><.a>..td..td..+?..td..td..+?..td..td..strong.(.+?)..strong...td><.tr>/){
    if ($line=~m/<span id=.rlsignature.>(.*?)<.span>/){
      push @signaturarray, $1;
    }

  }

  my $signaturstring=join(" ; ",@signaturarray);
  $signaturstring="<span id=\"rlsignature\">$signaturstring</span>";

  if ($singletit){
    # Konstruiere Tabelleneintrag der zur"uckgeliefert wird
    $retval="<td colspan=2>";

    my $verfasserstring="";

    $verfasserstring=join(" ; ",@verfasserarray);

    $retval.="<strong><span id=\"rlauthor\">$verfasserstring</span></strong><br>" if ($verfasserstring ne "");


    $retval.="<a href=\"$befehlsurl?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=2&amp;casesensitive=0&amp;maxhits=500&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;database=$database&amp;searchsingletit=$idn\">";

    # Wenn wir einen AST haben, dann hat er hoehere Prioritaet als ein der HST

    if ($ast){
      $hst=$ast;
    }

    if ($hst){
      $retval.="<strong><span id=\"rltitle\">$hst</span></strong></a>, ";
    }
    elsif ($sachlben){
      $retval.="<strong><span id=\"rltitle\">$sachlben</span></strong></a>, ";
    }
    elsif ($hst eq "" && $sachlben eq ""){
      $retval.="<strong><span id=\"rltitle\">Keine AST/HST vorhanden</span></strong></a>, ";
    }
    if ($verlag){
      $retval.="<span id=\"rlpublisher\">$verlag</span> ";
    }
    if ($erschjahr){
      $retval.="<span id=\"rlyearofpub\">$erschjahr</span>";
    }
    $retval.="</td><td><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$idn\" target=\"header\"><span id=\"rlmerken\"><img src=\"/images/openbib/3d-file-blue-clipboard.png\" height=\"29\" alt=\"In Merkliste\" border=0></span></a></td><td><b>$signaturstring</b>";
    return $retval;
  }
  else {
    return "none";
  }
}

sub conv2autoplus {

  my ($eingabe)=@_;

  my @phrasenbuf=();

  chomp($eingabe);

  # Token fuer Phrasensuche aussondern


  while ($eingabe=~/(".*?")/){
    my $phrase=$1;
    # Merken
    push @phrasenbuf, $phrase;

    # Entfernen
    $eingabe=~s/$phrase//;
  }

  # Innenliegende - durch Leerzeichen ersetzen

  $eingabe=~s/(\w)-(\w)/$1 $2/gi;


#  $eingabe=~s/\+(\w)/ $1/gi;

  $eingabe=~s/\+(\S)/ $1/gi;

  # Generell Plus vor Woertern durch Leerzeichen ersetzen

#  $eingabe=~s/(\S+)/%2B$1/gi;
  $eingabe=~s/(\S+)/%2B$1/gi;

  # Kombination -+ wird nun eliminiert
  $eingabe=~s/-%2B/-/gi;

  push @phrasenbuf, $eingabe;

  # Gemerkte Phrase werden wieder hinzugefuegt

  if ($#phrasenbuf >= 0){
     $eingabe=join(" ",@phrasenbuf);
   }

  return $eingabe;

}

sub print_recherche_hinweis {
 my ($hst,$verf,$kor,$ejahr,$issn,$isbn,$userdbh,$sessionID)=@_;

# Plus-Zeichen entfernen

  $verf=~s/%2B(\w+)/$1/g;
  $hst=~s/%2B(\w+)/$1/g;
  $kor=~s/%2B(\w+)/$1/g;
  $ejahr=~s/%2B(\w+)/$1/g;
  $isbn=~s/%2B(\w+)/$1/g;
  $issn=~s/%2B(\w+)/$1/g;


 # Haben wir eine Benutzernummer? Dann versuchen wir den 
 # Authentifizierten Sprung in die Digibib

 my $loginname="";
 my $password="";

 my $globalsessionID="$config{servername}:$sessionID";
 my $userresult=$userdbh->prepare("select user.loginname,user.pin from usersession,user where usersession.sessionid = ? and user.userid=usersession.userid") or die "Error -- $DBI::errstr";
 
 $userresult->execute($globalsessionID);
  
 if ($userresult->rows > 0){
   my $res=$userresult->fetchrow_hashref();
   
   $loginname=$res->{'loginname'};
   $password=$res->{'pin'};
 }
 $userresult->finish();
 
 
 my $authurl="";
 unless (Email::Valid->address($loginname)){

   # Hash im loginname durch %23 ersetzen

   $loginname=~s/#/\%23/;

   if ($loginname && $password){
     $authurl="&USERID=$loginname&PASSWORD=$password";
   }
 }

 my $hbzmonofernleihbaseurl=$config{hbzmonofernleih_exturl};
 my $hbzzeitfernleihbaseurl=$config{hbzzeitfernleih_exturl};
 my $dbisexturl=$config{dbis_exturl};

 print << "DIGIBIB";
<table width="100%">
<tr><th>Weitergehende Suchhinweise</th></tr>
<tr><td class="boxedclear" style="font-size:9pt">
Konnten Sie das von Ihnen gesuchte Buch oder den von Ihnen gesuchten Zeitschriftenartikel nicht im KUG finden?<br><br>
<b>B&uuml;cher</b>
<ul>
<li>Suchen Sie im Kartenkatalog einer infrage kommende Institutsbibliothek. Leider sind noch nicht alle B&uuml;cher elektronisch erfasst und damit &uuml;ber den KUG recherchierbar.</li>
<li>F&uuml;r verschiedene Institute und Seminare der Philosophischen Fakult&auml;t besteht die M&ouml;glichkeit der Suche in einem <a href="http://retro-philfak.ub.uni-koeln.de:8080/catalog/" target="_blank">Online-Kartenkatalog</a>.</li>
<li>Versuchen Sie das Buch in NRW oder deutschlandweit im Rahmen der <a href="$hbzmonofernleihbaseurl&D_PARAM_SEARCH_RLBKO=on&D_PARAM_SERVICEGROUP1.SERVICE.SEARCH_HBZ=on&D_PARAM_QUERY_bzAU=$verf&D_PARAM_QUERY_azTI=$hst&D_PARAM_QUERY_czCO=$kor&D_PARAM_QUERY_fzIB=$isbn&D_PARAM_QUERY_gzIS=$issn&D_PARAM_QUERY_hzYR=$ejahr$authurl" target="_blank">zentralen Fernleihe</a> in der Digitalen Bibliothek zu finden.</li>
</ul>
<b>Zeitschriftenartikel</b>
<ul>
<li>Suchen Sie in den elektronischen <a href="$dbisexturl" target="_blank">Fachdatenbanken</a> und den <a href="$config{ezb_exturl}" target="_blank">elektronisch verf&uuml;gbaren Zeitschriften</a> der Universit&auml;tsbibliothek.</a>
<li>Versuchen Sie den Artikel in NRW im Rahmen der <a href="$hbzzeitfernleihbaseurl&D_PARAM_SEARCH_RLBKO=on&D_PARAM_SERVICEGROUP1.SERVICE.SEARCH_ZDB=on&D_PARAM_QUERY_azTI=$hst&D_PARAM_QUERY_czCO=$kor&D_PARAM_QUERY_gzIS=$issn$authurl" target="_blank">Online-Zeitschriftenlieferung</a> in der Digitalen Bibliothek zu finden.</li>
</ul>
</td></tr>
</table>
<p>
DIGIBIB

}

sub cleansearchterm {
  my ($term)=@_;

  $term=~s/\'/ /g;

  return $term;
}

1;
