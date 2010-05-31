#####################################################################
#
#  OpenBib::Handler::Apache::StartOpac
#
#  Dieses File ist (C) 2001-2009 Oliver Flimm <flimm@openbib.org>
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

use Apache2::Connection ();
use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest (); # internal_redirect
use APR::Table;

use DBI;
use Encode qw(decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use URI::Escape;

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

    my $session = OpenBib::Session->instance({ apreq => $r });
    
    my $query   = Apache2::Request->new($r);

    my $fs   = $query->param('fs')      || '';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $database        = ($query->param('db'))?$query->param('db'):'';
    my $singleidn       = $query->param('singleidn') || '';
    my $action          = $query->param('action') || '';
    my $setmask         = $query->param('setmask') || '';
    my $searchsingletit = $query->param('searchsingletit') || '';
    my $searchsingleaut = $query->param('searchsingleaut') || '';
    my $searchsinglekor = $query->param('searchsinglekor') || '';
    my $searchsingleswt = $query->param('searchsingleswt') || '';
    my $searchsinglenot = $query->param('searchsinglenot') || '';
    my $searchlitlist   = $query->param('searchlitlist')   || '';
  
    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT') || '';

    # Loggen des Brower-Types
    $session->log_event({
        type      => 101,
        content   => $useragent,
    });

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $r->connection->remote_ip($1);
    }
    
    # Loggen der Client-IP
    $session->log_event({
        type      => 102,
        content   => $r->connection->remote_ip,
    });
    
    if ($view) {
        # Loggen der View-Auswahl
        $session->log_event({
            type      => 100,
            content   => $view,
        });
    }
    else {
        $logger->error("No view given");
    }

    if ($setmask) {
        $session->set_mask($setmask);
    }
    # Standard ist 'einfache Suche'
    else {
        $session->set_mask('simple');
        $setmask="simple";
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
    my $redirecturl = "$config->{base_loc}/$view/$config->{handler}{searchmask_loc}{name}/$setmask";

    my $viewstartpage_ref = $config->get_startpage_of_view($view);

    $logger->debug(YAML::Dump($viewstartpage_ref));
    
    if ($viewstartpage_ref->{start_loc}){
        $redirecturl = "$config->{base_loc}/$view/$config->{$viewstartpage_ref->{start_loc}}";

        if ($viewstartpage_ref->{start_stid}){
            $redirecturl.="/$viewstartpage_ref->{start_stid}";
        }
    }
    
    if ($searchsingletit && $database ){
        $redirecturl = "$config->{base_loc}/$view/$config->{handler}{resource_loc}{name}/title/$database/$searchsingletit/html";
    }
    
    if ($searchsingleaut && $database ){
        $redirecturl = "$config->{base_loc}/$view/$config->{handler}{resource_loc}{name}/person/$database/$searchsingleaut/html";
    }

    if ($searchsinglekor && $database ){
        $redirecturl = "$config->{base_loc}/$view/$config->{handler}{resource_loc}{name}/corporatebody/$database/$searchsinglekor/html";
    }

    if ($searchsingleswt && $database ){
        $redirecturl = "$config->{base_loc}/$view/$config->{handler}{resource_loc}{name}/subject/$database/$searchsingleswt/html";
    }

    if ($searchsinglenot && $database ){
        $redirecturl = "$config->{base_loc}/$view/$config->{handler}{resource_loc}{name}/classification/$database/$searchsinglenot/html";
    }
    
    if ($fs){
        $redirecturl = "$config->{base_loc}/$view/$config->{handler}{virtualsearch_loc}{name}?fs=".uri_escape($fs).";num=50;srt=author;srto=up;profil=;st=3";
    }

    if ($searchlitlist){
        $redirecturl = "$config->{base_loc}/$view/$config->{handler}{litlists_loc}{name}?action=show;litlistid=$searchlitlist";
    }

    $logger->info("Redirecting to $redirecturl");
    
    $r->internal_redirect($redirecturl);

    return Apache2::Const::OK;
}

1;
