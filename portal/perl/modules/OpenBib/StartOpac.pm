#####################################################################
#
#  OpenBib::StartOpac
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

package OpenBib::StartOpac;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common);
use Apache::Request ();
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util();
use OpenBib::Config();

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $fs=$query->param('fs') || '';

    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $database        = ($query->param('database'))?$query->param('database'):'';
    my $singleidn       = $query->param('singleidn') || '';
    my $action          = $query->param('action') || '';
    my $setmask         = $query->param('setmask') || '';
    my $searchsingletit = $query->param('searchsingletit') || '';
  
    my $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh);

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

    if ($setmask) {
        my $idnresult=$sessiondbh->prepare("insert into sessionmask values (?,?)") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID,$setmask) or $logger->error($DBI::errstr);
        $idnresult->finish();
    }
    # Standard ist 'einfache Suche'
    else {
        my $idnresult=$sessiondbh->prepare("insert into sessionmask values (?,'simple')") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
        $idnresult->finish();
    }
  
    # BEGIN View (Institutssicht)
    #
    ####################################################################
    # Wenn ein View aufgerufen wird, muss fuer die aktuelle Session
    # die Datenbankauswahl vorausgewaehlt und das Profil geaendert werden.
    ####################################################################
  
    if ($view ne "") {
        # 1. Gibt es diesen View?
        my $idnresult=$sessiondbh->prepare("select viewname from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($view) or $logger->error($DBI::errstr);
        my $anzahl=$idnresult->rows();
    
        if ($anzahl > 0) {
            # 2. Datenbankauswahl setzen, aber nur, wenn der Benutzer selbst noch
            #    keine Auswahl getroffen hat
      
            $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

            # Wenn noch keine Datenbank ausgewaehlt wurde, dann setze die
            # Auswahl auf die zum View gehoerenden Datenbanken
            my $anzahl=$idnresult->rows();
            if ($anzahl == 0) {
                $idnresult=$sessiondbh->prepare("select dbname from  viewdbs where viewname = ?") or $logger->error($DBI::errstr);
                $idnresult->execute($view) or $logger->error($DBI::errstr);
	
                while (my $result=$idnresult->fetchrow_hashref()) {
                    my $dbname=$result->{'dbname'};
                    my $idnresult2=$sessiondbh->prepare("insert into dbchoice (sessionid,dbname) values (?,?)") or $logger->error($DBI::errstr);
                    $idnresult2->execute($sessionID,$dbname) or $logger->error($DBI::errstr);
                    $idnresult2->finish();
                }
            }
            # 3. Assoziiere den View mit der Session (fuer Headframe/Merkliste);
            $idnresult=$sessiondbh->prepare("insert into sessionview values (?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$view) or $logger->error($DBI::errstr);
        }
        # Wenn es den View nicht gibt, dann wird gestartet wie ohne view
        else {
            $view="";
        }
        $idnresult->finish();
    }

    # Wenn effektiv kein valider View uebergeben wurde, dann wird
    # ein 'leerer' View mit der Session assoziiert.
    if ($view eq "") {
        my $idnresult=$sessiondbh->prepare("insert into sessionview values (?,?)") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID,$view) or $logger->error($DBI::errstr);
        $idnresult->finish();
    }
  
    my $headerframeurl = "$config{headerframe_loc}?sessionID=$sessionID";
    my $bodyframeurl   = "$config{searchframe_loc}?sessionID=$sessionID";

    if ($view ne "") {
        $headerframeurl.="&view=$view";
        $bodyframeurl.="&view=$view";
    }

    $logger->debug("StartOpac-sID: $sessionID");

    my $ttdata={
        headerframeurl  => $headerframeurl,
        bodyframeurl    => $bodyframeurl,
        view            => $view,
        sessionID       => $sessionID,
        fs              => $fs,
        searchsingletit => $searchsingletit,
        config          => \%config,
    };

    OpenBib::Common::Util::print_page($config{tt_startopac_tname},$ttdata,$r);

    $sessiondbh->disconnect();

    return OK;
}

1;
