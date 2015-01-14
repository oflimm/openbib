#####################################################################
#
#  OpenBib::Search::Factory
#
#  Dieses File ist (C) 2012-2015 Oliver Flimm <flimm@openbib.org>
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

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Search::Backend::BibSonomy;
use OpenBib::Search::Backend::DBIS;
use OpenBib::Search::Backend::ElasticSearch;
use OpenBib::Search::Backend::EZB;
use OpenBib::Search::Backend::Xapian;

sub create_searcher {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}        : undef;

    my $sb                 = exists $arg_ref->{sb}
        ? $arg_ref->{sb}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if ($logger->is_debug){
        $logger->debug("Trying to dispatch database $database") if (defined $database);
        $logger->debug("Trying to dispatch with optional sb $sb") if (defined $sb);
    }
    
    if (!defined $database && !defined $sb){
        $sb = $config->{local_search_backend};
    }
    
    elsif (defined $database && !defined $sb){
        my $system = $config->get_system_of_db($database);
        if    ($system eq "Backend: EZB"){
            $sb = "ezb";
        }
        elsif ($system eq "Backend: DBIS"){
            $sb = "dbis";
        }
        elsif ($system eq "Backend: BibSonomy"){
            $sb = "bibsonomy";
        }
        else {
            $sb = $config->{local_search_backend};
        }
    }

    $logger->debug("Dispatching to Search Backend $sb");
    
    if    ($sb eq "ezb"){        
        return new OpenBib::Search::Backend::EZB($arg_ref);
    }
    elsif ($sb eq "dbis"){        
        return new OpenBib::Search::Backend::DBIS($arg_ref);
    }
    elsif ($sb eq "bibsonomy"){        
        return new OpenBib::Search::Backend::BibSonomy($arg_ref);
    }
    elsif ($sb eq "xapian"){        
        return new OpenBib::Search::Backend::Xapian($arg_ref);
    }
    elsif ($sb eq "elasticsearch"){        
        return new OpenBib::Search::Backend::ElasticSearch($arg_ref);
    }
    else {
        $logger->fatal("Couldn't dispatch to any Search Backend");
    }

    return;
}

1;
