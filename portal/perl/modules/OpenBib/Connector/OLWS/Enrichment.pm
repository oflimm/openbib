####################################################################
#
#  OpenBib::Connector::OLWS::Enrichment.pm
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Connector::OLWS::Enrichment;

use strict;
use warnings;
no warnings 'redefine';

use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Enrichment;
use OpenBib::Config;

sub get_additional_normdata {
    my ($class, $args_ref) = @_;

    # Parameter
    my $isbn             = $args_ref->{isbn} || undef;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = OpenBib::Config->instance;


    if (!defined $isbn){
        return {
            error => "not enough parameters"
        };
    }

    my $enrichmnt = OpenBib::Enrichment->instance;

    my $normset_ref = $enrichmnt->get_additional_normdata({ isbn => $isbn});

    my @enrich_category_items = ();
    foreach my $category (keys %$normset_ref){
        my @enrich_content_items = ();
        foreach my $item (@{$normset_ref->{$category}}){
            $logger->debug($item);
            push @enrich_content_items, SOAP::Data->name(Content => $item)->type('string');
        }

        $logger->debug(YAML::Dump(\@enrich_content_items));
        push @enrich_category_items, SOAP::Data->name($category => \SOAP::Data->value(@enrich_content_items));
    }

    return SOAP::Data->name(EnrichResult  => \SOAP::Data->value(@enrich_category_items));
}

sub get_similar_isbns {
    my ($class, $args_ref) = @_;

    # Parameter
    my $isbn             = $args_ref->{isbn} || undef;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = OpenBib::Config->instance;


    if (!defined $isbn){
        return {
            error => "not enough parameters"
        };
    }

    my $enrichmnt = OpenBib::Enrichment->instance;

    my $similar_isbn_ref = $enrichmnt->get_similar_isbns({ isbn => $isbn});

    $logger->debug(YAML::Dump($similar_isbn_ref));

    my @similar_isbns = ();
    foreach my $similar_isbn (keys %$similar_isbn_ref){
        push @similar_isbns, SOAP::Data->name(ISBN => $similar_isbn)->type('string');
    }

    return SOAP::Data->name(EnrichResult  => \SOAP::Data->value(@similar_isbns));
}

1;
