#####################################################################
#
#  OpenBib::Leave
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

package OpenBib::Leave;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = new OpenBib::Session({
        sessionID => $query->param('sessionID'),
    });

    my $user      = new OpenBib::User();
    
    my $stylesheet = OpenBib::Common::Util::get_css_by_browsertype($r);

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
  
    # Haben wir eine authentifizierte Session?
    my $userid=$user->get_userid_of_session($session->{ID});
  
    if ($userid) {
        # Authentifiziert-Status der Session loeschen
        my $userresult=$user->{dbh}->prepare("delete from usersession where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        # Zwischengespeicherte Benutzerinformationen loeschen
        $userresult=$user->{dbh}->prepare("update user set nachname = '', vorname = '', strasse = '', ort = '', plz = '', soll = '', gut = '', avanz = '', branz = '', bsanz = '', vmanz = '', maanz = '', vlanz = '', sperre = '', sperrdatum = '', gebdatum = '' where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        $userresult->finish();
    }

    $session->clear_data();
  
    # Dann loeschen der Session in der Datenbank
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        config     => $config,
        msg        => $msg,
    };
  
    OpenBib::Common::Util::print_page($config->{tt_leave_tname},$ttdata,$r);
  
    return OK;
}

1;
