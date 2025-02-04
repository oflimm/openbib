#####################################################################
#
#  OpenBib::Mojo::Controller::Home
#
#  Dieses File ist (C) 2001-2014 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Home;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode qw(decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use URI::Escape;

use OpenBib::Common::Util();
use OpenBib::Config();
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show ($self) {

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

    # CGI Args
  
    $logger->debug("Home-sID: $session->{ID}");
    $logger->debug("Path-Prefix: ".$path_prefix);

    my $viewstartpage = $self->strip_suffix($config->get_startpage_of_view($view));

    $logger->debug("Alternative Interne Startseite: $viewstartpage");
    
    if ($viewstartpage){
        my $redirecturl = $viewstartpage.".".$self->param('representation')."?l=".$self->param('lang');

        $logger->info("Redirecting to $redirecturl");

        return $self->redirect($redirecturl);
    }
    else {
        # TT-Data erzeugen
        my $ttdata={
        };
        
        return $self->print_page($config->{'tt_home_tname'},$ttdata);
    }
}

1;
