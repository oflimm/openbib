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

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;
    
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

    my $access_national        = exists $arg_ref->{access_national}
        ? $arg_ref->{access_national}         : 0;
    
    my $colors  = $access_green + $access_yellow*44;
    my $ocolors = $access_red*8 + $access_national*32;

    # Wenn keine Parameter uebergeben wurden, dann Defaults nehmen
    if (!$colors && !$ocolors){
        $logger->debug("Using defaults for color and ocolor");

        $colors  = $config->{dbis_colors};
        $ocolors = $config->{dbis_ocolors};

        my $colors_mask  = OpenBib::Common::Util::dec2bin($colors);
        my $ocolors_mask = OpenBib::Common::Util::dec2bin($ocolors);
        
        $access_red      = ($ocolors_mask & 0b001000)?1:0;
        $access_national = ($ocolors_mask & 0b100000)?1:0;
        $access_green    = ($colors_mask  & 0b000001)?1:0;
        $access_yellow   = ($colors_mask  & 0b101100)?1:0;
    }
    else {
        $logger->debug("Using CGI values for color and ocolor");
    }
    
    my $self = { };

    bless ($self, $class);

    $self->{database}      = $database;
    $self->{client}        = LWP::UserAgent->new;            # HTTP client

    # Backend Specific Attributes
    $self->{access_green}    = $access_green;
    $self->{access_yellow}   = $access_yellow;
    $self->{access_red}      = $access_red;
    $self->{access_national} = $access_national;
    $self->{bibid}           = $bibid;
    $self->{lang}            = $lang if ($lang);
    $self->{colors}          = $colors if ($colors);
    
    return $self;
}

sub load_full_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    my $url="http://rzblx10.uni-regensburg.de/dbinfo/detail.php?colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&lett=f&titel_id=$id&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";

    $logger->debug("Request: $url");

    #    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');
    my $response = $self->{client}->get($url)->decoded_content(charset => 'utf8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $access_info_ref = {};
    
    $access_info_ref->{icon_url}   = $root->findvalue('/dbis_page/details/db_access_info/@access_icon');
    $access_info_ref->{desc}       = $root->findvalue('/dbis_page/details/db_access_info/db_access');
    $access_info_ref->{desc_short} = $root->findvalue('/dbis_page/details/db_access_info/db_access_short_text');
    
    my $db_type_ref = [];
    my @db_type_nodes = $root->findnodes('/dbis_page/list_dbs/db_type_infos/db_type_info');
    foreach my $db_type_node (@db_type_nodes){
        my $this_db_type_ref = {};
        $this_db_type_ref->{desc}       = $db_type_node->findvalue('db_type_long_text');
        $this_db_type_ref->{desc_short} = $db_type_node->findvalue('db_type');
        $this_db_type_ref->{desc}=~s/\|/<br\/>/g;
        push @$db_type_ref, $this_db_type_ref;
    }

    my @title_nodes = $root->findnodes('/dbis_page/details/titles/title');

    my $title_ref = {};
    $title_ref->{other} = [];

    foreach my $this_node (@title_nodes){
        $title_ref->{main}     =  decode_utf8($this_node->textContent) if ($this_node->findvalue('@main') eq "Y");
        push @{$title_ref->{other}}, decode_utf8($this_node->textContent) if ($this_node->findvalue('@main') eq "N");
    }

    my $access_ref = {};
    $access_ref->{other} = [];

    my @access_nodes = $root->findnodes('/dbis_page/details/accesses/access');

    foreach my $this_node (@access_nodes){
        $access_ref->{main}     =  decode_utf8($this_node->findvalue('@href')) if ($this_node->findvalue('@main') eq "Y");
        push @{$access_ref->{other}}, decode_utf8($this_node->findvalue('@href')) if ($this_node->findvalue('@main') eq "N");
    }
    
    my $hints   =  decode_utf8($root->findvalue('/dbis_page/details/hints'));
    my $content =  $root->findvalue('/dbis_page/details/content');
    my $instructions =  decode_utf8($root->findvalue('/dbis_page/details/instructions'));

    my @subjects_nodes =  $root->findnodes('/dbis_page/details/subjects/subject');

    my $subjects_ref = [];

    foreach my $subject_node (@subjects_nodes){
        push @{$subjects_ref}, decode_utf8($subject_node->textContent);
    }

    my @keywords_nodes =  $root->findnodes('/dbis_page/details/keywords/keyword');

    my $keywords_ref = [];

    foreach my $keyword_node (@keywords_nodes){
        push @{$keywords_ref}, decode_utf8($keyword_node->textContent);
    }

    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });

    $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $title_ref->{main}}) if ($title_ref->{main});

    my $mult=1;
    if (defined $title_ref->{other}){
        foreach my $othertitle (@{$title_ref->{other}}){
            $record->set_field({field => 'T0370', subfield => '', mult => $mult, content => $othertitle});
            $mult++;
        }
    }

    $mult=1;
    if (defined $access_ref->{main}){
        $record->set_field({field => 'T0662', subfield => '', mult => $mult, content => $config->{dbis_baseurl}.$access_ref->{main}}) if ($access_ref->{main});
        $mult++;
    }

    if (defined $access_ref->{other}){
        foreach my $access (@{$access_ref->{other}}){
            $record->set_field({field => 'T0662', subfield => '', mult => $mult, content => $config->{dbis_baseurl}.$access }) if ($access);
            $mult++;
        }
    }
    
    $mult=1;
    foreach my $subject (@$subjects_ref){
        $record->set_field({field => 'T0700', subfield => '', mult => $mult, content => $subject});
        $mult++;
    }

    $mult=1;
    foreach my $keyword (@$keywords_ref){
        $record->set_field({field => 'T0710', subfield => '', mult => $mult, content => $keyword});
        $mult++;
    }
    
    $record->set_field({field => 'T0750', subfield => '', mult => 1, content => $content}) if ($content);

    $mult=1;
    if ($access_info_ref->{desc_short}){
        $record->set_field({field => 'T0501', subfield => '', mult => $mult, content => $access_info_ref->{desc_short}});
        $mult++;
    }

    $record->set_field({field => 'T0501', subfield => '', mult => $mult, content => $instructions}) if ($instructions);

    $record->set_holding([]);
    $record->set_circulation([]);

    return $record;
}

sub load_brief_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->load_full_title_record($arg_ref);
}

sub get_classifications {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx10.uni-regensburg.de/dbinfo/fachliste.php?colors=$self->{colors}&ocolors=$self->{ocolors}&bib_id=$self->{dbis_bibid}&lett=l&lang=$self->{lang}&xmloutput=1";

    my $classifications_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'utf8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $maxcount=0;
    my $mincount=999999999;

    foreach my $classification_node ($root->findnodes('/dbis_page/list_subjects_collections/list_subjects_collections_item')) {
        my $singleclassification_ref = {} ;

        $singleclassification_ref->{name}    = $classification_node->findvalue('@notation');
        $singleclassification_ref->{count}   = $classification_node->findvalue('@number');
        #$singleclassification_ref->{lett}    = $classification_node->findvalue('@lett');
        $singleclassification_ref->{desc}    = decode_utf8($classification_node->textContent());

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

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($classifications_ref));
    }

    return $classifications_ref;
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
