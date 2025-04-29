#####################################################################
#
#  OpenBib::Catalog::Backend::EZB.pm
#
#  Objektorientiertes Interface zum EZB XML-API
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

package OpenBib::Catalog::Backend::EZB;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode qw(decode decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use URI::Escape;
use XML::LibXML;
use YAML ();
use Mojo::Base -strict, -signatures;

use OpenBib::API::HTTP::EZB;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $api = new OpenBib::API::HTTP::EZB($arg_ref);
    
    my $self = { };

    bless ($self, $class);

    $self->{api} = $api;
    
    return $self;
}

1;
__END__

=head1 NAME

OpenBib::EZB - Objektorientiertes Interface zum EZB XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API der
Elektronischen Zeitschriftenbibliothek (EZB) in Regensburg zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::DBIS;

 my $dbis = OpenBib::EZB->new({});

=head1 METHODS

=over 4

=item new({ bibid => $bibid, client_ip => $client_ip, colors => $colors, lang => $lang })

Erzeugung des EZB Objektes. Dabei wird die EZB-Kennung $bibid der
Bibliothek, die IP des aufrufenden Clients (zur Statistik), die
Sprachversion lang, sowie die Spezifikation der gewünschten
Zugriffsbedingungen color benötigt.

=item get_subjects

Liefert eine Listenreferenz der vorhandenen Fachgruppen zurück mit
einer Hashreferenz auf die jeweilige Notation notation, der
Datenbankanzahl count sowie der Beschreibung der Fachgruppe
desc. Zusätzlich werden für eine Wolkenanzeige die entsprechenden
Klasseninformationen hinzugefügt.

=item search_journals({ fs => $fs, notation => $notation,  sc => $sc, lc => $lc, sindex => $sindex })

Stellt die Suchanfrage $fs - optional eingeschränkt auf die Fachgruppe
$notation - an die EZB und liefert als Ergebnis verschiedene
Informatinen als Hashreferenz zurück. Weitere
Einschränkungsmöglichkeiten sind sc, lc und sindex.

Es sind dies die Informationen über die Ergebnisanzahl search_count,
die Navigation nav, die Fachgruppe subject, die Zeitschriften
journals, die aktuellen Einstellungen current_page sowie weitere
verfügbare Seiten other_pages.

=item get_journals({ notation => $notation, sc => $sc, lc => $lc, sindex => $sindex })

Liefert eine Liste mit Informationen über alle Zeitschriften der
Fachgruppe $notation aus der EZB als Hashreferenz zurück.

Es sind dies die Informationen über die Navigation nav, die Fachgruppe
subject, die Zeitschriften journals, die aktuellen Einstellungen
current_page sowie weitere verfügbare Seiten other_pages.

=item get_journalinfo({ id => $id })

Liefert Informationen über die Zeitschrift mit der Id $id als
Hashreferenz zurück. Es sind dies neben der Id $id auch Informationen
über den Titel title, publisher, ZDB_number, subjects, keywords, firstvolume, firstdate, appearence, costs, homepages sowie remarks.

=item get_journalreadme({ id => $id })

Liefert zur Zeitschriftk mit der Id $id generelle Nutzungsinformationen
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
