#####################################################################
#
#  OpenBib::Leave
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

package OpenBib::Leave;

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

  
  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  my $sessionID=$query->param('sessionID');
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or die "could not connect";
  
  # Haben wir eine authentifizierte Session?
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  # Assoziierten View zur Session aus Datenbank holen
  
  my $idnresult=$sessiondbh->prepare("select viewname from sessionview where sessionid='$sessionID'");
  $idnresult->execute();
  
  my $result=$idnresult->fetchrow_hashref();

  $idnresult->finish();

  my $view=$result->{'viewname'} || '';
  
  if ($sessionID ne ""){
    
    # Authentifiziert-Status der Session loeschen
    
    if ($userid){
      
      my $userresult=$userdbh->prepare("delete from usersession where userid=$userid") or die "Error -- $DBI::errstr";
      $userresult->execute();
      $userresult->finish();
    }
    
    # Zuallererst loeschen der Trefferliste fuer diese sessionID
    
    my $idnresult=$sessiondbh->prepare("delete from treffer where sessionid='$sessionID'");
    $idnresult->execute();
    
    $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid='$sessionID'");
    $idnresult->execute();
    
    $idnresult=$sessiondbh->prepare("delete from searchresults where sessionid='$sessionID'");
    $idnresult->execute();
    
    $idnresult=$sessiondbh->prepare("delete from sessionview where sessionid='$sessionID'");
    $idnresult->execute();
    
    $idnresult->finish();
    
    # Kopieren ins sessionlog
    
    #  $idnresult=$sessiondbh->prepare("insert into sessionlog (sessionid,query,createtime) select session.sessionid,session.query,session.createtime from session where sessionid='$sessionID')");
    #  $idnresult->execute();
    
    #  my $endtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());
    
    #  $idnresult=$sessiondbh->prepare("insert into sessionlog (endtime) values ('$endtime')  where sessionid='$sessionID')");
    #  $idnresult->execute();
    
    #  $idnresult->finish();
    
    # Dann loeschen der Session in der Datenbank
    
    my $anzahlresult=$sessiondbh->prepare("delete from session where sessionid='$sessionID'");
    $anzahlresult->execute();
    $anzahlresult->finish();

    my $template = Template->new({ 
				INCLUDE_PATH  => $config{tt_include_path},
				#    	    PRE_PROCESS   => 'config',
				OUTPUT        => $r,     # Output geht direkt an Apache Request
			       });

    # TT-Data erzeugen

    my $ttdata={
		title      => 'KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
		stylesheet => $stylesheet,
		view       => $view,
		show_corporate_banner => 1,
		show_foot_banner => 0,
		config     => \%config,
	       };
    
    # Dann Ausgabe des neuen Headers
    
    print $r->send_http_header("text/html");
    
    $template->process($config{tt_leave_tname}, $ttdata) || do { 
      $r->log_reason($template->error(), $r->filename);
      return SERVER_ERROR;
    };

  }
  else {
    my $template = Template->new({ 
				  INCLUDE_PATH  => $config{tt_include_path},
				  #    	    PRE_PROCESS   => 'config',
				  OUTPUT        => $r,     # Output geht direkt an Apache Request
				 });
    
    # TT-Data erzeugen

    my $ttdata={
		title      => 'Fehler: KUG - K&ouml;lner Universit&auml;tsGesamtkatalog',
		stylesheet => $stylesheet,

		show_corporate_banner => 1,
		show_foot_banner => 0,
		invisible_links => 0,

		errmsg     => 'Session nicht korrekt',
		config     => \%config,
	       };
    
    # Dann Ausgabe des neuen Headers
    
    print $r->send_http_header("text/html");
    
    $template->process($config{tt_error_tname}, $ttdata) || do { 
      $r->log_reason($template->error(), $r->filename);
      return SERVER_ERROR;
    };

    
  }
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  return OK;
}

1;
