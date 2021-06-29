#####################################################################
#
#  OpenBib::Index::Factory
#
#  Dieses File ist (C) 2013-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Index::Factory;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

use OpenBib::Index::Backend::ElasticSearch;
use OpenBib::Index::Backend::Solr;
use OpenBib::Index::Backend::Xapian;

sub create_indexer {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $sb                 = exists $arg_ref->{sb}
        ? $arg_ref->{sb}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    if (!defined $sb){
        $sb = $config->{default_local_search_backend};
    }

    $logger->debug("Dispatching to Indexer Backend $sb");
    
    if ($sb eq "xapian"){        
        return new OpenBib::Index::Backend::Xapian($arg_ref);
    }
    elsif ($sb eq "elasticsearch"){        
        return new OpenBib::Index::Backend::ElasticSearch($arg_ref);
    }
    elsif ($sb eq "solr"){        
        return new OpenBib::Index::Backend::Solr($arg_ref);
    }
    else {
        $logger->fatal("Couldn't dispatch to any Indexer Backend");
    }

    return;
}

1;
