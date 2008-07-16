#####################################################################
#
#  OpenBib::Handler::Apache::StartOpac
#
#  Dieses File ist (C) 2001-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::StartOpac;

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
use OpenBib::QueryOptions;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $session = OpenBib::Session->instance;
    
    my $query   = Apache::Request->instance($r);

    my $status = $query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $fs   = decode_utf8($query->param('fs')) || $query->param('fs')      || '';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $database        = ($query->param('database'))?$query->param('database'):'';
    my $singleidn       = $query->param('singleidn') || '';
    my $action          = $query->param('action') || '';
    my $setmask         = $query->param('setmask') || '';
    my $searchsingletit = $query->param('searchsingletit') || '';
    my $searchlitlist   = $query->param('searchlitlist')   || '';
  
    my $view="";

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT') || '';

    # Loggen des Brower-Types
    $session->log_event({
        type      => 101,
        content   => $useragent,
    });

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    if ($r->header_in('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $r->connection->remote_ip($1);
    }
    
    # Loggen der Client-IP
    $session->log_event({
        type      => 102,
        content   => $r->connection->remote_ip,
    });
    
    if ($query->param('view')) {
        $view=$query->param('view');

        # Loggen der View-Auswahl
        $session->log_event({
            type      => 100,
            content   => $view,
        });

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
            # 3. Assoziiere den View mit der Session (fuer Merkliste);
            $session->set_view($view);
        }
        # Wenn es den View nicht gibt, dann wird gestartet wie ohne view
        else {
            $view="";
        }
    }

    # Wenn effektiv kein valider View uebergeben wurde, dann wird
    # ein 'leerer' View mit der Session assoziiert.

    my $start_loc  = "";
    my $start_stid = "";
    
    if ($view eq "") {
        $session->set_view($view);
    }

    $logger->debug("StartOpac-sID: $session->{ID}");

    # Standard-URL
    my $redirecturl = "$config->{searchmask_loc}?sessionID=$session->{ID};view=$view;setmask=$setmask";

    my $viewstartpage_ref = $config->get_startpage_of_view($view);

    $logger->debug(YAML::Dump($viewstartpage_ref));
    
    if ($viewstartpage_ref->{start_loc}){
        $redirecturl = "$config->{$viewstartpage_ref->{start_loc}}?sessionID=$session->{ID};view=$view";

        if ($viewstartpage_ref->{start_stid}){
            $redirecturl.=";stid=$viewstartpage_ref->{start_stid}";
        }
    }
    
    if ($searchsingletit && $database ){
        $redirecturl = "$config->{search_loc}?sessionID=$session->{ID};search=Mehrfachauswahl;database=$database;searchsingletit=$searchsingletit;view=$view";
    }

    if ($fs){
        $redirecturl = "$config->{virtualsearch_loc}?view=$view;sessionID=$session->{ID};fs=$fs;hitrange=50;sorttype=author;sortorder=up;profil=;autoplus=0;sb=xapian;st=3";
    }

    if ($searchlitlist){
        $redirecturl = "$config->{litlists_loc}?view=$view;sessionID=$session->{ID};action=show;litlistid=$searchlitlist";
    }

    if ($config->{drilldown}){
        $redirecturl .= ";drilldown=1";
    }

    if ($config->{drilldown_option}{cloud}){
        $redirecturl .= ";dd_cloud=1";
    }

    if ($config->{drilldown_option}{categorized}){
        $redirecturl .= ";dd_categorized=1";
    }

    $logger->info("Redirecting to $redirecturl");
    
    $r->internal_redirect($redirecturl);

    return OK;
}

1;
