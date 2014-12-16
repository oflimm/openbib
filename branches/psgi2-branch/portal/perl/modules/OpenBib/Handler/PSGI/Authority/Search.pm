###################################################################
#
#  OpenBib::Handler::PSGI::Authority::Search.pm
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Authority::Search;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Data::Pageset;
use DBI;
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Storable ();
use String::Tokenizer;
use Search::Xapian;
use YAML ();

use OpenBib::Container;
use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Factory;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Backend::ElasticSearch;
use OpenBib::Search::Backend::Z3950;
use OpenBib::Search::Backend::EZB;
use OpenBib::Search::Backend::DBIS;
use OpenBib::Search::Backend::BibSonomy;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Search';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_search');
    $self->run_modes(
        'show_search'   => 'show_search',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub joined_search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;
    my $searchquery = OpenBib::SearchQuery->instance;

    $searchquery->set_type('authority');
    
    $logger->debug("Starting joined search");

    $self->search({authority => 1});
    
    my $templatename = $self->get_templatename_of_joined_search();

    $self->print_resultitem({templatename => $templatename});

    # Etwaige Kataloge, die nicht lokal vorliegen und durch ein API angesprochen werden
    foreach my $database ($config->get_databases_of_searchprofile($searchquery->get_searchprofile)) {
        my $system = $config->get_system_of_db($database);

        if ($system =~ /^Backend/){
            $self->param('database',$database);
            
            $self->search({database => $database});
            
            $self->print_resultitem({templatename => $config->{tt_search_title_item_tname}});
        }
    }

    
    return;
}

sub enforce_year_restrictions {
    my $self = shift;

    return;
}

sub get_start_templatename {
    my $self = shift;
    
    my $config = $self->param('config');
    
    return $config->{tt_authority_search_start_tname};
}

sub get_end_templatename {
    my $self = shift;
    
    my $config = $self->param('config');
    
    return $config->{tt_authority_search_end_tname};
}

sub get_templatename_of_joined_search {
    my $self = shift;

    my $config         = $self->param('config');

    return $config->{tt_authority_search_combined_tname};
}

1;
