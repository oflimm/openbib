#####################################################################
#
#  OpenBib::SearchFrame
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

package OpenBib::SearchFrame;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use POSIX;

use Digest::MD5;
use DBI;

use Template;

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
  
  my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
  
  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
  my $date=`date '+%Y%m%d'`;
  chop $date;
  
  my $year="";
  my $month="";
  my $day="";
  
  if ($date=~/^..(..)(..)(..)$/){
    $year=$1;
    $month=$2;
    $day=$3;
  }
  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  my @databases=($query->param('database'))?$query->param('database'):();
  my $singleidn=$query->param('singleidn') || '';
  my $action=($query->param('action'))?$query->param('action'):'';
  
  # TODO: $query statt query in alter Version
  
  my $view=($query->param('view'))?$query->param('view'):'';
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
  }

  # Authorisierte Session?

  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  my $showfs="1";
  my $showhst="1";
  my $showverf="1";
  my $showkor="1";
  my $showswt="1";
  my $shownotation="1";
  my $showisbn="1";
  my $showissn="1";
  my $showsign="1";
  my $showmart="0";
  my $showhststring="1";
  my $showejahr="1";
  
  my $userprofiles="";
  
  if ($userid){
    my $targetresult=$userdbh->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
    
    $targetresult->execute($userid) or $logger->error($DBI::errstr);
    
    my $result=$targetresult->fetchrow_hashref();
    
    $showfs=$result->{'fs'};
    $showhst=$result->{'hst'};
    $showverf=$result->{'verf'};
    $showkor=$result->{'kor'};
    $showswt=$result->{'swt'};
    $shownotation=$result->{'notation'};
    $showisbn=$result->{'isbn'};
    $showissn=$result->{'issn'};
    $showsign=$result->{'sign'};
    $showmart=$result->{'mart'};
    $showhststring=$result->{'hststring'};
    $showejahr=$result->{'ejahr'};
    $targetresult->finish();

    
    $targetresult=$userdbh->prepare("select profilid, profilename from userdbprofile where userid = ? order by profilename") or $logger->error($DBI::errstr);
    $targetresult->execute($userid) or $logger->error($DBI::errstr);
    
    if ($targetresult->rows > 0){
      $userprofiles.="<option value=\"\">Gespeicherte Katalogprofile:</option><option value=\"\">&nbsp;</option>";
    }
    
    while (my $res=$targetresult->fetchrow_hashref()){
      my $profilid=$res->{'profilid'};
      my $profilename=$res->{'profilename'};
      $userprofiles.="<option value=\"user$profilid\">- $profilename</option>";
    } 
    
    if ($targetresult->rows > 0){
      $userprofiles.="<option value=\"\">&nbsp;</option>"
    }
    
    $targetresult=$userdbh->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
    
    $targetresult->execute($userid) or $logger->error($DBI::errstr);
    
    $result=$targetresult->fetchrow_hashref();
    
    $targetresult->finish();
  }
  
  # CGI-Uebergabe
  
  my $fs=$query->param('fs') || ''; # Freie Suche
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
  my $mart=$query->param('mart') || '';
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
  
  my $benchmark=0;
  
  my $queryid=$query->param('queryid') || '';
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    
    return OK;
  }
  
  # Assoziierten View zur Session aus Datenbank holen
  
  my $idnresult=$sessiondbh->prepare("select viewinfo.description from sessionview,viewinfo where sessionview.sessionid = ? and sessionview.viewname=viewinfo.viewname") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  my $result=$idnresult->fetchrow_hashref();
  
  my $viewdesc=$result->{'description'} if (defined($result->{'description'}));
  
  $idnresult->finish();
  
  my $hits;
  
  if ($queryid ne ""){
    my $idnresult=$sessiondbh->prepare("select query,hits from queries where queryid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($queryid) or $logger->error($DBI::errstr);
    
    my $result=$idnresult->fetchrow_hashref();
    my $query=$result->{'query'};
    
    $query=~s/"/&quot;/g;

    $hits=$result->{'hits'};

    ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$bool1,$bool2,$bool3,$bool4,$bool5,$bool6,$bool7,$bool8,$bool9,$bool10,$bool11,$bool12)=split('\|\|',$query);
    $idnresult->finish();
  }

  # Wenn Datenbanken uebergeben wurden, dann werden diese eingetragen

  if ($#databases >= 0){
    my $thisdb="";
    my $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

    foreach $thisdb (@databases){
      $idnresult=$sessiondbh->prepare("insert into dbchoice values (?,?)") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$thisdb) or $logger->error($DBI::errstr);
    }
    $idnresult->finish;
  }



  # Erzeugung der database-Input Tags fuer die suche

  my $dbinputtags="";

  $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

  my $dbcount=0;
  while (my $result=$idnresult->fetchrow_hashref()){
  
    my $dbname=$result->{'dbname'};
    $dbinputtags.="<input type=\"hidden\" name=\"database\" value=\"$dbname\" />\n";
    $dbcount++; 
  }

  $idnresult=$sessiondbh->prepare("select dbname from dbinfo where active=1") or $logger->error($DBI::errstr);
  $idnresult->execute() or $logger->error($DBI::errstr);

  my $alldbs=$idnresult->rows;


  $idnresult=$sessiondbh->prepare("select sum(count) from titcount,dbinfo where  titcount.dbname=dbinfo.dbname and dbinfo.active=1") or $logger->error($DBI::errstr);
  $idnresult->execute() or $logger->error($DBI::errstr);

  my $alldbcount=$idnresult->fetchrow();

  $idnresult->finish();

  if ($dbcount != 0){
    $dbcount="<OPTION value=\"dbauswahl\">Aktuelle Katalogauswahl ($dbcount Datenbanken)<OPTION value=\"\">";
  }
  else {
    $dbcount="";
  }

  # Ausgabe der vorhandenen queries

  $idnresult=$sessiondbh->prepare("select * from queries where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  my $anzahl=$idnresult->rows();

  my $prevqueries="";

  if ($anzahl > 0){

    while (my $result=$idnresult->fetchrow_hashref()){

      my $queryid=$result->{'queryid'};

      my $query=$result->{'query'};
      my $hits=$result->{'hits'};

      my ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$bool1,$bool2,$bool3,$bool4,$bool5,$bool6,$bool7,$bool8,$bool9,$bool10,$bool11,$bool12)=split('\|\|',$query);

      $prevqueries.="<OPTION value=\"$queryid\">";

      $prevqueries.="FS: $fs " if ($fs);
      $prevqueries.="AUT: $verf " if ($verf);
      $prevqueries.="HST: $hst " if ($hst);
      $prevqueries.="SWT: $swt " if ($swt);
      $prevqueries.="KOR: $kor " if ($kor);
      $prevqueries.="NOT: $notation " if ($notation);
      $prevqueries.="SIG: $sign " if ($sign);
      $prevqueries.="EJAHR: $ejahr " if ($ejahr);
      $prevqueries.="ISBN: $isbn " if ($isbn);
      $prevqueries.="ISSN: $issn " if ($issn);
      $prevqueries.="MART: $mart " if ($mart);
      $prevqueries.="HSTR: $hststring " if ($hststring);
      $prevqueries.="= Treffer: $hits" if ($hits);
      $prevqueries.="</OPTION>"; 

    }

  }

  $idnresult->finish();
  my $template = Template->new({ 
				INCLUDE_PATH  => $config{tt_include_path},
				#    	    PRE_PROCESS   => 'config',
				OUTPUT        => $r,     # Output geht direkt an Apache Request
			       });

    # TT-Data erzeugen

    my $ttdata={
		title      => 'KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
		stylesheet   => $stylesheet,
		view         => $view,
                viewdesc     => $viewdesc,
                sessionID    => $sessionID,
                dbinputtags  => $dbinputtags,
                show_testsystem_info => 1,
                alldbs       => $alldbs,
                dbcount      => $dbcount,
                alldbcount   => $alldbcount,
                userprofiles => $userprofiles,
                showfs       => $showfs,
                showhst      => $showhst,
                showverf     => $showverf,
                showkor      => $showkor,
                showswt      => $showswt,
                shownotation => $shownotation,
                showisbn     => $showisbn,
                showissn     => $showissn,
                showsign     => $showsign,
                showmart     => $showmart,
                showhststring => $showhststring,
                showejahr    => $showejahr,

                fs           => $fs,
                hst          => $hst,
                hststring    => $hststring,
                verf         => $verf,
                kor          => $kor,
                swt          => $swt,
                notation     => $notation,
                isbn         => $isbn,
                issn         => $issn,
                sign         => $sign,
                mart         => $mart,
                ejahr        => $ejahr,

                anzahl       => $anzahl,
                prevqueries  => $prevqueries,
                useragent    => $useragent,                
		show_corporate_banner => 0,
		show_foot_banner      => 1,
		config       => \%config,
	       };
    
    # Dann Ausgabe des neuen Headers
    
    print $r->send_http_header("text/html");
    
    $template->process($config{tt_searchframe_tname}, $ttdata) || do { 
      $r->log_reason($template->error(), $r->filename);
      return SERVER_ERROR;
    };

  $sessiondbh->disconnect();
  $userdbh->disconnect();
  return OK;
}

1;
