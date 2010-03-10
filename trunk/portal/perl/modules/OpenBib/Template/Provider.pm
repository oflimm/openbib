#####################################################################
#
#  OpenBib::Template::Provider
#
#  Dieses File ist (C) 2003 Ilya Martynov  <ilya@iponweb.net>
#                      2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Template::Provider;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Reload;
use Encode qw(decode_utf8);

use base qw(Template::Provider);

sub _load {
    my $self = shift;

    my ($data, $error) = $self->SUPER::_load(@_);

    if(defined $data) {
        $data->{text} = conv2utf8($data->{text});
    }

    return ($data, $error);
}

sub conv2utf8 {
#    my @list = map pack('U*', unpack 'U0U*', $_), @_;
    my @list = map decode_utf8($_), @_;
    return wantarray ? @list : $list[0];
}

1;
