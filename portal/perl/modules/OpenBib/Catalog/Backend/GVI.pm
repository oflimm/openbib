#####################################################################
#
#  OpenBib::Catalog::Backend::GVI.pm
#
#  Objektorientiertes Interface zum GVI Solr API
#
#  Dieses File ist (C) 2022- Oliver Flimm <flimm@openbib.org>
#  basiert auf DBIS-Backend
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

package OpenBib::Catalog::Backend::GVI;

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
use JSON::XS;
use YAML ();
use Mojo::Base -strict, -signatures;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::API::HTTP::EDS;
use OpenBib::Record::Title;

use Mojo::Promise;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}        : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}          : OpenBib::Config->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
	my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $database})->single;
	
	my $user     = $dbinfo_ref->remoteuser;
	my $password = $dbinfo_ref->remotepassword;
	my $profile  = $dbinfo_ref->remotepath;
	
	$logger->debug("EDS API-Credentials: $user - $password - $profile");
	
	if ($user && $password && $profile){
	    $arg_ref->{api_user}     = $user;
	    $arg_ref->{api_password} = $password;
	    $arg_ref->{api_profile}  = $profile;
	}
    };

    if ($@){
	$logger->error($@);
    }
    
    my $api = new OpenBib::API::HTTP::Solr::GVI($arg_ref);
    
    my $self = { };

    bless ($self, $class);

    $self->{api} = $api;
    
    return $self;
}

sub load_full_title_record_p {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $promise = Mojo::Promise->new;
    
    $id = OpenBib::Common::Util::decode_id($id);

    my $record = $self->get_api->get_record({ database => $database, id => $id});

    return $promise->resolve($record);
}

1;
__END__

=head1 NAME

OpenBib::Catalog::Backend::GVI - Objektorientiertes Interface zum GVI Solr-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das Solr-API des GVI zugegriffen werden, um auf einen Katalog-Titel uber das vereinheitlichte OpenBib::Catalog Objekt zuzugreifen

=head1 SYNOPSIS

 use OpenBib::Catalog::Backend::GVI;

 my $eds = OpenBib::Catalog::Backend::GVI->new({});

=head1 METHODS

=over 4

=item new({ sessionID => $sessionID, id => $edsid })

Erzeugung des EDS Objektes. sessionID wird benoetigt, um OpenBib-Sessionbasiert das EDS-Sessiontoken via memcached zwischenzuspeichern.

=item load_full_title_record({ id => $gvi_id })

Abfrage des Records.

=item load_short_title_record({ id => $gvi_id })

Abfrage des Records. Nutzt load_full_title_record.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
