#####################################################################
#
#  OpenBib::QueryOptions
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

package OpenBib::QueryOptions;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use YAML;

use OpenBib::Config;
use OpenBib::Database::DBI;
use OpenBib::Session;

sub _new_instance {
    my ($class,$query) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance;

    $logger->debug("SessionID:".$session->{ID}) if (defined $session->{ID});

    my $self = {};

    bless ($self, $class);
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    # Hinweis: Bisher wuerde statt $query direkt das Request-Objekt $r
    # uebergeben und an dieser Stelle wieder ein $query-Objekt via
    # Apache::Request daraus erzeugt. Bei Requests, die via POST
    # sowohl mit dem enctype multipart/form-data wie auch
    # multipart/form-data abgesetzt wurden, lassen sich keine
    # Parameter ala sessionID extrahieren.  Das ist ein grosses
    # Problem. Andere Informationen lassen sich ueber das $r
    # aber sehr wohl extrahieren, z.B. der Useragent.

    if (!defined $session->{ID}){
      $logger->fatal("No SessionID");
      return $self;
    }	

    # Queryoptions zur Session einladen (default: alles undef via Session.pm)
    $self->load;

    my $default_queryoptions_ref = $self->get_default_options;

    my $altered=0;
    # Abgleich mit uebergebenen Parametern
    # Uebergebene Parameter 'ueberschreiben'und gehen vor
    foreach my $option (keys %$default_queryoptions_ref){
        if (defined $query->param($option)){
            # Es darf nicht hitrange = -1 (= hole alles) dauerhaft gespeichert
            # werden - speziell nicht bei einer anfaenglichen Suche
            # Dennoch darf - derzeit ausgehend von den Normdaten - alles
            # geholt werden
            unless ($option eq "hitrange" && $query->param($option) eq "-1"){
                $self->{option}->{$option}=$query->param($option);
                $logger->debug("Option $option received via HTTP");
                $altered=1;
            }
        }
    }

    # Abgleich mit Default-Werten:
    # Verbliebene "undefined"-Werte werden mit Standard-Werten belegt
    foreach my $option (keys %{$self->{option}}){
        if (!defined $self->{option}->{$option}){
            $self->{option}->{$option}=$default_queryoptions_ref->{$option};
	    $logger->debug("Option $option got default value");
	    $altered=1;
        }
    }

    if ($altered){
      $self->dump;
      $logger->debug("Options changed and dumped to DB");
    }

    
    $logger->debug("QueryOptions-Object created: ".YAML::Dump($self));

    return $self;
}

sub load {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("select queryoptions from session where sessionid = ?") or $logger->error($DBI::errstr);

    $request->execute($session->{ID}) or $logger->error($DBI::errstr);
  
    my $res=$request->fetchrow_hashref();
    $logger->debug($res->{queryoptions});
    $self->{option} = YAML::Load($res->{queryoptions});
    $request->finish();

    return $self;
}

sub dump {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("update session set queryoptions=? where sessionid = ?") or $logger->error($DBI::errstr);

    $request->execute(YAML::Dump($self->{option}),$session->{ID}) or $logger->error($DBI::errstr);

    $logger->debug("Dumped Options: ".YAML::Dump($self->{option})." for session $session->{ID}");
    $request->finish();

    return;
}

sub get_options {
    my ($self)=@_;

    return $self->{option};
}

sub get_option {
    my ($self,$option)=@_;

    return $self->{option}->{$option};
}

sub get_default_options {
    my ($class)=@_;

    return {
        hitrange  => 50,
        offset    => 1,
        l         => 'de',
        profil    => '',
        autoplus  => '',
        sb        => 'sql',
        js        => 0,
    };

};

1;
