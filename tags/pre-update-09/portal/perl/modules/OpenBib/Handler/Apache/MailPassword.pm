
#####################################################################
#
#  OpenBib::Handler::Apache::MailPassword
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

package OpenBib::Handler::Apache::MailPassword;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Lite;
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $code      = ($query->param('code'))?$query->param('code'):'1';
    my $targetid  = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password  = ($query->param('password'))?$query->param('password'):'';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    if ($action eq "show") {

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

        OpenBib::Common::Util::print_page($config->{tt_mailpassword_tname},$ttdata,$r);
    }
    elsif ($action eq "sendpw") {
        my $loginfailed=0;
    
        if ($loginname eq "") {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keine E-Mail Adresse eingegeben"),$r,$msg);
            return Apache2::Const::OK;
        }

        my ($dummy,$password)=$user->get_credentials({userid => $user->get_userid_for_username($loginname)});
    
        if (!$password) {
            OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Passwort für die Kennung $loginname"),$r,$msg);
            return Apache2::Const::OK;
        }

	my $anschreiben="";
	my $afile = "an." . $$;

	my $mainttdata = {
                          loginname => $loginname,
                          password  => $password,
                          user      => $user,
			  msg       => $msg,
			 };

	my $maintemplate = Template->new({
          LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
              INCLUDE_PATH   => $config->{tt_include_path},
              ABSOLUTE       => 1,
          }) ],
#         ABSOLUTE      => 1,
#         INCLUDE_PATH  => $config->{tt_include_path},
          # Es ist wesentlich, dass OUTPUT* hier und nicht im
          # Template::Provider definiert wird
          RECURSION      => 1,
          OUTPUT_PATH   => '/tmp',
          OUTPUT        => $afile,
        });

        $maintemplate->process($config->{tt_mailpassword_mail_main_tname}, $mainttdata ) || do {
            $r->log_error($maintemplate->error(), $r->filename);
            return Apache2::Const::SERVER_ERROR;
        };

        my $mailmsg = MIME::Lite->new(
            From            => $config->{contact_email},
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

        $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config->{contact_email}");
    

        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,

            config     => $config,
            user       => $user,
            msg        => $msg,
        };

        OpenBib::Common::Util::print_page($config->{tt_mailpassword_success_tname},$ttdata,$r);
    }

    return Apache2::Const::OK;
}

1;
