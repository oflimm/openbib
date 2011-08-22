#####################################################################
#
#  OpenBib::Handler::Apache::StartOpac
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

package OpenBib::Handler::Apache::StartOpac;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Connection ();
use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest (); # internal_redirect
use APR::Table;

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
  
    # Standard ist 'einfache Suche'
    my $setmask="simple";
    
    $session->set_mask($setmask);
  
    $logger->debug("StartOpac-sID: $session->{ID}");
    $logger->debug("Path-Prefix: ".$path_prefix);

    # Standard-URL
    my $redirecturl = "$config->{base_loc}/$view/$config->{searchform_loc}/$setmask.html?l=".$self->param('lang');

    my $viewstartpage = $self->strip_suffix($config->get_startpage_of_view($view));

    $logger->debug("Alternative Interne Startseite: $viewstartpage");
    
    if ($viewstartpage){
        $redirecturl = $viewstartpage.".".$self->param('representation')."?l=".$self->param('lang');
    }
    
    $logger->info("Redirecting to $redirecturl");
    
    $r->internal_redirect($redirecturl);

    return Apache2::Const::OK;
}

1;
