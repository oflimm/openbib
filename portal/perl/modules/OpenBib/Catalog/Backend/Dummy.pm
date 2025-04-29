#####################################################################
#
#  OpenBib::Catalog::Backend::Dummy.pm
#
#  Objektorientiertes Beispiel Interface
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

package OpenBib::Catalog::Backend::Dummy;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;
    
    # Set defaults
    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}         : undef;

    my $lang      = exists $arg_ref->{l}
        ? $arg_ref->{l}           : undef;

    my $arg1     = exists $arg_ref->{arg1}
        ? $arg_ref->{arg1}       : undef;

    my $arg2     = exists $arg_ref->{arg2}
        ? $arg_ref->{arg2}       : $config->{arg_2};
    
    my $self = { };

    bless ($self, $class);

    $self->{database}      = $database;

    # Backend Specific Attributes
    $self->{arg1}            = $arg1;
    $self->{arg2}            = $arg2;
    $self->{lang}            = $lang if ($lang);
    
    return $self;
}

sub load_full_title_record_p {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $promise = Mojo::Promise->new;
    
    # Retrieve information

    # ...
    
    # and build title record with it
    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });

    $record->set_field({field => 'T0331', subfield => '', mult => 1, content => ''});

    # ...
    
    return $promise->resolve($record);
}

sub load_brief_title_record_p {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    return $self->load_full_title_record($arg_ref);
}

sub get_classifications {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $classifications_ref = [];

    # Retrieve classifications

	my $mincount = 0;
	my $maxcount = 9999;
    # add Cloud-Information
    $classifications_ref = OpenBib::Common::Util::gen_cloud_class({
        items => $classifications_ref, 
        min   => $mincount, 
        max   => $maxcount, 
        type  => 'log'});

    $logger->debug(YAML::Dump($classifications_ref));

    return $classifications_ref;
}

sub DESTROY {
    my $self = shift;

    return;
}

1;
__END__

=head1 NAME

OpenBib::Catalog::Backend::Dummy - Objektorientiertes Interface zum Dummy API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API von Dummy zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::Catalog::Backend::Dummy;

 my $catalog = OpenBib::Catalog::Backend->new({ database => "openlibrary" });

oder alternativ ueber die Catalog-Factory, wenn die Datenbank ueber 'System' in der Administration
sowie einer entsprechenden Regel in OpenBib::Catalog::Factory dem Backend zugeordnet ist.

 my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => "openlibrary" });

 my $classifications_ref = $catalog->get_classifications;

 my $record = new OpenBib::Record::Title({ database => 'openlibrary', id => '0815' })->load_full_record;

=head1 METHODS

=over 4

=item new({ database => database })

Erzeugung des Dummy Objektes. Der Parameter database muss immer uebergeben werden. Zusaetzlich
koennen beliebige weitere Parameter entgegengenommen werden und im Objekt selbst gespeichert werden.

=item get_classifications

Liefert eine Listenreferenz der vorhandenen Klassifikationen zurück.
Zusätzlich werden für eine Wolkenanzeige die entsprechenden
Klasseninformationen hinzugefügt.

=item load_full_record ({ database => $database, id => $id })

Liefert einen Titel-Record zurueck.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
