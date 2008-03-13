####################################################################
#
#  OpenBib::Handler::Apache::DatabaseProfile
#
#  Dieses File ist (C) 2005-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::DatabaseProfile;

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
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query=Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe
    my @databases  = ($query->param('database'))?$query->param('database'):();

    # Main-Actions
    my $do_showprofile = $query->param('do_showprofile') || '';
    my $do_saveprofile = $query->param('do_saveprofile') || '';
    my $do_delprofile  = $query->param('do_delprofile' ) || '';

    my $newprofile = $query->param('newprofile') || '';
    my $profilid   = $query->param('profilid')   || '';

    my $checkeddb_ref;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
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

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return OK;
    }

    my $idnresult="";

    #####################################################################   
    # Anzeigen der Profilmanagement-Seite
    #####################################################################   

    if ($do_showprofile) {
        my $profilname="";
    
        if ($profilid) {
            # Zuerst Profil-Description zur ID holen
            $profilname = $user->get_profilename_of_profileid($profilid);

            foreach my $dbname ($user->get_profiledbs_of_profileid($profilid)){
                $checkeddb_ref->{$dbname}=1;
            }
        }
    
        my @userdbprofiles = $user->get_all_profiles;
        my $targettype     = $user->get_targettype_of_session($session->{ID});

        my $maxcolumn      = $config->{databasechoice_maxcolumn};
        my @catdb          = $config->get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref});

        # TT-Data erzeugen
        my $colspan=$maxcolumn*3;
    
        my $ttdata={
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},
            targettype     => $targettype,
            profilname     => $profilname,
            userdbprofiles => \@userdbprofiles,
            maxcolumn      => $maxcolumn,
            colspan        => $colspan,
            catdb          => \@catdb,
            config         => $config,
            user           => $user,
            msg            => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_databaseprofile_tname},$ttdata,$r);
        return OK;
    }

    #####################################################################   
    # Abspeichern eines Profils
    #####################################################################   

    elsif ($do_saveprofile) {
    
        # Wurde ueberhaupt ein Profilname eingegeben?
        if (!$newprofile) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keinen Profilnamen eingegeben!"),$r,$msg);
            return OK;
        }

        my $profilid = $user->dbprofile_exists($newprofile);

        # Wenn noch keine Profilid (=kein Profil diesen Namens)
        # existiert, dann wird eins erzeugt.
        unless ($profilid) {
            $profilid = $user->new_dbprofile($newprofile);
        }
    
        # Jetzt habe ich eine profilid und kann Eintragen
        # Auswahl wird immer durch aktuelle ueberschrieben.
        # Daher erst potentiell loeschen
        $user->delete_profiledbs($profilid);
    
        foreach my $database (@databases) {
            # ... und dann eintragen
            $user->add_profiledb($profilid,$database);
        }
        $r->internal_redirect("http://$config->{servername}$config->{databaseprofile_loc}?sessionID=$session->{ID}&do_showprofile=1");
    }
    # Loeschen eines Profils
    elsif ($do_delprofile) {
        $user->delete_dbprofile($profilid);
        $user->delete_profiledbs($profilid);

        $r->internal_redirect("http://$config->{servername}$config->{databaseprofile_loc}?sessionID=$session->{ID}&do_showprofile=1");
    }
    # ... andere Aktionen sind nicht erlaubt
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion"),$r,$msg);
    }
    return OK;
}

1;
