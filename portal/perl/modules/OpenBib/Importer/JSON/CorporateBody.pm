#####################################################################
#
#  OpenBib::Importer::JSON::CorporateBody.pm
#
#  Koerperschaft
#
#  Dieses File ist (C) 2014-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Importer::JSON::CorporateBody;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8/;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use YAML ();
use Business::ISBN;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Container;
use OpenBib::Index::Document;

use base 'OpenBib::Importer::JSON';

sub set_defaults {
    my $self=shift;

    $self->{'field_prefix'}           = 'C';
    $self->{'indexed_authority'}      = 'indexed_corporatebody';
    $self->{'listitemdata_authority'} = 'listitemdata_corporatebody';
    $self->{'inverted_authority'}     = 'inverted_corporatebody';
    $self->{'blacklist_authority'}    = 'blacklist_corporatebody';

    return $self;
}

1;
