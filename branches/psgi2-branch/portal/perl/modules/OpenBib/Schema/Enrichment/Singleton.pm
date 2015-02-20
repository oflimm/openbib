#####################################################################
#
#  OpenBib::Schema::Enrichment::Singleton
#
#  Singleton fuer den Schema-Zugriff
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
#
#  Idee von brian d foy 'The singleton design pattern', The Perl Review
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

package OpenBib::Schema::Enrichment::Singleton;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Class::Singleton);

use OpenBib::Config::File;
use OpenBib::Schema::Enrichment;
use Log::Log4perl qw(get_logger :levels);

sub _new_instance {
    my $class = shift;
    my @args  = @_;

    my $logger = get_logger();
    
    my $self = {};

    bless ($self, $class);
    
    # Ininitalisierung mit Config-Parametern
    my $config = OpenBib::Config::File->instance;

    eval {
        $self->{schema} = OpenBib::Schema::Enrichment->connect("DBI:Pg:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},$config->{enrichmntdboptions}) ;
    };

    if ($@){
        $logger->error("Error connecting to Enrichment-DB");
    }
    
    return $self;
}

sub get_schema {
    my $self = shift;

    return $self->{schema};
}

1;
__END__

=head1 NAME

OpenBib::Schema::Enrichment::Singleton - Singleton zum Spooling von Enrichment-Schemas

=head1 DESCRIPTION

Dieses Singleton kann durch Method-Overriding der connect-Methode des
Schema-Objektes seine DB-Handles spoolen. Dies wird aus Effizienztgründen
für die Systemdatenbanken config, session, enrichmnt, statistics und
user verwendet - nicht jedoch für die Vielzahl an Katalogdatenbanken.

=head1 SYNOPSIS

 use OpenBib::Schema::Enrichment::Singleton;

 my $schema = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};
                 host=$config->{userschemaost};port=$config->{userdbport}",
                 $config->{userdbuser}, $config->{userdbpasswd})
           or $logger->error($DBI::errstr);

=head1 METHODS

=over 4

=item connect

Überschriebene Methode des DBI-Objektes. Entsprechend der übergebenen
Verbindungsparameter werden die Verbindungen in einer
Klassen-Variablen $schema_pool gespoolt.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
