#####################################################################
#
#  OpenBib::Catalog::Backend::DBIS.pm
#
#  Objektorientiertes Interface zum DBIS XML-API
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

package OpenBib::Catalog::Backend::DBIS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Reload;
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

    # Set defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : undef;

    my $client_ip = exists $arg_ref->{client_ip}
        ? $arg_ref->{client_ip}   : undef;

    my $colors    = exists $arg_ref->{colors}
        ? $arg_ref->{colors}      : undef;

    my $ocolors   = exists $arg_ref->{ocolors}
        ? $arg_ref->{ocolors}     : undef;

    my $lang      = exists $arg_ref->{lang}
        ? $arg_ref->{lang}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);

    $logger->debug("Initializing with colors = ".(defined $colors || '')." and ocolors = ".(defined $ocolors | '')." and lang = ".(defined $lang || ''));
    
    $self->{bibid}      = (defined $bibid)?$bibid:(defined $config->{dbis_bibid})?$config->{dbis_bibid}:undef;
    $self->{colors}     = (defined $colors)?$colors:(defined $config->{dbis_colors})?$config->{dbis_colors}:undef;
    $self->{ocolors}    = (defined $ocolors)?$ocolors:(defined $config->{dbis_ocolors})?$config->{dbis_ocolors}:undef;
    $self->{client_ip}  = (defined $client_ip )?$client_ip:undef;
    $self->{lang}       = (defined $lang )?$lang:undef;

    $self->{client}  = LWP::UserAgent->new;            # HTTP client

    return $self;
}

sub get_subjects {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx10.uni-regensburg.de/dbinfo/fachliste.php?colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&bib_id=".((defined $self->{bibid})?$self->{bibid}:"")."&lett=l&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";

    my $subjects_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'utf8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $maxcount=0;
    my $mincount=999999999;

    foreach my $subject_node ($root->findnodes('/dbis_page/list_subjects_collections/list_subjects_collections_item')) {
        my $singlesubject_ref = {} ;

        $singlesubject_ref->{notation}   = $subject_node->findvalue('@notation');
        $singlesubject_ref->{count}      = $subject_node->findvalue('@number');
        $singlesubject_ref->{lett}      = $subject_node->findvalue('@lett');
        $singlesubject_ref->{desc}       = decode_utf8($subject_node->textContent());

        if ($maxcount < $singlesubject_ref->{count}){
            $maxcount = $singlesubject_ref->{count};
        }
        
        if ($mincount > $singlesubject_ref->{count}){
            $mincount = $singlesubject_ref->{count};
        }

        push @{$subjects_ref}, $singlesubject_ref;
    }

    $subjects_ref = OpenBib::Common::Util::gen_cloud_class({
        items => $subjects_ref, 
        min   => $mincount, 
        max   => $maxcount, 
        type  => 'log'});

    $logger->debug(YAML::Dump($subjects_ref));

    return $subjects_ref;
}

sub search_dbs {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fs       = exists $arg_ref->{fs}
        ? $arg_ref->{fs}           : '';

    my $notation = exists $arg_ref->{notation}
        ? $arg_ref->{notation}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($notation){
        $notation="&gebiete[]=$notation";
    }
    
    my $url="http://rzblx10.uni-regensburg.de/dbinfo/dbliste.php?bib_id=usb_k&colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&lett=fs&Suchwort=$fs&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."$notation&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";
    
    my $titles_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $current_page_ref = {};

    $current_page_ref->{term} = $fs;

    foreach my $nav_node ($root->findnodes('/dbis_page/page_vars')) {
        $current_page_ref->{lett}     = $nav_node->findvalue('lett');
        $current_page_ref->{colors}   = $nav_node->findvalue('colors');
        $current_page_ref->{ocolors}  = $nav_node->findvalue('ocolors');
    }
    
    my $subjectinfo_ref = {};

    $subjectinfo_ref->{notation} = $root->findvalue('/dbis_page/page_vars/gebiete');
    $subjectinfo_ref->{desc}     = $root->findvalue('/dbis_page/headline');

    my $access_info_ref = {};

    my @access_info_nodes = $root->findnodes('/dbis_page/list_dbs/db_access_infos/db_access_info');

    foreach my $access_info_node (@access_info_nodes){
        my $id                              = $access_info_node->findvalue('@access_id');
        $access_info_ref->{$id}{icon_url}   = $access_info_node->findvalue('@access_icon');
        $access_info_ref->{$id}{desc_short} = $access_info_node->findvalue('db_access');
        $access_info_ref->{$id}{desc}       = $access_info_node->findvalue('db_access_short_text');
    }

    my $db_type_ref = {};
    my @db_type_nodes = $root->findnodes('/dbis_page/list_dbs/db_type_infos/db_type_info');
    foreach my $db_type_node (@db_type_nodes){
        my $id                          = $db_type_node->findvalue('@db_type_id');
        $db_type_ref->{$id}{desc}       = $db_type_node->findvalue('db_type_long_text');
        $db_type_ref->{$id}{desc_short} = $db_type_node->findvalue('db_type');
        $db_type_ref->{$id}{desc}=~s/\|/<br\/>/g;
    }

    my $db_group_ref             = {};
    my $have_group_ref           = {};
    $db_group_ref->{group_order} = [];
    
    foreach my $db_group_node ($root->findnodes('/dbis_page/list_dbs/dbs')) {
        my $db_type                 = $db_group_node->findvalue('@db_type_ref');
        my $topdb                   = $db_group_node->findvalue('@top_db') || 0;

        $db_type = "topdb" if (!$db_type && $topdb);
        $db_type = "all" if (!$db_type && !$topdb);

        push @{$db_group_ref->{group_order}}, $db_type unless $have_group_ref->{$db_type};
        $have_group_ref->{$db_type} = 1;

        $db_group_ref->{$db_type}{count} = decode_utf8($db_group_node->findvalue('@db_count'));
        $db_group_ref->{$db_type}{dbs} = [];
        
        foreach my $db_node ($db_group_node->findnodes('db')) {
            my $single_db_ref = {};

            $single_db_ref->{id}       = $db_node->findvalue('@title_id');
            $single_db_ref->{access}   = $db_node->findvalue('@access_ref');
            my @types = split(" ",$db_node->findvalue('@db_type_refs'));

            $single_db_ref->{db_types} = \@types;
            $single_db_ref->{title}     = decode_utf8($db_node->textContent);

            push @{$db_group_ref->{$db_type}{dbs}}, $single_db_ref;
        }
    }

    return {
        current_page   => $current_page_ref,
        subject        => $subjectinfo_ref,
        db_groups      => $db_group_ref,
        access_info    => $access_info_ref,
        db_type        => $db_type_ref,
    };
}

sub get_dbs {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $notation = exists $arg_ref->{notation}
        ? $arg_ref->{notation}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx10.uni-regensburg.de/dbinfo/dbliste.php?bib_id=usb_k&colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&lett=f&gebiete=$notation&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";
    
    my $titles_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $current_page_ref = {};
    
    foreach my $nav_node ($root->findnodes('/dbis_page/page_vars')) {
        $current_page_ref->{lett}     = $nav_node->findvalue('lett');
        $current_page_ref->{colors}   = $nav_node->findvalue('colors');
        $current_page_ref->{ocolors}  = $nav_node->findvalue('ocolors');
    }
    
    my $subjectinfo_ref = {};

    $subjectinfo_ref->{notation} = $root->findvalue('/dbis_page/page_vars/gebiete');
    $subjectinfo_ref->{desc}     = $root->findvalue('/dbis_page/headline');

    my $access_info_ref = {};

    my @access_info_nodes = $root->findnodes('/dbis_page/list_dbs/db_access_infos/db_access_info');

    foreach my $access_info_node (@access_info_nodes){
        my $id                              = $access_info_node->findvalue('@access_id');
        $access_info_ref->{$id}{icon_url}   = $access_info_node->findvalue('@access_icon');
        $access_info_ref->{$id}{desc_short} = $access_info_node->findvalue('db_access');
        $access_info_ref->{$id}{desc}       = $access_info_node->findvalue('db_access_short_text');
    }

    my $db_type_ref = {};
    my @db_type_nodes = $root->findnodes('/dbis_page/list_dbs/db_type_infos/db_type_info');
    foreach my $db_type_node (@db_type_nodes){
        my $id                          = $db_type_node->findvalue('@db_type_id');
        $db_type_ref->{$id}{desc}       = $db_type_node->findvalue('db_type_long_text');
        $db_type_ref->{$id}{desc_short} = $db_type_node->findvalue('db_type');
        $db_type_ref->{$id}{desc}=~s/\|/<br\/>/g;
    }

    my $db_group_ref             = {};
    my $have_group_ref           = {};
    $db_group_ref->{group_order} = [];
    
    foreach my $db_group_node ($root->findnodes('/dbis_page/list_dbs/dbs')) {
        my $db_type                 = $db_group_node->findvalue('@db_type_ref');
        my $topdb                   = $db_group_node->findvalue('@top_db') || 0;

        $db_type = "topdb" if (!$db_type && $topdb);
        $db_type = "all" if (!$db_type && !$topdb);

        push @{$db_group_ref->{group_order}}, $db_type unless $have_group_ref->{$db_type};
        $have_group_ref->{$db_type} = 1;

        $db_group_ref->{$db_type}{count} = decode_utf8($db_group_node->findvalue('@db_count'));
        $db_group_ref->{$db_type}{dbs} = [];
        
        foreach my $db_node ($db_group_node->findnodes('db')) {
            my $single_db_ref = {};

            $single_db_ref->{id}       = $db_node->findvalue('@title_id');
            $single_db_ref->{access}   = $db_node->findvalue('@access_ref');
            my @types = split(" ",$db_node->findvalue('@db_type_refs'));

            $single_db_ref->{db_types} = \@types;
            $single_db_ref->{title}     = decode_utf8($db_node->textContent);

            push @{$db_group_ref->{$db_type}{dbs}}, $single_db_ref;
        }
    }

    return {
        subject        => $subjectinfo_ref,
        db_groups      => $db_group_ref,
        access_info    => $access_info_ref,
        db_type        => $db_type_ref,
    };
}

sub get_dbinfo {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx10.uni-regensburg.de/dbinfo/detail.php?colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&lett=f&titel_id=$id&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";

    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');

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
    my $content =  decode_utf8($root->findvalue('/dbis_page/details/content'));
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

    my $appearence  =  decode_utf8($root->findvalue('/ezb_page/ezb_detail_about_db/db/detail/appearence'));

    return {
        id             => $id,
        title          => $title_ref,
        hints          => $hints,
        content        => $content,
        instructions   => $instructions,
        subjects       => $subjects_ref,
        keywords       => $keywords_ref,
        appearence     => $appearence,
        access         => $access_ref,
        access_info    => $access_info_ref,
        db_type        => $db_type_ref,
    };
}

sub get_dbreadme {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/show_readme.phtml?colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&jour_id=$id&xmloutput=1";

    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");

    # Fehlermeldungen im XML entfernen

    $response=~s/^.*?<\?xml/<?xml/smx;

    $logger->debug("gereinigte Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $location =  $root->findvalue('/ezb_page/ezb_readme_page/location');

    return {
        location => $location
    } if ($location);

    my $title    =  decode_utf8($root->findvalue('/ezb_page/ezb_readme_page/db/title'));

    my @periods_nodes =  $root->findnodes('/ezb_page/ezb_readme_page/db/periods/period');

    my $periods_ref = [];

    foreach my $period_node (@periods_nodes){
        my $this_period_ref = {};

        $this_period_ref->{color}       = decode_utf8($period_node->('db_color/@color'));
        $this_period_ref->{label}       = decode_utf8($period_node->('label'));
        $this_period_ref->{readme_link} = decode_utf8($period_node->('readme_link/@url'));
        $this_period_ref->{warpto_link} = decode_utf8($period_node->('warpto_link/@url'));

        $logger->debug(YAML::Dump($this_period_ref));
        push @{$periods_ref}, $this_period_ref;
    }

    return {
        periods  => $periods_ref,
        title    => $title,
    };
}

sub DESTROY {
    my $self = shift;

    return;
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
