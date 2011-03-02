#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Login
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin::Login;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('form');
    $self->run_modes(
        'form'               => 'process_form',
        'authenticate'       => 'process_authentication',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub process_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $stid           = $self->param('stid')           || '';
    my $representation = $self->param('representation') || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    # Expliziter aufruf und default bei keiner Parameteruebergabe
    if ($r->method eq "GET" && ! scalar $r->args) {
    
        # TT-Data erzeugen
    
        my $ttdata={
            view       => $view,
            
            stylesheet => $stylesheet,
            config     => $config,     
            msg        => $msg,
        };

        my $templatename = ($stid && $stid ne "default")?"tt_admin_login_".$stid."_tname":"tt_admin_login_tname";

        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
    }
    
    return Apache2::Const::OK;
}


sub process_authentication {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $stid           = $self->param('stid')           || '';
    my $representation = $self->param('representation') || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};

    # Variables for this action
    my $passwd          = $query->param('passwd')          || '';
    my $username        = $query->param('username')        || '';
    
    # Sessionid erzeugen
    if ($username ne $adminuser) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben als Benutzer entweder keinen oder nicht den Admin-Benutzer eingegeben"),$r,$msg);
        return Apache2::Const::OK;
    }
    
    if ($passwd ne $adminpasswd) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben ein falsches Passwort eingegeben"),$r,$msg);
        return Apache2::Const::OK;
    }
    
    # Session ist nun authentifiziert und wird mit dem Admin 
    # assoziiert.
    $session->set_user($adminuser);
    
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        session    => $session,
        config     => $config,
        
        msg        => $msg,
    };
    
    my $templatename = ($stid && $stid ne "default")?"tt_admin_loggedin_".$stid."_tname":"tt_admin_loggedin_tname";
    
    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
    return Apache2::Const::OK;
}

1;
