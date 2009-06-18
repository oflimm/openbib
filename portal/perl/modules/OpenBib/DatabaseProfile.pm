#####################################################################
#
#  OpenBib::DatabaseProfile
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

package OpenBib::DatabaseProfile;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Config;
use OpenBib::Record::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id           = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    if (defined $id){
        $self->{id}       = $id;
    }

    $self->{_litlist}     = [];
    $self->{_properties}  = {};
    $self->{_size}        = 0;

    return $self;
}

sub load {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    return if (!$self->{id});

    # Zuerst Profil-Description zur ID holen
    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error($DBI::errstr);

    return $self if (!defined $dbh);

    my $request = $dbh->prepare("select profilename from dbprofile where profileid = ?") or $logger->error($DBI::errstr);
    $request->execute($self->{id}) or $logger->error($DBI::errstr);
      
    my $result=$request->fetchrow_hashref();
    
    $self->{name} = decode_utf8($result->{'profilename'});

    $request=$dbh->prepare("select dbname from profildb where profilid = ?") or $logger->error($DBI::errstr);
    $request->execute($self->{id}) or $logger->error($DBI::errstr);

    while (my $result=$request->fetchrow_hashref()){
        my $database = decode_utf8($result->{'dbname'});
        
        $self->{database}->{$database} = 1;
    }
    
    $request->finish();

    return $self;
}

sub load_from_handler {
    my ($self,$r)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $query=Apache2::Request->new($r);

    my $status=$query->parse;
    
    if ($status) {
        $logger->error("Cannot parse Arguments");
    }
    
    my $profilename = ($query->param('profilename'))?$query->param('profilename'):'Datenbank-Profil';
    my @databases   = ($query->param('database'))?$query->param('database'):();

    foreach my $database (@databases){
        $self->{database}->{$database} = 1;
    }
    
    return $self;
}

sub write {
    my ($self)=@_;
}

sub contains {
    my ($self,$database) = @_;

    return (exists $self->{database}->{$database})?1:0;
}

1;
