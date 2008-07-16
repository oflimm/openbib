#####################################################################
#
#  OpenBib::Handler::Apache::SelfReg
#
#  Dieses File ist (C) 2004-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::SelfReg;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request();          # CGI-Handling (or require)
use DBI;
use Email::Valid;               # EMail-Adressen testen
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;

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
    
    my $query  = Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password1 = ($query->param('password1'))?$query->param('password1'):'';
    my $password2 = ($query->param('password2'))?$query->param('password2'):'';

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
  
    if ($action eq "show") {
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_selfreg_tname},$ttdata,$r);
    }
    elsif ($action eq "auth") {
        if ($loginname eq "" || $password1 eq "" || $password2 eq "") {
            OpenBib::Common::Util::print_warning($msg->maketext("Es wurde entweder kein Benutzername oder keine zwei Passworte eingegeben"),$r,$msg);
            return OK;
        }

        if ($password1 ne $password2) {
            OpenBib::Common::Util::print_warning($msg->maketext("Die beiden eingegebenen Passworte stimmen nicht überein."),$r,$msg);
            return OK;
        }

        # Ueberpruefen, ob es eine gueltige Mailadresse angegeben wurde.
        unless (Email::Valid->address($loginname)){
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keine gütige Mailadresse eingegeben. Gehen Sie bitte [_1]zurück[_2] und korrigieren Sie Ihre Eingabe","<a href=\"http://$config->{servername}$config->{selfreg_loc}?sessionID=$session->{ID}&action=show\">","</a>"),$r,$msg);
            return OK;
        }

        if ($user->user_exists($loginname)) {
            OpenBib::Common::Util::print_warning($msg->maketext("Ein Benutzer mit dem Namen [_1] existiert bereits. Haben Sie vielleicht Ihr Passwort vergessen? Dann gehen Sie bitte [_2]zurück[_3] und lassen es sich zumailen.","$loginname","<a href=\"http://$config->{servername}$config->{selfreg_loc}?sessionID=$session->{ID};view=$view;action=show\">","</a>"),$r,$msg);
            return OK;
        }

        # ab jetzt ist klar, dass es den Benutzer noch nicht gibt.
        # Jetzt eintragen und session mit dem Benutzer assoziieren;

        $user->add({
            loginname => $loginname,
            password  => $password1,
            email     => $loginname,
        });

        my $userid   = $user->get_userid_for_username($loginname);
        my $targetid = $user->get_id_of_selfreg_logintarget();

        $user->connect_session({
            sessionID => $session->{ID},
            userid    => $userid,
            targetid  => $targetid,
        });

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            loginname  => $loginname,
	      
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_selfreg_success_tname},$ttdata,$r);
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Unerlaubte Aktion"),$r,$msg);
    }
    return OK;
}

1;
