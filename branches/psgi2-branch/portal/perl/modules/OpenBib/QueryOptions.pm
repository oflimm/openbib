#####################################################################
#
#  OpenBib::QueryOptions
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

package OpenBib::QueryOptions;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use JSON::XS qw(encode_json decode_json);
use YAML::Syck;


use OpenBib::Config;
use OpenBib::Schema::System;
use OpenBib::Session;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $query    = exists $arg_ref->{query}
        ? $arg_ref->{query}             : undef;

    my $session  = exists $arg_ref->{session}
        ? $arg_ref->{session}           : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $self = {};

    bless ($self, $class);

    $self->connectDB();
    $self->connectMemcached();
    
    $self->{_altered} = 0;

    if (defined $query){
        $self->set_query($query);
    }

    if (defined $session){
        $self->set_session($session);
    }
    
    if ($logger->is_debug){
        $logger->debug("Query: Stage 1 ".YAML::Dump($self->{option}));
    }
    
    # Initializierung mit Defaults
#    $self->initialize_defaults;
    
    # Queryoptions zur Session einladen, falls Session existiert
    $self->load_from_session;
    
    # Abgleich mit uebergebenen Parametern
    # Uebergebene Parameter 'ueberschreiben'und gehen vor
    $self->load_from_query;

    # Entsprechende Optionen wieder zurueck in die Session schreiben
    $self->dump_into_session;

    $logger->debug("srt Option: ".$self->{option}->{'srt'});
    
    # Wenn srto in srt enthalten, dann aufteilen
    if ($self->{option}{'srt'} =~m/^([^_]+)_([^_]+)$/){
        $self->{option}{'srt'}=$1;
        $self->{option}{'srto'}=$2;
        $logger->debug("srt Option split: srt = $1, srto = $2");
    }

    if ($logger->is_debug){
        $logger->debug("QueryOptions-Object created with options ".YAML::Syck::Dump($self->get_options));
    }


    return $self;
}

sub load_from_query {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return unless (defined $self->{_query});
                   
    my $config  = OpenBib::Config->instance;

    my $queryoptions_ref = $self->get_option_definition;

    foreach my $option (keys %$queryoptions_ref){
        if (defined $self->get_query->param($option)){
            # Es darf nicht hitrange = -1 (= hole alles) dauerhaft gespeichert
            # werden - speziell nicht bei einer anfaenglichen Suche
            # Dennoch darf - derzeit ausgehend von den Normdaten - alles
            # geholt werden
            $self->{option}->{$option}=$self->get_query->param($option);
            if ($queryoptions_ref->{$option}{storage} eq "session"){
                $self->{_altered} = 1;
            }
        }
        else {
            $logger->debug("Option $option NOT received via HTTP");
        }
    }
    
    return;
}

sub load_from_session {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;
    my $session = $self->get_session;

    $logger->debug("SessionID:".$session->{ID}) if (defined $session->{ID});

    
    # DBI: "select queryoptions from sessioninfo where sessionid = ?"
    my $queryoptions_rs = $self->{schema}->resultset('Sessioninfo')->single({id => $session->{sid}});

    if ($queryoptions_rs){
      my $queryoptions = $queryoptions_rs->queryoptions;
      $logger->debug("Loaded Queryoptions: $queryoptions");
      my $stored_options_ref = decode_json($queryoptions);

      my $queryoptions_ref = $self->get_option_definition;

      foreach my $option (keys %$queryoptions_ref){
          if ($queryoptions_ref->{$option}->{storage} eq "session"){
              if (defined $stored_options_ref->{$option}){
                  $self->set_option($option,$stored_options_ref->{$option});
              }
          }
          else {
              $self->set_option($option,$queryoptions_ref->{$option}{value});
          }
      }
  }
    
    return $self;
}

sub dump_into_session {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    return unless ($self->{_altered});
    
    my $config  = OpenBib::Config->instance;
    my $session = $self->get_session;
    
    my $queryoptions_rs = $self->{schema}->resultset('Sessioninfo')->single({id => $session->{sid}});
    
    if ($queryoptions_rs){
        $queryoptions_rs->update(
            {
                queryoptions => encode_json($self->get_session_options),
            }
        );
    }
    
    $logger->debug("Dumped Options: ".encode_json($self->get_session_options)." for session $session->{ID}");
    
    return;
}

sub get_options {
    my ($self)=@_;
    
    return $self->{option};
}

sub get_session_options {
    my ($self)=@_;
    
    my $options_ref = {};
    
    my $queryoptions_ref = $self->get_option_definition;
    
    foreach my $option (keys %$queryoptions_ref){
        if ($queryoptions_ref->{$option}->{storage} eq "session"){
            $options_ref->{$option}= $self->get_option($option);
        }
    }
    
    return $options_ref;
}

sub get_session_defaults {
    my ($self)=@_;
    
    my $options_ref = {};
    
    my $queryoptions_ref = $self->get_option_definition;
    
    foreach my $option (keys %$queryoptions_ref){
        if ($queryoptions_ref->{$option}->{storage} eq "session"){
            $options_ref->{$option} = $queryoptions_ref->{$option}->{value};
        }
    }
    
    return $options_ref;
}

sub get_option {
    my ($self,$option)=@_;
    
    return $self->{option}->{$option};
}

sub set_option {
    my ($self,$option,$value)=@_;
    
    $self->{option}->{$option} = $value;
    return;
}

sub get_query {
    my ($self)=@_;
    
    return $self->{_query};
}

sub set_query {
    my ($self,$query)=@_;
    
    $self->{_query} = $query;
    return;
}

sub get_session {
    my ($self)=@_;
    
    return $self->{_session};
}

sub set_session {
    my ($self,$session)=@_;
    
    $self->{_session} = $session;
    return;
}

sub get_option_definition {
    my ($class)=@_;
    
    my $config  = OpenBib::Config->instance;
    
    return $config->{queryoptions};
}

sub initialize_defaults {
    my ($self)=@_;
    
    my $queryoptions_ref = $self->get_option_definition;
    
    foreach my $option (keys %$queryoptions_ref){
        $self->set_option($option,$queryoptions_ref->{$option}{value});
    }
    
    return $self;
}

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
    
    return @cgiparams;
}

sub to_cgi_querystring {
    my ($self,$arg_ref)=@_;

    my @cgiparams = $self->to_cgi_params($arg_ref);
    
    return join(";",@cgiparams);
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    eval {        
        $self->{schema} = OpenBib::Schema::System->connect("DBI:Pg:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},$config->{systemdboptions}) or $logger->error_die($DBI::errstr);

    };

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self->{schema}));
    }
    
    if ($@){
        $logger->fatal("Unable to connect to database $config->{systemdbname}");
    }

    return $self;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    if (!exists $config->{memcached}){
      $logger->debug("No memcached configured");
      return;
    }

    # Verbindung zu Memchached herstellen
    $self->{memc} = new Cache::Memcached($config->{memcached});

    if (!$self->{memc}->set('isalive',1)){
        $logger->fatal("Unable to connect to memcached");
    }

    return;
}

1;
__END__

=head1 NAME

OpenBib::QueryOptions - Objekt zur Behandlung von Recherche-Optionen

=head1 DESCRIPTION

Dieses Singleton Verwaltet die Recherche-Optionen wie num,
offset, Sprache l, Profil profile, Automatische Und-Verknuepfung
autoplus, Such-Backend sb sowie den Trefferlistentyp listtype.

=head1 SYNOPSIS

 use OpenBib::QueryOptions;

 my $queryoptions  = OpenBib::QueryOptions->new;

 my $lang = $queryoptions->get_option('l');

 my $current_options = $queryoptions->get_options;

=head1 METHODS

=over 4

=item instance

Instanziierung des Singleton.

=item load

Einladen der aktuellen QueryOptions der Session.

=item dump

Abspeichern der QueryOptions in der Session

=item get_options

Liefert alle QueryOptions als Hashreferenz

=item get_option($option)

Liefert den Wert der Option $option

=item get_option_definition

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
