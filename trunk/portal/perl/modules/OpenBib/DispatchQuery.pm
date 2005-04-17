#####################################################################
#
#  OpenBib::DispatchQuery
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

package OpenBib::DispatchQuery;

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
  
  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  my $action=($query->param('action'))?$query->param('action'):'';
  my $view=($query->param('view'))?$query->param('view'):'';
  my $queryid=$query->param('queryid') || '';

  if ($action eq "Als Suchvorlage"){
      $r->internal_redirect("http://$config{servername}$config{searchframe_loc}?sessionID=$sessionID&queryid=$queryid&view=$view");
      return OK;
  }
  elsif ($action eq "Zur Trefferliste"){
      $r->internal_redirect("http://$config{servername}$config{virtualsearch_loc}?sessionID=$sessionID&view=$view&trefferliste=choice&queryid=$queryid");
      return OK;
  }
  elsif ($action eq "Weiter als externe Recherche"){
      $r->internal_redirect("http://$config{servername}$config{externaljump_loc}?sessionID=$sessionID&view=$view&queryid=$queryid");
      return OK;
  }
  else {
    OpenBib::Common::Util::print_warning("Ung&uuml;ltige Aktion",$r);
    return OK;
  }
  
  return OK;
}

1;
