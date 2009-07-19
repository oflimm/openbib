#####################################################################
#
#  OpenBib::Config::DatabaseInfoTable
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Config::DatabaseInfoTable;

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
    # Dynamische Definition diverser Variablen
  
    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $dbinforesult=$dbh->prepare("select dbname,sigel,url,description,shortdesc,use_libinfo from dbinfo") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);;
  
    while (my $result=$dbinforesult->fetchrow_hashref()) {
        my $dbname      = decode_utf8($result->{'dbname'});
        my $sigel       = decode_utf8($result->{'sigel'});
        my $url         = decode_utf8($result->{'url'});
        my $description = decode_utf8($result->{'description'});
        my $shortdesc   = decode_utf8($result->{'shortdesc'});
        my $use_libinfo = decode_utf8($result->{'use_libinfo'});
    
        ##################################################################### 
        ## Wandlungstabelle Bibliothekssigel <-> Bibliotheksname
    
        $self->{sigel}->{"$sigel"} = {
            full   => $description,
            short  => $shortdesc,
            dbname => $dbname,
        };
    
        #####################################################################
        ## Wandlungstabelle Bibliothekssigel <-> Informations-URL
    
        $self->{bibinfo}->{"$sigel"} = "$url";
        
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
        
        $self->{dbases}->{"$dbname"}       = "$sigel";

        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Datenbankinfo

        $self->{dbnames}->{"$dbname"}      = {
            full  => $description,
            short => $shortdesc,
        };

        $self->{urls}->{"$dbname"}        = $url;
        $self->{use_libinfo}->{"$dbname"} = $use_libinfo;

    }
  
    $dbinforesult->finish;

    return $self;
}

sub get {
    my ($self,$key) = @_;

    return $self->{$key};
}

1;
__END__

=head1 NAME

OpenBib::Config::DatabaseInfoTable - Apache-Singleton mit Informationen über alle Datenbanken/Kataloge

=head1 DESCRIPTION

Dieses Apache-Singleton enthält Informtionen über alle Datenbanken
bzw. Kataloge.


=head1 SYNOPSIS

 use OpenBib::Config::CirculationInfoTable;

 my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

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
