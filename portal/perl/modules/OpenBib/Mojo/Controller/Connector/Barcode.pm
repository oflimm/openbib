####################################################################
#
#  OpenBib::Mojo::Controller::Connector::Barcode.pm
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Connector::Barcode;

use strict;
use warnings;
no warnings 'redefine';

use URI;

use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;
use GD::Barcode::Code39;
use URI::Escape;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Enrichment;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view       = $self->param('view');

    # Shared Args
    my $r          = $self->stash('r');

    # CGI Args
    my $text       = $query->stash('text')      || '';

    $text = uri_unescape($text) if ($text);

    $text=~s/#/\/C/g; 
    
    $logger->debug("Trying to print barcode for $text");
    
    binmode STDOUT;
    my $code =  GD::Barcode::Code39->new('*'.$text.'*');

    $self->header_add('Content-Type' => 'image/png');

    return unless ($code);
    
    return $code->plot( NoText => 1)->png;
}

1;
