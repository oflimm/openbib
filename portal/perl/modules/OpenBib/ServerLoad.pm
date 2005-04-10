#####################################################################
#
#  OpenBib::ServerLoad
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

package OpenBib::ServerLoad;

use Apache::Constants qw(:common);

use Log::Log4perl qw(get_logger :levels);

use strict;
use warnings;

use DBI;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
  my $r=shift;

  # Log4perl logger erzeugen

  my $logger = get_logger();

  my $sessiondbstatus="offline";

  #####################################################################
  # Test-Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) and $sessiondbstatus="online";

  if ($sessiondbstatus eq "online"){
    $sessiondbh->disconnect();
  }

  print $r->send_http_header("text/plain");

  print "SessionDB: $sessiondbstatus\n";

  open(LOADAVG,"/proc/loadavg") or $logger->error_die($DBI::errstr);

  print "Load: ".<LOADAVG>;
  
  close(LOADAVG);

  return OK;
}

1;
