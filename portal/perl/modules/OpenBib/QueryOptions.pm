#####################################################################
#
#  OpenBib::QueryOptions
#
#  Dieses File ist (C) 2008-2011 Oliver Flimm <flimm@openbib.org>
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
    # Apache2::Request daraus erzeugt. Bei Requests, die via POST
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
            unless ($option eq "num" && $query->param($option) eq "-1"){
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

    my $config  = OpenBib::Config->instance;

    return $config->{default_query_options};
};

sub to_cgi_params {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $exclude_array_ref    = exists $arg_ref->{exclude}
        ? $arg_ref->{exclude}        : [];

    my $exclude_ref = {};

    foreach my $param (@{$exclude_array_ref}){
        $exclude_ref->{$param} = 1;
    }
    
    my @cgiparams = ();

    foreach my $param (keys %{$self->{option}}){
        if ($self->{option}->{$param} && ! exists $exclude_ref->{$param}){
            push @cgiparams, "$param=".$self->{option}->{$param};
        }
    }
    
    return join(";",@cgiparams);
}

1;
__END__

=head1 NAME

OpenBib::QueryOptions - Apache-Singleton zur Behandlung von Recherche-Optionen

=head1 DESCRIPTION

Dieses Apache-Singleton Verwaltet die Recherche-Optionen wie num,
offset, Sprache l, Profil profile, Automatische Und-Verknuepfung
autoplus, Such-Backend sb sowie den Trefferlistentyp listtype.

=head1 SYNOPSIS

 use OpenBib::QueryOptions;

 my $queryoptions  = OpenBib::QueryOptions->instance;

 my $lang = $queryoptions->get_option('l');

 my $current_options = $queryoptions->get_options;

=head1 METHODS

=over 4

=item instance

Instanziierung des Apache-Singleton.

=item load

Einladen der aktuellen QueryOptions der Session.

=item dump

Abspeichern der QueryOptions in der Session

=item get_options

Liefert alle QueryOptions als Hashreferenz

=item get_option($option)

Liefert den Wert der Option $option

=item get_default_options

Liefert die Standardeinstellung default_query_options aus der
Konfigurationsdatei portal.yml.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
