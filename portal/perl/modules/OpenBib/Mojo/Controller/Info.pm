#####################################################################
#
#  OpenBib::Mojo::Controller::Info
#
#  Dieses File ist (C) 2006-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Info;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;
use OpenBib::Template::Utilities;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $stid           = $self->strip_suffix($self->param('stid'))           || '';
    
    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');    
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');    
    
    # CGI Args
    my $format         = $r->param('format')         || '';
    my $id             = $r->param('id')             || '';
    
    my $statistics  = new OpenBib::Statistics();
    my $utils       = new OpenBib::Template::Utilities;
    my $convconfig  = new OpenBib::Conv::Config;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    
    # TT-Data erzeugen
    my $ttdata={
        format        => $format,
        stid          => $stid,
        id            => $id,
        viewdesc      => $viewdesc,
        statistics    => $statistics,
        utils         => $utils,
        convconfig    => $convconfig,
    };

    my $templatename = ($stid && $stid ne "default")?"tt_info_".$stid."_tname":"tt_info_tname";

    $logger->debug("Template name: $templatename");
    
    return $self->print_page($config->{$templatename},$ttdata);
}

1;
