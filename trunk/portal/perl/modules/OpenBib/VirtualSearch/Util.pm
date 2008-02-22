#####################################################################
#
#  OpenBib::VirtualSearch::Util
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::VirtualSearch::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

sub conv2autoplus {
    my ($eingabe)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Original: $eingabe");

    my @phrasenbuf=();

    chomp($eingabe);

    # Token fuer Phrasensuche aussondern
    while ($eingabe=~/(".*?")/) {
        my $phrase=$1;

        # Merken
        push @phrasenbuf, $phrase;

        # Entfernen
        $eingabe=~s/$phrase//;
    }

    # Innenliegende - durch Leerzeichen ersetzen
    $eingabe=~s/(\w)-(\w)/$1 $2/gi;
    #  $eingabe=~s/\+(\w)/ $1/gi;
    $eingabe=~s/\+(\S)/ $1/gi;

    # Generell Plus vor Woertern durch Leerzeichen ersetzen
    #  $eingabe=~s/(\S+)/%2B$1/gi;
    $eingabe=~s/(\S+)/%2B$1/gi;

    # Kombination -+ wird nun eliminiert
    $eingabe=~s/-%2B/-/gi;

    # URL-Code fuer + in richtiges Plus umwandeln
    $eingabe=~s/%2B/+/g;

    push @phrasenbuf, $eingabe;

    # Gemerkte Phrase werden wieder hinzugefuegt
    if ($#phrasenbuf >= 0) {
        $eingabe=join(" ",@phrasenbuf);
    }

    $logger->debug("Gewandelt: $eingabe");

    return $eingabe;
}

sub cleansearchterm {
    my ($term)=@_;

    $term=~s/\'/ /g;

    return $term;
}

sub externalsearchterm {
    my ($term)=@_;

    $term=~s/%2B(\w+)/$1/g;

    return $term;
}

1;
