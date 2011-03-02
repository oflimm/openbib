#####################################################################
#
#  OpenBib::Config::CirculationInfoTable
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

package OpenBib::Config::CirculationInfoTable;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);

use DBI;
use Encode qw(decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use YAML;

use OpenBib::Config;

sub _new_instance {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $self = {};

    bless ($self, $class);

    #####################################################################
    ## Ausleihkonfiguration fuer den Katalog einlesen

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{configdbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $dbinforesult=$dbh->prepare("select dbname,circ,circurl,circwsurl,circdb from databaseinfo where circ = 1") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);;

    while (my $result=$dbinforesult->fetchrow_hashref()) {
        my $dbname                             = decode_utf8($result->{'dbname'});

        $self->{$dbname}{circ}         = decode_utf8($result->{'circ'});
        $self->{$dbname}{circurl}      = decode_utf8($result->{'circurl'});
        $self->{$dbname}{circcheckurl} = decode_utf8($result->{'circwsurl'});
        $self->{$dbname}{circdb}       = decode_utf8($result->{'circdb'});
    }

    $dbinforesult->finish();

    return $self;
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

1;
__END__

=head1 NAME

OpenBib::Config::CirculationInfoTable - Apache-Singleton mit
Informationen zur Kopplung mit den jeweiligen Ausleihsystemen

=head1 DESCRIPTION

Dieses Apache-Singleton enthält für alle Datenbanken bzw. Kataloge die
Informationen über einen Zugriff über OLWS (circ, ja = 1, nein = 0),
den DB-Namen im Lokalsystem für den Zugriff über OLWS (circdb), den
Zugriffs-URL für OLWS (circheckurl) sowie einen optionalen
Web-OPAC-URL (circurl). Wenn circurl definiert ist, wird bei den
Ausleihdaten in den damit spezifizierten OPAC gesprungen, sonst werden
die ausleihrelevanten Funktionen transparent über OLWS innerhalb von
OpenBib angeboten.

=head1 SYNOPSIS

 use OpenBib::Config::CirculationInfoTable;

 my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;

=head1 METHODS

=over 4

=item instance

Instanziierung des Apache-Singleton.

=item get($dbname)

Liefert die Kopplungsinformationen zur Datenbank $dbname

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
