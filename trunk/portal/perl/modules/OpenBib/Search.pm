#####################################################################
#
#  OpenBib::Search.pm 
#
#  Copyright 1997-2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use DBI;

use POSIX;

# LWP fuer Buchstatus
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;

use OpenBib::Search::Util;

use OpenBib::Common::Util;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

# Module fuer SessionID
use Digest::MD5; # qw(md5 md5_hex md5_base64);

####                                                              ### 
###### B E G I N N  V A R I A B L E N D E K L A R A T I O N E N #####
####                                                              ###

#####################################################################
# Lokale Einstellungen - Allgemein 
#####################################################################

sub handler {
  
  my $r=shift;

  # Log4perl logger erzeugen

  my $logger = get_logger();
  
  #####################################################################
  ## Wandlungstabelle Erscheinungsjahroperator
  
  my %ejop=(
	    'genau' => '=',
	    'jünger' => '>',
	    'älter' => '<'
	   );
  
  my $query=Apache::Request->new($r);
  
  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
  #####################################################################
  # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen 
  #####################################################################
  
  #####################################################################
  ## Debug: Ausgabe zus"atzlicher Informationen?
  ##        0 - nein
  ##        1 - ja
  
  my $debug=($query->param('debug'))?$query->param('debug'):0;
  
  #####################################################################
  ## Searchmode: Art der Recherche
  ##               0 - Vollst"andig stamdateiorientierte Suche 
  ##               1 - Vollst"andig titelorientierte Suche
  ##               2 - Standardrecherche (Mix aus 0 und 1)
  
  my $searchmode=($query->param('searchmode'))?$query->param('searchmode'):0;
  
  #####################################################################
  ## Casesensitive: Unterscheidung Gro"s/Kleinschreibung bei SQL-Suche
  ##                0 - nein
  ##                1 - ja
  
  my $casesensitive=($query->param('casesensitive'))?$query->param('casesensitive'):0;
  
  #####################################################################
  ## Showmexintit: Anzeige der Exemplardaten (Bibliothek, Signatur, ...)
  ##               0 - Verweis auf die Exemplardaten in der Titelaufnahme
  ##               1 - Exemplardaten direkt in der Titelaufnahme
  
  my $showmexintit=($query->param('showmexintit'))?$query->param('showmexintit'):0;
  
  #####################################################################
  ## Mask: Eingabemaske ausgeben
  ##       0 - nein
  ##       1 - ja
  
  my $mask=($query->param('mask'))?$query->param('mask'):0;
  
  #####################################################################
  ## Maxhits: Maximale Trefferzahl
  ##          > 0  - gibt die maximale Zahl an
  
  my $maxhits=($query->param('maxhits'))?$query->param('maxhits'):400;
  
  #####################################################################
  ## Rating
  ##          0 - nein
  ##          1 - ja
  
  my $rating=($query->param('rating'))?$query->param('rating'):0;
  
  #####################################################################
  ## Bookinfo
  ##          0 - nein
  ##          1 - ja
  
  my $bookinfo=($query->param('bookinfo'))?$query->param('bookinfo'):0;
  
  #####################################################################
  ## Hitrange: Anzahl gleichzeitig ausgegebener Treffer bei Anfangs-Suche
  ##          >0  - gibt die maximale Zahl an
  ##          <=0 - gibt immer alle Treffer aus 
  
  my $hitrange=($query->param('hitrange'))?$query->param('hitrange'):-1;
  if ($hitrange eq "alles"){
    $hitrange=-1
  }
  
  #####################################################################
  ## Starthit: Maximale Anzahl ausgegebener Treffer bei Anfangs-Suche
  ##          >0  - hitrange Treffer werden ab dieser Nr. ausgegeben 
  
  my $starthit=($query->param('starthit'))?$query->param('starthit'):1;
  
  #####################################################################
  ## Database: Name der verwendeten SQL-Datenbank
  
  my $database=($query->param('database'))?$query->param('database'):'inst001';
  
  #####################################################################
  ## dbmode: Art des Zugriffs
  ##         1: Single-DB Single-Pool
  ##         2: Multi-DB Single-Pool (Sigel-Prefix)
  
  my $dbmode=($query->param('dbmode'))?$query->param('dbmode'):'1';
  
  if ($database eq "institute"){
    $dbmode=2;
  }
  
  #####################################################################
  ## Verknuepfung: Verkn"upfung der Eingabefelder (leere Felder werden ignoriert)
  ##               und  - Und-Verkn"upfung
  ##               oder - Oder-Verkn"upfung
  ## OBSOLET, wird jetzt feingranulierter ueber die boolX-Parameter
  ## gesteuert
  
  ## my $verknuepfung=($query->param('verknuepfung'))?$query->param('verknuepfung'):"und";
  
  #####################################################################
  ## boolX: Verkn"upfung der Eingabefelder (leere Felder werden ignoriert)
  ##        AND  - Und-Verkn"upfung
  ##        OR   - Oder-Verkn"upfung
  ##        NOT  - Und Nicht-Verknuepfung
  
  my $boolverf=($query->param('bool9'))?$query->param('bool9'):"AND";
  my $boolhst=($query->param('bool1'))?$query->param('bool1'):"AND";
  my $boolswt=($query->param('bool2'))?$query->param('bool2'):"AND";
  my $boolkor=($query->param('bool3'))?$query->param('bool3'):"AND";
  my $boolnotation=($query->param('bool4'))?$query->param('bool4'):"AND";
  my $boolisbn=($query->param('bool5'))?$query->param('bool5'):"AND";
  my $boolissn=($query->param('bool8'))?$query->param('bool8'):"AND";
  my $boolsign=($query->param('bool6'))?$query->param('bool6'):"AND";
  my $boolejahr=($query->param('bool7'))?$query->param('bool7'):"AND";
  my $boolfs=($query->param('bool10'))?$query->param('bool10'):"AND";
  my $boolmart=($query->param('bool11'))?$query->param('bool11'):"AND";
  my $boolhststring=($query->param('bool12'))?$query->param('bool12'):"AND";


  # Sicherheits-Checks

  if ($boolverf ne "AND" && $boolverf ne "OR" && $boolverf ne "NOT"){
    $boolverf="AND";
  }

  if ($boolhst ne "AND" && $boolhst ne "OR" && $boolhst ne "NOT"){
    $boolhst="AND";
  }

  if ($boolswt ne "AND" && $boolswt ne "OR" && $boolswt ne "NOT"){
    $boolswt="AND";
  }

  if ($boolkor ne "AND" && $boolkor ne "OR" && $boolkor ne "NOT"){
    $boolkor="AND";
  }

  if ($boolnotation ne "AND" && $boolnotation ne "OR" && $boolnotation ne "NOT"){
    $boolnotation="AND";
  }

  if ($boolisbn ne "AND" && $boolisbn ne "OR" && $boolisbn ne "NOT"){
    $boolisbn="AND";
  }

  if ($boolissn ne "AND" && $boolissn ne "OR" && $boolissn ne "NOT"){
    $boolissn="AND";
  }

  if ($boolsign ne "AND" && $boolsign ne "OR" && $boolsign ne "NOT"){
    $boolsign="AND";
  }

  if ($boolejahr ne "AND"){
    $boolejahr="AND";
  }

  if ($boolfs ne "AND" && $boolfs ne "OR" && $boolfs ne "NOT"){
    $boolfs="AND";
  }

  if ($boolmart ne "AND" && $boolmart ne "OR" && $boolmart ne "NOT"){
    $boolmart="AND";
  }

  if ($boolhststring ne "AND" && $boolhststring ne "OR" && $boolhststring ne "NOT"){
    $boolhststring="AND";
  }

  $boolverf="AND NOT" if ($boolverf eq "NOT");
  $boolhst="AND NOT" if ($boolhst eq "NOT");
  $boolswt="AND NOT" if ($boolswt eq "NOT");
  $boolkor="AND NOT" if ($boolkor eq "NOT");
  $boolnotation="AND NOT" if ($boolnotation eq "NOT");
  $boolisbn="AND NOT" if ($boolisbn eq "NOT");
  $boolissn="AND NOT" if ($boolissn eq "NOT");
  $boolsign="AND NOT" if ($boolsign eq "NOT");
  $boolfs="AND NOT" if ($boolfs eq "NOT");
  $boolmart="AND NOT" if ($boolmart eq "NOT");
  $boolhststring="AND NOT" if ($boolhststring eq "NOT");
  
  #####################################################################
  ## Debug schlie"st Benchmarking ein
  
  my $benchmark;
  
  if ($debug){
    $benchmark=1;
    use Benchmark;
  }
  
  #####################################################################
  ## Sortierung der Titellisten
  
  my $sorttype=($query->param('sorttype'))?$query->param('sorttype'):"author";
  my $sortorder=($query->param('sortorder'))?$query->param('sortorder'):"up";
  
  #####################################################################
  # Variablen in <FORM>, die den Such-Flu"s steuern 
  #####################################################################
  
  #####################################################################
  ## Initialsearch: 
  
  my $initialsearch=$query->param('initialsearch') || '';
  my $generalsearch=$query->param('generalsearch') || '';
  my $stammsearch=$query->param('stammsearch') || '';
  my $stammvalue=$query->param('stammvalue') || '';
  my $searchall=$query->param('searchall') || '';
  my $swtindex=$query->param('swtindex') || '';
  my $swtindexall=$query->param('swtindexall') || '';
  my $searchsingletit=$query->param('searchsingletit') || '';
  my $searchsingleaut=$query->param('searchsingleaut') || '';
  my $searchsingleswt=$query->param('searchsingleswt') || '';
  my $searchsinglenot=$query->param('searchsinglenot') || '';
  my $searchsinglekor=$query->param('searchsinglekor') || '';
  my $searchsinglemex=$query->param('searchsinglemex') || '';
  my $searchmultipleaut=$query->param('searchmultipleaut') || '';
  my $searchmultipletit=$query->param('searchmultipletit') || '';
  my $searchmultiplekor=$query->param('searchmultiplekor') || '';
  my $searchmultiplenot=$query->param('searchmultiplenot') || '';
  my $searchmultipleswt=$query->param('searchmultipleswt') || '';
  my $searchmultiplemex=$query->param('searchmultiplemex') || '';
  my $searchtitofaut=$query->param('searchtitofaut') || '';
  my $searchtitofswt=$query->param('searchtitofswt') || '';
  my $searchtitofkor=$query->param('searchtitofkor') || '';
  my $searchtitofnot=$query->param('searchtitofnot') || '';
  my $searchtitofurh=$query->param('searchtitofurh') || '';
  my $searchtitofurhkor=$query->param('searchtitofurhkor') || '';
  my $searchtitofmex=$query->param('searchtitofmex') || '';
  my $searchgtmtit=$query->param('gtmtit') || '';
  my $searchgtftit=$query->param('gtftit') || '';
  my $searchinvktit=$query->param('invktit') || '';
  my $searchgtf=$query->param('gtf') || '';
  my $searchinvk=$query->param('invk') || '';
  my $fs=$query->param('fs') || ''; # Freie Suche 
  my $mart=$query->param('mart') || ''; # MedienArt
  my $verf=$query->param('verf') || ''; 
  my $hst=$query->param('hst') || '';
  my $hststring=$query->param('hststring') || '';
  my $swt=$query->param('swt') || '';
  my $kor=$query->param('kor') || '';
  my $sign=$query->param('sign') || '';
  my $isbn=$query->param('isbn') || '';
  my $issn=$query->param('issn') || '';
  my $notation=$query->param('notation') || '';
  my $ejahr=$query->param('ejahr') || '';
  my $ejahrop=$query->param('ejahrop') || '';
  my $freequery=$query->param('freequery') || '';
  
  my $withumlaut=0;
  
  #####################################################################
  # Sonstige Variablen 
  #####################################################################
  
  my %titeltyp=(
		'1' => 'Einb&auml;ndige Werke und St&uuml;cktitel',
		'2' => 'Gesamtaufnahme fortlaufender Sammelwerke',
		'3' => 'Gesamtaufnahme mehrb&auml;ndig begrenzter Werke',
		'4' => 'Bandauff&uuml;hrung',
		'5' => 'Unselbst&auml;ndiges Werk',
		'6' => 'Allegro-Daten',
		'7' => 'Lars-Daten',
		'8' => 'Sisis-Daten',
		'9' => 'Sonstige Daten'  
	       );
  
  #####                                                          ######
  ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
  #####                                                          ######
  
  ###########                                               ###########
  ############## B E G I N N  P R O G R A M M F L U S S ###############
  ###########                                               ###########
  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  
  #####################################################################
  # Dynamische Definition diverser Variablen
  
  # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
  my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description from dbinfo") or $logger->error($DBI::errstr);
  $dbinforesult->execute() or $logger->error($DBI::errstr);;
  
  my %sigel=();
  my %bibinfo=();
  my %dbinfo=();
  my %dbases=();
  
  while (my $result=$dbinforesult->fetchrow_hashref()){
    my $dbname=$result->{'dbname'};
    my $sigel=$result->{'sigel'};
    my $url=$result->{'url'};
    my $description=$result->{'description'};
    
    ##################################################################### 
    ## Wandlungstabelle Bibliothekssigel <-> Bibliotheksname
    
    $sigel{"$sigel"}="$description";
    
    #####################################################################
    ## Wandlungstabelle Bibliothekssigel <-> Informations-URL
    
    $bibinfo{"$sigel"}="$url";
    
    #####################################################################
    ## Wandlungstabelle  Name SQL-Datenbank <-> Datenbankinfo
    
    # Wenn ein URL fuer die Datenbankinformation definiert ist, dann wird
    # damit verlinkt
    
    if ($url ne ""){
      $dbinfo{"$dbname"}="<a href=\"$url\" target=_blank>$description</a>";
    }
    else {
      $dbinfo{"$dbname"}="$description";
    }
    
    #####################################################################
    ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
    
    $dbases{"$dbname"}="$sigel";
  }
  
  $sigel{''}="Unbekannt";
  $bibinfo{''}="http://www.ub.uni-koeln.de/dezkat/bibinfo/noinfo.html";
  $dbases{''}="Unbekannt";

  #####################################################################
  ## Ausleihkonfiguration fuer den Katalog einlesen

  $dbinforesult=$sessiondbh->prepare("select circ,circurl,circcheckurl from dboptions where dbname = ?") or $logger->error($DBI::errstr);
  $dbinforesult->execute($database) or $logger->error($DBI::errstr);;

  my $circ=0;
  my $circurl="";
  my $circcheckurl="";

  while (my $result=$dbinforesult->fetchrow_hashref()){
    $circ=$result->{'circ'};
    $circurl=$result->{'circurl'};
    $circcheckurl=$result->{'circcheckurl'};
  }

  $dbinforesult->finish();
  
  
  # Generiere SessionID, wenn noch keine vorhanden ist
  
  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Search::Util::print_warning("Ung&uuml;ltige Session",$r);
    goto LEAVEPROG;
  }

  
  #####################################################################
  ## Eigentliche Suche (default) 
  
  if ($swtindex ne ""){
    
    print $r->send_http_header("text/html");
    my $fullpoolname=$sigel{$dbases{$database}};
    #    print $query->start_html(-title=>"Such-Client zur Datenbank: $fullpoolname -- Schlagwortindex '$swtindex'",-BGCOLOR=>"white",-style=>{"src"=>"/styles/openbib.css"});
    
    print << "HEAD3";
<html>
<head>$stylesheet<title>Such-Client zur Datenbank: $fullpoolname</title>
</head><body bgcolor=\"white\">
HEAD3
    
    my @requests=("select schlagw from swt where schlagw like '$swtindex%' order by schlagw");
    my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    
    my @schlagwte=sort @temp;
    my $schlagw;
    my $swtcount;
    $swtcount=0;
    
    
    if ($#schlagwte > 5000){
      print "<h1>$fullpoolname:</h1>\n";
      print "<h2>Es wurden zu viele Schlagworte beginnend mit <b>'$swtindex'</b></h2>\n";
      print "Mehr als 5000 Schlagworte wurden gefunden. Eine vollst&auml;ndige Darstellung ist daher leider nicht m&ouml;glich. Wir bitten um Ihr Verst&auml;ndnis.<p>Erweitern Sie daher bitte Ihre Anfrage um weitere Zeichen, um die Treffermenge weiter einzuschr&auml;nken.<p>\n";
      
      goto LEAVEPROG;
      
    }
    
    print "<h1>$fullpoolname:</h1>\n";
    print "<h2>Index der Schlagworte beginnend mit <b>'$swtindex'</b></h2>\n";
    
    print "Es wurden ".($#schlagwte+1)." Schlagworte beginnend mit <b>'$swtindex'</b> in dieser Datenbank gefunden<p>\n";
    
    # Zuerst alle vergebenen SWT-Idns in der Alphabetischen Reihenfolge
    # ihrer Schlagworte holen
    
    print "<table cellpadding=2>\n";
    
    if ($#schlagwte+1 == 1){
      print "<tr><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td></tr>\n";
    }
    elsif ($#schlagwte+1 == 2){
      print "<tr><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td></tr>\n";
    }
    elsif ($#schlagwte+1 > 2){
      print "<tr><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td></tr>\n";
    }
    
    while ($swtcount <= $#schlagwte){
      $schlagw=$schlagwte[$swtcount];
      @requests=("select idn from swt where schlagw like '$schlagw'");
      my @swtidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      @requests=("select titidn from titswtlok where swtverw=".$swtidns[0]);
      my $swtanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
      if ($swtcount%3 == 0){
	print "<tr><td><a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchtitofswt=".$swtidns[0]."\">";
	print "$schlagw</a></td><td>$swtanzahl</td>";
      }
      elsif ($swtcount%3 == 1) {
	print "<td><a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchtitofswt=".$swtidns[0]."\">";
	print "$schlagw</a></td><td>$swtanzahl</td>";
      }
      elsif ($swtcount%3 == 2){
	print "<td><a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchtitofswt=".$swtidns[0]."\">";
	print "$schlagw</a></td><td>$swtanzahl</td></tr>\n";
      }
      $swtcount++;
    }
    print "</table>";
    
    goto LEAVEPROG;
    
  }
  
  if ($swtindexall eq "Schlagwortindex"){
    print $r->send_http_header("text/html");
    my $fullpoolname=$sigel{$dbases{$database}};
    #    print $query->start_html(-title=>"Such-Client zur Datenbank: $fullpoolname -- Schlagwortindex",-BGCOLOR=>"white",-style=>{"src"=>"/styles/openbib.css"});
    
    print << "HEAD2";
<html>
<head>$stylesheet<title>Such-Client zur Datenbank: $fullpoolname</title>
</head><body bgcolor=\"white\">
HEAD2
    
    
    my @requests=("select schlagw from swt order by schlagw");
    my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    
    my @schlagwte=sort @temp;
    my $schlagw;
    my $swtcount;
    $swtcount=0;
    
    print "<h1>Schlagwortindex der Datenbank $database</h1>\n";
    
    print "Es wurden ".$#schlagwte." Schlagworte in dieser Datenbank gefunden<p>\n";
    
    # Zuerst alle vergebenen SWT-Idns in der Alphabetischen Reihenfolge
    # ihrer Schlagworte holen
    
    print "<table cellpadding=2>\n";
    print "<tr><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td><td bgcolor=\"lightblue\">Schlagwort</td><td bgcolor=\"lightblue\">Titelzahl</td></tr>\n";
    
    while ($swtcount < $#schlagwte){
      $schlagw=$schlagwte[$swtcount];
      @requests=("select idn from swt where schlagw like '$schlagw'");
      my @swtidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      @requests=("select titidn from titswtlok where swtverw=".$swtidns[0]);
      my $swtanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
      if ($swtcount%3 == 0){
	print "<tr><td><a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchtitofswt=".$swtidns[0]."\">";
	print "$schlagw</a></td><td>$swtanzahl</td>";
      }
      elsif ($swtcount%3 == 1) {
	print "<td><a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchtitofswt=".$swtidns[0]."\">";
	print "$schlagw</a></td><td>$swtanzahl</td>";
      }
      elsif ($swtcount%3 == 2){
	print "<td><a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchtitofswt=".$swtidns[0]."\">";
	print "$schlagw</a></td><td>$swtanzahl</td></tr>\n";
      }
      $swtcount++;
    }
    print "</table>";
    
    goto LEAVEPROG;
  }
  
  # Standard Ergebnisbehandlung bei Suchanfragen
  
  print $r->send_http_header("text/html");
  
  my $fullpoolname=$sigel{$dbases{$database}};
  
  print << "HEAD1";
<html>
<head>$stylesheet<title>Such-Client zur Datenbank: $fullpoolname</title>
</head><body bgcolor=\"white\">
HEAD1

  #####################################################################
  
  my $suchbegriff;
  
  if ($stammsearch){
    $initialsearch=$stammsearch;
    $suchbegriff=OpenBib::Search::Util::input2sgml($stammvalue,1,$withumlaut);
  }
  
  #####################################################################
  
  if ($searchall){ # Standardsuche
    
    my %alltitidns;
    
    my $sqlselect="";
    my $sqlfrom="";
    my $sqlwhere="";
    
    
    if ($fs){	
      my @fsidns;
      
      $fs=OpenBib::Search::Util::input2sgml($fs,1,$withumlaut);
      $fs="match (verf,hst,kor,swt,notation,sign,isbn,issn) against ('$fs' IN BOOLEAN MODE)";
    }
    
    if ($verf){	
      my @autidns;
      
      $verf=OpenBib::Search::Util::input2sgml($verf,1,$withumlaut);
      $verf="match (verf) against ('$verf' IN BOOLEAN MODE)";
    }
    
    my @tittit;
    
    if ($hst){
      $hst=OpenBib::Search::Util::input2sgml($hst,1,$withumlaut);
      $hst="match (hst) against ('$hst' IN BOOLEAN MODE)";
    }
    
    my @swtidns;
    
    if ($swt){
      $swt=OpenBib::Search::Util::input2sgml($swt,1,$withumlaut);
      $swt="match (swt) against ('$swt' IN BOOLEAN MODE)";
    }
    
    my @koridns;
    
    if ($kor){
      $kor=OpenBib::Search::Util::input2sgml($kor,1,$withumlaut);
      $kor="match (kor) against ('$kor' IN BOOLEAN MODE)";
    }
    
    my $notfrom="";
    my @notidns;
    
    # TODO: SQL-Statement fuer Notationssuche optimieren
    
    if ($notation){
      $notation=OpenBib::Search::Util::input2sgml($notation,1,$withumlaut);
      $notation="((notation.notation like '$notation%' or notation.benennung like '$notation%') and search.verwidn=titnot.titidn and notation.idn=titnot.notidn)";
      $notfrom=", notation, titnot";
    }
    
    my $signfrom="";
    my @signidns;
    
    if ($sign){
      $sign=OpenBib::Search::Util::input2sgml($sign,1,$withumlaut);
      $sign="(search.verwidn=mex.titidn and mex.idn=mexsign.mexidn and mexsign.signlok like '$sign%')";
      $signfrom=", mex, mexsign";
    }
    
    my @isbnidns;
    
    if ($isbn){
      $isbn=OpenBib::Search::Util::input2sgml($isbn,1,$withumlaut);
      $isbn=~s/-//g;
      $isbn="match (isbn) against ('$isbn' IN BOOLEAN MODE)";
    }
    
    my @issnidns;
    
    if ($issn){
      $issn=OpenBib::Search::Util::input2sgml($issn,1,$withumlaut);
      $issn=~s/-//g;
      $issn="match (issn) against ('$issn' IN BOOLEAN MODE)";
    }
    
    my @martidns;
    
    if ($mart){
      $mart=OpenBib::Search::Util::input2sgml($mart,1,$withumlaut);
      $mart="match (artinh) against ('$mart' IN BOOLEAN MODE)";
    }
    
    my @hststringidns;
    
    if ($hststring){
      $hststring=OpenBib::Search::Util::input2sgml($hststring,1,$withumlaut);
      $hststring="(search.hststring = '$hststring')";
    }

    my $ejtest;
    
    ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
    if (!$ejtest){
      $ejahr=""; # Nur korrekte Jahresangaben werden verarbeitet
    }              # alles andere wird ignoriert...
    
    if ($ejahr){	   
      $ejahr="$boolejahr ejahr".$ejahrop."$ejahr";
    }
    
    my @tidns;
    
    # Einfuegen der Boolschen Verknuepfungsoperatoren in die SQL-Queries
    
    if (($ejahr) && ($boolejahr eq "OR")){
      OpenBib::Search::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Ihr Verst&auml;ndnis f&uuml;r diese Ma&szlig;nahme");
      goto LEAVEPROG;
    }
    
    # SQL-Search
    
    my $notfirstsql=0;
    my $sqlquerystring="";
    
    if ($fs){
      $notfirstsql=1;
      $sqlquerystring=$fs;
    }
    if ($hst){
      if ($notfirstsql){
	$sqlquerystring.=" $boolhst ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$hst;
    }
    if ($verf){
      if ($notfirstsql){
	$sqlquerystring.=" $boolverf ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$verf;
    }
    if ($kor){
      if ($notfirstsql){
	$sqlquerystring.=" $boolkor ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$kor;
    }
    if ($swt){
      if ($notfirstsql){
	$sqlquerystring.=" $boolswt ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$swt;
    }
    if ($notation){
      if ($notfirstsql){
	$sqlquerystring.=" $boolnotation ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$notation;
    }
    if ($isbn){
      if ($notfirstsql){
	$sqlquerystring.=" $boolisbn ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$isbn;
    }
    if ($issn){
      if ($notfirstsql){
	$sqlquerystring.=" $boolissn ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$issn;
    }
    if ($sign){
      if ($notfirstsql){
	$sqlquerystring.=" $boolsign ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$sign;
    }
    if ($mart){
      if ($notfirstsql){
	$sqlquerystring.=" $boolmart ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$mart;
    }
    if ($hststring){
      if ($notfirstsql){
        $sqlquerystring.=" $boolhststring ";
      }
      $notfirstsql=1;
      $sqlquerystring.=$hststring;
    }
   
    if ($ejahr){
      if ($sqlquerystring eq ""){
	OpenBib::Search::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Ihr Verst&auml;ndnis f&uuml;r diese Ma&szlig;nahme");
	goto LEAVEPROG;
      }
      else {
	$sqlquerystring="$sqlquerystring $ejahr";
      }
    }
    
    $sqlquerystring="select verwidn from search$signfrom$notfrom where $sqlquerystring limit $maxhits";
   
    my @requests=($sqlquerystring);
    
    @tidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    
    # Ende Initial Search
    
    # Kein Treffer
    if ($#tidns == -1){
      OpenBib::Search::Util::no_result();
    }
    
    # Genau ein Treffer
    if ($#tidns == 0){
      OpenBib::Search::Util::get_tit_by_idn("$tidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    
    # Mehr als ein Treffer
    if ($#tidns > 0){
      my $treffer=$#tidns+1;
      my $nextstarthit;
      
      if ($hitrange>0){
	
	$nextstarthit=$starthit+$hitrange;
	
	if ($verf=~/au=\((.*)\)/){
	  $verf=$1;
	}
	
	if ($hst=~/ti=\((.*)\)/){
	  $hst=$1;
	}
	
	if ($kor=~/ko=\((.*)\)/){
	  $kor=$1;
	}
	
	if ($swt=~/sw=\((.*)\)/){
	  $swt=$1;
	}
	
	if ($notation=~/no=\((.*)\)/){
	  $notation=$1;
	}
	
	if ($ejahr=~/ej=\((.*)\)/){
	  $ejahr=$1;
	}
	
	my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	#	    print "treffer ".$treffer."nextstarthit $nextstarthit endhit $endhit nextrange $nextrange<p>";
	print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	my $navigate;
	
	if ($nextstarthit-$hitrange-1 > 0){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&searchall=1&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&verf=$verf&hst=$hst&swt=$swt&kor=$kor&notation=$notation&ejahr=$ejahr&ejahrop=$ejahrop&bool1=$boolhst&bool2=$boolswt&bool3=$boolkor&bool4=$boolnotation&bool5=$boolisbn&bool6=$boolsign&bool7=$boolejahr\">Vorige ".$hitrange." Treffer</a>\n";
	  $navigate=1;
	}
	
	if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&searchall=1&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&verf=$verf&hst=$hst&swt=$swt&kor=$kor&notation=$notation&ejahr=$ejahr&ejahrop=$ejahrop&bool1=$boolhst&bool2=$boolswt&bool3=$boolkor&bool4=$boolnotation&bool5=$boolisbn&bool6=$boolsign&bool7=$boolejahr\">N&auml;chste ".$nextrange." Treffer</a>\n";
	  $navigate=1;
	}
	print "<hr>\n" if ($navigate);
      }
      else {
	
	OpenBib::Search::Util::print_inst_head($database,"base");
#	OpenBib::Search::Util::print_sort_nav_updown($r);
	OpenBib::Common::Util::print_sort_nav($r,'',0);        
	
	OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
	
      }
      
      print "<table cellpadding=2>\n";
      
      if ($dbmode == 1){
	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";
	
      }
      if ($dbmode == 2){
	print "<tr><td>Katalog</td><td>Titel</td></tr>\n";
      }
      
      my $maxcount;
      
      if ($hitrange <= 0){
	$maxcount=0;
      }	
      
      my $idn;
      
      my @outputbuffer=();
      my $outidx=0;
      
      foreach $idn (@tidns){
	if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	  $maxcount++;
	  next;
	}
	
	my $omode=($dbmode == 2)?8:5;
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","none",$omode,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	  $maxcount++;		
	}
	
	if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	  last;
	}
	
      }	    
      
      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      my $linecolor="aliceblue";
      
      foreach $outidx (@sortedoutputbuffer){
	
	$outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	
	# Eintraege merken fuer Lastresultset
	
	my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	my ($resdatabase)=$outidx=~/database=(\w+)/;
	push @resultset, "$resdatabase:$katkey";
	
	print $outidx;
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
	
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      print "</table>";
      
      if ($dbmode == 1){
	print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";
      }
    }	
    goto LEAVEPROG;
  }
  
  ###############################################################################
  
  if ($generalsearch) { # Nachdem initial per SQL nach den Usereingaben eine Treffermenge gefunden wurde, geht es nun exklusiv in der SQL-DB weiter
    
    if (($generalsearch=~/^verf/)||($generalsearch=~/^pers/)){
      if ($searchmode == 1){
	$searchtitofaut=$query->param("$generalsearch");
      }
      else {		
	my $verfidn=$query->param("$generalsearch");
	OpenBib::Search::Util::get_aut_set_by_idn("$verfidn",$dbh,$searchmultipleaut,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
	goto LEAVEPROG;
      }
    } 
    
    if ($generalsearch=~/^kor/){
      if ($searchmode == 1){
	$searchtitofkor=$query->param("$generalsearch");
      }
      else {		
	my $koridn=$query->param("$generalsearch");
	OpenBib::Search::Util::get_kor_set_by_idn("$koridn",$dbh,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
	goto LEAVEPROG;
      }
    } 
    
    if ($generalsearch=~/^urh/){
      if ($searchmode == 1){
	$searchtitofurh=$query->param("$generalsearch");
      }
      else {		
	my $koridn=$query->param("$generalsearch");
	OpenBib::Search::Util::get_kor_set_by_idn("$koridn",$dbh,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
	goto LEAVEPROG;
      }
    } 
    
    if ($generalsearch=~/^gtftit/){
      my $gtftit=$query->param("$generalsearch");
      my @requests=("select titidn from titgtf where verwidn=$gtftit");
      my @gtfidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      
      if ($#gtfidns == -1){
	OpenBib::Search::Util::no_result();
      }
      
      if ($#gtfidns == 0){
	OpenBib::Search::Util::get_tit_by_idn($gtfidns[0],"none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      }
      
      if ($#gtfidns > 0){
	my $treffer=$#gtfidns+1;
	my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
	my $nextstarthit;
	
	if ($hitrange>0){
	  
	  $nextstarthit=$starthit+$hitrange;
	  
	  my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	  my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;

	  print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	  
	  my $navigate;
	  if ($nextstarthit-$hitrange-1 > 0){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&generalsearch=gtftit&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&gtftit=$gtftit\">Vorige ".$hitrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  
	  if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&generalsearch=gtftit&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&gtftit=$gtftit\">N&auml;chste ".$nextrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  print "<hr>\n" if ($navigate);
	}
	else {
	  
	  OpenBib::Search::Util::print_inst_head($database,"base");
#	  OpenBib::Search::Util::print_sort_nav_updown($r);
	  OpenBib::Common::Util::print_sort_nav($r,'',0);        
	  OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
	  
	}
	
	my $maxcount;
	
	if ($hitrange <= 0){
	  $maxcount=0;
	}	
	print "<table cellpadding=2>\n";
	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";
	my $gtfidn;
	
	my @outputbuffer=();
	my $outidx=0;
	
	foreach $gtfidn (@gtfidns){
	  if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	    $maxcount++;
	    next;
	  }
	  
	  if (length($gtfidn)>0){
	    $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$gtfidn","$gtftit",6,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	    $maxcount++;		
	  }
	  
	  if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	    last;
	  }
	  
	}	    
	
	my @sortedoutputbuffer=();
	
	my @resultset=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
	my $linecolor="aliceblue";
	
	foreach $outidx (@sortedoutputbuffer){
	  
	  $outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	  
	  # Eintraege merken fuer Lastresultset
	  
	  my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	  my ($resdatabase)=$outidx=~/database=(\w+)/;
	  push @resultset, "$resdatabase:$katkey";
	  
	  print $outidx;
	  
	  if ($linecolor eq "white"){
	    $linecolor="aliceblue";
	  }
	  else {
	    $linecolor="white";
	  }
	  
	}
	
	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
	
	print "</table>";
	print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";;  
      }
      goto LEAVEPROG;
    }
    
    if ($generalsearch=~/^gtmtit/){
      my $gtmtit=$query->param("$generalsearch");
      my @requests=("select titidn from titgtm where verwidn=$gtmtit");
      my @gtmidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      
      if ($#gtmidns == -1){
	OpenBib::Search::Util::no_result();
      }
      
      if ($#gtmidns == 0){
	OpenBib::Search::Util::get_tit_by_idn("$gtmidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      }
      
      if ($#gtmidns > 0){
	my $treffer=$#gtmidns+1;
	my $nextstarthit;
	$maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
	
	if ($hitrange>0){
	  
	  $nextstarthit=$starthit+$hitrange;
	  
	  my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	  my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	  #	    print "treffer ".$treffer."nextstarthit $nextstarthit endhit $endhit nextrange $nextrange<p>";
	  print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	  
	  my $navigate;
	  if ($nextstarthit-$hitrange-1 > 0){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&generalsearch=gtmtit&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&gtmtit=$gtmtit\">Vorige ".$hitrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  
	  if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&generalsearch=gtmtit&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&gtmtit=$gtmtit\">N&auml;chste ".$nextrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  print "<hr>\n" if ($navigate);
	}
	else {
	  OpenBib::Search::Util::print_inst_head($database,"base");
#	  OpenBib::Search::Util::print_sort_nav_updown($r);
	  OpenBib::Common::Util::print_sort_nav($r,'',0);        
	  OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
	}
	my $maxcount;
	if ($hitrange <= 0){
	  $maxcount=0;
	}	
	print "<table cellpadding=2>\n";
	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";	    
	my $idn;
	
	my @outputbuffer=();
	my $outidx=0;
	
	foreach $idn (@gtmidns){
	  if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	    $maxcount++;
	    next;
	  }
	  
	  if (length($idn)>0){
	    $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","$gtmtit",7,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	    $maxcount++;		
	  }
	  
	  if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	    last;
	  }
	  
	}	    
	
	my @sortedoutputbuffer=();
	
	my @resultset=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
	my $linecolor="aliceblue";
	
	foreach $outidx (@sortedoutputbuffer){
	  
	  $outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	  
	  # Eintraege merken fuer Lastresultset
	  
	  my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	  my ($resdatabase)=$outidx=~/database=(\w+)/;
	  push @resultset, "$resdatabase:$katkey";
	  
	  print $outidx;
	  
	  if ($linecolor eq "white"){
	    $linecolor="aliceblue";
	  }
	  else {
	    $linecolor="white";
	  }
	  
	}
	
	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
	
	print "</table>";
	print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";;  
      }
      goto LEAVEPROG;
    }
    
    if ($generalsearch=~/^invktit/){
      my $invktit=$query->param("$generalsearch");
      my @requests=("select titidn from titinverkn where titverw=$invktit");
      my @invkidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      
      if ($#invkidns == -1){
	OpenBib::Search::Util::no_result();
      }
      
      if ($#invkidns == 0){
	OpenBib::Search::Util::get_tit_by_idn("$invkidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      }
      
      if ($#invkidns > 0){
	my $treffer=$#invkidns+1;
	my $nextstarthit;
	my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
	
	if ($hitrange>0){
	  
	  $nextstarthit=$starthit+$hitrange;
	  
	  my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	  my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	  print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer gefundenen Titeln</h1>\n";	    
	  
	  my $navigate;
	  if ($nextstarthit-$hitrange-1 > 0){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&generalsearch=invktit&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&invktit=$invktit\">Vorige ".$hitrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  
	  if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&generalsearch=invktit&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&invktit=$invktit\">N&auml;chste ".$nextrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  print "<hr>\n" if ($navigate);
	}
	else {
	  OpenBib::Search::Util::print_inst_head($database,"base");
#	  OpenBib::Search::Util::print_sort_nav_updown($r);
	  OpenBib::Common::Util::print_sort_nav($r,'',0);        
	  OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
	}
	
	my $maxcount;
	if ($hitrange <= 0){
	  $maxcount=0;
	}	
	print "<table cellpadding=2>\n";
	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";	    
	my $idn;
	
	my @outputbuffer=();
	my $outidx=0;
	
	foreach $idn (@invkidns){
	  if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	    $maxcount++;
	    next;
	  }
	  
	  if (length($idn)>0){
	    $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","$invktit",8,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	    $maxcount++;		
	  }
	  
	  if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	    last;
	  }
	  
	}	    
	
	my @sortedoutputbuffer=();
	
	my @resultset=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
	my $linecolor="aliceblue";
	
	foreach $outidx (@sortedoutputbuffer){
	  
	  $outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	  
	  # Eintraege merken fuer Lastresultset
	  
	  my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	  my ($resdatabase)=$outidx=~/database=(\w+)/;
	  push @resultset, "$resdatabase:$katkey";
	  
	  print $outidx;
	  
	  if ($linecolor eq "white"){
	    $linecolor="aliceblue";
	  }
	  else {
	    $linecolor="white";
	  }
	  
	}
	
	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
	
	print "</table>";
	print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";;  
      }
      goto LEAVEPROG;
    }
    
    if ($generalsearch=~/^mextit/){
      my $mextit=$query->param("$generalsearch");
      my @requests=("select idn from mex where titidn=$mextit");
      my @mexidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      
      if ($#mexidns == -1){
	OpenBib::Search::Util::no_result();
      }
      
      if ($#mexidns == 0){
	OpenBib::Search::Util::get_mex_by_idn("$mexidns[0]",3,$dbh,$benchmark,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%sigel,\%dbases,\%bibinfo,$searchmultiplemex,$sessionID);
      }
      
      if ($#mexidns > 0){
	print "<table cellpadding=2>";
	print "<tr><td>Suche</td><td>Besitzende Bibliothek, Signatur(en)</td></tr>\n";
	my $idn;
	foreach $idn (@mexidns){
	  if (length($idn)>0){
	    OpenBib::Search::Util::get_mex_by_idn("$idn",5,$dbh,$benchmark,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%sigel,\%dbases,\%bibinfo,$searchmultiplemex,$sessionID);
	  }
	}
	print "\n";
	print "</table>";
	print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";;  
      }
      goto LEAVEPROG;
    }
    
    if ($generalsearch=~/^hst/){
      my $titidn=$query->param("$generalsearch");
      OpenBib::Search::Util::get_tit_by_idn("$titidn","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      goto LEAVEPROG;
    }
    
    if ($generalsearch=~/^swt/){
      if ($searchmode == 1){
	$searchtitofswt=$query->param("$generalsearch");
      }
      else {
	my $swtidn=$query->param("$generalsearch");
	OpenBib::Search::Util::get_swt_by_idn("$swtidn",3,$dbh,$benchmark,$searchmultipleswt,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,$sessionID);
	goto LEAVEPROG;
      }
    } 
    
    if ($generalsearch=~/^not/){
      if ($searchmode == 1){
	$searchtitofnot=$query->param("notation");
      }
      else {
	my $notidn=$query->param("notation");
	OpenBib::Search::Util::get_not_by_idn("$notidn",3,$dbh,$benchmark,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
	goto LEAVEPROG;
      }
    } 
    
    if ($generalsearch=~/^singlegtm/){
      my $titidn=$query->param("$generalsearch");
      OpenBib::Search::Util::get_tit_by_idn("$titidn","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      goto LEAVEPROG;
    } 
    
    if ($generalsearch=~/^singlegtf/){
      my $titidn=$query->param("$generalsearch");
      OpenBib::Search::Util::get_tit_by_idn("$titidn","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      goto LEAVEPROG;
    } 
  }
  
  #####################################################################
  
  if ($searchmultipletit){
    my @mtitidns=$query->param('searchmultipletit');
    print "<h1>Ausgew&auml;hlte Titel</h1>\n";
    
    my $mtit;
    foreach $mtit (@mtitidns){
      OpenBib::Search::Util::get_tit_by_idn("$mtit","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchmultipleaut){
    my @mautidns=$query->param('searchmultipleaut');
    print "<h1>Ausgew&auml;hlte Autoren</h1>\n";
    
    my $maut;
    foreach $maut (@mautidns){
      OpenBib::Search::Util::get_aut_set_by_idn("$maut",$dbh,$searchmultipleaut,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
    }
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchmultiplekor){
    my @mkoridns=$query->param('searchmultiplekor');
    print "<h1>Ausgew&auml;hlte K&ouml;rperschaften</h1>\n";
    
    my $mkor;
    foreach $mkor (@mkoridns){
      OpenBib::Search::Util::get_kor_set_by_idn("$mkor",$dbh,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
    }
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchmultiplenot){
    my @mtitidns=$query->param('searchmultipletit');
    print "<h1>Ausgew&auml;hlte Titel</h1>\n";
    
    my $mtit;
    foreach $mtit (@mtitidns){
      OpenBib::Search::Util::get_tit_by_idn("$mtit","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchmultipleswt){
    my @mswtidns=$query->param('searchmultipleswt');
    print "<h1>Ausgew&auml;hlte Schlagworte</h1>\n";
    
    my $mswt;
    foreach $mswt (@mswtidns){
      OpenBib::Search::Util::get_swt_by_idn("$mswt",3,$dbh,$benchmark,$searchmultipleswt,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,$sessionID);
    }
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchmultiplemex){
    my @mmexidns=$query->param('searchmultiplemex');
    print "<h1>Ausgew&auml;hlte Exemplardaten</h1>\n";
    
    my $mmex;
    foreach $mmex (@mmexidns){
      OpenBib::Search::Util::get_mex_by_idn("$mmex",3,$dbh,$benchmark,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%sigel,\%dbases,\%bibinfo,$searchmultiplemex,$sessionID);
    }
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchsingletit){
    OpenBib::Search::Util::get_tit_by_idn("$searchsingletit","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchsingleswt){
    if ($searchmode == 1){
      $searchtitofswt=$searchsingleswt;
    }
    else {		
      OpenBib::Search::Util::get_swt_by_idn("$searchsingleswt",3,$dbh,$benchmark,$searchmultipleswt,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,$sessionID);
      goto LEAVEPROG;	
    }
  }    
  
  ######################################################################
  
  if ($searchsinglekor){
    if ($searchmode == 1){
      $searchtitofkor=$searchsinglekor;
    }
    else {		
      OpenBib::Search::Util::get_kor_set_by_idn("$searchsinglekor",$dbh,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
      goto LEAVEPROG;	
    }
  }    
  
  ######################################################################
  
  if ($searchsinglenot){
    if ($searchmode == 1){
      $searchtitofnot=$searchsinglenot;
    }
    else {		
      OpenBib::Search::Util::get_not_by_idn("$searchsinglenot",3,$dbh,$benchmark,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
      goto LEAVEPROG;	
    }
  }    
  
  #####################################################################
  
  if ($searchsingleaut){
    if ($searchmode == 1){
      $searchtitofaut=$searchsingleaut;
    }
    else {		
      OpenBib::Search::Util::get_aut_set_by_idn("$searchsingleaut",$dbh,$searchmultipleaut,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID);
      goto LEAVEPROG;	
    }
  }    
  
  #####################################################################
  
  if ($searchsinglemex){
    OpenBib::Search::Util::get_mex_by_idn("$searchsinglemex",3,$dbh,$benchmark,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%sigel,\%dbases,\%bibinfo,$searchmultiplemex,$sessionID);
    goto LEAVEPROG;	
  }    
  
  #####################################################################
  
  if ($searchtitofaut){
    my @requests=("select titidn from titverf where verfverw=$searchtitofaut","select titidn from titpers where persverw=$searchtitofaut","select titidn from titgpers where persverw=$searchtitofaut");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);	
    
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
    }
    
    if ($#titelidns == 0){
      OpenBib::Search::Util::get_tit_by_idn("$titelidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    
    if ($#titelidns > 0){
      my $treffer=$#titelidns+1;
      my $nextstarthit;
      my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
      
      if ($hitrange>0){
	
	$nextstarthit=$starthit+$hitrange;
	
	my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	
	my $navigate;
	if ($nextstarthit-$hitrange-1 > 0){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&searchtitofaut=$searchtitofaut\">Vorige ".$hitrange." Treffer</a>\n";
	  $navigate=1;
	}
	
	if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&searchtitofaut=$searchtitofaut\">N&auml;chste ".$nextrange." Treffer</a>\n";
	  $navigate=1;
	}
	print "<hr>\n" if ($navigate);
      }
      else {
	OpenBib::Search::Util::print_inst_head($database,"base");
#	OpenBib::Search::Util::print_sort_nav_updown($r);
	OpenBib::Common::Util::print_sort_nav($r,'',0);        
	OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
      }
      
      my $maxcount;
      if ($hitrange <= 0){
	$maxcount=0;
      }	
      print "<table cellpadding=2>\n";
      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";	    	
      my $idn;
      
      my @outputbuffer=();
      my $outidx=0;
      
      foreach $idn (@titelidns){
	if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	  $maxcount++;
	  next;
	}
	
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","none",5,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	  $maxcount++;		
	}
	
	if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	  last;
	}
	
      }	
      
      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      my $linecolor="aliceblue";
      
      foreach $outidx (@sortedoutputbuffer){
	
	$outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	
	# Eintraege merken fuer Lastresultset
	
	my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	my ($resdatabase)=$outidx=~/database=(\w+)/;
	push @resultset, "$resdatabase:$katkey";
	
	print $outidx;
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
	
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      print "</table>";
      print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";
    }	
    goto LEAVEPROG;		
  }    
  
  #####################################################################
  
  if ($searchtitofurhkor){
    my @requests=("select titidn from titurh where urhverw=$searchtitofurhkor","select titidn from titkor where korverw=$searchtitofurhkor");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    if ($#titelidns == 0){
      OpenBib::Search::Util::get_tit_by_idn("$titelidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    if ($#titelidns > 0){
      my $treffer=$#titelidns+1;
      my $nextstarthit;
      my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
      
      if ($hitrange>0){
	
	$nextstarthit=$starthit+$hitrange;
	
	my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	#	    print "treffer ".$treffer."nextstarthit $nextstarthit endhit $endhit nextrange $nextrange<p>";
	print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	
	my $navigate;
	if ($nextstarthit-$hitrange-1 > 0){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&searchtitofurhkor=$searchtitofurhkor\">Vorige ".$hitrange." Treffer</a>\n";
	  $navigate=1;
	}
	
	if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&searchtitofurhkor=$searchtitofurhkor\">N&auml;chste ".$nextrange." Treffer</a>\n";
	  $navigate=1;
	}
	print "<hr>\n" if ($navigate);
      }
      else {
	OpenBib::Search::Util::print_inst_head($database,"base");
#	OpenBib::Search::Util::print_sort_nav_updown($r);
	OpenBib::Common::Util::print_sort_nav($r,'',0);        
	OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
      }
      
      my $maxcount;
      if ($hitrange <= 0){
	$maxcount=0;
      }	
      print "<table cellpadding=2>\n";
      print "<tr bgcolor=\"lightblue\"><td>Suche</td><td>Titel</td><td>&nbsp;&nbsp;&nbsp;</td><td align=left>Signatur</td><td></td></tr>\n";
      
      my $idn;
      
      my @outputbuffer=();
      my $outidx=0;
      
      foreach $idn (@titelidns){
	if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	  $maxcount++;
	  next;
	}
	
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","none",5,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	  $maxcount++;		
	}
	
	if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	  last;
	}
	
      }	    
      
      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      my $linecolor="aliceblue";
      
      foreach $outidx (@sortedoutputbuffer){
	
	$outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	
	# Eintraege merken fuer Lastresultset
	
	my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	my ($resdatabase)=$outidx=~/database=(\w+)/;
	push @resultset, "$resdatabase:$katkey";
	
	print $outidx;
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
	
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      print "</table>";
      print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";
    }	
    goto LEAVEPROG;		
  }    
  
  #####################################################################
  
  if ($searchtitofurh){
    my @requests=("select titidn from titurh where urhverw=$searchtitofurh");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    if ($#titelidns == 0){
      OpenBib::Search::Util::get_tit_by_idn("$titelidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    if ($#titelidns > 0){
      my $treffer=$#titelidns+1;
      my $nextstarthit;
      my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
      
      if ($hitrange>0){
	
	$nextstarthit=$starthit+$hitrange;
	
	my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	
	my $navigate;
	if ($nextstarthit-$hitrange-1 > 0){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&searchtitofurh=$searchtitofurh\">Vorige ".$hitrange." Treffer</a>\n";
	  $navigate=1;
	}
	
	if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&searchtitofurh=$searchtitofurh\">N&auml;chste ".$nextrange." Treffer</a>\n";
	  $navigate=1;
	}
	print "<hr>\n" if ($navigate);
      }
      else {
	OpenBib::Search::Util::print_inst_head($database,"base");
#	OpenBib::Search::Util::print_sort_nav_updown($r);
	OpenBib::Common::Util::print_sort_nav($r,'',0);        
	OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
      }
      
      my $maxcount;
      if ($hitrange <= 0){
	$maxcount=0;
      }	
      print "<table cellpadding=2>\n";
      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";	    		
      my $idn;
      
      my @outputbuffer=();
      my $outidx=0;
      
      foreach $idn (@titelidns){
	if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	  $maxcount++;
	  next;
	}
	
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","none",5,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	  $maxcount++;		
	}
	
	if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	  last;
	}
	
      }	    
      
      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      my $linecolor="aliceblue";
      
      foreach $outidx (@sortedoutputbuffer){
	
	$outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	
	# Eintraege merken fuer Lastresultset
	
	my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	my ($resdatabase)=$outidx=~/database=(\w+)/;
	push @resultset, "$resdatabase:$katkey";
	
	print $outidx;
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
	
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      print "</table>";
      print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";;  
    }	
    goto LEAVEPROG;		
  }    
  
  #######################################################################
  
  if ($searchtitofkor){
    my @requests=("select titidn from titkor where korverw=$searchtitofkor");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);	
    if ($#titelidns == 0){
      OpenBib::Search::Util::get_tit_by_idn("$titelidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    if ($#titelidns > 0){
      my $treffer=$#titelidns+1;
      my $nextstarthit;
      my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
      
      if ($hitrange>0){
	
	$nextstarthit=$starthit+$hitrange;
	
	my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	
	my $navigate;
	if ($nextstarthit-$hitrange-1 > 0){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&searchtitofkor=$searchtitofkor\">Vorige ".$hitrange." Treffer</a>\n";
	  $navigate=1;
	}
	
	if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&searchtitofkor=$searchtitofkor\">N&auml;chste ".$nextrange." Treffer</a>\n";
	  $navigate=1;
	}
	print "<hr>\n" if ($navigate);
      }
      else {
	OpenBib::Search::Util::print_inst_head($database,"base");
#	OpenBib::Search::Util::print_sort_nav_updown($r);
	OpenBib::Common::Util::print_sort_nav($r,'',0);        
	OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
      }
      
      my $maxcount;
      if ($hitrange <= 0){
	$maxcount=0;
      }	
      print "<table cellpadding=2>\n";
      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";	    			
      my $idn;
      
      my @outputbuffer=();
      my $outidx=0;
      
      foreach $idn (@titelidns){
	if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	  $maxcount++;
	  next;
	}
	
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","none",5,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	  $maxcount++;		
	}
	
	if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	  last;
	}
      }	    

      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      my $linecolor="aliceblue";
      
      foreach $outidx (@sortedoutputbuffer){
	
	$outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	
	# Eintraege merken fuer Lastresultset
	
	my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	my ($resdatabase)=$outidx=~/database=(\w+)/;
	push @resultset, "$resdatabase:$katkey";
	
	print $outidx;
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
	
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      print "</table>";
      print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";
    }	
    goto LEAVEPROG;		
  }    
  
  #######################################################################
  
  if ($searchtitofswt){
    my @requests=("select titidn from titswtlok where swtverw=$searchtitofswt");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);	
    
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
    }
    if ($#titelidns == 0){
      OpenBib::Search::Util::get_tit_by_idn("$titelidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    if ($#titelidns > 0){
      my $treffer=$#titelidns+1;
      my $nextstarthit;
      my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
      
      if ($hitrange>0){
	
	$nextstarthit=$starthit+$hitrange;
	
	my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	
	my $navigate;
	if ($nextstarthit-$hitrange-1 > 0){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&searchtitofswt=$searchtitofswt\">Vorige ".$hitrange." Treffer</a>\n";
	  $navigate=1;
	}
	
	if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&searchtitofswt=$searchtitofswt\">N&auml;chste ".$nextrange." Treffer</a>\n";
	  $navigate=1;
	}
	print "<hr>\n" if ($navigate);
      }
      else {
	OpenBib::Search::Util::print_inst_head($database,"base");
#	OpenBib::Search::Util::print_sort_nav_updown($r);
	OpenBib::Common::Util::print_sort_nav($r,'',0);        
	OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
      }
      
      my $maxcount;
      if ($hitrange <= 0){
	$maxcount=0;
      }	
      print "<table cellpadding=2>\n";
      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";
      
      my $idn;
      
      my @outputbuffer=();
      my $outidx=0;
      
      foreach $idn (@titelidns){
	if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	  $maxcount++;
	  next;
	}
	
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","none",5,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	  $maxcount++;		
	}
	
	if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	  last;
	}
	
      }	    
      
      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      my $linecolor="aliceblue";
      
      foreach $outidx (@sortedoutputbuffer){
	
	$outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	
	# Eintraege merken fuer Lastresultset
	
	my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	my ($resdatabase)=$outidx=~/database=(\w+)/;
	push @resultset, "$resdatabase:$katkey";
	
	print $outidx;
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      print "</table>";
      print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";
    }	
    goto LEAVEPROG;		
  }    
  
  
  #######################################################################
  
  if ($searchtitofnot){
    my @requests=("select titidn from titnot where notidn=$searchtitofnot");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);	
    
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
    }
    
    if ($#titelidns == 0){
      OpenBib::Search::Util::get_tit_by_idn("$titelidns[0]","none",1,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
    }
    
    if ($#titelidns > 0){
      my $treffer=$#titelidns+1;
      my $nextstarthit;
      my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
      
      if ($hitrange>0){
	
	$nextstarthit=$starthit+$hitrange;
	
	my $endhit=($nextstarthit > $treffer)?$treffer:$nextstarthit-1;
	my $nextrange=($nextstarthit+$hitrange > $treffer)?$treffer-$nextstarthit+1:$hitrange;
	print "<h1>Auswahlliste: Titel $starthit - $endhit von $treffer</h1>\n";	    
	
	my $navigate;
	if ($nextstarthit-$hitrange-1 > 0){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=".($starthit-$hitrange)."&showmexintit=$showmexintit&database=$database&searchtitofnot=$searchtitofnot\">Vorige ".$hitrange." Treffer</a>\n";
	  $navigate=1;
	}
	
	if (($nextstarthit+$nextrange-1 <= $treffer)&&($nextrange>0)){
	  print "<a href=\"$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&casesensitive=$casesensitive&hitrange=$hitrange&maxhits=$maxhits&rating=$rating&starthit=$nextstarthit&showmexintit=$showmexintit&database=$database&searchtitofnot=$searchtitofnot\">N&auml;chste ".$nextrange." Treffer</a>\n";
	  $navigate=1;
	}
	print "<hr>\n" if ($navigate);
      }
      else {
	OpenBib::Search::Util::print_inst_head($database,"base");
#	OpenBib::Search::Util::print_sort_nav_updown($r);
	OpenBib::Common::Util::print_sort_nav($r,'',0);        
	OpenBib::Search::Util::print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
      }
      
      my $maxcount;
      if ($hitrange <= 0){
	$maxcount=0;
      }	
      print "<table cellpadding=2>\n";
      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td><span id=\"rldbase\">".$dbinfo{"$database"}."</span></td><td align=left colspan=2><span id=\"rlhits\"><strong>$treffer Treffer</strong></span></td></tr>\n";
      my $idn;
      
      my @outputbuffer=();
      my $outidx=0;
      
      foreach $idn (@titelidns){
	if (($hitrange > 0)&&($maxcount < ($starthit-1))){
	  $maxcount++;
	  next;
	}
	
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_by_idn("$idn","none",5,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	  $maxcount++;		
	}
	
	if (($hitrange > 0)&&($maxcount >= $nextstarthit-1)){
	  last;
	}
	
      }	    
      
      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      my $linecolor="aliceblue";
      
      foreach $outidx (@sortedoutputbuffer){
	
	$outidx=~s/<tr>/<tr bgcolor=\"$linecolor\">/;
	
	# Eintraege merken fuer Lastresultset
	
	my ($katkey)=$outidx=~/searchsingletit=(\d+)/;
	my ($resdatabase)=$outidx=~/database=(\w+)/;
	push @resultset, "$resdatabase:$katkey";
	
	print $outidx;
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
	
      }
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      
      print "</table>";
      print "<table><tr><td><input type=submit name=search value=Mehrfachauswahl></td></tr></table>\n";
    }	
    goto LEAVEPROG;		
  }    
  
  # Falls bis hierhin noch nicht abgearbeitet, dann wirds wohl nichts mehr geben
  
  print "<p>\n";
  OpenBib::Search::Util::no_result();
  
  # Keine Verwendung von exit, da sonst Probleme mit mod_perl. Stattdessen 
  # Sprung mit goto ans Programmende zum Label LEAVEPROG
  
LEAVEPROG: 

  print << "SWTIDX";
</form>
<hr>
<table>
<tr><td bgcolor="lightblue">Schlagwortindex dieses Katalogs&nbsp;</td><td>
<form method="get" action="$config{search_loc}">
<input type="hidden" name="sessionID" value="$sessionID">
<input type="hidden" name="searchmode" value="$searchmode">
<input type="hidden" name="rating" value="$rating">
<input type="hidden" name="bookinfo" value="$bookinfo">
<input type="hidden" name="casesensitive" value="$casesensitive">
<input type="hidden" name="hitrange" value="$hitrange">
<input type="hidden" name="showmexintit" value="$showmexintit">
<input type="hidden" name="database" value="$database">
&nbsp;
<input type="text" name="swtindex" value="$swtindex" size="4" maxlength="50" title="Geben Sie hier den Schlagwortanfang ein">
&nbsp;
<input type="submit" value="Suchen">
&nbsp;</td>
</tr>
</table>
</form>
<p>
SWTIDX
  
  OpenBib::Common::Util::print_footer();
  
  $dbh->disconnect;
  $sessiondbh->disconnect;
  return OK;
}

1;
