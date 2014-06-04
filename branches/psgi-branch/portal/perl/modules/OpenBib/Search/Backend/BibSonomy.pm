#####################################################################
#
#  OpenBib::Search::Backend::BibSonomy.pm
#
#  Objektorientiertes Interface zum BibSonomy XML-API
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Backend::BibSonomy;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode qw(decode decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::Catalog::Factory;

use base qw(OpenBib::Search);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);

    $self->{_database}  = $database if ($database);
    $self->{args}          = $arg_ref;

    return $self;
}

sub search {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = OpenBib::Config->instance;
    my $searchquery  = OpenBib::SearchQuery->instance;
    my $queryoptions = OpenBib::QueryOptions->instance;

    # Pagination parameters
    my $page              = $queryoptions->get_option('page');
    my $num               = $queryoptions->get_option('num');

    my $offset            = $page*$num-$num;

    # BibSonomy verfuegt nur ueber eine Recherche nach 'bibkey', 'tag', 'user' und 'mediatyp' (=digital/web bzw. publication)

    $self->parse_query($searchquery);

    $self->{_querystring}{start} = $offset;
    $self->{_querystring}{end}   = $offset+$num;
    
    my $recordlist = OpenBib::BibSonomy->new()->get_posts($self->{_querystring});

    $self->{resultcount}   = $recordlist->get_size();
    $self->{_matches}      = $recordlist;
    
    return $self;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_matches};
}

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my @searchterms = ();
    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{norm})?$searchquery->get_searchfield($field)->{norm}:'';
        if ($searchtermstring) {
            # Freie Suche
            if    ($field eq "freesearch" && $searchtermstring) {
                push @searchterms, {
                    field   => 'search',
                    content => $searchtermstring
                };
            }
            elsif    ($field eq "subjectstring" && $searchtermstring) {
                push @searchterms, {
                    field   => 'tag',
                    content => $searchtermstring
                };
            }
            elsif ($field eq "bibkey" && $searchtermstring) {
                push @searchterms, {
                    field   => 'bibkey',
                    content => $searchtermstring
                };
            }
            elsif ($field eq "user" && $searchtermstring) {
                push @searchterms, {
                    field   => 'user',
                    content => $searchtermstring
                };
            }
            elsif ($field eq "mediatype" && $searchtermstring) {
                push @searchterms, {
                    field   => 'type',
                    content => $searchtermstring,
                };
            }
        }
    }

    my $query_string_ref = {};
    foreach my $search_ref (@searchterms){
        $query_string_ref->{$search_ref->{field}} = $search_ref->{content};
    }

    # Resource-type muss immer gesetzt sein
    unless ($query_string_ref->{type}){
        $query_string_ref->{type} = 'publication';
        $searchquery->set_searchfield('mediatype','publication');
    }
    
    if ($logger->is_debug){
        $logger->debug("Bibsonomy-Querystring: ".YAML::Dump($query_string_ref));
    }
    
    $self->{_querystring} = $query_string_ref;

    return $self;
}

1;
__END__

=head1 NAME

OpenBib::Search::Backend::BibSonomy - Objektorientiertes Interface zum BibSonomy XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API von BibSonomy für Rechercheanfragen zugegriffen werden.

=head1 SYNOPSIS

=head1 METHODS

=over 4

=item XXX

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
