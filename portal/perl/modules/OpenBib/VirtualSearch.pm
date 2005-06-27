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
  my $bool1=$query->param('bool1') || '';
  my $bool2=$query->param('bool2') || '';
  my $bool3=$query->param('bool3') || '';
  my $bool4=$query->param('bool4') || '';
  my $bool5=$query->param('bool5') || '';
  my $bool6=$query->param('bool6') || '';
  my $bool7=$query->param('bool7') || '';
  my $bool8=$query->param('bool8') || '';
  my $bool9=$query->param('bool9') || '';
  my $bool10=$query->param('bool10') || '';
  my $bool11=$query->param('bool11') || '';
  my $bool12=$query->param('bool12') || '';
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
  
  my %fakultaeten=(
		   '0ungeb' => '1',
		   '1wiso' => '1',
		   '2recht' => '1',
		   '3ezwheil' => '1',
		   '4phil' => '1',
		   '5matnat' => '1'
		  );
  
  $profil="" if ((!defined $fakultaeten{$profil}) && $profil ne "dbauswahl" && !$profil=~/^user/);
  
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
    # Fakultaetsspezifische Datenbankprofile
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
  
  if ($bool7 eq "OR"){
    if ($ejahr){
      OpenBib::Common::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der
UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verst&auml;ndnis f&uuml;r diese Einschr&auml;nkung.",$r);
      goto LEAVEPROG;
    }
  }
  
  if ($bool7 eq "AND"){
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
  
  # Plus-Zeichen nicht verlieren...!
  
  $fs=~s/\+/%2B/g;
  $verf=~s/\+/%2B/g;
  $hst=~s/\+/%2B/g;
  $swt=~s/\+/%2B/g;
  $kor=~s/\+/%2B/g;
  $notation=~s/\+/%2B/g;
  $sign=~s/\+/%2B/g;
  $isbn=~s/\+/%2B/g;
  $issn=~s/\+/%2B/g;
  $ejahr=~s/\+/%2B/g;
  
  
  my $gesamttreffer=0;
  my $database;
  
  # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
  #
  ######################################################################
  # Schleife ueber alle Datenbanken 
  ######################################################################
  
  my @resultset=();
  
  foreach $database (@databases){


    my $suchstring="sessionID=$sessionID&search=$search&fs=$fs&verf=$verf&hst=$hst&hststring=$hststring&swt=$swt&kor=$kor&sign=$sign&isbn=$isbn&issn=$issn&mart=$mart&notation=$notation&verknuepfung=$verknuepfung&ejahr=$ejahr&ejahrop=$ejahrop&searchmode=$searchmode&maxhits=$maxhits&hitrange=-1&searchall=$searchall&dbmode=$dbmode&bool1=$bool1&bool2=$bool2&bool3=$bool3&bool4=$bool4&bool5=$bool5&bool6=$bool6&bool7=$bool7&bool8=$bool8&bool9=$bool9&bool10=$bool10&bool11=$bool11&bool12=$bool12&sorttype=$sorttype&sortorder=$sortorder&database=$database";

    my $request=new HTTP::Request GET => "$befehlsurl?$suchstring";
    
    $logger->debug("Sending ",$suchstring," to ",$befehlsurl);
    
    my $response=$ua->request($request);
    
    if ($response->is_success) {
      $logger->debug("Getting ", $response->content);
    }
    else {
      $logger->error("Getting ", $response->status_line);
    }
    
    my $ergebnis=$response->content();
    
    my $multiple=OpenBib::VirtualSearch::Util::is_multiple_tit($ergebnis);
    my $single=OpenBib::VirtualSearch::Util::is_single_tit($ergebnis,$befehlsurl,$database,$hitrange,$sessionID,$sorttype);
    
    my $outputbuffer="";
    my $treffer=0;
    
    my $linecolor="aliceblue";
    
    if ($multiple){
      my @titel=OpenBib::VirtualSearch::Util::extract_singletit_from_multiple($ergebnis,$hitrange,\%dbases,$sorttype);
      my $tit;
      foreach $tit (@titel){
	
	# Wenn wir keinen leeren Titel in der Trefferzeile haben, dann...
	if (!($tit=~/<span id=.rltitle.> <.span>/)){
	  $treffer++;
	  $outputbuffer.="<tr bgcolor=\"$linecolor\"><td bgcolor=\"lightblue\"><strong>$treffer</strong></td>".$tit."\n";
	  
	  my $katkey="";
	  
	  ($katkey)=$tit=~/searchsingletit=(\d+)/;
	  push @resultset, { 'database' => $database,
			     'idn' => $katkey
			   };
	    	  
	  
	}
	# .. ansonsten wird ein generischer Text als HST gesetzt
	else {
	  $treffer++;
	  $tit=~s/<span id=.rltitle.> <.span>/<strong>&lt;Kein HST\/AST\/EST vorhanden&gt;<\/strong>/;
	  $outputbuffer.="<tr bgcolor=\"$linecolor\"><td bgcolor=\"lightblue\"><strong>$treffer</strong></td>".$tit."\n";
	  
	}
	
	if ($linecolor eq "white"){
	  $linecolor="aliceblue";
	}
	else {
	  $linecolor="white";
	}
      } 
    }
    
    if ($single ne "none"){
      if (!($single=~/<strong> <.strong><.a>,/)){
	$treffer++;
	$outputbuffer.="<tr bgcolor=\"aliceblue\"><td bgcolor=\"lightblue\"><strong>$treffer</strong></td>".$single."</td></tr>\n";
	my ($katkey)=$single=~/searchsingletit=(\d+)/;
	
	push @resultset, { 'database' => $database,
			   'idn' => $katkey
			 };
      }
      else {
	$treffer++;
	$single=~s/<strong> <.strong>/<strong>&lt;Kein HST\/AST\/EST vorhanden&gt;<\/strong>/;
	$outputbuffer.="<tr bgcolor=\"aliceblue\"><td bgcolor=\"lightblue\"><strong>$treffer</strong></td>".$single."</td></tr>\n";
      }
    }
    
    
    if ($treffer != 0){
      my $tmp="<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbases{"$database"}."</td><td align=right colspan=3><strong>$treffer Treffer</strong></td></tr>\n$outputbuffer<tr>\n<td colspan=3>&nbsp;<td></tr>\n";
      print $tmp;
      $r->rflush();
      $trefferpage{$database}=$tmp;
      $dbhits{$database}=$treffer;
    }
    
    $gesamttreffer+=$treffer;
    $ergidx++;
  }
  
  ######################################################################
  #
  # ENDE Anfrage an Datenbanken schicken und Ergebnisse einsammeln

  $logger->info("InitialSearch: ", $sessionID, " ", $gesamttreffer, " fs=(", $fs, ") verf=(", $bool9, "#", $verf, ") hst=(", $bool1, "#", $hst, ") hststring=(", $bool12, "#", $hststring, ") swt=(", $bool2, "#", $swt, ") kor=(", $bool3, "#", $kor, ") sign=(", $bool6, "#", $sign, ") isbn=(", $bool5, "#", $isbn, ") issn=(", $bool8, "#", $issn, ") mart=(", $bool11, "#", $mart, ") notation=(", $bool4, "#", $notation, ") ejahr=(", $bool7, "#", $ejahr, ") ejahrop=(", $ejahrop, ") databases=(",join(' ',sort @databases),") ");

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

    my $thisquerystring="$fs||$verf||$hst||$swt||$kor||$sign||$isbn||$issn||$notation||$mart||$ejahr||$hststring||$bool1||$bool2||$bool3||$bool4||$bool5||$bool6||$bool7||$bool8||$bool9||$bool10||$bool11||$bool12";
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
	my $num=$dbhits{$db};
	$idnresult->execute($sessionID,$db,$res,$num,$queryid) or $logger->error($DBI::errstr);
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
