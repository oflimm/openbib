#####################################################################
#
#  OpenBib::Schema::Catalog::Singleton
#
#  Singleton fuer den Schema-Zugriff
#
#  Dieses File ist (C) 2008-2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Schema::Catalog::Singleton;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::Schema::Catalog);
use OpenBib::Schema::Catalog;
use Log::Log4perl qw(get_logger :levels);
use YAML;

my %schema_pool = ();

sub connect {
    my $class = shift;
    my @args  = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $args_key = 'schema_catalog_singleton_';
    $args_key   .=unpack "H*",join("_",@args);

    $logger->debug("Args-Key: $args_key");
    
    return $schema_pool{$args_key} if (defined $schema_pool{$args_key});
    
    $schema_pool{$args_key} = OpenBib::Schema::Catalog->connect(@args);

    $logger->debug("Neues schema erzeugt");

    return $schema_pool{$args_key};
}

1;
__END__

=head1 NAME

OpenBib::Schema::DBI - Singleton zum Spooling von DB-Handles

=head1 DESCRIPTION

Dieses Singleton kann durch Method-Overriding der connect-Methode des
DBI-Objektes seine DB-Handles spoolen. Dies wird aus Effizienztgründen
für die Systemdatenbanken config, session, enrichmnt, statistics und
user verwendet - nicht jedoch für die Vielzahl an Katalogdatenbanken.

=head1 SYNOPSIS

 use OpenBib::Schema::DBI;

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
