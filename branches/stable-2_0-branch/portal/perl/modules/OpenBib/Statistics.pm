#####################################################################
#
#  OpenBib::Statistics
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Statistics;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable ();

use OpenBib::Config;

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $self = { };

    bless ($self, $class);

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
            or $logger->error_die($DBI::errstr);

    $self->{dbh}       = $dbh;

    return $self;
}

sub store_relevance {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id    }        : undef;
    my $isbn              = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn  }        : undef;
    my $dbname            = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}        : undef;
    my $katkey            = exists $arg_ref->{katkey}
        ? $arg_ref->{katkey}        : undef;
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type  }        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef unless (defined $id && defined $dbname && defined $katkey && defined $type);
    
    my $request=$self->{dbh}->prepare("insert into relevance values (?,?,?,?,?)") or $logger->error($DBI::errstr);
    $request->execute($id,$isbn,$dbname,$katkey,$type) or $logger->error($DBI::errstr);
    return;
}

sub store_result {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id           } : undef;
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type  }        : undef;
    my $data_ref          = exists $arg_ref->{data}
        ? $arg_ref->{data  }        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef unless (defined $id && defined $type && defined $data_ref);
    
    my $request=$self->{dbh}->prepare("delete from result_data where id=? and type=?") or $logger->error($DBI::errstr);
    $request->execute($id,$type) or $logger->error($DBI::errstr);

    my $datastring=unpack "H*", Storable::freeze($data_ref);
    
    $request=$self->{dbh}->prepare("insert into result_data values (?,NULL,?,?)") or $logger->error($DBI::errstr);
    $request->execute($id,$type,$datastring) or $logger->error($DBI::errstr);

    return;
}

sub get_result {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id           } : undef;
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type  }        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef unless (defined $id && defined $type);
    
    my $request=$self->{dbh}->prepare("select data from result_data where id=? and type=?") or $logger->error($DBI::errstr);
    $request->execute($id,$type) or $logger->error($DBI::errstr);

    my $data_ref;
    while (my $result=$request->fetchrow_hashref){
        my $datastring = $result->{data};
        
        $data_ref     = Storable::thaw(pack "H*",$datastring);
    }

    return $data_ref;
}

1;
