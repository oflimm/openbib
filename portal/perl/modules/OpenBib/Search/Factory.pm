#####################################################################
#
#  OpenBib::Search::Factory
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Factory;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use OpenBib::Config;
use OpenBib::Search::Backend::EZB;
use OpenBib::Search::Backend::DBIS;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Backend::ElasticSearch;

sub create_searcher {
    my $self = shift;
    my $database = shift;

    my $config = OpenBib::Config->instance;

    my $system = $config->get_system_of_db($database);

    return new OpenBib::Search::Backend::EZB($database)  if ($system eq "Backend: EZB");
    return new OpenBib::Search::Backend::DBIS($database) if ($system eq "Backend: DBIS");

    if ($config->{local_search_backend} eq "xapian"){ # Default
        return new OpenBib::Search::Backend::Xapian($database);
    }
    elsif ($config->{local_search_backend} eq "elasticsearch"){ # Default
        return new OpenBib::Search::Backend::ElasticSearch($database);
    }
}

1;
