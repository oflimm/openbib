#####################################################################
#
#  OpenBib::Config::LocationInfoTable
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Config::LocationInfoTable;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Class::Singleton);

use Benchmark ':hireswallclock';
use OpenBib::Schema::System::Singleton;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode qw(decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use YAML::Syck;

use OpenBib::Config;

sub _new_instance {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = {};

    bless ($self, $class);

    $self->load;
    
    return $self;
}

sub load {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;
    
    #####################################################################
    # Dynamische Definition diverser Variablen
    
    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Bisherige Belegung loeschen
    delete $self->{identifier};
    
    my $schema = OpenBib::Schema::System::Singleton->instance->get_schema;

    my $locinfos = $schema->resultset('Locationinfo')->search_rs(
        undef,
        {
            select => ['identifier','description','type'],
            as     => ['thislocation','thisdescription','thistype'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    while (my $locinfo = $locinfos->next){
        my $description  = $locinfo->{thisdescription} || '';
        my $identifier   = $locinfo->{thislocation};
        my $type         = $locinfo->{type}       || '';

        ##################################################################### 
        ## Wandlungstabelle Identifier <-> Standortbeschreibung

        $self->{identifier}->{$identifier} = {
            description  => $description,
            type         => $type,
        };
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time is ".timestr($timeall));
    }

    return $self;
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

1;
__END__

=head1 NAME

OpenBib::Config::LocationInfoTable - Apache-Singleton mit Informationen über alle Standorte

=head1 DESCRIPTION

Dieses Apache-Singleton enthält Informtionen über alle Standorte


=head1 SYNOPSIS

 use OpenBib::Config::LocationInfoTable;

 my $locinfotable = OpenBib::Config::LocationInfoTable->instance;

 # Bibliothekssigel <-> Bibliotheksname
 my $full_db_info  = $dbinfotable->get("sigel")->{$sigel}->{full};
 my $short_db_info = $dbinfotable->get("sigel")->{$sigel}->{short};
 my $dbname        = $dbinfotable->get("sigel")->{$sigel}->{dbname};

 # Bibliothekssigel <-> Informations-URL
 my $info_url      = $dbinfotable->get("bibinfo")->{$sigel};

 # Name SQL-Datenbank <-> Bibliothekssigel
 my $sigel         = $dbinfotable->get("dbases")->{$dbname};

 # Name SQL-Datenbank <-> Datenbankinfo
 my $full_db_info  = $dbinfotable->get("dbnames")->{$dbname}->{full};
 my $short_db_info = $dbinfotable->get("dbnames")->{$dbname}->{short};

 # Name SQL-Datenbank <-> Informations-URL
 my $info_url      = $dbinfotable->get("urls")->{$dbname};

 # Lokale Bibliotheksinformationen (Bibliotheksführer) für Datenbank nutzen
 my use_libinfo    = $dbinfotable->get("use_libinfo")->{$dbname};

=head1 METHODS

=over 4

=item instance

Instanziierung des Apache-Singleton.

=item get($type)

Liefert die Informationen zu den Datenbanken entsprechend der Typen
"sigel", "bibinfo", "dbases", "dbnames", "urls" sowie "use_libinfo".

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
