#####################################################################
#
#  OpenBib::Circulation
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

package OpenBib::Circulation;

use Apache::Constants qw(:common);

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request();      # CGI-Handling (or require)

use Log::Log4perl qw(get_logger :levels);

use SOAP::Lite;

use POSIX;
use Socket;

use Digest::MD5;
use DBI;
use Email::Valid;                           # EMail-Adressen testen

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

  my $action=($query->param('action'))?$query->param('action'):'none';
  my $circaction=($query->param('circaction'))?$query->param('circaction'):'none';
  my $offset=($query->param('offset'))?$query->param('offset'):0;
  my $listlength=($query->param('listlength'))?$query->param('listlength'):10;
  my $sessionID=$query->param('sessionID')||'';
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
  my $userdbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd}) or $logger->error_die($DBI::errstr);
  
  unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){

    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);

    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
  }  
  
  my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
  unless($userid){

    OpenBib::Common::Util::print_warning("Diese Session ist nicht authentifiziert.",$r);

    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
  }
  
  my ($loginname,$password)=OpenBib::Common::Util::get_cred_for_userid($userdbh,$userid);

  my $database=OpenBib::Common::Util::get_targetdb_of_session($userdbh,$sessionID);

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

  if ($action eq "showcirc"){

    if ($circaction eq "reservations"){
      my $circexlist=undef;
      
      my $soap = SOAP::Lite
	-> uri("urn:/Circulation")
	  -> proxy($circcheckurl);
      my $result = $soap->get_reservations($loginname,$password,$circdb);
      
      unless ($result->fault) {
	$circexlist=$result->result;
      }
      else {
	$logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
      }
      
      # TT-Data erzeugen
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  loginname => $loginname,
		  password => $password,
		  
		  reservations => $circexlist,
		  
		  utf2iso => sub { 
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		    return $string;
		  },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_circulation_reserv_tname},$ttdata,$r);

    }
    elsif ($circaction eq "reminders"){
      my $circexlist=undef;
      
      my $soap = SOAP::Lite
	-> uri("urn:/Circulation")
	  -> proxy($circcheckurl);
      my $result = $soap->get_reminders($loginname,$password,$circdb);
      
      unless ($result->fault) {
	$circexlist=$result->result;
      }
      else {
	$logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
      }
      
      # TT-Data erzeugen
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  loginname => $loginname,
		  password => $password,
		  
		  reminders => $circexlist,
		  
		  utf2iso => sub { 
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		    return $string;
		  },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_circulation_remind_tname},$ttdata,$r);
    }
    elsif ($circaction eq "orders"){
      my $circexlist=undef;
      
      my $soap = SOAP::Lite
	-> uri("urn:/Circulation")
	  -> proxy($circcheckurl);
      my $result = $soap->get_orders($loginname,$password,$circdb);
      
      unless ($result->fault) {
	$circexlist=$result->result;
      }
      else {
	$logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
      }
      
      # TT-Data erzeugen
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  loginname => $loginname,
		  password => $password,
		  
		  orders => $circexlist,
		  
		  utf2iso => sub { 
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		    return $string;
		  },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_circulation_orders_tname},$ttdata,$r);
    }
    else {
      my $circexlist=undef;
      
      my $soap = SOAP::Lite
	-> uri("urn:/Circulation")
	  -> proxy($circcheckurl);
      my $result = $soap->get_borrows($loginname,$password,$circdb);
      
      unless ($result->fault) {
	$circexlist=$result->result;
      }
      else {
	$logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
      }
      
      # TT-Data erzeugen
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  
		  sessionID  => $sessionID,
		  loginname => $loginname,
		  password => $password,
		  
		  borrows => $circexlist,
		  
		  utf2iso => sub { 
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		    return $string;
		  },
		  
		  show_corporate_banner => 0,
		  show_foot_banner => 1,
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_circulation_tname},$ttdata,$r);
    }


  }
  else {

    OpenBib::Common::Util::print_warning("Unerlaubte Aktion",$r);
 
  }
  
  $sessiondbh->disconnect();
  $userdbh->disconnect();
  return OK;
}

1;
__END__

=head1 NAME

OpenBib::Circulation - Benutzerkonto

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
