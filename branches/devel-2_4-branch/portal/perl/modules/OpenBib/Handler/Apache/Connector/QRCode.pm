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
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');

    # CGI Args
    my $text       = $query->param('text')      || '';
    my $size       = $query->param('size')      || 365; # maximale Pixelzahl pro Dimension
    
    my $lt         = length($text); # Binary corresp. http://www.denso-wave.com/qrcode/vertable1-e.html

    my $version    = 22;
    my $modulesize = int($size/(105+4)); # inklusive Rahmen von 4 Modules

    if    ($lt <  26){
        $version   = 2;
        $modulesize = int($size/(25+4));
    }
    elsif ($lt <  42){
        $version   = 3;
        $modulesize = int($size/(29+4));
    }
    elsif ($lt <  62){
        $version   = 4;
        $modulesize = int($size/(33+4));
    }
    elsif ($lt <  106){
        $version   = 6;
        $modulesize = int($size/(41+4));
    }
    elsif ($lt <  152){
        $version   = 8;
        $modulesize = int($size/(49+4));
    }
    elsif ($lt <  213){
        $version   = 10;
        $modulesize = int($size/(57+4));
    }
    elsif ($lt <  287){
        $version    = 12;
        $modulesize = int($size/(65+4));
    }

    $logger->debug("Using Version $version with ModuleSize $modulesize for Text with length $lt");
    
    binmode STDOUT;
    my $code = GD::Barcode::QRcode->new($text,
                                        {ECC => 'M', Version => $version, ModuleSize => $modulesize}

                                    );
    $r->content_type("image/png");
    $r->print($code->plot->png);

    return Apache2::Const::OK;
}

1;
