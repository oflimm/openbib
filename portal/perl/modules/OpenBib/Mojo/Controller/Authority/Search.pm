###################################################################
#
#  OpenBib::Mojo::Controller::Authority::Search.pm
#
#  Dieses File ist (C) 2013-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Authority::Search;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Data::Pageset;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
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

use base 'OpenBib::Mojo::Controller::Search';

sub joined_search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = $self->stash('config');
    my $searchquery = $self->stash('searchquery');
    my $writer      = $self->stash('writer');

    $searchquery->set_type('authority');
    
    $logger->debug("Starting joined search");

    $self->search({authority => 1});
    
    my $templatename = $self->get_templatename_of_joined_search();

    my $content_searchresult = $self->print_resultitem({templatename => $templatename});

    $writer->write(encode_utf8($content_searchresult));
    
    return;
}

sub enforce_year_restrictions {
    my $self = shift;

    return;
}

sub get_start_templatename {
    my $self = shift;
    
    my $config = $self->stash('config');
    
    return $config->{tt_authority_search_start_tname};
}

sub get_end_templatename {
    my $self = shift;
    
    my $config = $self->stash('config');
    
    return $config->{tt_authority_search_end_tname};
}

sub get_templatename_of_joined_search {
    my $self = shift;

    my $config         = $self->stash('config');

    return $config->{tt_authority_search_combined_tname};
}

1;
