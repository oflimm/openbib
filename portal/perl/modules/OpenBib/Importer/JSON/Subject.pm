#####################################################################
#
#  OpenBib::Importer::JSON::Subject.pm
#
#  Schlagworte
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

package OpenBib::Importer::JSON::Subject;

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

sub process_mainentry {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id         = exists $arg_ref->{id}
        ? $arg_ref->{id}              : undef;

    my $mainentry  = exists $arg_ref->{mainentry}
        ? $arg_ref->{mainentry}       : undef;

    my $fields_ref = exists $arg_ref->{fields}
        ? $arg_ref->{fields}          : {};
        
    if (defined $fields_ref->{'0800'}[1]) {
        # Schlagwortketten zusammensetzen
        my @mainentries = ();
        foreach my $item (map { $_->[0] }
                              sort { $a->[1] <=> $b->[1] }
                                  map { [$_, $_->{mult}] } @{$fields_ref->{'0800'}}) {
            push @mainentries, $item->{content};
            $mainentry = join (' / ',@mainentries);
        }
        
        $fields_ref->{'0800'} = [
            {
                content  => $mainentry,
                mult     => 1,
                subfield => '',
            }
        ];
    }
    
    $self->{storage}{$self->{'listitemdata_authority'}}{$id}=$mainentry;
}

sub set_defaults {
    my $self=shift;

    $self->{'field_prefix'}           = 'S';
    $self->{'indexed_authority'}      = 'indexed_subject';
    $self->{'listitemdata_authority'} = 'listitemdata_subject';
    $self->{'inverted_authority'}     = 'inverted_subject';
    $self->{'blacklist_authority'}    = 'blacklist_subject';

    return $self;
}

1;
