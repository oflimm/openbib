#####################################################################
#
#  OpenBib::Config::DatabaseInfoTable
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

package OpenBib::Config::DatabaseInfoTable;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Cache::Memcached::Fast;
use Compress::LZ4;
use OpenBib::Schema::System;
use OpenBib::Schema::System::Singleton;
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

    $self->load;
    
    return $self;
}

sub load {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;
    
    $self->connectMemcached;

    #####################################################################
    # Dynamische Definition diverser Variablen
  
    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $memc_key = "config:databaseinfotable";

    if ($self->{memc}){
        my $dbinfo= $self->{memc}->get($memc_key);

        if ($dbinfo){
            $self->{dbinfo}= $dbinfo;
            
            $logger->debug("Got dbinfo from memcached");
            
            if ($config->{benchmark}) {
                $btime=new Benchmark;
                $timeall=timediff($btime,$atime);
                $logger->info("Total time for is ".timestr($timeall));
            }

	    $self->disconnectMemcached;
            
            return $self ;
        }
    }

    $self->connectDB;

    my $dbinfos = $self->get_schema->resultset('Databaseinfo')->search_rs(
        undef,
        {
            select => ['me.dbname','me.description','me.shortdesc','me.sigel','me.url','me.schema','locationid.identifier','locationid.type'],
            as     => ['thisdbname','thisdescription','thisshortdesc','thissigel','thisurl','thisschema','thislocationid','thislocationtype'],
            join   => ['locationid'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    while (my $dbinfo = $dbinfos->next){
        my $description  = $dbinfo->{thisdescription} || '';
        my $shortdesc    = $dbinfo->{thisshortdesc}   || '';
        my $dbname       = $dbinfo->{thisdbname};
        my $sigel        = $dbinfo->{thissigel}       || '';
        my $url          = $dbinfo->{thisurl}         || '';
        my $schema       = $dbinfo->{thisschema}      || '';
        my $locationid   = $dbinfo->{thislocationid};
        my $locationtype = $dbinfo->{thislocationtype};
        
        ##################################################################### 
        ## Wandlungstabelle Bibliothekssigel <-> Bibliotheksname

        $self->{dbinfo}{sigel}{$sigel} = {
            full   => $description,
            short  => $shortdesc,
            dbname => $dbname,
        };
        
        #####################################################################
        ## Wandlungstabelle Bibliothekssigel <-> Informations-URL

        $self->{dbinfo}{bibinfo}{$sigel} = $url;
        
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
        
        $self->{dbinfo}{dbases}{$dbname}       = $sigel;

        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Datenbankinfo

        $self->{dbinfo}{dbnames}{$dbname}      = {
            full  => $description,
            short => $shortdesc,
        };

        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> URL
	
        $self->{dbinfo}{urls}{$dbname}        = $url;

        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Metadaten Schema
	
        $self->{dbinfo}{schema}{$dbname}      = $schema;
	
        if (defined $locationtype && defined $locationid){
            $self->{dbinfo}{locationid}{$dbname}  = $locationid;
        }
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time is ".timestr($timeall));
    }

    if ($self->{memc}){
        $self->{memc}->set($memc_key,$self->{dbinfo},$config->{memcached_expiration}{$memc_key});
    }

    $self->disconnectDB;
    $self->disconnectMemcached;
    
    return $self;
}


sub get {
    my ($self,$key) = @_;

    return $self->{dbinfo}{$key} if (defined $self->{dbinfo}{$key});

    return;
}

sub has_dbinfo {
    my ($self,$key) = @_;

    return (defined $self->{dbinfo}{$key})?1:0;
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

    if (defined $self->{schema}){
        $self->disconnectDB;
    }

    if (defined $self->{memc}){
        $self->disconnectMemcached;
    }
    
    return;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;

    if (!defined $config->{memcached}){
      $logger->debug("No memcached configured");
      return;
    }

    # Verbindung zu Memchached herstellen
    $self->{memc} = new Cache::Memcached::Fast($config->{memcached});

    if (!$self->{memc}->set('isalive',1)){
        $logger->fatal("Unable to connect to memcached");
    }

    return;
}

sub disconnectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;
    
    if (!exists $config->{memcached}){
      $logger->debug("No memcached configured");
      return;
    }

    $logger->debug("Disconnecting memcached");
    
    $self->{memc}->disconnect_all if (defined $self->{memc});
    delete $self->{memc};

    return;
}

1;
__END__

=head1 NAME

OpenBib::Config::DatabaseInfoTable - Informationen über alle Datenbanken/Kataloge

=head1 DESCRIPTION

Dieses Apache-Singleton enthält Informtionen über alle Datenbanken
bzw. Kataloge.


=head1 SYNOPSIS

 use OpenBib::Config::DatabaseInfoTable;

 my $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;

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

=item new

Instanziierung des Objekts

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
