#####################################################################
#
#  OpenBib::ManageCollection
#
#  Dieses File ist (C) 2001-2005 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;

use POSIX;

use Digest::MD5;
use DBI;

use OpenBib::Common::Util;
use OpenBib::ManageCollection::Util;

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
  
  # Dynamische Definition diverser Variablen

  my %sigel=();
  my %bibinfo=();
  my %dbinfo=();
  my %dbases=();
  my %dbnames=();

  {  
    my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description from dbinfo") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);;
    
    
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
      ## Wandlungstabelle  Name SQL-Datenbank <-> Beschreibung (ohne URL)
      
      $dbnames{"$dbname"}=$description;
      
      #####################################################################
      ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
      
      $dbases{"$dbname"}="$sigel";
      
    }
    
    $sigel{''}="Unbekannt";
    $bibinfo{''}="http://www.ub.uni-koeln.de/dezkat/bibinfo/noinfo.html";
    $dbases{''}="Unbekannt";
    
    $dbinforesult->finish();
  }

  # Assoziierten View zur Session aus Datenbank holen
  
  my $idnresult=$sessiondbh->prepare("select viewname from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
  my $result=$idnresult->fetchrow_hashref();
  
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

    my @collection=();

    my @dbidnlist=();
    while (my $result=$idnresult->fetchrow_hashref()){
      my $database=$result->{'dbname'};
      my $singleidn=$result->{'singleidn'};
      
      push @dbidnlist, {
			database => $database,
			singleidn => $singleidn,
		       };
    }

    foreach my $dbidn (@dbidnlist){
      my $database=@{$dbidn}{database};
      my $singleidn=@{$dbidn}{singleidn};
      
      my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);

      my $hint="none";
      my $searchmultipleaut=0;
      my $searchmultiplekor=0;
      my $searchmultipleswt=0;
      my $searchmultipletit=0;
      my $searchmode=2;
      my $hitrange=-1;
      my $rating="";
      my $bookinfo="";
#      my $circ="";
#      my $circurl="";
#      my $circcheckurl="";
#      my $circdb="";
      my $sorttype="";
      my $sortorder="";
      
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
      
      my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($singleidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      

      if ($type eq "Text"){
	$normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
      }
      elsif ($type eq "EndNote"){
	$normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
      }

      $dbh->disconnect();

      $logger->info("Merklistensatz geholt");
  
      push @collection, { 
			 database => $database,
			 dbdesc   => $dbinfo{$database},
			 titidn   => $singleidn,
			 tit => $normset, 
			 mex => $mexnormset, 
			 circ => $circset 
			};
    }
    
    $idnresult->finish();
    
    # TT-Data erzeugen
    
    my $ttdata={
		stylesheet => $stylesheet,
		
		sessionID  => $sessionID,
		
		type => $type,
		
		collection => \@collection,
		
		utf2iso => sub {
		  my $string=shift;
		  $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		  return $string;
		},
		
		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };
    
    OpenBib::Common::Util::print_page($config{tt_managecollection_show_tname},$ttdata,$r);
    return OK;
  }
  
  #####################################################################
  # Abspeichern der Merkliste
  
  elsif ($action eq "save"){
    
    my @dbidnlist=();
    
    if ($singleidn && $database){
      push @dbidnlist, {
			database => $database,
			singleidn => $singleidn,
		       };
    }
    else {

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
            
      while (my $result=$idnresult->fetchrow_hashref()){
	my $database=$result->{'dbname'};
	my $singleidn=$result->{'singleidn'};
	
	push @dbidnlist, {
			  database => $database,
			  singleidn => $singleidn,
			 };
      }

    }      

    my @collection=();
    
    foreach my $dbidn (@dbidnlist){
      my $database=@{$dbidn}{database};
      my $singleidn=@{$dbidn}{singleidn};
      
      my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
      
      my $hint="none";
      my $searchmultipleaut=0;
      my $searchmultiplekor=0;
      my $searchmultipleswt=0;
      my $searchmultipletit=0;
      my $searchmode=2;
      my $hitrange=-1;
      my $rating="";
      my $bookinfo="";
      #      my $circ="";
      #      my $circurl="";
      #      my $circcheckurl="";
      #      my $circdb="";
      my $sorttype="";
      my $sortorder="";
      
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
      
      my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($singleidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      
      
      if ($type eq "Text"){
	$normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
      }
      elsif ($type eq "EndNote"){
	$normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
      }
      
      $dbh->disconnect();
      
      $logger->info("Merklistensatz geholt");
      
      push @collection, { 
			 database => $database,
			 dbdesc   => $dbinfo{$database},
			 titidn   => $singleidn,
			 tit => $normset, 
			 mex => $mexnormset, 
			 circ => $circset 
			};
    }
    
    $idnresult->finish();
    
    # TT-Data erzeugen
    
    my $ttdata={
		stylesheet => $stylesheet,
		
		sessionID  => $sessionID,
		
		type => $type,
		
		collection => \@collection,
		
		utf2iso => sub {
		  my $string=shift;
		  $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		  return $string;
		},
		
		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };
    
    if ($type eq "HTML"){
      
      print $r->header_out("Content-Type" => "text/html");
      print $r->header_out("Content-Disposition" => "attachment;filename=\"kugliste.html\"");
      OpenBib::Common::Util::print_page($config{tt_managecollection_save_html_tname},$ttdata,$r);
    }
    else {
      print $r->header_out("Content-Type" => "text/plain");
      print $r->header_out("Content-Disposition" => "attachment;filename=\"kugliste.txt\"");
      OpenBib::Common::Util::print_page($config{tt_managecollection_save_plain_tname},$ttdata,$r);
    }
    
    return OK;
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

    my @dbidnlist=();
    
    if ($singleidn && $database){
      push @dbidnlist, {
			database => $database,
			singleidn => $singleidn,
		       };
    }
    else {

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
            
      while (my $result=$idnresult->fetchrow_hashref()){
	my $database=$result->{'dbname'};
	my $singleidn=$result->{'singleidn'};
	
	push @dbidnlist, {
			  database => $database,
			  singleidn => $singleidn,
			 };
      }

    }      

    my @collection=();
    
    foreach my $dbidn (@dbidnlist){
      my $database=@{$dbidn}{database};
      my $singleidn=@{$dbidn}{singleidn};
      
      my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
      
      my $hint="none";
      my $searchmultipleaut=0;
      my $searchmultiplekor=0;
      my $searchmultipleswt=0;
      my $searchmultipletit=0;
      my $searchmode=2;
      my $hitrange=-1;
      my $rating="";
      my $bookinfo="";
      #      my $circ="";
      #      my $circurl="";
      #      my $circcheckurl="";
      #      my $circdb="";
      my $sorttype="";
      my $sortorder="";
      
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
      
      my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($singleidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      
      
      if ($type eq "Text"){
	$normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
      }
      elsif ($type eq "EndNote"){
	$normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
      }
      
      $dbh->disconnect();
      
      $logger->info("Merklistensatz geholt");
      
      push @collection, { 
			 database => $database,
			 dbdesc   => $dbinfo{$database},
			 titidn   => $singleidn,
			 tit => $normset, 
			 mex => $mexnormset, 
			 circ => $circset 
			};
    }
    
    $idnresult->finish();
    
    # TT-Data erzeugen
    
    my $ttdata={
		stylesheet => $stylesheet,
		
		sessionID  => $sessionID,
		
		type => $type,
	
		loginname => $loginname,
		singleidn => $singleidn,
		database => $database,

		collection => \@collection,
		
		utf2iso => sub {
		  my $string=shift;
		  $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		  return $string;
		},
		
		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };
    
    OpenBib::Common::Util::print_page($config{tt_managecollection_mail_tname},$ttdata,$r);
    return OK;
  }

  #####################################################################
  # Ausdrucken der Merkliste (HTML) ueber Browser

  elsif ($action eq "print"){

    # Weg mit der Singleidn - muss spaeter gefixed werden
    
    my $userresult=$userdbh->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);
    $userresult->execute($userid) or $logger->error($DBI::errstr);
    
    my $loginname="";
    
    if ($userresult->rows > 0){
      my $res=$userresult->fetchrow_hashref();
      $loginname=$res->{'loginname'};
    }
    
    my @dbidnlist=();
    
    if ($singleidn && $database){
      push @dbidnlist, {
			database => $database,
			singleidn => $singleidn,
		       };
    }
    else {
      
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
      
      while (my $result=$idnresult->fetchrow_hashref()){
	my $database=$result->{'dbname'};
	my $singleidn=$result->{'singleidn'};
	
	push @dbidnlist, {
			  database => $database,
			  singleidn => $singleidn,
			 };
      }
      
    }      
    
    my @collection=();
    
    foreach my $dbidn (@dbidnlist){
      my $database=@{$dbidn}{database};
      my $singleidn=@{$dbidn}{singleidn};
      
      my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
      
      my $hint="none";
      my $searchmultipleaut=0;
      my $searchmultiplekor=0;
      my $searchmultipleswt=0;
      my $searchmultipletit=0;
      my $searchmode=2;
      my $hitrange=-1;
      my $rating="";
      my $bookinfo="";
      #      my $circ="";
      #      my $circurl="";
      #      my $circcheckurl="";
      #      my $circdb="";
      my $sorttype="";
      my $sortorder="";
      
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
      
      my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($singleidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%dbinfo,\%titeltyp,\%sigel,\%dbases,\%bibinfo,$sessionID);
      
      
      if ($type eq "Text"){
	$normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
      }
      elsif ($type eq "EndNote"){
	$normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
      }
      
      $dbh->disconnect();
      
      $logger->info("Merklistensatz geholt");
      
      push @collection, { 
			 database => $database,
			 dbdesc   => $dbinfo{$database},
			 titidn   => $singleidn,
			 tit => $normset, 
			 mex => $mexnormset, 
			 circ => $circset 
			};
    }
    
    $idnresult->finish();
    
    # TT-Data erzeugen
    
    my $ttdata={
		stylesheet => $stylesheet,
		
		sessionID  => $sessionID,
		
		type => $type,
	
		loginname => $loginname,
		singleidn => $singleidn,
		database => $database,

		collection => \@collection,
		
		utf2iso => sub {
		  my $string=shift;
		  $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		  return $string;
		},
		
		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };
    
    OpenBib::Common::Util::print_page($config{tt_managecollection_print_tname},$ttdata,$r);
    return OK;
  }
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  return OK;
}

1;
