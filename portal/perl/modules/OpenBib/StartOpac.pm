#####################################################################
#
#  OpenBib::StartOpac
#
#  Dieses File ist (C) 2001-2006 Oliver Flimm <flimm@openbib.org>
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
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util();
use OpenBib::Config();
use OpenBib::L10N;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();

    my $session = new OpenBib::Session();
    
    my $query  = Apache::Request->new($r);

    my $status = $query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $fs   = $query->param('fs') || '';

    my $queryoptions_ref
        = $session->get_queryoptions($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $database        = ($query->param('database'))?$query->param('database'):'';
    my $singleidn       = $query->param('singleidn') || '';
    my $action          = $query->param('action') || '';
    my $setmask         = $query->param('setmask') || '';
    my $searchsingletit = $query->param('searchsingletit') || '';
  
    my $sessionID       = $session->{ID};
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    if ($setmask) {
        $session->set_mask($setmask);
    }
    # Standard ist 'einfache Suche'
    else {
        $session->set_mask('simple');
    }
  
    # BEGIN View (Institutssicht)
    #
    ####################################################################
    # Wenn ein View aufgerufen wird, muss fuer die aktuelle Session
    # die Datenbankauswahl vorausgewaehlt und das Profil geaendert werden.
    ####################################################################
  
    if ($view ne "") {
        # 1. Gibt es diesen View?
        if ($config->view_exists($view)) {
            # 2. Datenbankauswahl setzen, aber nur, wenn der Benutzer selbst noch
            #    keine Auswahl getroffen hat
      

            # Wenn noch keine Datenbank ausgewaehlt wurde, dann setze die
            # Auswahl auf die zum View gehoerenden Datenbanken
            if ($session->get_number_of_dbchoice == 0) {
                my @viewdbs=$config->get_dbs_of_view($view);

                foreach my $dbname (@viewdbs){
                    $session->set_dbchoice($dbname);
                }
            }
            # 3. Assoziiere den View mit der Session (fuer Headframe/Merkliste);
            $session->set_view($view);
        }
        # Wenn es den View nicht gibt, dann wird gestartet wie ohne view
        else {
            $view="";
        }
    }

    # Wenn effektiv kein valider View uebergeben wurde, dann wird
    # ein 'leerer' View mit der Session assoziiert.
    if ($view eq "") {
        $session->set_view($view);
    }
  
    $logger->debug("StartOpac-sID: $sessionID");

    my $ttdata={
        view            => $view,
        sessionID       => $session->{ID},
        setmask         => $setmask,
        fs              => $fs,
        database        => $database,
        searchsingletit => $searchsingletit,
        config          => $config,
        msg             => $msg,
    };

    OpenBib::Common::Util::print_page($config->{tt_startopac_tname},$ttdata,$r);

    return OK;
}

1;
