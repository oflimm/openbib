####################################################################
#
#  OpenBib::VirtualSearch.pm
#
#  Dieses File ist (C) 1997-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::VirtualSearch;

use Apache::Constants qw(:common);

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;

use YAML ();

use POSIX;

use Digest::MD5;
use DBI;
use Email::Valid;                           # EMail-Adressen testen

use OpenBib::Search::Util;
use OpenBib::VirtualSearch::Util;

use OpenBib::Common::Util;
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
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  # Standardwerte festlegen
  
  my $befehlsurl="http://$config{servername}$config{search_loc}";
  
  my $searchmode=2;
  my $searchall=1;
  my $search="Suche";
  my $dbmode=1;
  
  # CGI-Input auslesen
  
  my $fs=$query->param('fs') || '';
  my $verf=$query->param('verf') || '';
  my $hst=$query->param('hst') || '';
  my $hststring=$query->param('hststring') || '';
  my $swt=$query->param('swt') || '';
  my $kor=$query->param('kor') || '';
  my $sign=$query->param('sign') || '';
  my $isbn=$query->param('isbn') || '';
  my $issn=$query->param('issn') || '';
  my $mart=$query->param('mart') || '';
  my $notation=$query->param('notation') || '';
  my $ejahr=$query->param('ejahr') || '';
  my $ejahrop=$query->param('ejahrop') || '=';
  my $verknuepfung=$query->param('verknuepfung') || '';
  my @databases=($query->param('database'))?$query->param('database'):();
  my $starthit=($query->param('starthit'))?$query->param('starthit'):1;
  my $hitrange=($query->param('hitrange'))?$query->param('hitrange'):20;
  my $maxhits=($query->param('maxhits'))?$query->param('maxhits'):500;
  my $sorttype=($query->param('sorttype'))?$query->param('sorttype'):"author";
  my $sortall=($query->param('sortall'))?$query->param('sortall'):'0';
  my $sortorder=($query->param('sortorder'))?$query->param('sortorder'):'up';
  my $tosearch=$query->param('tosearch') || '';
  my $verfindex=$query->param('verfindex') || '';
  my $korindex=$query->param('korindex') || '';
  my $swtindex=$query->param('swtindex') || '';
  my $profil=$query->param('profil') || '';
  my $trefferliste=$query->param('trefferliste') || '';
  my $autoplus=$query->param('autoplus') || '';
  my $queryid=$query->param('queryid') || '';
  my $view=$query->param('view') || '';

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


  # Filter: ISBN und ISSN
  
  # Entfernung der Minus-Zeichen bei der ISBN
  $fs=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
  $isbn=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
  
  # Entfernung der Minus-Zeichen bei der ISSN
  $fs=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)/$1$2$3$4$5$6$7$8/g;
  $issn=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)/$1$2$3$4$5$6$7$8/g;
  
  $fs=OpenBib::VirtualSearch::Util::cleansearchterm($fs);
  
  # Filter Rest
  
  $verf=OpenBib::VirtualSearch::Util::cleansearchterm($verf);
  $hst=OpenBib::VirtualSearch::Util::cleansearchterm($hst);
  $hststring=OpenBib::VirtualSearch::Util::cleansearchterm($hststring);

  # Bei hststring zusaetzlich normieren durch Weglassung des ersten
  # Stopwortes

  $hststring=OpenBib::Common::Stopwords::strip_first_stopword($hststring);

  $swt=OpenBib::VirtualSearch::Util::cleansearchterm($swt);
  $kor=OpenBib::VirtualSearch::Util::cleansearchterm($kor);
  $sign=OpenBib::VirtualSearch::Util::cleansearchterm($sign);
  $isbn=OpenBib::VirtualSearch::Util::cleansearchterm($isbn);
  $issn=OpenBib::VirtualSearch::Util::cleansearchterm($issn);
  $mart=OpenBib::VirtualSearch::Util::cleansearchterm($mart);
  $notation=OpenBib::VirtualSearch::Util::cleansearchterm($notation);
  $ejahr=OpenBib::VirtualSearch::Util::cleansearchterm($ejahr);
  $ejahrop=OpenBib::VirtualSearch::Util::cleansearchterm($ejahrop);
  
  
  # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
  
  if ($autoplus eq "1"){
    
    $fs=OpenBib::VirtualSearch::Util::conv2autoplus($fs) if ($fs);
    $verf=OpenBib::VirtualSearch::Util::conv2autoplus($verf) if ($verf);
    $hst=OpenBib::VirtualSearch::Util::conv2autoplus($hst) if ($hst);
    $kor=OpenBib::VirtualSearch::Util::conv2autoplus($kor) if ($kor);
    $swt=OpenBib::VirtualSearch::Util::conv2autoplus($swt) if ($swt);
    $isbn=OpenBib::VirtualSearch::Util::conv2autoplus($isbn) if ($isbn);
    $issn=OpenBib::VirtualSearch::Util::conv2autoplus($issn) if ($issn);
    
  }
  
  if ($hitrange eq "alles"){
    $hitrange=-1;
  }

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

  
  #####################################################################
  # Dynamische Definition diverser Variablen
  
  # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
  my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description from dbinfo") or $logger->error($DBI::errstr);
  $dbinforesult->execute() or $logger->error($DBI::errstr);;
  
  my %sigel=();
  my %bibinfo=();
  my %dbinfo=();
  my %dbases=();
  my %dbnames=();

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

    $dbnames{"$dbname"}=$description;
  }
  
  $sigel{''}="Unbekannt";
  $bibinfo{''}="http://www.ub.uni-koeln.de/dezkat/bibinfo/noinfo.html";
  $dbases{''}="Unbekannt";


  $profil="" if ((!exists $config{units}{$profil}) && $profil ne "dbauswahl" && !$profil=~/^user/ && $profil ne "alldbs");
  
  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
    goto LEAVEPROG;
  }
  
  # Authorisierter user?
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);

  $logger->info("Authorization: ", $sessionID, " ", ($userid)?$userid:'none');
  
   my $ua=new LWP::UserAgent;
   my $item;
   my $alldbs;
  

  # Ueber view koennen bei Direkteinsprung in VirtualSearch die
  # entsprechenden Kataloge vorausgewaehlt werden

  if ($view && $#databases == -1){
    my $idnresult=$sessiondbh->prepare("select dbname from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($view) or $logger->error($DBI::errstr);
    
    @databases=();
    my @idnres;
    while (@idnres=$idnresult->fetchrow){	    
      push @databases, $idnres[0];
    }
    $idnresult->finish();

  }

  if ($tosearch eq "In allen Katalogen suchen"){
    
    my $idnresult=$sessiondbh->prepare("select dbname,description from dbinfo where active=1 order by faculty,description") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    
    @databases=();
    my @idnres;
    while (@idnres=$idnresult->fetchrow){	    
      push @databases, $idnres[0];
    }
    $idnresult->finish();
    
  }
  elsif (($tosearch eq "In ausgewählten Katalogen suchen")&&(($#databases == -1) && ($profil eq ""))){
    OpenBib::Common::Util::print_warning("Sie haben \"In ausgew&auml;hlten Katalogen suchen\" angeklickt, obwohl sie keine <a href=\"$config{databasechoice_loc}?sessionID=$sessionID\" target=\"body\">Kataloge</a> oder Suchprofile ausgew&auml;hlt haben. Bitte w&auml;hlen Sie die gew&uuml;nschten Kataloge/Suchprofile aus oder bet&auml;tigen Sie \"In allen Katalogen suchen\".",$r);
    goto LEAVEPROG;
  }

  # Wenn ein anderes Profil als 'dbauswahl' ausgewaehlt wuerde
  if ($profil ne "" && $profil ne "dbauswahl"){
    @databases=();
    
    # Benutzerspezifische Datenbankprofile
    if ($profil=~/^user(\d+)/){
      my $profilid=$1;
      
      my $profilresult=$userdbh->prepare("select profildb.dbname from profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid = ? and userdbprofile.profilid=profildb.profilid order by dbname") or $logger->error($DBI::errstr);
      $profilresult->execute($userid,$profilid) or $logger->error($DBI::errstr);
      
      my @poolres;
      while (@poolres=$profilresult->fetchrow){	    
	push @databases, $poolres[0];
      }
      $profilresult->finish();
      
    }
    elsif ($profil eq "alldbs"){
    # Alle Datenbanken
      my $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1 order by faculty,dbname") or $logger->error($DBI::errstr);
      $idnresult->execute() or $logger->error($DBI::errstr);
      
      my @idnres;
      while (@idnres=$idnresult->fetchrow){	    
	push @databases, $idnres[0];
      }
      $idnresult->finish();
    }
    else {
      my $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1 and faculty = ? order by faculty,dbname") or $logger->error($DBI::errstr);
      $idnresult->execute($profil) or $logger->error($DBI::errstr);
      
      my @idnres;
      while (@idnres=$idnresult->fetchrow){	    
	push @databases, $idnres[0];
      }
      $idnresult->finish();
    }
  }
  
  # Wenn Profil aufgerufen wurde, dann abspeichern fuer Recherchemaske

  if ($profil){
      my $idnresult=$sessiondbh->prepare("delete from sessionprofile where sessionid = ? ") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

      $idnresult=$sessiondbh->prepare("insert into sessionprofile values (?,?) ") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$profil) or $logger->error($DBI::errstr);
    
      $idnresult->finish();
  }


  # BEGIN Indizes
  ####################################################################
  # Wenn ein kataloguebergreifender Verfasserindex ausgewaehlt wurde
  ####################################################################

  if ($verfindex){
    $verf=~s/\+//g;
    $verf=~s/%2B//g;

    if (!$verf){
      OpenBib::Common::Util::print_warning("Sie haben keinen Verfasser eingegeben",$r);
    return OK;
    }

    # TODO: Einbeziehung der Datenbankauswahl, Umorganisierug der
    # Daten (Schlagwort mit all seinen Datenbanken und Treffern)

    my %verfindex=();

    foreach my $database (@databases){
      my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
      my $thisindex=OpenBib::Search::Util::get_index_by_verf($verf,$dbh);

      # Umorganisierung der Daten

      foreach my $item (@$thisindex){
	my %item=%$item;

	# Korrekte Initialisierung mit 0
	if (! $verfindex{$item{verf}}{titanzahl}){
	  $verfindex{$item{verf}}{titanzahl}=0;
	}
	
	my $verfdb={
		   'dbname' => $database,
		   'dbdesc' => $dbnames{$database},
		   'verfidn' => $item{verfidn},
		   'titanzahl' => $item{titanzahl},
		  };

	push @{$verfindex{$item{verf}}{databases}}, $verfdb;
	$verfindex{$item{verf}}{titanzahl}=$verfindex{$item{verf}}{titanzahl}+$item{titanzahl};
      }


      $dbh->disconnect;
    }

    # TT-Data erzeugen
    
    my $ttdata={
		stylesheet => $stylesheet,
		
		sessionID  => $sessionID,
		
		searchmode => $searchmode,
	
		verf      => $verf,
		verfindex => \%verfindex,
		databases => \@databases,
		
		utf2iso => sub {
		  my $string=shift;
		  $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		  return $string;
		},
		
		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };
  
    OpenBib::Common::Util::print_page($config{tt_virtualsearch_showverfindex_tname},$ttdata,$r);

    return OK;
  }

  # BEGIN Koerperschaften
  ####################################################################
  # Wenn ein kataloguebergreifender Koerperschaftsindex ausgewaehlt wurde
  ####################################################################

  if ($korindex){
    $kor=~s/\+//g;
    $kor=~s/%2B//g;

    if (!$kor){
      OpenBib::Common::Util::print_warning("Sie haben keine K&ouml;rperschaft eingegeben",$r);
    return OK;
    }

    # TODO: Einbeziehung der Datenbankauswahl, Umorganisierug der
    # Daten (Schlagwort mit all seinen Datenbanken und Treffern)

    my %korindex=();

    foreach my $database (@databases){
      my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
      my $thisindex=OpenBib::Search::Util::get_index_by_kor($kor,$dbh);

      # Umorganisierung der Daten

      foreach my $item (@$thisindex){
	my %item=%$item;

	# Korrekte Initialisierung mit 0
	if (! $korindex{$item{kor}}{titanzahl}){
	  $korindex{$item{kor}}{titanzahl}=0;
	}
	
	my $kordb={
		   'dbname' => $database,
		   'dbdesc' => $dbnames{$database},
		   'koridn' => $item{koridn},
		   'titanzahl' => $item{titanzahl},
		  };

	push @{$korindex{$item{kor}}{databases}}, $kordb;
	$korindex{$item{kor}}{titanzahl}=$korindex{$item{kor}}{titanzahl}+$item{titanzahl};
      }


      $dbh->disconnect;
    }

    # TT-Data erzeugen
    
    my $ttdata={
		stylesheet => $stylesheet,
		
		sessionID  => $sessionID,
		
		searchmode => $searchmode,
	
		kor      => $kor,
		korindex => \%korindex,
		databases => \@databases,

		utf2iso => sub {
		  my $string=shift;
		  $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		  return $string;
		},
		
		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };
  
    OpenBib::Common::Util::print_page($config{tt_virtualsearch_showkorindex_tname},$ttdata,$r);

    return OK;
  }


  # BEGIN Schlagworte
  # (derzeit nicht unterstuetzt)
  ####################################################################
  # Wenn ein kataloguebergreifender Schlagwortindex ausgewaehlt wurde
  ####################################################################

  if ($swtindex){
    $swt=~s/\+//g;
    $swt=~s/%2B//g;

    if (!$swt){
      OpenBib::Common::Util::print_warning("Sie haben kein Schlagwort eingegeben",$r);
    return OK;
    }

    # TODO: Einbeziehung der Datenbankauswahl, Umorganisierug der
    # Daten (Schlagwort mit all seinen Datenbanken und Treffern)

    my %swtindex=();

    foreach my $database (@databases){
      my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
      my $thisindex=OpenBib::Search::Util::get_index_by_swt($swt,$dbh);

      # Umorganisierung der Daten

      foreach my $item (@$thisindex){
	my %item=%$item;

	# Korrekte Initialisierung mit 0
	if (! $swtindex{$item{swt}}{titanzahl}){
	  $swtindex{$item{swt}}{titanzahl}=0;
	}

	my $swtdb={
		   'dbname' => $database,
		   'dbdesc' => $dbnames{$database},
		   'swtidn' => $item{swtidn},
		   'titanzahl' => $item{titanzahl},
		  };

	push @{$swtindex{$item{swt}}{databases}}, $swtdb;
	$swtindex{$item{swt}}{titanzahl}=$swtindex{$item{swt}}{titanzahl}+$item{titanzahl};
      }


      $dbh->disconnect;
    }

    # TT-Data erzeugen
    
    my $ttdata={
		stylesheet => $stylesheet,
		
		sessionID  => $sessionID,
		
		searchmode => $searchmode,
	
		swt      => $swt,
		swtindex => \%swtindex,
		databases => \@databases,
		
		utf2iso => sub {
		  my $string=shift;
		  $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		  return $string;
		},
		
		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };
  
    OpenBib::Common::Util::print_page($config{tt_virtualsearch_showswtindex_tname},$ttdata,$r);

    return OK;
  }

  ####################################################################
  # ENDE Indizes
  #


  # Folgende nicht erlaubte Anfragen werden sofort ausgesondert 
  
  my $firstsql;
  if ($fs){
    $firstsql=1;
  }
  if ($verf){
    $firstsql=1;
  }
  if ($kor){
    $firstsql=1;
  }
  if ($hst){
    $firstsql=1;
  }
  if ($swt){
    $firstsql=1;
  }
  if ($notation){
    $firstsql=1;
  }
  
  if ($sign){
    $firstsql=1;
  }
  
  if ($isbn){
    $firstsql=1;
  }
  
  if ($issn){
    $firstsql=1;
  }
  
  if ($mart){
    $firstsql=1;
  }

  if ($hststring){
    $firstsql=1;
  }
  
  if ($ejahr){
    my ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
    if (!$ejtest){
      OpenBib::Common::Util::print_warning("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein.",$r);
      goto LEAVEPROG;
      
    }        
  }
  
  if ($boolejahr eq "OR"){
    if ($ejahr){
      OpenBib::Common::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der
UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verst&auml;ndnis f&uuml;r diese Einschr&auml;nkung.",$r);
      goto LEAVEPROG;
    }
  }
  
  if ($boolejahr eq "AND"){
    if ($ejahr){
      if (!$firstsql){
	OpenBib::Common::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der
UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verst&auml;ndnis f&uuml;r diese Einschr&auml;nkung.",$r);
	goto LEAVEPROG;
      }
    }
  }
  
  if (!$firstsql){
    OpenBib::Common::Util::print_warning("Es wurde kein Suchkriterium eingegeben.",$r);
    goto LEAVEPROG;
  }
  
  
  my @ergebnisse;
  
  my $ergidx;
  
  my %trefferpage=();
  my %dbhits=();
  
  # Header mit allen Elementen ausgeben
  
  OpenBib::Common::Util::print_simple_header("Such-Client des Virtuellen Katalogs",$r);
  
  print << "HEADER";
<ul id="tabbingmenu">
   <li><a class="active" href="$config{virtualsearch_loc}?sessionID=$sessionID;trefferliste=choice;view=$view">Trefferliste</a></li>
</ul>

<div id="content">

<FORM METHOD="GET">
<p>
HEADER
  
  # Suchhinweis Digibib
  
  OpenBib::VirtualSearch::Util::print_recherche_hinweis($hst,$verf,$kor,$ejahr,$issn,$isbn,$userdbh,$sessionID);
  
  OpenBib::Common::Util::print_sort_nav($r,'sortboth',1);        
  
  # Bisherigen Header ausgeben
  
  $r->rflush();
  
  
  print"<table>\n";
  
  my $gesamttreffer=0;
  
  # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
  #
  ######################################################################
  # Schleife ueber alle Datenbanken 
  ######################################################################


  my @resultset=();
  
  foreach my $database (@databases){

    #####################################################################
    ## Ausleihkonfiguration fuer den Katalog einlesen
    
    my $dbinforesult=$sessiondbh->prepare("select circ,circurl,circcheckurl,circdb from dboptions where dbname = ?") or $logger->error($DBI::errstr);
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
    

    my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);

    my @tidns=OpenBib::Search::Util::initital_search_for_titidns($fs,$verf,$hst,$hststring,$swt,$kor,$notation,$isbn,$issn,$sign,$ejahr,$ejahrop,$mart,$boolfs,$boolverf,$boolhst,$boolhststring,$boolswt,$boolkor,$boolnotation,$boolisbn,$boolissn,$boolsign,$boolejahr,$boolmart,$dbh,$maxhits);


    # Wenn mindestens ein Treffer gefunden wurde

    if ($#tidns >= 0){
      my @outputbuffer=();
      my $outidx=0;
      
      my $atime;
      my $btime;
      my $timeall;
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }
      
      my $searchmultipleaut=0;
      my $searchmultiplekor=0;
      my $searchmultipleswt=0;
      my $searchmultipletit=0;
      my $rating=0;
      my $bookinfo=0;

      foreach my $idn (@tidns){

	# Zuerst in Resultset eintragen zur spaeteren Navigation
	
	push @resultset, { 'database' => $database,
			   'idn' => $idn
			 };
	
	
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
      
      
      OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

      my $treffer=$#sortedoutputbuffer+1;

      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td><td align=right colspan=3><strong>$treffer Treffer</strong></td></tr>\n";

      my $linecolor="aliceblue";
      
      my $count=1;
      foreach my $item (@sortedoutputbuffer){

	my $author=@{$item}{verfasser};
	my $titidn=@{$item}{idn};
	my $title=@{$item}{title};
	my $publisher=@{$item}{publisher};
	my $signature=@{$item}{signatur};
	my $yearofpub=@{$item}{erschjahr};
	my $thisdatabase=@{$item}{database};

	print << "TITITEM";
<tr bgcolor="$linecolor"><td bgcolor="lightblue"><strong>$count</strong></td><td colspan=2><strong><span id="rlauthor">$author</span></strong><br /><a href="$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=;sorttype=$sorttype&database=$thisdatabase;searchsingletit=$titidn"><strong><span id="rltitle">$title</span></strong></a>, <span id="rlpublisher">$publisher</span> <span id="rlyearofpub">$yearofpub</span></td><td><a href="/portal/merkliste?sessionID=$sessionID;action=insert;database=$thisdatabase;singleidn=$titidn" target="header"><span id="rlmerken"><a href="/portal/merkliste?sessionID=$sessionID;action=insert;database=$thisdatabase;singleidn=$titidn" target="header" title="In die Merkliste"><img src="/images/openbib/3d-file-blue-clipboard.png" height="29" alt="In die Merkliste" border=0></a></span></a></td><td align=left><b>$signature</b></td></tr>
TITITEM

	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}

        $count++;

      }

      print "<tr>\n<td colspan=3>&nbsp;<td></tr>\n";      
      $trefferpage{$database}=\@sortedoutputbuffer;
      $dbhits{$database}=$treffer;
      $gesamttreffer=$gesamttreffer+$treffer;


    }

    $dbh->disconnect;

    $r->rflush();

    
  }
  
  ######################################################################
  #
  # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln

  $logger->info("InitialSearch: ", $sessionID, " ", $gesamttreffer, " fs=(", $fs, ") verf=(", $boolverf, "#", $verf, ") hst=(", $boolhst, "#", $hst, ") hststring=(", $boolhststring, "#", $hststring, ") swt=(", $boolswt, "#", $swt, ") kor=(", $boolkor, "#", $kor, ") sign=(", $boolsign, "#", $sign, ") isbn=(", $boolisbn, "#", $isbn, ") issn=(", $boolissn, "#", $issn, ") mart=(", $boolmart, "#", $mart, ") notation=(", $boolnotation, "#", $notation, ") ejahr=(", $boolejahr, "#", $ejahr, ") ejahrop=(", $ejahrop, ") databases=(",join(' ',sort @databases),") ");

  # Wenn nichts gefunden wurde, dann entsprechende Information
  
  if ($gesamttreffer == 0) {
    my $tmp="<tr><td colspan=3><strong>Es wurden keine Treffer gefunden</strong></td></tr>\n";
    print $tmp;
  }
  # Ansonsten kann ein Resultset eingetragen werden
  else {
    OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
  }
  ######################################################################
  # Bei einer SessionID von -1 wird effektiv keine Session verwendet
  ######################################################################
  
  if ($sessionID ne "-1"){
    
    # Jetzt update der Trefferinformationen
    
    # Plus-Zeichen fuer Abspeicherung wieder hinzufuegen...!
    
    $fs=~s/%2B/\+/g;
    $verf=~s/%2B/\+/g;
    $hst=~s/%2B/\+/g;
    $swt=~s/%2B/\+/g;
    $kor=~s/%2B/\+/g;
    $notation=~s/%2B/\+/g;
    $sign=~s/%2B/\+/g;
    $isbn=~s/%2B/\+/g;
    $issn=~s/%2B/\+/g;
    $ejahr=~s/%2B/\+/g;
    
    
    my $dbasesstring=join("||",@databases);

    my $thisquerystring="$fs||$verf||$hst||$swt||$kor||$sign||$isbn||$issn||$notation||$mart||$ejahr||$hststring||$boolhst||$boolswt||$boolkor||$boolnotation||$boolisbn||$boolsign||$boolejahr||$boolissn||$boolverf||$boolfs||$boolmart||$boolhststring";
    my $idnresult=$sessiondbh->prepare("select * from queries where query = ? and sessionid = ? and dbases = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($thisquerystring,$sessionID,$dbasesstring) or $logger->error($DBI::errstr);
    
    my $queryalreadyexists=0;
    
    # Neuer Query
    if ($idnresult->rows <= 0){
      $idnresult=$sessiondbh->prepare("insert into queries (queryid,sessionid,query,hits,dbases) values (NULL,?,?,?,?)") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$thisquerystring,$gesamttreffer,$dbasesstring) or $logger->error($DBI::errstr);
    }
    
    # Query existiert schon
    else {
      $queryalreadyexists=1;
    }
    
    
    $idnresult=$sessiondbh->prepare("select queryid from queries where query = ? and sessionid = ? and dbases = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($thisquerystring,$sessionID,$dbasesstring) or $logger->error($DBI::errstr);
    
    my @idnres;
    my $queryid;
    while (@idnres=$idnresult->fetchrow){	    
      $queryid=$idnres[0];
    }
    
    if ($queryalreadyexists == 0){
      
      my $db="";
      
      $idnresult=$sessiondbh->prepare("insert into searchresults values (?,?,?,?,?)") or $logger->error($DBI::errstr);
      
      foreach $db (keys %trefferpage){
	my $res=$trefferpage{$db};

	my $yamlres=YAML::Dump($res);


	$logger->info("YAML-Dumped: $yamlres");
	my $num=$dbhits{$db};
	$idnresult->execute($sessionID,$db,$yamlres,$num,$queryid) or $logger->error($DBI::errstr);
      }
    }
    
    $idnresult->finish();
    
  }
  
  print "</table></div><p>";
  OpenBib::Common::Util::print_footer();
  
LEAVEPROG: sleep 0;
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  
  return OK;
}

1;
