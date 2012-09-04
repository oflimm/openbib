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

use Apache2::Reload;
use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode qw(decode decode_utf8);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Set defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : $config->{ezb_bibid};

    my $client_ip = exists $arg_ref->{client_ip}
        ? $arg_ref->{client_ip}   : undef;

    my $lang      = exists $arg_ref->{l}
        ? $arg_ref->{l}           : undef;

    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}         : undef;

    my $access_green           = exists $arg_ref->{access_green}
        ? $arg_ref->{access_green}            : 0;

    my $access_yellow          = exists $arg_ref->{access_yellow}
        ? $arg_ref->{access_yellow}           : 0;

    my $access_red             = exists $arg_ref->{access_red}
        ? $arg_ref->{access_red}              : 0;

    my $colors = $access_green + $access_yellow*2 + $access_red*4;

    if (!$colors){
        $colors=$config->{ezb_colors};

        my $colors_mask  = dec2bin($colors);

        $logger->debug("Access: mask($colors_mask)");
        
        $access_green  = ($colors_mask & 0b001)?1:0;
        $access_yellow = ($colors_mask & 0b010)?1:0;
        $access_red    = ($colors_mask & 0b100)?1:0;
    }
    
    my $self = { };

    bless ($self, $class);

    $self->{database}      = $database;
    $self->{client}        = LWP::UserAgent->new;            # HTTP client

    # Backend Specific Attributes
    $self->{access_green}  = $access_green;
    $self->{access_yellow} = $access_yellow;
    $self->{access_red}    = $access_red;
    $self->{bibid}         = $bibid;
    $self->{lang}          = $lang if ($lang);
    $self->{colors}        = $colors if ($colors);
    
    return $self;
}

sub get_classifications {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $url="http://rzblx1.uni-regensburg.de/ezeit/fl.phtml?colors=$self->{colors}&bibid=$self->{bibid}&lang=$self->{lang}&xmloutput=1";

    my $classifications_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->content; # decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $maxcount=0;
    my $mincount=999999999;

    foreach my $classification_node ($root->findnodes('/ezb_page/ezb_subject_list/subject')) {
        my $singleclassification_ref = {} ;

        $singleclassification_ref->{name}       = $classification_node->findvalue('@notation');
        $singleclassification_ref->{count}      = $classification_node->findvalue('@journalcount');
        $singleclassification_ref->{desc}       = $classification_node->textContent();

        if ($maxcount < $singleclassification_ref->{count}){
            $maxcount = $singleclassification_ref->{count};
        }
        
        if ($mincount > $singleclassification_ref->{count}){
            $mincount = $singleclassification_ref->{count};
        }
        
        push @{$classifications_ref}, $singleclassification_ref;
    }

    $classifications_ref = OpenBib::Common::Util::gen_cloud_class({
        items => $classifications_ref, 
        min   => $mincount, 
        max   => $maxcount, 
        type  => 'log'});
    
    $logger->debug(YAML::Dump($classifications_ref));

    return $classifications_ref;
}


sub load_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $url="http://rzblx1.uni-regensburg.de/ezeit/detail.phtml?colors=".((defined $arg_ref->{colors})?$arg_ref->{colors}:$config->{ezb_colors})."&bibid=".((defined $arg_ref->{bibid})?$arg_ref->{bibid}:$config->{ezb_bibid})."&lang=".((defined $arg_ref->{lang})?$arg_ref->{lang}:"de")."&jour_id=$id&xmloutput=1";

    my $titles_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->content; # decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $title     =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_journal/journal/title'));
    my $publisher =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/publisher'));
    my @zdb_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/ZDB_number');

    my $zdb_node_ref = {};
    
    foreach my $zdb_node (@zdb_nodes){
        $zdb_node_ref->{ZDB_number}{url} = $zdb_node->findvalue('@url');
        $zdb_node_ref->{ZDB_number}{content} = decode_utf8($zdb_node->textContent);
    }

    my @classifications_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/subjects/subject');

    my $classifications_ref = [];

    foreach my $classification_node (@classifications_nodes){
        push @{$classifications_ref}, decode_utf8($classification_node->textContent);
    }

    my @subjects_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/keywords/keyword');

    my $subjects_ref = [];

    foreach my $subject_node (@subjects_nodes){
        push @{$subjects_ref}, decode_utf8($subject_node->textContent);
    }

    my @homepages_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/hompages/homepage');

    my $homepages_ref = [];

    foreach my $homepage_node (@homepages_nodes){
        push @{$homepages_ref}, decode_utf8($homepage_node->textContent);
    }
    
    my $firstvolume =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/first_fulltext_issue/first_volume'));
    my $firstdate   =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/first_fulltext_issue/first_date'));
    my $appearence  =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/appearence'));
    my $costs       =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/costs'));
    my $remarks     =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/remarks'));

    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });

    $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $title}) if ($title);
    $record->set_field({field => 'T0412', subfield => '', mult => 1, content => $publisher}) if ($publisher);

    $record->set_field({field => 'T0662', subfield => '', mult => 1, content => $zdb_node_ref->{ZDB_number}{url}}) if ($zdb_node_ref->{ZDB_number}{url});
    $record->set_field({field => 'T0663', subfield => '', mult => 1, content => $zdb_node_ref->{ZDB_number}{content}}) if ($zdb_node_ref->{ZDB_number}{content});

    my $mult=1;
    foreach my $classification (@$classifications_ref){
        $record->set_field({field => 'T0700', subfield => '', mult => $mult, content => $classification});
        $mult++;
    }

    $mult=1;
    foreach my $subject (@$subjects_ref){
        $record->set_field({field => 'T0710', subfield => '', mult => $mult, content => $subject});
        $mult++;
    }
    
    $record->set_field({field => 'T0523', subfield => '', mult => 1, content => $appearence}) if ($appearence);
    $record->set_field({field => 'T0511', subfield => '', mult => 1, content => $costs}) if ($costs);
    $record->set_field({field => 'T0501', subfield => '', mult => 1, content => $remarks}) if ($remarks);

    foreach my $homepage (@$homepages_ref){
        $record->set_field({field => 'T2662', subfield => '', mult => 1, content => $homepage});
    }
    
    return $record;
}


sub DESTROY {
    my $self = shift;

    return;
}

sub dec2bin {
    my $str = unpack("B32", pack("N", shift));
    $str =~ s/^0+(?=\d)//;   # strip leading zeroes
    return $str;
}
sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
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

 my $dbis = OpenBib::DBIS->new({});

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
