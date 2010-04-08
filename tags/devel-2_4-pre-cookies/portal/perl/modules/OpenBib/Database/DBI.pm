#####################################################################
#
#  OpenBib::Database::DBI
#
#  Singleton fuer den DBI-Zugriff
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Database::DBI;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(DBI);
use DBI;
use Log::Log4perl qw(get_logger :levels);
use YAML;

my %dbh_pool = ();

sub connect {
    my $class = shift;
    my @args  = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $args_key = 'dbi_singleton_';
    $args_key   .=unpack "H*",join("_",@args);

    $logger->debug("Args-Key: $args_key");
    
    return $dbh_pool{$args_key} if (defined $dbh_pool{$args_key} and $dbh_pool{$args_key}->ping());
    
    $dbh_pool{$args_key} = DBI->connect(@args);

    $logger->debug("Neuen dbh erzeugt");

    $logger->debug("Alle dbh's: ".YAML::Dump(\%dbh_pool));
    
    return $dbh_pool{$args_key};
}

1;
__END__

=head1 NAME

OpenBib::Database::DBI - Singleton zum Spooling von DB-Handles

=head1 DESCRIPTION

Dieses Singleton kann durch Method-Overriding der connect-Methode des
DBI-Objektes seine DB-Handles spoolen. Dies wird aus Effizienztgründen
für die Systemdatenbanken config, session, enrichmnt, statistics und
user verwendet - nicht jedoch für die Vielzahl an Katalogdatenbanken.

=head1 SYNOPSIS

 use OpenBib::Database::DBI;

 my $dbh = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};
                 host=$config->{userdbhost};port=$config->{userdbport}",
                 $config->{userdbuser}, $config->{userdbpasswd})
           or $logger->error($DBI::errstr);

=head1 METHODS

=over 4

=item connect

Überschriebene Methode des DBI-Objektes. Entsprechend der übergebenen
Verbindungsparameter werden die Verbindungen in einer
Klassen-Variablen $dbh_pool gespoolt.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
