
#####################################################################
#
#  OpenBib::MailPassword
#
#  Dieses File ist (C) 2004-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::MailPassword;

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
use MIME::Lite;
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;

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
    my $code      = ($query->param('code'))?$query->param('code'):'1';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password  = ($query->param('password'))?$query->param('password'):'';
    my $sessionID = $query->param('sessionID')||'';
  
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
    
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
            loginname  => $loginname,

            config     => \%config,
            msg        => $msg,
        };

        OpenBib::Common::Util::print_page($config{tt_mailpassword_tname},$ttdata,$r);
    }
    elsif ($action eq "sendpw") {
        my $loginfailed=0;
    
        if ($loginname eq "") {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keine E-Mail Adresse eingegeben"),$r,$msg);
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }
    
        my $targetresult=$userdbh->prepare("select pin from user where loginname = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($loginname) or $logger->error($DBI::errstr);
    
        my $result=$targetresult->fetchrow_hashref();
        my $password = decode_utf8($result->{'pin'});
        $targetresult->finish();
    
        if (!$password) {
            OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Passwort für die Kennung $loginname"),$r,$msg);
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }

	my $anschreiben="";
	my $afile = "an." . $$;

	my $mainttdata = {
                          loginname => $loginname,
                          password  => $password,
			  msg       => $msg,
			 };

	my $maintemplate = Template->new({
          LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
              INCLUDE_PATH   => $config{tt_include_path},
              ABSOLUTE       => 1,
          }) ],
#         ABSOLUTE      => 1,
#         INCLUDE_PATH  => $config{tt_include_path},
          # Es ist wesentlich, dass OUTPUT* hier und nicht im
          # Template::Provider definiert wird
          OUTPUT_PATH   => '/tmp',
          OUTPUT        => $afile,
        });

        $maintemplate->process($config{tt_mailpassword_mail_main_tname}, $mainttdata ) || do {
            $r->log_reason($maintemplate->error(), $r->filename);
            return SERVER_ERROR;
        };

        my $mailmsg = MIME::Lite->new(
            From            => $config{contact_email},
            To              => $loginname,
            Subject         => $msg->maketext("Ihr vergessenes KUG-Passwort"),
            Type            => 'multipart/mixed'
        );

        my $anschfile="/tmp/" . $afile;

        $mailmsg->attach(
            Type            => 'TEXT',
            Encoding        => '8bit',
            #Data            => $anschreiben,
            Path            => $anschfile,
        );

        $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config{contact_email}");
    

        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,

            config     => \%config,
            msg        => $msg,
        };

        OpenBib::Common::Util::print_page($config{tt_mailpassword_success_tname},$ttdata,$r);
    }

    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
}

1;
