
#####################################################################
#
#  OpenBib::MailPassword
#
#  Dieses File ist (C) 2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::MailPassword;

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use POSIX;
use Socket;

use Digest::MD5;
use DBI;

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

  my $action=($query->param('action'))?$query->param('action'):'none';
  my $code=($query->param('code'))?$query->param('code'):'1';
  my $targetid=($query->param('targetid'))?$query->param('targetid'):'none';
  my $loginname=($query->param('loginname'))?$query->param('loginname'):'';
  my $password=($query->param('password'))?$query->param('password'):'';
  my $sessionID=$query->param('sessionID');
  my $view=$query->param('view')||'';
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
    
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    
    return OK;
  }
  
  if ($action eq "show"){

    # TT-Data erzeugen

    my $ttdata={
		title      => 'KUG: Zusendung vergessener Passworte',
		stylesheet => $stylesheet,
		view       => '',

		sessionID  => $sessionID,
		loginname => $loginname,

		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };

    OpenBib::Common::Util::print_page($config{tt_mailpassword_tname},$ttdata,$r);
    
  }
  elsif ($action eq "sendpw"){
    my $loginfailed=0;
    
    if ($loginname eq ""){
      OpenBib::Common::Util::print_warning("Sie haben keine E-Mail Adresse eingegeben",$r);
      $sessiondbh->disconnect();
      $userdbh->disconnect();
      return OK;
    }
    
    my $targetresult=$userdbh->prepare("select pin from user where loginname = ?") or $logger->error($DBI::errstr);
    
    $targetresult->execute($loginname) or $logger->error($DBI::errstr);
    
    my $result=$targetresult->fetchrow_hashref();
    my $password=$result->{'pin'};
    $targetresult->finish();
    
    if (!$password){
      OpenBib::Common::Util::print_warning("Es existiert kein Passwort f&uuml;r die Kennung $loginname",$r);
      $sessiondbh->disconnect();
      $userdbh->disconnect();
      return OK;
    }
    
    open(MAIL,"| /usr/lib/sendmail -t -f$config{contact_email}");
    print MAIL << "MAILSEND";
From: $config{contact_email}
To: $loginname
Subject: Ihr vergessenes KUG-Passwort

Sehr geehrte(r) $loginname,

Sie haben sich ueber http://kug.ub.uni-koeln.de/ Ihr vergessenes
KUG-Passwort zusenden lassen.

Ihre gewuenschten Anmeldeinformationen lauten:

Benutzername : $loginname
Passwort     : $password

Mit freundlichen Gruessen

Ihr KUG-Team
MAILSEND

    my $ttdata={
		title      => 'Versendung des Passwortes erfolgreich',
		stylesheet => $stylesheet,
		view       => '',

		show_corporate_banner => 0,
		show_foot_banner => 1,
		config     => \%config,
	       };

    OpenBib::Common::Util::print_page($config{tt_mailpassword_success_tname},$ttdata,$r);
  
  }
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  return OK;
}

1;
