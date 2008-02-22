#####################################################################
#
#  OpenBib::L10N
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::L10N;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

use base 'Locale::Maketext';

# Locale::Maketext::Lexicon und Template Toolkit:
#
# Hinweise
#
# 1) In den Templates muss die Bracket-Notation verwendet werden.
# 2) Beim extrahieren mit xgettext.pl wird diese automatisch in die
#    gettext-Notation (%) umgewandelt, die so in die Message-Kataloge
#    wandert und auch so uebersetzt werden muss
# 3) Es ist irrelevant, ob _style => 'gettext' gesetzt wird.
# 4) Argumente muessen in Double-Quotes eingegeben werden, z.B.
#    "${alldbcount}"

use Locale::Maketext::Lexicon {
    '*'        => [Gettext => OpenBib::Config->instance->{locale_base_path}."/*/LC_MESSAGES/openbib.po"],
#   _style     => 'gettext', # fuer korrektes TT-handling irrelevant
    _decode    => 1,         # UTF-8 handling on
#   _use_fuzzy => 1,         # Fuzzy-Matching off
};

sub failure_handler {
    my($failing_msg, $key, $params) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->error(ref($failing_msg), $key);

    return "No translation available";
}

1;
