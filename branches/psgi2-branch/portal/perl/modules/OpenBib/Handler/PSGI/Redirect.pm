#####################################################################
#
#  OpenBib::Handler::Apache::Redirect
#
#  Dieses File ist (C) 2007-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Redirect;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common REDIRECT);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::URI ();
use APR::URI ();

use Encode qw(decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use URI::Escape qw(uri_unescape);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;

use base 'OpenBib::Handler::Apache';

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
    my $view           = $self->param('view');

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
    my $url  = uri_unescape($query->param('url'));
    my $type = $query->param('type');

    $logger->debug("SessionID: $session->{ID} - Type: $type - URL: $url");

    my $valid_redirection_type_ref = {
        500 => 1, # TOC / hbz-Server
        501 => 1, # TOC / ImageWaere-Server
	502 => 1, # USB ebook Vollzugriff
	503 => 1, # Nationallizenzen Vollzugriff
        504 => 1, # Gutenberg Vollzugriff
        505 => 1, # OpenLibrary Vollzugriff
        510 => 1, # BibSonomy Einzeltreffer hochladen
        511 => 1, # BibSonomy Sprung zum Titel in BibSonomy
        520 => 1, # Wikipedia / Personen
        521 => 1, # Wikipedia / ISBN
        522 => 1, # Wikipedia / Artikel
        525 => 1, # Google Books
        526 => 1, # Cover-Scan
        530 => 1, # EZB
        531 => 1, # DBIS
        532 => 1, # Kartenkatalog Philfak
        533 => 1, # MedPilot
        534 => 1, # Digitaler Kartenkatalog der Philfak
        540 => 1, # HBZ-Monofernleihe
        541 => 1, # HBZ-Dokumentenlieferung
        550 => 1, # WebOPAC
        560 => 1, # DFG-Viewer
    };

    if (exists $valid_redirection_type_ref->{$type}){
        $session->log_event({
            type      => $type,
            content   => $url,
        });

        $self->query->method('GET');
        $self->query->content_type('text/html');
        $self->query->headers_out->add(Location => $url);
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $self->print_warning($msg->maketext("Typ [_1] ist nicht definiert",$type));
        $logger->error("Typ $type nicht definiert");
        return Apache2::Const::OK;
    }
}

1;
