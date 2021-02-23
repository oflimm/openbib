#####################################################################
#
#  OpenBib::Handler::PSGI::Logout
#
#  Dieses File ist (C) 2001-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Logout;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use CGI::Cookie;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;


use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    $logger->debug("Deleting Cookie with SessionID $session->{ID}");

    my $purge_private_userinfo = $query->param('purge_private_userinfo');
    
    my $cookie = CGI::Cookie->new($r,
                                      -name    => "sessionID",
                                      -value   => "",
                                      -path    => '/',
                                      -expires => 'now',
                                  );
    
    $self->header_add('Set-Cookie', $cookie);

    if ($user->{ID}) {
        # Authentifiziert-Status der Session loeschen
        $user->disconnect_session();
    
        # Zwischengespeicherte Benutzerinformationen ggf. loeschen
        $user->delete_private_info() if ($purge_private_userinfo);
    }

    $session->clear_data();
  
    # Dann loeschen der Session in der Datenbank

    if ($self->param('representation') eq "html"){
    
	# TT-Data erzeugen
	my $ttdata={
	};
	
	return $self->print_page($config->{tt_logout_tname},$ttdata);
    }
    else {
	# Bei einem stateless API Zugriff interessieren nur angemeldete Nutzer
	if ($user->{ID}) {
	    return $self->print_json({ success => 1 });
	}
	else {
	    return $self->print_json({ success => 0 });
	}
    }
}

1;
