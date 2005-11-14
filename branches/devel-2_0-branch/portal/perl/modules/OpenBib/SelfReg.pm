#####################################################################
#
#  OpenBib::SelfReg
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::SelfReg;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Request();          # CGI-Handling (or require)
use DBI;
use Email::Valid;               # EMail-Adressen testen
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;

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

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password1 = ($query->param('password1'))?$query->param('password1'):'';
    my $password2 = ($query->param('password2'))?$query->param('password2'):'';
    my $sessionID = $query->param('sessionID');
  
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd})
            or $logger->error_die($DBI::errstr);
  
    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning("Ungültige Session",$r);
        $sessiondbh->disconnect();
        $userdbh->disconnect();
        return OK;
    }
  
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }
  
    if ($action eq "show") {
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,

            show_corporate_banner => 0,
            show_foot_banner      => 1,
            config     => \%config,
        };
        OpenBib::Common::Util::print_page($config{tt_selfreg_tname},$ttdata,$r);
    }
    elsif ($action eq "auth") {
        if ($loginname eq "" || $password1 eq "" || $password2 eq "") {
            OpenBib::Common::Util::print_warning("Es wurde entweder kein Benutzername oder keine zwei Passworte eingegeben",$r);
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }

        if ($password1 ne $password2) {
            OpenBib::Common::Util::print_warning("Die beiden eingegebenen Passworte stimmen nicht überein.",$r);
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }

        # Ueberpruefen, ob es eine gueltige Mailadresse angegeben wurde.
        unless (Email::Valid->address($loginname)){
            OpenBib::Common::Util::print_warning("Sie haben keine gütige Mailadresse eingegeben. Gehen Sie bitte <a href=\"http://$config{servername}$config{selfreg_loc}?sessionID=$sessionID&action=show\">zurück</a> und korrigieren Sie Ihre Eingabe",$r);
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }

        my $userresult=$userdbh->prepare("select count(*) as rowcount from user where loginname = ?") or $logger->error($DBI::errstr);
        $userresult->execute($loginname) or $logger->error($DBI::errstr);
        my $res  = $userresult->fetchrow_hashref;
        my $rows = $res->{rowcount};

        if ($rows > 0) {
            OpenBib::Common::Util::print_warning("Ein Benutzer mit dem Namen $loginname existiert bereits. Haben Sie vielleicht Ihr Passwort vergessen? Dann gehen Sie bitte <a href=\"http://$config{servername}$config{login_loc}?sessionID=$sessionID?action=login\">zurück</a> und lassen es sich zumailen.",$r);
            $userresult->finish();

            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }

        # ab jetzt ist klar, dass es den Benutzer noch nicht gibt.
        # Jetzt eintragen und session mit dem Benutzer assoziieren;

        $userresult=$userdbh->prepare("insert into user values (NULL,'',?,?,'','','','',0,'','','','','','','','','','','',?,'')") or $logger->error($DBI::errstr);
        $userresult->execute($loginname,$password1,$loginname) or $logger->error($DBI::errstr);

        $userresult=$userdbh->prepare("select userid from user where loginname = ?") or $logger->error($DBI::errstr);
        $userresult->execute($loginname) or $logger->error($DBI::errstr);

        $res=$userresult->fetchrow_hashref();

        my $userid = decode_utf8($res->{'userid'});

        $userresult=$userdbh->prepare("select targetid from logintarget where type = 'self'") or $logger->error($DBI::errstr);
        $userresult->execute() or $logger->error($DBI::errstr);

        $res=$userresult->fetchrow_hashref();

        my $targetid = $res->{'targetid'};
    
        # Es darf keine Session assoziiert sein. Daher stumpf loeschen
        $userresult=$userdbh->prepare("delete from usersession where sessionid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($sessionID) or $logger->error($DBI::errstr);

        $userresult=$userdbh->prepare("insert into usersession values (?,?,?)") or $logger->error($DBI::errstr);
        $userresult->execute($sessionID,$userid,$targetid) or $logger->error($DBI::errstr);

        $userresult->finish();

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,

            loginname  => $loginname,
	      
            show_corporate_banner => 0,
            show_foot_banner      => 1,
            config     => \%config,
        };
        OpenBib::Common::Util::print_page($config{tt_selfreg_success_tname},$ttdata,$r);
    }
    else {
        OpenBib::Common::Util::print_warning("Unerlaubte Aktion",$r);
    }

    $sessiondbh->disconnect();
    $userdbh->disconnect();
  
    return OK;
}

1;
