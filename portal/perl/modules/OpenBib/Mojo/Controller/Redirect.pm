#####################################################################
#
#  OpenBib::Mojo::Controller::Redirect
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

package OpenBib::Mojo::Controller::Redirect;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Encode qw(decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use URI::Escape qw(uri_unescape);
use URI::URL;
use YAML;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $servername     = $self->stash('servername');
    
    # CGI Args
    my $url  = uri_unescape($r->param('url'));
    my $type = $r->param('type');

    my $referer = $r->referer;

    my $referer_host = "";

    if ($referer){
	my $referer_url = new URI::URL($referer);
	$referer_host = $referer_url->host;
    }

    if ($referer_host ne $servername){
	$self->res->code(403); # 403 FORBIDDEN
        return;
    }
    
    $logger->debug("This Host: ".$self->stash('servername')." Referer Host: $referer_host");
    
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

        # TODO GET?
        $self->res->headers->content_type('text/html');
        $self->redirect($url);

        return;
    }
    else {
        $logger->error("Typ $type nicht definiert");
        return $self->print_warning($msg->maketext("Typ [_1] ist nicht definiert",$type));
    }    
}

1;
