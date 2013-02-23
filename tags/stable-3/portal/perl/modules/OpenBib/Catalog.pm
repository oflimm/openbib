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

use base qw(Apache::Singleton);

use Business::ISBN;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Config;
use OpenBib::Schema::DBI;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

sub new {
    my ($class,$database) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->{database} = $database;
    
    $self->connectDB($database);
    
    return $self;
}


sub get_recent_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    my $titles = $self->{schema}->resultset('Title')->search_rs(
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
    my $database = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    eval {
        # UTF8: {'pg_enable_utf8'    => 1} 
        $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:Pg:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'pg_enable_utf8'    => 1 }) or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect schema to database $config->{dbname}: DBI:Pg:dbname=$config->{dbname};host=$config->{dbhost};port=$config->{dbport}");
    }

    return;

}

sub DESTROY {
    my $self = shift;

    return;
}

1;
__END__

=head1 NAME

OpenBib::Catalog - Apache-Singleton für den Zugriff auf
Informationen in einer Katalog-Datenbank.

=head1 DESCRIPTION

Dieses Apache-Singleton bietet einen Zugriff auf die Informationen in
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
