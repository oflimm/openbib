#####################################################################
#
#  OpenBib::Config::CirculationInfoTable
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

package OpenBib::Config::CirculationInfoTable;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBIx::Class::ResultClass::HashRefInflator;
use Encode qw(decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use YAML::Syck;

use OpenBib::Config::File;

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = {};

    bless ($self, $class);

    $self->{circinfo} = {};
    
    $self->connectMemcached;
    $self->load;
    
    return $self;
}

sub load {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config::File->instance;
    
    #####################################################################
    ## Ausleihkonfiguration fuer den Katalog einlesen

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $memc_key = "config:circulationinfotable";

    if ($self->{memc}){
        my $circinfo = $self->{memc}->get($memc_key);

        if ($circinfo){
            $self->{circinfo} = $circinfo;
      
            $logger->debug("Got circinfo from memcached");
      
            if ($config->{benchmark}) {
                $btime=new Benchmark;
                $timeall=timediff($btime,$atime);
                $logger->info("Total time for is ".timestr($timeall));
            }
            
            return $self;
        }
    }
    
    my $dbinfos = $self->get_schema->resultset('Databaseinfo')->search_rs(
        {
            circ => 1,
        },
        {
            columns => ['dbname','circ','circurl','circwsurl','circdb'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    while (my $dbinfo = $dbinfos->next){
        my $dbname                     = $dbinfo->{dbname};

        $self->{circinfo}{$dbname}{circ}         = $dbinfo->{circ};
        $self->{circinfo}{$dbname}{circurl}      = $dbinfo->{circurl};
        $self->{circinfo}{$dbname}{circcheckurl} = $dbinfo->{circwsurl};
        $self->{circinfo}{$dbname}{circdb}       = $dbinfo->{circdb};
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time is ".timestr($timeall));
    }

    if ($self->{memc}){
        $self->{memc}->set($memc_key,$self->{circinfo},$config->{memcached_expiration}{$memc_key});
    }
    
    return $self;
    
}
             
sub get {
    my ($self,$key) = @_;

    return $self->{circinfo}{$key} if (defined $self->{circinfo}{$key});

    return;
}

sub has_circinfo {
    my ($self,$key) = @_;

    return (defined $self->{circinfo}{$key})?1:0;
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;

    # UTF8: {'pg_enable_utf8'    => 1}
    if ($config->{'systemdbsingleton'}){
        eval {        
            my $schema = OpenBib::Schema::System::Singleton->instance;
            $self->{schema} = $schema->get_schema;
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
    else {
        eval {        
            $self->{schema} = OpenBib::Schema::System->connect("DBI:Pg:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},$config->{systemdboptions}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
        
    
    return;
}

sub get_schema {
    my $self = shift;

    if (defined $self->{schema}){
        return $self->{schema};
    }

    $self->connectDB;

    return $self->{schema};
}

sub disconnectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (defined $self->{schema}){
        eval {
            $self->{schema}->storage->dbh->disconnect;
        };

        if ($@){
            $logger->error($@);
        }
    }

    return;
}

sub DESTROY {
    my $self = shift;

    $self->disconnectDB;

    return;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;

    if (!exists $config->{memcached}){
      $logger->debug("No memcached configured");
      return;
    }

    # Verbindung zu Memchached herstellen
    $self->{memc} = new Cache::Memcached::libmemcached($config->{memcached});

    if (!$self->{memc}->set('isalive',1)){
        $logger->fatal("Unable to connect to memcached");
    }

    return;
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

 my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

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
