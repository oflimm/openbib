#####################################################################
#
#  OpenBib::Template::Utilities
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Template::Utilities;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use OpenBib::Common::Util;

sub new {
    my $class = shift;

    my $self = {};

    bless ($self, $class);

    return $self;
}

sub normalize_drilldown {
    my ($self, $content) = @_;

    # Kategorie in Feld einfuegen            
    $content = OpenBib::Common::Util::grundform({
        content   => $content,
        searchreq => 1,
    });
        
    $content=~s/\W/_/g;
    
    return $content;
}

1;
