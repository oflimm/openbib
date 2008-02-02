#####################################################################
#
#  OpenBib::Handler::Apache::DatabaseChoice
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

package OpenBib::Handler::Apache::DatabaseChoice;

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
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;

sub handler {
    my $r=shift;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe

    my @databases = ($query->param('database'))?$query->param('database'):();
    my $singleidn = $query->param('singleidn') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';
    my $do_choose = $query->param('do_choose') || '';
    my $verf      = $query->param('verf')      || '';
    my $hst       = $query->param('hst')       || '';
    my $swt       = $query->param('swt')       || '';
    my $kor       = $query->param('kor')       || '';
    my $sign      = $query->param('sign')      || '';
    my $isbn      = $query->param('isbn')      || '';
    my $issn      = $query->param('issn')      || '';
    my $notation  = $query->param('notation')  || '';
    my $ejahr     = $query->param('ejahr')     || '';
    my $queryid   = $query->param('queryid')   || '';
  
    my %checkeddb;
  
    my $queryoptions_ref
        = $session->get_queryoptions($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }
    
    my $idnresult="";
  
    # Wenn Kataloge ausgewaehlt wurden
    if ($do_choose) {
        # Zuerst die bestehende Auswahl loeschen
        $session->clear_dbchoice();
      
        # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
        foreach my $database (@databases) {
            $session->set_dbchoice($database);
        }

        # Neue Datenbankauswahl ist voreingestellt
        $session->set_profile('dbauswahl');
      
        $r->internal_redirect("http://$config->{servername}$config->{searchmask_loc}?sessionID=$session->{ID}&view=$view");
    }
    # ... sonst anzeigen
    else {

        # Ausgewaehlte Datenbanken bestimmen
        my $checkeddb_ref = {};
        foreach my $dbname ($session->get_dbchoice()){
            $checkeddb_ref->{$dbname}=1;
        }
        
        my $maxcolumn = $config->{databasechoice_maxcolumn};
        my @catdb     = $config->get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref});
        
        # TT-Data erzeugen
        my $colspan=$maxcolumn*3;

        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            maxcolumn  => $maxcolumn,
            colspan    => $colspan,
            catdb      => \@catdb,
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_databasechoice_tname},$ttdata,$r);
        return OK;
    }
    return OK;
}

1;
