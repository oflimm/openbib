####################################################################
#
#  OpenBib::Handler::Apache::Connector::QRCode.pm
#
#  Dieses File ist (C) 2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::QRCode;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();   # CGI-Handling (or require)
use Apache2::RequestIO (); # rflush, print
use Apache2::RequestRec ();
use Apache2::URI ();
use APR::URI ();
use URI;

use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;
use GD::Barcode::QRcode;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Enrichment;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $query  = Apache2::Request->new($r);

    my $text       = $query->param('text')      || '';

    binmode STDOUT;
    my $code = GD::Barcode::QRcode->new($text,
                                        {ECC => 'M', Version => 12, ModuleSize => 3}

                                    );
    $r->content_type("image/png");
    $r->print($code->plot->png);
                                  
    return Apache2::Const::OK;
}

1;
