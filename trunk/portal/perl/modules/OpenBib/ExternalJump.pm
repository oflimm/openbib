#####################################################################
#
#  OpenBib::ExternalJump
#
#  Dieses File ist (C) 2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::ExternalJump;

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

  my $thisquery="";

  
  if ($queryid ne ""){
    my $idnresult=$sessiondbh->prepare("select query,hits from queries where queryid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($queryid) or $logger->error($DBI::errstr);
    
    my $result=$idnresult->fetchrow_hashref();
    my $query=$result->{'query'};
    
    $query=~s/"/&quot;/g;

    $hits=$result->{'hits'};

    ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$bool1,$bool2,$bool3,$bool4,$bool5,$bool6,$bool7,$bool8,$bool9,$bool10,$bool11,$bool12)=split('\|\|',$query);
    $idnresult->finish();
    
    $thisquery.="FS: $fs " if ($fs);
    $thisquery.="AUT: $verf " if ($verf);
    $thisquery.="HST: $hst " if ($hst);
    $thisquery.="SWT: $swt " if ($swt);
    $thisquery.="KOR: $kor " if ($kor);
    $thisquery.="NOT: $notation " if ($notation);
    $thisquery.="SIG: $sign " if ($sign);
    $thisquery.="EJAHR: $ejahr " if ($ejahr);
    $thisquery.="ISBN: $isbn " if ($isbn);
    $thisquery.="ISSN: $issn " if ($issn);
    $thisquery.="MART: $mart " if ($mart);
    $thisquery.="HSTR: $hststring " if ($hststring);
    $thisquery.="= Treffer: $hits" if ($hits);

    # Plus-Zeichen entfernen
    
    $verf=~s/%2B(\w+)/$1/g;
    $hst=~s/%2B(\w+)/$1/g;
    $kor=~s/%2B(\w+)/$1/g;
    $ejahr=~s/%2B(\w+)/$1/g;
    $isbn=~s/%2B(\w+)/$1/g;
    $issn=~s/%2B(\w+)/$1/g;

    $verf=~s/\+(\w+)/$1/g;
    $hst=~s/\+(\w+)/$1/g;
    $kor=~s/\+(\w+)/$1/g;
    $ejahr=~s/\+(\w+)/$1/g;
    $isbn=~s/\+(\w+)/$1/g;
    $issn=~s/\+(\w+)/$1/g;
    
  }
  else {
    OpenBib::Common::Util::print_warning("Keine g&uuml;ltige Anfrage-ID",$r);
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    
    return OK;
    
  }

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
		queryid      => $queryid,

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
		thisquery    => $thisquery,
		authurl      => $authurl,

		show_corporate_banner => 0,
		show_foot_banner      => 1,
		config       => \%config,
	       };
    
    # Dann Ausgabe des neuen Headers
    
    print $r->send_http_header("text/html");
    
    $template->process($config{tt_externaljump_tname}, $ttdata) || do { 
      $r->log_reason($template->error(), $r->filename);
      return SERVER_ERROR;
    };

  $sessiondbh->disconnect();
  $userdbh->disconnect();
  return OK;
}

1;
