#####################################################################
#
#  OpenBib::Common::Stopwords
#
#  Dieses File ist (C) 2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Common::Stopwords;

use Apache::Constants qw(:common);

use strict;
use warnings;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub strip_first_stopword {
    my ($content)=@_;

    my @stopwords = (
        'A',
        'a',
        'Alla',
        'alla',
        'Al-',
        'al-',
        'Au',
        'au',
        'Das',
        'das',
        'De',
        'de',
        'Dei',
        'dei',
        'Della',
        'della',
        'Dem',
        'dem',
        'Den',
        'den',
        'Der',
        'der',
        'Des',
        'des',
        'Det',
        'det',
        'Die',
        'die',
        'Du',
        'du',
        'Een',
        'een',
        'Ein',
        'ein',
        'Eine',
        'eine',
        'Einem',
        'einem',
        'Einen',
        'einen',
        'Einer',
        'einer',
        'Eines',
        'eines',
        'El',
        'el',
        'Het',
        'het',
        'I',
        'i',
        'Il',
        'il',
        'La',
        'la',
        'Las',
        'las',
        'Le',
        'le',
        'Les',
        'les',
        'Lo',
        'lo',
        'Los',
        'los',
        'L\'',
        'l\'',
        'The',
        'the',
        'Uma',
        'uma',
        'Uno',
        'uno',
        'Ye',
        'ye',
        '\'n',
        '\'t',
    );

  CLEANSW:
    foreach my $sw (@stopwords) {
        if ($content=~/^$sw\s+/) {
            $content=~s/^$sw\s+//;
            last CLEANSW;
        }
    }

    return $content;
}

1;
