#####################################################################
#
#  OpenBib::DatabaseChoice
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

package OpenBib::DatabaseChoice;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

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
  
  my $categories=[
	   {
	    full => 'Fakult&auml;tsungebunden',
	    short => '0ungeb',
	    nr => '0',
	   },
	   {
	    full => 'Wirtschafts- u. Sozialwissenschaftliche Fakult&auml;',
	    short => '1wiso',
	    nr   => '1',
	   },
	   {
	    full => 'Rechtswissenschaftliche Fakult&auml;t',
	    short => '2recht',
	    nr   => '2',
	   },
	   {
	    full => 'Erziehungswissenschaftliche u. Heilp&auml;dagogische Fakult&auml;t',
	    short => '3ezwheil',
	    nr => '3',
	   },
	   {
	    full => 'Philosophische Fakult&auml;t',
	    short => '4phil',
	    nr => '4',
	   },
	   {
	    full => 'Mathematisch-Naturwissenschaftliche Fakult&auml;t',
	    short => '5matnat',
	    nr => '5',
	   },
	   ];
  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or die "could not connect";
  
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
      
      $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid='$sessionID'");
      $idnresult->execute();
      
      # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
      my $database;
      foreach $database (@databases){
	$idnresult=$sessiondbh->prepare("insert into dbchoice (sessionid,dbname) values ('$sessionID','$database')");
	$idnresult->execute();
      }
      
      $idnresult->finish();
      
      $r->internal_redirect("http://$config{servername}$config{searchframe_loc}?sessionID=$sessionID&view=$view");
      
    }
    
    # ... sonst anzeigen
    else {
      $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid='$sessionID'");
      $idnresult->execute();
      while (my $result=$idnresult->fetchrow_hashref()){
	my $dbname=$result->{'dbname'};
	$checkeddb{$dbname}="checked=\"checked\"";
      }
      $idnresult->finish();

      my $lastcategory="";
      my $count=0;

      my $maxcolumn=$config{databasechoice_maxcolumn};
      
      my %stype;
	    
      $idnresult=$sessiondbh->prepare("select * from dbinfo where active=1 order by faculty ASC, description ASC");
      $idnresult->execute();

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
		  categories => $categories,
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
