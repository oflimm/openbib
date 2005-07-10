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

use Template;

use YAML;

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

  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
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

    $sessiondbh->disconnect();
    $userdbh->disconnect();
  
    return OK;  
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

      $sessiondbh->disconnect();
      $userdbh->disconnect();
      
      return OK;
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
      
      my @queries=();

      while (my @res=$idnresult->fetchrow){

	my ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$bool1,$bool2,$bool3,$bool4,$bool5,$bool6,$bool7,$bool8,$bool9,$bool10,$bool11,$bool12)=split('\|\|',$res[1]);

	push @queries, {
			id => $res[0],

			fs => $fs,
			verf => $verf,
			hst => $hst,
			swt => $swt,
			kor => $kor,
			notation => $notation,
			sign => $sign,
			ejahr => $ejahr,
			isbn => $isbn,
			issn => $issn,
			mart => $mart,
			hststring => $hststring,
			
			hits => $res[2],
		       };
	
      }
      
      # Finde den aktuellen Query

      my $thisquery={};


      # Wenn keine Queryid angegeben wurde, dann nehme den ersten Eintrag,
      # da dieser der aktuellste ist
      if ($queryid eq ""){
	$thisquery=$queries[0];
      }
      # ansonsten nehmen den ausgewaehlten
      else{
	foreach my $query (@queries){
	  if (@{$query}{id} eq "$queryid"){
	    $thisquery=$query;
	  }
	  
	}
      }
      
      
      $idnresult=$sessiondbh->prepare("select dbname,hits from searchresults where sessionid = ? and queryid = ? order by hits desc") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,@{$thisquery}{id}) or $logger->error($DBI::errstr);


      my $hitcount=0;
      
      my @resultdbs=();

      while (my @res=$idnresult->fetchrow){
	push @resultdbs, {
			  trefferdb => $res[0],
			  trefferdbdesc => $dbnames{$res[0]},
			  trefferzahl => $res[1],
			 };
	
	$hitcount+=$res[1];
      }


      # TT-Data erzeugen
      
      my $ttdata={
		  title      => 'KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
		  stylesheet   => $stylesheet,
		  view         => $view,
		  sessionID    => $sessionID,


		  thisquery => $thisquery,
		  
		  queryid => $queryid,

		  hitcount => $hitcount,
	
		  resultdbs => \@resultdbs,

		  queries => \@queries,

		  show_foot_banner      => 1,
		  
		  config       => \%config,
		 };
      

      
      OpenBib::Common::Util::print_page($config{tt_resultlists_choice_tname},$ttdata,$r);
      
      return OK;
      
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
      
      
      $idnresult=$sessiondbh->prepare("select searchresults.searchresult,searchresults.dbname from searchresults, dbinfo where searchresults.dbname=dbinfo.dbname and sessionid = ? and queryid = ? order by dbinfo.faculty,searchresults.dbname") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$queryid) or $logger->error($DBI::errstr);

      my @resultset=();
      
      if ($sortall == 1){

	my @outputbuffer=();

	while (my @res=$idnresult->fetchrow){
	  my $yamlres=YAML::Load($res[0]);

	  push @outputbuffer, @$yamlres;
	}

	my $treffer=$#outputbuffer+1;

	# Sortierung
	
	my @sortedoutputbuffer=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);


	my $loginname="";
	my $password="";

	my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
	
	($loginname,$password)=get_cred_for_userid($userdbh,$userid) if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self");
	
	# Hash im Loginname ersetzen
	
	$loginname=~s/#/\%23/;

	my $hostself="http://".$r->hostname.$r->uri;
	
	my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1);
	

	# TT-Data erzeugen
	
	my $ttdata={
		    title      => 'KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
		    stylesheet   => $stylesheet,
		    view         => $view,
		    sessionID    => $sessionID,

		    searchmode => 2,
		    bookinfo => 0,
		    rating => 0,
		    
		    resultlist => \@sortedoutputbuffer,
		    dbinfo     => \%dbinfo,
		    
		    loginname => $loginname,
		    password => $password,
		    
		    queryargs => $queryargs,
		    sortselect => $sortselect,
		    thissortstring => $thissortstring,
		    
		    show_foot_banner      => 1,
		    
		    config       => \%config,
		   };
      

      
      OpenBib::Common::Util::print_page($config{tt_resultlists_showall_sortall_tname},$ttdata,$r);

	# Eintraege merken fuer Lastresultset

	foreach my $item (@sortedoutputbuffer){
	  push @resultset, { 'database' => @{$item}{database},
			     'idn' => @{$item}{idn},
			   };
	}


	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
	$idnresult->finish();

      }
      elsif ($sortall == 0) {
	
	# Katalogoriertierte Sortierung

	my @resultlists=();

	while (my @res=$idnresult->fetchrow){
	  my $yamlres=YAML::Load($res[0]);

          my $database=$res[1];

	  my @outputbuffer=@$yamlres;

	  my $treffer=$#outputbuffer+1;

	  # Sortierung
	  
	  my @sortedoutputbuffer=();
	  
	  OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	  push @resultlists, {
			      database => $database,
			      resultlist => \@sortedoutputbuffer,
			     };
	  


	  # Eintraege merken fuer Lastresultset
	  
	  foreach my $item (@sortedoutputbuffer){
	    push @resultset, { 'database' => @{$item}{database},
			       'idn' => @{$item}{idn},
			     };
	  }
	}
	
	my $loginname="";
	my $password="";
	
	my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
	
	($loginname,$password)=get_cred_for_userid($userdbh,$userid) if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self");
	
	# Hash im Loginname ersetzen
	
	$loginname=~s/#/\%23/;

	my $hostself="http://".$r->hostname.$r->uri;
	
	my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1);
	

	# TT-Data erzeugen
	
	my $ttdata={
		    title      => 'KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
		    stylesheet   => $stylesheet,
		    view         => $view,
		    sessionID    => $sessionID,

		    searchmode => 2,
		    bookinfo   => 0,
		    rating     => 0,
		    
		    resultlists => \@resultlists,
		    dbinfo      => \%dbinfo,
		    
		    loginname => $loginname,
		    password  => $password,
		    
		    queryargs  => $queryargs,
		    sortselect => $sortselect,
		    thissortstring => $thissortstring,
		    
		    show_foot_banner      => 1,
		    
		    config       => \%config,
		   };
      
	OpenBib::Common::Util::print_page($config{tt_resultlists_showall_tname},$ttdata,$r);


	OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
	$idnresult->finish();

      }
      
      $idnresult->finish();
      
      $sessiondbh->disconnect();
      $userdbh->disconnect();
      
      return OK;
    }
    
    ####################################################################
    # ... falls die Treffer zu einer queryid aus einer Datenbank 
    # angezeigt werden sollen
    ####################################################################
    
    elsif ($dbases{$trefferliste} ne "") {
      
      my @resultset=();
      
      $idnresult=$sessiondbh->prepare("select searchresult from searchresults where sessionid = ? and dbname = ? and queryid = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$trefferliste,$queryid) or $logger->error($DBI::errstr);
      
      
      my @resultlists=();

      while (my @res=$idnresult->fetchrow){
	my $yamlres=YAML::Load($res[0]);
	
	my @outputbuffer=@$yamlres;
	
	my $treffer=$#outputbuffer+1;
	
	# Sortierung
	
	my @sortedoutputbuffer=();
	
	OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
	push @resultlists, {
			    database => $trefferliste,
			    resultlist => \@sortedoutputbuffer,
			   };
	
	
	
	# Eintraege merken fuer Lastresultset
	
	foreach my $item (@sortedoutputbuffer){
	  push @resultset, { 'database' => $trefferliste,
			     'idn' => @{$item}{idn},
			   };
	}
	
	
	
      }
      
      my $loginname="";
      my $password="";
      
      my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
      
      ($loginname,$password)=get_cred_for_userid($userdbh,$userid) if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self");
      
      # Hash im Loginname ersetzen
      
      $loginname=~s/#/\%23/;
      
      my $hostself="http://".$r->hostname.$r->uri;
      
      my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortsingle',1);
      
      
      # TT-Data erzeugen
      
      my $ttdata={
		  title      => 'KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
		  stylesheet   => $stylesheet,
		  view         => $view,
		  sessionID    => $sessionID,
		  
		  searchmode => 2,
		  bookinfo   => 0,
		  rating     => 0,
		  
		  resultlists => \@resultlists,
		  dbinfo      => \%dbinfo,
		  
		  loginname => $loginname,
		  password  => $password,
		  
		  queryargs  => $queryargs,
		  sortselect => $sortselect,
		  thissortstring => $thissortstring,
		  
		  show_foot_banner      => 1,
		  
		  config       => \%config,
		 };
      
      
      
      OpenBib::Common::Util::print_page($config{tt_resultlists_showsinglepool_tname},$ttdata,$r);
      

      OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
      $idnresult->finish();

      $sessiondbh->disconnect();
      $userdbh->disconnect();
      
      return OK;
    }
    
  }
  
  ####################################################################
  # ENDE Trefferliste
  #

  $sessiondbh->disconnect();
  $userdbh->disconnect();
  
  return OK;
}

1;
