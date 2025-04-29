#####################################################################
#
#  OpenBib::Catalog::Backend::DBIS.pm
#
#  Objektorientiertes Interface zum DBIS XML-API
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Catalog::Backend::DBIS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();
use Mojo::Base -strict, -signatures;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::API::HTTP::DBIS;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $api = new OpenBib::API::HTTP::DBIS($arg_ref);
    
    my $self = { };

    bless ($self, $class);

    $self->{api} = $api;
    
    return $self;
}


1;
__END__

=head1 NAME

OpenBib::DBIS - Objektorientiertes Interface zum DBIS XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API des
Datenbankinformationssystems (DBIS) in Regensburg zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::DBIS;

 my $dbis = OpenBib::DBIS->new({});

=head1 METHODS

=over 4

=item new({ bibid => $bibid, client_ip => $client_ip, colors => $colors, ocolors => $ocolors, lang => $lang })

Erzeugung des DBIS Objektes. Dabei wird die DBIS-Kennung $bibid der
Bibliothek, die IP des aufrufenden Clients (zur Statistik), die
Sprachversion lang, sowie die Spezifikation der gewünschten
Zugriffsbedingungen color und ocolor benötigt.

=item get_subjects

Liefert eine Listenreferenz der vorhandenen Fachgruppen zurück mit
einer Hashreferenz auf die jeweilige Notation notation, der
Datenbankanzahl count, des Anfangbuchstabens lett sowie der
Beschreibung der Fachgruppe desc. Zusätzlich werden für eine
Wolkenanzeige die entsprechenden Klasseninformationen hinzugefügt.

=item search_dbs({ fs => $fs, notation => $notation })

Stellt die Suchanfrage $fs - optional eingeschränkt auf die Fachgruppe
$notation - an DBIS und liefert als Ergebnis verschiedene Informatinen
als Hashreferenz zurück.

Es sind dies die Informationen über die aktuelle Ergebnisseite
current_page (mit lett, colors, ocolors), die Fachgruppe subject, die
Kategorisierung von Datenbanken db_groups, die Zugriffsbedingungen
access_info sowie die jeweiligen Datenbanktypen db_type.

=item get_dbs({ notation => $notation, fs => $fs, lett => $lett, sc => $sc, lc => $lc, sindex => $sindex })

Liefert eine Liste mit Informationen über alle Datenbanken der
Fachgruppe $notation aus DBIS als Hashreferenz zurück.

Es sind dies die Informationen über die Fachgruppe subject, die
Kategorisierung von Datenbanken db_groups, die Zugriffsbedingungen
access_info sowie die jeweiligen Datenbanktypen db_type.

=item get_dbinfo({ id => $id })

Liefert Informationen über die Datenbank mit der Id $id als
Hashreferenz zurück. Es sind dies neben der Id $id auch Informationen
über den Titel title, hints, content, instructions, subjects,
keywords, appearance, access, access_info sowie db_type.

=item get_dbreadme({ id => $id })

Liefert zur Datenbank mit der Id $id generelle Nutzungsinformationen
als Hashreferenz zurück. Neben dem Titel title sind das Informationen
periods (color, label, readme_link, warpto_link) über alle
verschiedenen Zeiträume.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
