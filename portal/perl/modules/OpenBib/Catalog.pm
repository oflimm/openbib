#####################################################################
#
#  OpenBib::Catalog
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

package OpenBib::Catalog;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Class::Singleton);

use Business::ISBN;
use Cache::Memcached::Fast;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Schema::DBI;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}         : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);
    
    $self->{database} = $database;
    
    return $self;
}


sub get_database {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    return $self->{database};
}

sub get_recent_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    my $titles = $self->get_schema->resultset('Title')->search_rs(
        undef,
        {
            order_by => ['tstamp_create DESC'],
            rows     => $limit,
        }
    );

    my $recordlist = new OpenBib::RecordList::Title();

    foreach my $title ($titles->all){
        $logger->debug("Adding Title ".$title->id);
        $recordlist->add(new OpenBib::Record::Title({ database => $self->{database} , id => $title->id, date => $title->tstamp_create}));
    }

    return $recordlist;
}

sub get_schema {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Schema $self");
    
    if (defined $self->{schema}){
        $logger->debug("Reusing Schema $self");
        return $self->{schema};
    }

    $logger->debug("Creating new Schema $self");    
    
    $self->connectDB;
    
    return $self->{schema};
}

sub get_recent_titles {
    return new OpenBib::RecordList::Title();
}

sub get_recent_titles_of_person {
    return new OpenBib::RecordList::Title();
}

sub get_recent_titles_of_corporatebody {
    return new OpenBib::RecordList::Title();
}

sub get_recent_titles_of_classification {
    return new OpenBib::RecordList::Title();
}

sub get_recent_titles_of_subject {
    return new OpenBib::RecordList::Title();
}

sub connectDB {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;

    eval {
        # UTF8: {'pg_enable_utf8'    => 1} 
        $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:Pg:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},$config->{dboptions}) or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect schema to database $self->{database}: DBI:Pg:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}");
    }

    return;

}

sub disconnectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Try disconnecting from Catalog-DB $self");
    
    if (defined $self->{schema}){
        eval {
            $logger->debug("Disconnect from Catalog-DB now $self");
            $self->{schema}->storage->disconnect;
            delete $self->{schema};
        };

        if ($@){
            $logger->error($@);
        }
    }
    
    return;
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Destroying Catalog-Object $self");

    if (defined $self->{schema}){
        $self->disconnectDB;
    }

    return;
}

sub get_config {
    my ($self) = @_;

    return $self->{_config};
}

sub get_client {
    my ($self) = @_;

    return $self->{client};
}

sub get_searchquery {
    my ($self) = @_;

    return $self->{_searchquery};
}

sub get_queryoptions {
    my ($self) = @_;

    return $self->{_queryoptions};
}

sub have_field_content {
    my ($self,$field,$content)=@_;

    my $have_field = 0;
    
    eval {
	$have_field = $self->{have_field_content}{$field}{$content};
    };

    $self->{have_field_content}{$field}{$content} = 1;

    return $have_field;
}

sub load_full_title_record {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $record = $self->get_api->get_titles_record($arg_ref);
    
    return $record;
}

sub load_brief_title_record {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->load_full_title_record($arg_ref);
}

sub get_classifications {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $classifications_ref = $self->get_api->get_classifications();
    
    return $classifications_ref;
}

sub get_api {
    my $self = shift;

    return $self->{api};
}

sub get_common_holdings {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $locations_ref       = exists $arg_ref->{locations}
        ? $arg_ref->{locations}        : ();

    my $config              = exists $arg_ref->{config}
        ? $arg_ref->{config}        : OpenBib::Config->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->error("Method get_common_holdings not supported for this catalog backend");
    
    return ();
}

1;
__END__

=head1 NAME

OpenBib::Catalog - Singleton für den Zugriff auf
Informationen in einer Katalog-Datenbank.

=head1 DESCRIPTION

Dieses Singleton bietet einen Zugriff auf die Informationen in
einer Katalogdatenbank.

=head1 SYNOPSIS

 use OpenBib::Catalog;

 my $catalog = OpenBib::Catalog->new;

=head1 METHODS

=over 4

=item new

Erzeugung des Objektes

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
