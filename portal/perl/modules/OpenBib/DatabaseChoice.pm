#####################################################################
#
#  OpenBib::DatabaseChoice
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

package OpenBib::DatabaseChoice;

use Apache::Constants qw(:common);

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

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

  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  my @databases=($query->param('database'))?$query->param('database'):();
  my $singleidn=$query->param('singleidn') || '';
  my $view=$query->param('view') || '';
  my $action=($query->param('action'))?$query->param('action'):'';
  
  # CGI-Uebergabe
  
  my $verf=$query->param('verf') || '';
  my $hst=$query->param('hst') || '';
  my $swt=$query->param('swt') || '';
  my $kor=$query->param('kor') || '';
  my $sign=$query->param('sign') || '';
  my $isbn=$query->param('isbn') || '';
  my $issn=$query->param('issn') || '';
  my $notation=$query->param('notation') || '';
  my $ejahr=$query->param('ejahr') || '';
  my $bool1=$query->param('bool1') || '';
  my $bool2=$query->param('bool2') || '';
  my $bool3=$query->param('bool3') || '';
  my $bool4=$query->param('bool4') || '';
  my $bool5=$query->param('bool5') || '';
  my $bool6=$query->param('bool6') || '';
  my $bool7=$query->param('bool7') || '';
  my $queryid=$query->param('queryid') || '';
  
  my %checkeddb;
  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
      
    $sessiondbh->disconnect();
    $userdbh->disconnect();
      
    return OK;
  }
    
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);

  my $idnresult="";
  
  if ($sessionID ne ""){
    
    # Wenn Kataloge ausgewaehlt wurden
    if ($action eq "Kataloge auswählen"){
      
      # Zuerst die bestehende Auswahl loeschen
      
      $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      
      # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
      my $database;
      foreach $database (@databases){
	$idnresult=$sessiondbh->prepare("insert into dbchoice (sessionid,dbname) values (?,?)") or $logger->error($DBI::errstr);
	$idnresult->execute($sessionID,$database) or $logger->error($DBI::errstr);
      }

      # Neue Datenbankauswahl ist voreingestellt

      $idnresult=$sessiondbh->prepare("delete from sessionprofile where sessionid = ? ") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

      $idnresult=$sessiondbh->prepare("insert into sessionprofile values (?,'dbauswahl') ") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    
      $idnresult->finish();
      
      $r->internal_redirect("http://$config{servername}$config{searchframe_loc}?sessionID=$sessionID&view=$view");
      
    }
    
    # ... sonst anzeigen
    else {
      $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      while (my $result=$idnresult->fetchrow_hashref()){
	my $dbname=$result->{'dbname'};
	$checkeddb{$dbname}="checked=\"checked\"";
      }
      $idnresult->finish();

      my $lastcategory="";
      my $count=0;

      my $maxcolumn=$config{databasechoice_maxcolumn};
      
      my %stype;
	    
      $idnresult=$sessiondbh->prepare("select * from dbinfo where active=1 order by faculty ASC, description ASC") or $logger->error($DBI::errstr);
      $idnresult->execute() or $logger->error($DBI::errstr);

      my @catdb=();

      while (my $result=$idnresult->fetchrow_hashref){
	my $category=$result->{'faculty'};
	my $name=$result->{'description'};
	my $systemtype=$result->{'system'};
	my $pool=$result->{'dbname'};
	my $url=$result->{'url'};
	my $sigel=$result->{'sigel'};
	
	my $rcolumn;

	if ($systemtype eq "a"){
	  $stype{$pool}="yellow";
	}
	elsif ($systemtype eq "b"){
	  $stype{$pool}="red";
	}
	elsif ($systemtype eq "l"){
	  $stype{$pool}="green";
	}
	elsif ($systemtype eq "s"){
	  $stype{$pool}="blue";
	}

	if ($category ne $lastcategory){
	  while ($count % $maxcolumn != 0){

	    $rcolumn=($count % $maxcolumn)+1;
	    # 'Leereintrag erzeugen'
	    push @catdb, { 
			  column => $rcolumn, 
			  category => $lastcategory,
			  db => '',
			  name => '',
			  systemtype => '',
			  sigel => '',
			  url => '',
			 };
	    
	    $count++;
	  }

	  $count=0;
	}

	$lastcategory=$category;

	$rcolumn=($count % $maxcolumn)+1;

	my $checked="";
	if (defined $checkeddb{$pool}){
          $checked="checked=\"checked\"";
        }

	push @catdb, { 
		      column => $rcolumn,
		      category => $category,
		      db => $pool,
		      name => $name,
		      systemtype => $stype{$pool},
		      sigel => $sigel,
		      url => $url,
		      checked => $checked,
		     };


	$count++;
      }
      
      # TT-Data erzeugen

      my $colspan=$maxcolumn*3;

      my $ttdata={
		  title      => 'KUG: Katalogauswahl',
		  stylesheet => $stylesheet,
		  view       => $view,
		  sessionID  => $sessionID,
		  show_corporate_banner => 0,
		  show_foot_banner      => 1,
		  show_testsystem_info  => 0,
		  maxcolumn  => $maxcolumn,
		  colspan    => $colspan,
		  catdb      => \@catdb,
		  config     => \%config,
		 };
    
      OpenBib::Common::Util::print_page($config{tt_databasechoice_tname},$ttdata,$r);


      $idnresult->finish();
      $sessiondbh->disconnect();
      
    }
  }
  else {
    OpenBib::Common::Util::print_warning("Sie haben keine gueltige Session.",$r);
  }
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  
  return OK;
}

1;
