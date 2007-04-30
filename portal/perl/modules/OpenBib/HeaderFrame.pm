#####################################################################
#
#  OpenBib::HeaderFrame
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

package OpenBib::HeaderFrame;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
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

    my $session = new OpenBib::Session({
        sessionID => $query->param('sessionID'),
    });

    my $user    = new OpenBib::User();
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
    
    my $database  = $query->param('database')  || '';
    my $singleidn = $query->param('singleidn') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'HTML';

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

    my $primrssfeed="";

    if ($view){
        $primrssfeed=$config->get_primary_rssfeed_of_view($view);
    }
    
    # Haben wir eine authentifizierte Session?
    my $userid=$user->get_userid_of_session($session->{ID});
  
    # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    # Dementsprechend einen LoginLink oder ein ProfilLink ausgeben
    my $anzahl="";

    # Wenn wir authentifiziert sind, dann
    my $username="";
    if ($userid) {
        $username=$user->get_username_for_userid($userid);

        # Anzahl Eintraege der privaten Merkliste bestimmen
        # Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
        $anzahl =    $user->get_number_of_items_in_collection($userid);
    }
    else {
        #  Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
        $anzahl = $session->get_number_of_items_in_collection();
    }

    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }
    
    # TT-Data erzeugen
    my $ttdata={
        view              => $view,
        primrssfeed       => $primrssfeed,
        stylesheet        => $stylesheet,
        sessionID         => $session->{ID},
        username          => $username,
        anzahl            => $anzahl,
        config            => $config,
        msg               => $msg,
    };

    OpenBib::Common::Util::print_page($config->{tt_headerframe_tname},$ttdata,$r);

    return OK;
}

1;
