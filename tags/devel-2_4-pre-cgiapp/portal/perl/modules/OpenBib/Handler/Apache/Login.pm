#####################################################################
#
#  OpenBib::Handler::Apache::Login
#
#  Dieses File ist (C) 2004-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Login;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common REDIRECT);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest (); # internal_redirect
use DBI;
use Digest::MD5;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Socket;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Login::Util;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    # Standardwerte festlegen
    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $code      = ($query->param('code'))?$query->param('code'):'1';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $validtarget = ($query->param('validtarget'))?$query->param('validtarget'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password  = decode_utf8($query->param('password')) || $query->param('password') || '';

    # Main-Actions
    my $do_login       = $query->param('do_login')        || '';
    my $do_auth        = $query->param('do_auth' )        || '';
    my $do_loginfailed = $query->param('do_loginfailed')  || '';

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};

    my $return_url = $session->get_returnurl();

    # Wenn die Session schon authentifiziert ist, dann wird
    # wird in die Benutzereinstellungen gesprungen
    if ($user->{ID} && !$validtarget){

        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{userprefs_loc}{name}?action=showfields");

        return Apache2::Const::OK;
    }

    if ($do_login) {
        my $logintargets_ref = $user->get_logintargets();

        # TT-Data erzeugen
        my $ttdata={
            view         => $view,
            stylesheet   => $stylesheet,
            sessionID    => $session->{ID},
            logintargets => $logintargets_ref,
            validtarget  => $validtarget,
            loginname    => $loginname,
            return_url   => $return_url,
            config       => $config,
            user         => $user,
            msg          => $msg,
        };
    
        my $templatename = ($type)?"tt_login_".$type."_tname":"tt_login_tname";

        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
    }
    elsif ($do_auth) {
        my $loginfailed=0;
    
        if ($loginname eq "" || $password eq "") {
            $loginfailed=1;
        }

        my $logintarget_ref = $user->get_logintarget_by_id($targetid);
    
        my $hostname    = $logintarget_ref->{hostname};
        my $port        = $logintarget_ref->{port};
        my $username    = $logintarget_ref->{username};
        my $db          = $logintarget_ref->{dbname};
        my $description = $logintarget_ref->{description};
        my $type        = $logintarget_ref->{type};
  
        $logger->debug("Hostname: $hostname Port: $port Username: $username DB: $db Description: $description Type: $type");
        
        ## Ausleihkonfiguration fuer den Katalog einlesen
        my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;

        if ($type eq "olws") {
            $logger->debug("Trying to authenticate via OLWS: ".YAML::Dump($circinfotable));
            
            my $userinfo_ref=OpenBib::Login::Util::authenticate_olws_user({
                username      => $loginname,
                pin           => $password,
                circcheckurl  => $circinfotable->{$db}{circcheckurl},
                circdb        => $circinfotable->{$db}{circdb},
            });
        
            my %userinfo=%$userinfo_ref;

            $logger->debug("Authentication via OLWS done");
            
            if ($userinfo{'erfolgreich'} ne "1") {
                $loginfailed=2;
            }
      
            # Gegebenenfalls Benutzer lokal eintragen
            else {
                my $userid;

                # Eintragen, wenn noch nicht existent
                if (!$user->user_exists($loginname)) {
                    # Neuen Satz eintragen
                    $user->add({
                        loginname => $loginname,
                        password  => $password,
                    });
                }
                else {
                    # Satz aktualisieren
                    $user->set_credentials({
                        loginname => $loginname,
                        password  => $password,
                    });
                }

                # Benuzerinformationen eintragen
                $user->set_private_info($loginname,$userinfo_ref);
            }
        }
        elsif ($type eq "self") {
            my $result = $user->authenticate_self_user({
                username  => $loginname,
                pin       => $password,
            });
      
            if ($result <= 0) {
                $loginfailed=2;
            }
        }
        else {
            $loginfailed=2;
        }
    
        if (!$loginfailed) {
            # Jetzt wird die Session mit der Benutzerid assoziiert
            my $userid = $user->get_userid_for_username($loginname);

            $user->connect_session({
                sessionID => $session->{ID},
                userid    => $userid,
                targetid  => $targetid,
            });
      
            # Falls noch keins da ist, eintragen
            if (!$user->fieldchoice_exists($userid)) {
                $user->set_default_fieldchoice($userid);
            }
      
            if (!$user->spelling_suggestion_exists($userid)) {
                $user->set_default_spelling_suggestion($userid);
            }

            if (!$user->livesearch_exists($userid)) {
                $user->set_default_livesearch($userid);
            }

            # Jetzt wird die bestehende Trefferliste uebernommen.
            # Gehe ueber alle Eintraege der Trefferliste

            my $recordlist_existing_collection = $session->get_items_in_collection();

            $logger->debug("Items in Session: ".YAML::Dump($recordlist_existing_collection));
            
            foreach my $record (@{$recordlist_existing_collection->to_list}){
                $logger->debug("Adding item to personal collection of user $userid: ".YAML::Dump($record));

                $user->add_item_to_collection({
                    userid => $userid,
                    item   => {
                        dbname     => $record->{database},
                        singleidn  => $record->{id},
                    },
                });
            }
            
            # Bestimmen des Recherchemasken-Typs
            my $masktype = $user->get_mask($userid);

            $session->set_mask($masktype);
        }

        my $redirecturl
            = "http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{userprefs_loc}{name}?action=showfields";
        
        if ($view ne "") {
            $redirecturl.=";view=$view";
        }

        # Wenn Return_url existiert, dann wird im Body-Frame dorthin gesprungen
        if ($return_url){
            $redirecturl=$return_url;

            $session->set_returnurl('');
        }
        
        # Fehlerbehandlung
        if ($loginfailed) {
            $redirecturl="http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_loginfailed=1;code=$loginfailed";
        }

        $logger->debug("Redirecting to $redirecturl");

        $r->content_type('text/html');
        $r->headers_out->add("Location" => $redirecturl);

        return Apache2::Const::REDIRECT;
    }
    elsif ($do_loginfailed) {
        if    ($code eq "1") {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder kein Passwort oder keinen Loginnamen eingegeben"),$r,$msg);
        }
        elsif ($code eq "2") {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie konnten mit Ihrem angegebenen Benutzernamen und Passwort nicht erfolgreich authentifiziert werden"),$r,$msg);
        }
        else {
            OpenBib::Common::Util::print_warning($msg->maketext("Falscher Fehler-Code"),$r,$msg);
        }
    }
    return Apache2::Const::OK;
}

1;
