#####################################################################
#
#  OpenBib::Search.pm
#
#  Copyright 1997-2005 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use SOAP::Lite;

use DBI;

use POSIX;

use Template;

use OpenBib::Search::Util;

use OpenBib::Common::Util;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

my $benchmark;

if ($OpenBib::Config::config{benchmark}){
  use Benchmark ':hireswallclock';
}

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
  ## Searchmode: Art der Recherche
  ##               0 - Vollst"andig stamdateiorientierte Suche 
  ##               1 - Vollst"andig titelorientierte Suche
  ##               2 - Standardrecherche (Mix aus 0 und 1)
  
  my $searchmode=($query->param('searchmode'))?$query->param('searchmode'):0;
  
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
  ## Offset: Maximale Anzahl ausgegebener Treffer bei Anfangs-Suche
  ##          >0  - hitrange Treffer werden ab dieser Nr. ausgegeben 
  
  my $offset=($query->param('offset'))?$query->param('offset'):1;
  
  #####################################################################
  ## Database: Name der verwendeten SQL-Datenbank
  
  my $database=($query->param('database'))?$query->param('database'):'inst001';
  
  #####################################################################
  ## Sortierung der Titellisten
  
  my $sorttype=($query->param('sorttype'))?$query->param('sorttype'):"author";
  my $sortorder=($query->param('sortorder'))?$query->param('sortorder'):"up";

  my $benchmark=0;

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
  my $searchmultipleaut=$query->param('searchmultipleaut') || '';
  my $searchmultipletit=$query->param('searchmultipletit') || '';
  my $searchmultiplekor=$query->param('searchmultiplekor') || '';
  my $searchmultiplenot=$query->param('searchmultiplenot') || '';
  my $searchmultipleswt=$query->param('searchmultipleswt') || '';
  my $searchtitofaut=$query->param('searchtitofaut') || '';
  my $searchtitofswt=$query->param('searchtitofswt') || '';
  my $searchtitofkor=$query->param('searchtitofkor') || '';
  my $searchtitofnot=$query->param('searchtitofnot') || '';
  my $searchtitofurh=$query->param('searchtitofurh') || '';
  my $searchtitofurhkor=$query->param('searchtitofurhkor') || '';
  my $searchgtmtit=$query->param('gtmtit') || '';
  my $searchgtftit=$query->param('gtftit') || '';
  my $searchinvktit=$query->param('invktit') || '';
  my $searchgtf=$query->param('gtf') || '';
  my $searchinvk=$query->param('invk') || '';

  my $fs=$query->param('fs') || '';               # Freie Suche
  my $verf=$query->param('verf') || '';           # Verfasser
  my $hst=$query->param('hst') || '';             # Titel
  my $hststring=$query->param('hststring') || ''; # Exakter Titel
  my $swt=$query->param('swt') || '';             # Schlagwort
  my $kor=$query->param('kor') || '';             # Koerperschaft
  my $sign=$query->param('sign') || '';           # Signatur
  my $isbn=$query->param('isbn') || '';           # ISBN
  my $issn=$query->param('issn') || '';           # ISSN
  my $notation=$query->param('notation') || '';   # Notation
  my $ejahr=$query->param('ejahr') || '';         # Erscheinungsjahr
  my $ejahrop=$query->param('ejahrop') || '=';    # Vergleichsoperator ejahr
  my $mart=$query->param('mart') || '';           # Medienart

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

  $dbinforesult=$sessiondbh->prepare("select circ,circurl,circcheckurl,circdb from dboptions where dbname = ?") or $logger->error($DBI::errstr);
  $dbinforesult->execute($database) or $logger->error($DBI::errstr);;

  my $circ=0;
  my $circurl="";
  my $circcheckurl="";
  my $circdb="";

  while (my $result=$dbinforesult->fetchrow_hashref()){
    $circ=$result->{'circ'};
    $circurl=$result->{'circurl'};
    $circcheckurl=$result->{'circcheckurl'};
    $circdb=$result->{'circdb'};
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

  #####################################################################
  ## Schlagwortindex
  
  if ($swtindex ne ""){
    
    OpenBib::Search::Util::print_index_by_swt($swtindex,$dbh,$sessiondbh,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);

    return OK;    
  }

  # Standard Ergebnisbehandlung bei Suchanfragen
  #####################################################################
  
  my $suchbegriff;
  
  if ($stammsearch){
    $initialsearch=$stammsearch;
    $suchbegriff=OpenBib::Search::Util::input2sgml($stammvalue,1,$withumlaut);
  }
  
  #####################################################################
  
  if ($searchall){ # Standardsuche

    my @tidns=OpenBib::Search::Util::initital_search_for_titidns($fs,$verf,$hst,$hststring,$swt,$kor,$notation,$isbn,$issn,$sign,$ejahr,$ejahrop,$mart,$boolfs,$boolverf,$boolhst,$boolhststring,$boolswt,$boolkor,$boolnotation,$boolisbn,$boolissn,$boolsign,$boolejahr,$boolmart,$dbh,$maxhits);
    
    
    # Kein Treffer
    if ($#tidns == -1){
      OpenBib::Search::Util::no_result();
      return OK;
    }
    
    # Genau ein Treffer
    if ($#tidns == 0){
      
      OpenBib::Search::Util::print_tit_set_by_idn("$tidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);

      return OK;
    }
    
    # Mehr als ein Treffer
    if ($#tidns > 0){
      my @outputbuffer=();
      my $outidx=0;
      
      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }

      foreach my $idn (@tidns){
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	}
      }	    

      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $outidx Titel : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }
      
      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
 
      OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);

      return OK;
    }	
  }
  
  #######################################################################
  # Nachdem initial per SQL nach den Usereingaben eine Treffermenge 
  # gefunden wurde, geht es nun exklusiv in der SQL-DB weiter

  if ($generalsearch) { 
    if (($generalsearch=~/^verf/)||($generalsearch=~/^pers/)){
      if ($searchmode == 1){
	$searchtitofaut=$query->param("$generalsearch");
      }
      else {		
	my $verfidn=$query->param("$generalsearch");

	my $normset=OpenBib::Search::Util::get_aut_set_by_idn("$verfidn",$dbh,$searchmultipleaut,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);

	# TT-Data erzeugen
	
	my $ttdata={
		    stylesheet => $stylesheet,
		    
		    sessionID  => $sessionID,

		    database => $database,

		    searchmode => $searchmode,
		    hitrange => $hitrange,
		    rating => $rating,
		    bookinfo => $bookinfo,
		    sessionID => $sessionID,

		    normset => $normset,

		    utf2iso => sub { 
		      my $string=shift;
		      $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		      return $string;
		    },
		    
		    show_corporate_banner => 0,
		    show_foot_banner => 1,
		    config     => \%config,
		   };
      
	OpenBib::Common::Util::print_page($config{tt_search_showautset_tname},$ttdata,$r);

	return OK;
      }
    } 
    
    if ($generalsearch=~/^kor/){
      if ($searchmode == 1){
	$searchtitofkor=$query->param("$generalsearch");
      }
      else {		
	my $koridn=$query->param("$generalsearch");
	my $normset=OpenBib::Search::Util::get_kor_set_by_idn("$koridn",$dbh,$searchmultiplekor,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);

	# TT-Data erzeugen
	
	my $ttdata={
		    stylesheet => $stylesheet,
		    
		    sessionID  => $sessionID,
		    
		    database => $database,
		    
		    searchmode => $searchmode,
		    hitrange => $hitrange,
		    rating => $rating,
		    bookinfo => $bookinfo,
		    sessionID => $sessionID,
		    
		    normset => $normset,
		    
		    utf2iso => sub { 
		      my $string=shift;
		      $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		      return $string;
		    },
		    
		    show_corporate_banner => 0,
		    show_foot_banner => 1,
		    config     => \%config,
		   };
	
	OpenBib::Common::Util::print_page($config{tt_search_showkorset_tname},$ttdata,$r);
	
	return OK;
      }
    } 
    
    if ($generalsearch=~/^urh/){
      if ($searchmode == 1){
	$searchtitofurh=$query->param("$generalsearch");
      }
      else {		
	my $koridn=$query->param("$generalsearch");
	my $normset=OpenBib::Search::Util::get_kor_set_by_idn("$koridn",$dbh,$searchmultiplekor,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);

	# TT-Data erzeugen
	
	my $ttdata={
		    stylesheet => $stylesheet,
		    
		    sessionID  => $sessionID,
		    
		    database => $database,
		    
		    searchmode => $searchmode,
		    hitrange => $hitrange,
		    rating => $rating,
		    bookinfo => $bookinfo,
		    sessionID => $sessionID,
		    
		    normset => $normset,
		    
		    utf2iso => sub { 
		      my $string=shift;
		      $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		      return $string;
		    },
		    
		    show_corporate_banner => 0,
		    show_foot_banner => 1,
		    config     => \%config,
		   };
	
	OpenBib::Common::Util::print_page($config{tt_search_showkorset_tname},$ttdata,$r);
	
	return OK;
      }
    } 
    
    if ($generalsearch=~/^gtftit/){
      my $gtftit=$query->param("$generalsearch");
      my @requests=("select titidn from titgtf where verwidn=$gtftit");
      my @gtfidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
      if ($#gtfidns == -1){
	OpenBib::Search::Util::no_result();
	return OK;
      }
      
      if ($#gtfidns == 0){
	OpenBib::Search::Util::print_tit_set_by_idn($gtfidns[0],"none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
	return OK;

      }
      
      if ($#gtfidns > 0){
	my $treffer=$#gtfidns+1;
	my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
	my $nextoffset;
	
	if ($hitrange>0){
	  
	  $nextoffset=$offset+$hitrange;
	  
	  my $endhit=($nextoffset > $treffer)?$treffer:$nextoffset-1;
	  my $nextrange=($nextoffset+$hitrange > $treffer)?$treffer-$nextoffset+1:$hitrange;

	  print "<h1>Auswahlliste: Titel $offset - $endhit von $treffer</h1>\n";	    
	  
	  my $navigate;
	  if ($nextoffset-$hitrange-1 > 0){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;generalsearch=gtftit;searchmode=$searchmode;hitrange=$hitrange;maxhits=$maxhits;rating=$rating;offset=".($offset-$hitrange).";database=$database;gtftit=$gtftit\">Vorige ".$hitrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  
	  if (($nextoffset+$nextrange-1 <= $treffer)&&($nextrange>0)){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;generalsearch=gtftit;searchmode=$searchmode;hitrange=$hitrange;maxhits=$maxhits;rating=$rating;offset=$nextoffset;database=$database;gtftit=$gtftit\">N&auml;chste ".$nextrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  print "<hr>\n" if ($navigate);
	}
	
	my $maxcount;
	
	if ($hitrange <= 0){
	  $maxcount=0;
	}	

	my $gtfidn;
	
	my @outputbuffer=();
	my $outidx=0;
	
	foreach $gtfidn (@gtfidns){
	  if (($hitrange > 0)&&($maxcount < ($offset-1))){
	    $maxcount++;
	    next;
	  }
	  
	  if (length($gtfidn)>0){
	    $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$gtfidn","$gtftit",6,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	    $maxcount++;		
	  }
	  
	  if (($hitrange > 0)&&($maxcount >= $nextoffset-1)){
	    last;
	  }
	  
	}	    
	
	my @sortedoutputbuffer=();
	
	my @resultset=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
	
	OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);

	return OK;
      }
    }
    
    if ($generalsearch=~/^gtmtit/){
      my $gtmtit=$query->param("$generalsearch");
      my @requests=("select titidn from titgtm where verwidn=$gtmtit");
      my @gtmidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
      if ($#gtmidns == -1){
	OpenBib::Search::Util::no_result();
	return OK;
      }
      
      if ($#gtmidns == 0){
	OpenBib::Search::Util::print_tit_set_by_idn("$gtmidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
	return OK;
      }
      
      if ($#gtmidns > 0){
	my $treffer=$#gtmidns+1;
	my $nextoffset;
	$maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
	
	if ($hitrange>0){
	  
	  $nextoffset=$offset+$hitrange;
	  
	  my $endhit=($nextoffset > $treffer)?$treffer:$nextoffset-1;
	  my $nextrange=($nextoffset+$hitrange > $treffer)?$treffer-$nextoffset+1:$hitrange;
	  #	    print "treffer ".$treffer."nextoffset $nextoffset endhit $endhit nextrange $nextrange<p>";
	  print "<h1>Auswahlliste: Titel $offset - $endhit von $treffer</h1>\n";	    
	  
	  my $navigate;
	  if ($nextoffset-$hitrange-1 > 0){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;generalsearch=gtmtit;searchmode=$searchmode;hitrange=$hitrange;maxhits=$maxhits;rating=$rating;offset=".($offset-$hitrange).";database=$database;gtmtit=$gtmtit\">Vorige ".$hitrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  
	  if (($nextoffset+$nextrange-1 <= $treffer)&&($nextrange>0)){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;generalsearch=gtmtit;searchmode=$searchmode;hitrange=$hitrange;maxhits=$maxhits;rating=$rating;offset=$nextoffset;database=$database;gtmtit=$gtmtit\">N&auml;chste ".$nextrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  print "<hr>\n" if ($navigate);
	}

	my $maxcount;
	if ($hitrange <= 0){
	  $maxcount=0;
	}	

	my $idn;
	
	my @outputbuffer=();
	my $outidx=0;
	
	foreach $idn (@gtmidns){
	  if (($hitrange > 0)&&($maxcount < ($offset-1))){
	    $maxcount++;
	    next;
	  }
	  
	  if (length($idn)>0){
	    $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","$gtmtit",7,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	    $maxcount++;		
	  }
	  
	  if (($hitrange > 0)&&($maxcount >= $nextoffset-1)){
	    last;
	  }
	  
	}	    
	
	my @sortedoutputbuffer=();
	
	my @resultset=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);

	OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);
	
	return OK;
      }
    }
    
    if ($generalsearch=~/^invktit/){
      my $invktit=$query->param("$generalsearch");
      my @requests=("select titidn from titinverkn where titverw=$invktit");
      my @invkidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
      if ($#invkidns == -1){
	OpenBib::Search::Util::no_result();
	return OK;
      }
      
      if ($#invkidns == 0){
	OpenBib::Search::Util::print_tit_set_by_idn("$invkidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
	return OK;
      }
      
      if ($#invkidns > 0){
	my $treffer=$#invkidns+1;
	my $nextoffset;
	my $maxhits=10000; # Es sollen immer ALLE Treffer ausgegeben werden
	
	if ($hitrange>0){
	  
	  $nextoffset=$offset+$hitrange;
	  
	  my $endhit=($nextoffset > $treffer)?$treffer:$nextoffset-1;
	  my $nextrange=($nextoffset+$hitrange > $treffer)?$treffer-$nextoffset+1:$hitrange;
	  print "<h1>Auswahlliste: Titel $offset - $endhit von $treffer gefundenen Titeln</h1>\n";	    
	  
	  my $navigate;
	  if ($nextoffset-$hitrange-1 > 0){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;generalsearch=invktit;searchmode=$searchmode;hitrange=$hitrange;maxhits=$maxhits;rating=$rating;offset=".($offset-$hitrange).";database=$database;invktit=$invktit\">Vorige ".$hitrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  
	  if (($nextoffset+$nextrange-1 <= $treffer)&&($nextrange>0)){
	    print "<a href=\"$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;generalsearch=invktit;searchmode=$searchmode;hitrange=$hitrange;maxhits=$maxhits;rating=$rating;offset=$nextoffset;database=$database;invktit=$invktit\">N&auml;chste ".$nextrange." Treffer</a>\n";
	    $navigate=1;
	  }
	  print "<hr>\n" if ($navigate);
	}
	
	my $maxcount;
	if ($hitrange <= 0){
	  $maxcount=0;
	}	

	my $idn;
	
	my @outputbuffer=();
	my $outidx=0;
	
	foreach $idn (@invkidns){
	  if (($hitrange > 0)&&($maxcount < ($offset-1))){
	    $maxcount++;
	    next;
	  }
	  
	  if (length($idn)>0){
	    $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","$invktit",8,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	    $maxcount++;		
	  }
	  
	  if (($hitrange > 0)&&($maxcount >= $nextoffset-1)){
	    last;
	  }
	  
	}	    
	
	my @sortedoutputbuffer=();
	
	my @resultset=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
	OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);
	
	return OK;
     }
    }
        
    if ($generalsearch=~/^hst/){
      my $titidn=$query->param("$generalsearch");

      OpenBib::Search::Util::print_tit_set_by_idn("$titidn","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;
    }
    
    if ($generalsearch=~/^swt/){
      if ($searchmode == 1){
	$searchtitofswt=$query->param("$generalsearch");
      }
      else {
	my $swtidn=$query->param("$generalsearch");
	my $normset=OpenBib::Search::Util::get_swt_set_by_idn("$swtidn",$dbh,$searchmultipleswt,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,$sessionID);
	
	# TT-Data erzeugen
	
	my $ttdata={
		    stylesheet => $stylesheet,
		    
		    sessionID  => $sessionID,

		    database => $database,

		    searchmode => $searchmode,
		    hitrange => $hitrange,
		    rating => $rating,
		    bookinfo => $bookinfo,
		    sessionID => $sessionID,

		    normset => $normset,

		    utf2iso => sub { 
		      my $string=shift;
		      $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		      return $string;
		    },
		    
		    show_corporate_banner => 0,
		    show_foot_banner => 1,
		    config     => \%config,
		   };
      
	OpenBib::Common::Util::print_page($config{tt_search_showswtset_tname},$ttdata,$r);

	return OK;
      }
    } 
    
    if ($generalsearch=~/^not/){
      if ($searchmode == 1){
	$searchtitofnot=$query->param("notation");
      }
      else {
	my $notidn=$query->param("notation");
	my $normset=OpenBib::Search::Util::get_not_set_by_idn("$notidn",$dbh,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);
	
	# TT-Data erzeugen
	
	my $ttdata={
		    stylesheet => $stylesheet,
		    
		    sessionID  => $sessionID,

		    database => $database,

		    searchmode => $searchmode,
		    hitrange => $hitrange,
		    rating => $rating,
		    bookinfo => $bookinfo,
		    sessionID => $sessionID,

		    normset => $normset,

		    utf2iso => sub { 
		      my $string=shift;
		      $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		      return $string;
		    },
		    
		    show_corporate_banner => 0,
		    show_foot_banner => 1,
		    config     => \%config,
		   };
      
	OpenBib::Common::Util::print_page($config{tt_search_shownotset_tname},$ttdata,$r);

	return OK;
      }
    } 
    
    if ($generalsearch=~/^singlegtm/){
      my $titidn=$query->param("$generalsearch");

      OpenBib::Search::Util::print_tit_set_by_idn("$titidn","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;
    } 
    
    if ($generalsearch=~/^singlegtf/){
      my $titidn=$query->param("$generalsearch");

      OpenBib::Search::Util::print_tit_set_by_idn("$titidn","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;

    } 
  }
  
  #####################################################################
  
  if ($searchmultipletit){
    my @mtitidns=$query->param('searchmultipletit');

    OpenBib::Search::Util::print_mult_tit_set_by_idn(\@mtitidns,"none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
    return OK;
  }
  
  #####################################################################
  # Wird derzeit nicht unterstuetzt

#   if ($searchmultipleaut){
#     my @mautidns=$query->param('searchmultipleaut');
#     print "<h1>Ausgew&auml;hlte Autoren</h1>\n";
    
#     my $maut;
#     foreach $maut (@mautidns){
#       my $autset=OpenBib::Search::Util::get_aut_set_by_idn("$maut",$dbh,$searchmultipleaut,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);
#     }
#     goto LEAVEPROG;	
#   }    
  
  #####################################################################
  # Wird derzeit nicht unterstuetzt

#   if ($searchmultiplekor){
#     my @mkoridns=$query->param('searchmultiplekor');
#     print "<h1>Ausgew&auml;hlte K&ouml;rperschaften</h1>\n";
    
#     my $mkor;
#     foreach $mkor (@mkoridns){
#       OpenBib::Search::Util::get_kor_set_by_idn("$mkor",$dbh,$searchmultiplekor,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);
#     }
#     goto LEAVEPROG;	
#   }    
  
  #####################################################################
  # Wird derzeit nicht unterstuetzt
  
#   if ($searchmultiplenot){
#     my @mtitidns=$query->param('searchmultipletit');
#     print "<h1>Ausgew&auml;hlte Titel</h1>\n";
    
#     my $mtit;
#     foreach $mtit (@mtitidns){
#       OpenBib::Search::Util::get_tit_by_idn("$mtit","none",1,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
#     }
#     goto LEAVEPROG;	
#   }    
  
  #####################################################################
  # Wird derzeit nicht unterstuetzt
  
#   if ($searchmultipleswt){
#     my @mswtidns=$query->param('searchmultipleswt');
#     print "<h1>Ausgew&auml;hlte Schlagworte</h1>\n";
    
#     my $mswt;
#     foreach $mswt (@mswtidns){
#       OpenBib::Search::Util::get_swt_set_by_idn("$mswt",$dbh,$searchmultipleswt,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,$sessionID);
#     }
#     goto LEAVEPROG;	
#   }    
  
  #####################################################################
  
  if ($searchsingletit){

    OpenBib::Search::Util::print_tit_set_by_idn("$searchsingletit","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
    return OK;
	
  }    
  
  #####################################################################
  
  if ($searchsingleswt){
    if ($searchmode == 1){
      $searchtitofswt=$searchsingleswt;
    }
    else {		
      my $normset=OpenBib::Search::Util::get_swt_set_by_idn("$searchsingleswt",$dbh,$searchmultipleswt,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,$sessionID);
	
      # TT-Data erzeugen
	
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  
		  database => $database,
		  
		  searchmode => $searchmode,
		  hitrange => $hitrange,
		  rating => $rating,
		  bookinfo => $bookinfo,
		  sessionID => $sessionID,
		  
		  normset => $normset,
		  
		  utf2iso => sub { 
		      my $string=shift;
		      $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		      return $string;
		    },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_search_showswtset_tname},$ttdata,$r);

      return OK;
    }
  }    
  
  ######################################################################
  
  if ($searchsinglekor){
    if ($searchmode == 1){
      $searchtitofkor=$searchsinglekor;
    }
    else {		
      my $normset=OpenBib::Search::Util::get_kor_set_by_idn("$searchsinglekor",$dbh,$searchmultiplekor,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);

      # TT-Data erzeugen
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  
		  database => $database,
		  
		  searchmode => $searchmode,
		  hitrange => $hitrange,
		  rating => $rating,
		  bookinfo => $bookinfo,
		  sessionID => $sessionID,
		  
		  normset => $normset,
		    
		  utf2iso => sub { 
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		    return $string;
		  },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_search_showkorset_tname},$ttdata,$r);
      
      return OK;
    }
  }    
  
  ######################################################################
  
  if ($searchsinglenot){
    if ($searchmode == 1){
      $searchtitofnot=$searchsinglenot;
    }
    else {		
      my $normset=OpenBib::Search::Util::get_not_set_by_idn("$searchsinglenot",$dbh,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);
	
      # TT-Data erzeugen
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  
		  database => $database,
		  
		  searchmode => $searchmode,
		  hitrange => $hitrange,
		  rating => $rating,
		  bookinfo => $bookinfo,
		  sessionID => $sessionID,
		  
		  normset => $normset,
		  
		  utf2iso => sub { 
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		    return $string;
		  },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_search_shownotset_tname},$ttdata,$r);
      
      return OK;
    }
  }    
  
  #####################################################################
  
  if ($searchsingleaut){
    if ($searchmode == 1){
      $searchtitofaut=$searchsingleaut;
    }
    else {		
      my $normset=OpenBib::Search::Util::get_aut_set_by_idn("$searchsingleaut",$dbh,$searchmultipleaut,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);
      
      # TT-Data erzeugen
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  
		  database => $database,
		  
		  searchmode => $searchmode,
		  hitrange => $hitrange,
		  rating => $rating,
		  bookinfo => $bookinfo,
		  sessionID => $sessionID,
		  
		  normset => $normset,
		  
		  utf2iso => sub { 
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		    return $string;
		  },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_search_showautset_tname},$ttdata,$r);
      
      return OK;
    }
  }    
  
  if ($searchtitofaut){
    my @requests=("select titidn from titverf where verfverw=$searchtitofaut","select titidn from titpers where persverw=$searchtitofaut","select titidn from titgpers where persverw=$searchtitofaut");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);	
    
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
      return OK;
    }
    
    if ($#titelidns == 0){

      OpenBib::Search::Util::print_tit_set_by_idn("$titelidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;

    }
    
    if ($#titelidns > 0){
      my @outputbuffer=();
      my $outidx=0;

      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }
      
      foreach my $idn (@titelidns){
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	}
      }	
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $outidx Titel : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
      OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);
      
      return OK;
    }	
  }    
  
  #####################################################################
  
  if ($searchtitofurhkor){
    my @requests=("select titidn from titurh where urhverw=$searchtitofurhkor","select titidn from titkor where korverw=$searchtitofurhkor");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
      return OK;
    }

    if ($#titelidns == 0){

      OpenBib::Search::Util::print_tit_set_by_idn("$titelidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;

    }
    if ($#titelidns > 0){
      my @outputbuffer=();
      my $outidx=0;
      
      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }

      foreach my $idn (@titelidns){
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	}
      }	    
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $outidx Titel : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
      OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);
      
      return OK;
    }	
  }    
  
  #####################################################################
  
  if ($searchtitofurh){
    my @requests=("select titidn from titurh where urhverw=$searchtitofurh");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
      return OK;
    }

    if ($#titelidns == 0){

      OpenBib::Search::Util::print_tit_set_by_idn("$titelidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;

    }
    if ($#titelidns > 0){
      my @outputbuffer=();
      my $outidx=0;
      
      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }

      foreach my $idn (@titelidns){
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	}
      }	    
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $outidx Titel : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
      OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);
      

      return OK;
    }	
  }    
  
  #######################################################################
  
  if ($searchtitofkor){
    my @requests=("select titidn from titkor where korverw=$searchtitofkor");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);	
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
      return OK;
    }

    if ($#titelidns == 0){
      OpenBib::Search::Util::print_tit_set_by_idn("$titelidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;

    }
    if ($#titelidns > 0){
      my @outputbuffer=();
      my $outidx=0;
      
      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }

      foreach my $idn (@titelidns){
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	}
      }	    

      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $outidx Titel : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
      OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);
      
      return OK;
    }	
  }    
  
  #######################################################################
  
  if ($searchtitofswt){
    my @requests=("select titidn from titswtlok where swtverw=$searchtitofswt");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);	
    
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
      return OK;
    }
    if ($#titelidns == 0){

      OpenBib::Search::Util::print_tit_set_by_idn("$titelidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;
    }
    if ($#titelidns > 0){
      my @outputbuffer=();
      my $outidx=0;
      
      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }

      foreach my $idn (@titelidns){
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	}
      }	    
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $outidx Titel : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
      OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet,$hitrange,$offset);
      
      return OK;
    }	
  }    
  
  
  #######################################################################
  
  if ($searchtitofnot){
    my @requests=("select titidn from titnot where notidn=$searchtitofnot");
    my @titelidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);	
    
    if ($#titelidns == -1){
      OpenBib::Search::Util::no_result();
      return OK;
    }
    
    if ($#titelidns == 0){

      OpenBib::Search::Util::print_tit_set_by_idn("$titelidns[0]","none",$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID,$r,$stylesheet);
      return OK;
    }
    
    if ($#titelidns > 0){
      my @outputbuffer=();
      my $outidx=0;
      
      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }

      foreach my $idn (@titelidns){
	if (length($idn)>0){
	  $outputbuffer[$outidx++]=OpenBib::Search::Util::get_tit_listitem_by_idn("$idn","none",5,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
	}
      }	    
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $outidx Titel : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      my @sortedoutputbuffer=();
      
      my @resultset=();
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
      
      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);

      OpenBib::Search::Util::print_tit_list_by_idn(\@sortedoutputbuffer,\%dbinfo,$searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet);
      
      return OK;
    }	
  }    
  
  # Falls bis hierhin noch nicht abgearbeitet, dann wirds wohl nichts mehr geben
  
  print "<p>\n";
  OpenBib::Search::Util::no_result();
  $logger->error("Unerlaubt das Ende erreicht");
  
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
<input type="hidden" name="hitrange" value="$hitrange">
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
