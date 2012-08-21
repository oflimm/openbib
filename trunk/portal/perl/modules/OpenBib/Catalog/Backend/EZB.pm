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

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : undef;

    my $client_ip = exists $arg_ref->{client_ip}
        ? $arg_ref->{client_ip}   : undef;

    my $colors    = exists $arg_ref->{colors}
        ? $arg_ref->{colors}      : undef;

    my $lang      = exists $arg_ref->{lang}
        ? $arg_ref->{lang}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);

    $logger->debug("Initializing with colors = ".(defined $colors || '')." and lang = ".(defined $lang || ''));

    $self->{bibid}      = (defined $bibid)?$bibid:(defined $config->{ezb_bibid})?$config->{ezb_bibid}:undef;
    $self->{colors}     = (defined $colors)?$colors:(defined $config->{ezb_colors})?$config->{ezb_colors}:undef;
    $self->{client_ip}  = (defined $client_ip )?$client_ip:undef;
    $self->{lang}       = (defined $lang )?$lang:undef;

    $self->{client}     = LWP::UserAgent->new;            # HTTP client

    return $self;
}

sub get_subjects {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/fl.phtml?notation=&colors=".((defined $self->{colors})?$self->{colors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";

    my $subjects_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->content; # decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $maxcount=0;
    my $mincount=999999999;

    foreach my $subject_node ($root->findnodes('/ezb_page/ezb_subject_list/subject')) {
        my $singlesubject_ref = {} ;

        $singlesubject_ref->{notation}   = $subject_node->findvalue('@notation');
        $singlesubject_ref->{count}      = $subject_node->findvalue('@journalcount');
        $singlesubject_ref->{desc}       = $subject_node->textContent();

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

sub get_journals {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $notation = exists $arg_ref->{notation}
        ? $arg_ref->{notation}     : '';

    my $sc       = exists $arg_ref->{sc}
        ? $arg_ref->{sc}           : '';
    
    my $lc       = exists $arg_ref->{lc}
        ? $arg_ref->{lc}           : '';

    my $sindex   = exists $arg_ref->{sindex}
        ? $arg_ref->{sindex}       : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/fl.phtml?notation=$notation&colors=".((defined $self->{colors})?$self->{colors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&sc=$sc&lc=$lc&sindex=$sindex&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";
    
    my $titles_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->content; # decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $current_page_ref = {};
    
    foreach my $nav_node ($root->findnodes('/ezb_page/page_vars')) {        
        $current_page_ref->{sc}   = $nav_node->findvalue('sc/@value');
        $current_page_ref->{lc}   = $nav_node->findvalue('lc/@value');
        $current_page_ref->{sindex}   = $nav_node->findvalue('sindex/@value');
        $current_page_ref->{sindex}   = $nav_node->findvalue('sindex/@value');
    }
    
    my $subjectinfo_ref = {};

    $subjectinfo_ref->{notation} = decode_utf8($root->findvalue('/ezb_page/ezb_alphabetical_list/subject/@notation'));
    $subjectinfo_ref->{desc}     = decode_utf8($root->findvalue('/ezb_page/ezb_alphabetical_list/subject'));

    my $nav_ref = [];

    my @first_nodes = $root->findnodes('/ezb_page/ezb_alphabetical_list/first_fifty');
    if (@first_nodes){
        foreach my $nav_node (@first_nodes){
            my $current_nav_ref = {};
            $current_nav_ref->{sc}     = $nav_node->findvalue('@sc');
            $current_nav_ref->{lc}     = $nav_node->findvalue('@lc');
            $current_nav_ref->{sindex} = $nav_node->findvalue('@sindex');
            push @{$nav_ref}, $current_nav_ref;
        }
        push @{$nav_ref}, {
            sc     => $current_page_ref->{sc},
            lc     => $current_page_ref->{lc},
            sindex => $current_page_ref->{sindex},
        };

    }
    else {
        push @{$nav_ref}, {
            sc     => $current_page_ref->{sc},
            lc     => $current_page_ref->{lc},
            sindex => $current_page_ref->{sindex},
        };
    }

    my @next_nodes = $root->findnodes('/ezb_page/ezb_alphabetical_list/next_fifty');
    if (@next_nodes){
        foreach my $nav_node (@next_nodes){
            my $current_nav_ref = {};
            $current_nav_ref->{sc}     = $nav_node->findvalue('@sc');
            $current_nav_ref->{lc}     = $nav_node->findvalue('@lc');
            $current_nav_ref->{sindex} = $nav_node->findvalue('@sindex');
            push @{$nav_ref}, $current_nav_ref;
        }
    }

    my $alphabetical_nav_ref = [];

    foreach my $nav_node ($root->findnodes('/ezb_page/ezb_alphabetical_list/navlist/current_page')) {        
        $current_page_ref->{desc}   = decode_utf8($nav_node->textContent);
    }

    my @nav_nodes = $root->findnodes('/ezb_page/ezb_alphabetical_list/navlist');
    if (@nav_nodes){
        foreach my $this_node ($nav_nodes[0]->childNodes){
            my $singlenav_ref = {} ;
            
            $logger->debug($this_node->toString);
            $singlenav_ref->{sc}   = $this_node->findvalue('@sc');
            $singlenav_ref->{lc}   = $this_node->findvalue('@lc');
            $singlenav_ref->{desc} = $this_node->textContent;
            
            push @{$alphabetical_nav_ref}, $singlenav_ref if ($singlenav_ref->{desc} && $singlenav_ref->{desc} ne "\n");
        }
    }
    my $journals_ref = [];

    foreach my $journal_node ($root->findnodes('/ezb_page/ezb_alphabetical_list/alphabetical_order/journals/journal')) {
        
        my $singlejournal_ref = {} ;
        
        $singlejournal_ref->{id}          = $journal_node->findvalue('@jourid');
        $singlejournal_ref->{title}       = decode_utf8($journal_node->findvalue('title'));
        $singlejournal_ref->{color}{code} = $journal_node->findvalue('journal_color/@color_code');
        $singlejournal_ref->{color}{desc} = $journal_node->findvalue('journal_color/@color');

        push @{$journals_ref}, $singlejournal_ref;
    }

    return {
        nav            => $nav_ref,
        subject        => $subjectinfo_ref,
        journals       => $journals_ref,
        current_page   => $current_page_ref,
        other_pages    => $alphabetical_nav_ref,
    };
}

sub search_journals {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fs       = exists $arg_ref->{fs}
        ? $arg_ref->{fs}           : '';

    my $notation = exists $arg_ref->{notation}
        ? $arg_ref->{notation}     : '';

    my $sc       = exists $arg_ref->{sc}
        ? $arg_ref->{sc}           : '';
    
    my $lc       = exists $arg_ref->{lc}
        ? $arg_ref->{lc}           : '';

    my $sindex   = exists $arg_ref->{sindex}
        ? $arg_ref->{sindex}       : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/searchres.phtml?colors=".((defined $self->{colors})?$self->{colors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&sc=$sc&lc=$lc&sindex=$sindex&jq_type1=KT&jq_term1=$fs&Notations[]=$notation&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";
#    my $url="http://rzblx1.uni-regensburg.de/ezeit/searchres.phtml?bibid=USBK&colors=7&lang=de&jq_type1=KT&jq_term1=review&jq_bool2=AND&jq_not2=+&jq_type2=KS&jq_term2=&jq_bool3=AND&jq_not3=+&jq_type3=PU&jq_term3=&jq_bool4=AND&jq_not4=+&jq_type4=IS&jq_term4=&offset=-1&hits_per_page=50&search_journal=Suche+starten&Notations[]=AZ&colors=3&xmloutput=1";
    my $titles_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->content; # decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $current_page_ref = {};
    
    foreach my $nav_node ($root->findnodes('/ezb_page/page_vars')) {        
        $current_page_ref->{sc}   = $nav_node->findvalue('sc/@value');
        $current_page_ref->{lc}   = $nav_node->findvalue('lc/@value');
        $current_page_ref->{sindex}   = $nav_node->findvalue('sindex/@value');
        $current_page_ref->{sindex}   = $nav_node->findvalue('sindex/@value');
        $current_page_ref->{category} = $nav_node->findvalue('jq_type1/@value');
        $current_page_ref->{term}     = $nav_node->findvalue('jq_term1/@value');
        $current_page_ref->{hits_per_page}     = $nav_node->findvalue('hits_per_page/@value');
    }

    my $search_count = $root->findvalue('/ezb_page/ezb_alphabetical_list_searchresult/search_count');
    
    my $nav_ref = [];
    
    my @first_nodes = $root->findnodes('/ezb_page/ezb_alphabetical_list_searchresult/first_fifty');
    if (@first_nodes){
        foreach my $nav_node (@first_nodes){
            my $current_nav_ref = {};
            $current_nav_ref->{sc}     = $nav_node->findvalue('@sc');
            $current_nav_ref->{lc}     = $nav_node->findvalue('@lc');
            $current_nav_ref->{sindex} = $nav_node->findvalue('@sindex');
            push @{$nav_ref}, $current_nav_ref;
        }
        push @{$nav_ref}, {
            sc     => $current_page_ref->{sc},
            lc     => $current_page_ref->{lc},
            sindex => $current_page_ref->{sindex},
        };

    }
    else {
        push @{$nav_ref}, {
            sc     => $current_page_ref->{sc},
            lc     => $current_page_ref->{lc},
            sindex => $current_page_ref->{sindex},
        };
    }

    my @next_nodes = $root->findnodes('/ezb_page/ezb_alphabetical_list_searchresult/next_fifty');
    if (@next_nodes){
        foreach my $nav_node (@next_nodes){
            my $current_nav_ref = {};
            $current_nav_ref->{sc}     = $nav_node->findvalue('@sc');
            $current_nav_ref->{lc}     = $nav_node->findvalue('@lc');
            $current_nav_ref->{sindex} = $nav_node->findvalue('@sindex');
            push @{$nav_ref}, $current_nav_ref;
        }
    }

    my $alphabetical_nav_ref = [];

    foreach my $nav_node ($root->findnodes('/ezb_page/ezb_alphabetical_list_searchresult/navlist/current_page')) {        
        $current_page_ref->{desc}   = decode_utf8($nav_node->textContent);
    }

    my @nav_nodes = $root->findnodes('/ezb_page/ezb_alphabetical_list_searchresult/navlist');
    if ( @nav_nodes){
        foreach my $this_node ($nav_nodes[0]->childNodes){
            my $singlenav_ref = {} ;
            
            $logger->debug($this_node->toString);
            $singlenav_ref->{sc}   = $this_node->findvalue('@sc');
            $singlenav_ref->{lc}   = $this_node->findvalue('@lc');
            $singlenav_ref->{desc} = $this_node->textContent;
            
            push @{$alphabetical_nav_ref}, $singlenav_ref if ($singlenav_ref->{desc} && $singlenav_ref->{desc} ne "\n");
        }
    }

    my $journals_ref = [];

    foreach my $journal_node ($root->findnodes('/ezb_page/ezb_alphabetical_list_searchresult/alphabetical_order/journals/journal')) {
        
        my $singlejournal_ref = {} ;
        
        $singlejournal_ref->{id}          = $journal_node->findvalue('@jourid');
        $singlejournal_ref->{title}       = decode_utf8($journal_node->findvalue('title'));
        $singlejournal_ref->{color}{code} = $journal_node->findvalue('journal_color/@color_code');
        $singlejournal_ref->{color}{desc} = $journal_node->findvalue('journal_color/@color');

        push @{$journals_ref}, $singlejournal_ref;
    }

    return {
        search_count   => $search_count,
        nav            => $nav_ref,
        journals       => $journals_ref,
        current_page   => $current_page_ref,
        other_pages    => $alphabetical_nav_ref,
    };
}

sub get_journalinfo {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/detail.phtml?colors=".((defined $self->{colors})?$self->{colors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&jour_id=$id&xmloutput=1";

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

    my @subjects_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/subjects/subject');

    my $subjects_ref = [];

    foreach my $subject_node (@subjects_nodes){
        push @{$subjects_ref}, decode_utf8($subject_node->textContent);
    }

    my @keywords_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/keywords/keyword');

    my $keywords_ref = [];

    foreach my $keyword_node (@keywords_nodes){
        push @{$keywords_ref}, decode_utf8($keyword_node->textContent);
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

    return {
        id             => $id,
        title          => $title,
        publisher      => $publisher,
        ZDB_number     => $zdb_node_ref,
        subjects       => $subjects_ref,
        keywords       => $keywords_ref,
        firstvolume    => $firstvolume,
        firstdate      => $firstdate,
        appearence     => $appearence,
        costs          => $costs,
        homepages      => $homepages_ref,
        remarks        => $remarks,
    };
}

sub get_journalreadme {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/show_readme.phtml?colors=".((defined $self->{colors})?$self->{colors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&jour_id=$id&xmloutput=1";

    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->content; # decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");

    # Fehlermeldungen im XML entfernen

    $response=~s/^.*?<\?xml/<?xml/smx;

    $logger->debug("gereinigte Response: $response");
    
    my $parser = XML::LibXML->new();
    $parser->recover(1);
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $location =  $root->findvalue('/ezb_page/ezb_readme_page/location');

    if ($location){
        # Lokaler Link in der EZB
        unless ($location=~m/^http/){
            $location="http://rzblx1.uni-regensburg.de/ezeit/$location";
        }
        
        return {
            location => $location
        };
    }

    my $title    =  decode_utf8($root->findvalue('/ezb_page/ezb_readme_page/journal/title'));

    my @periods_nodes =  $root->findnodes('/ezb_page/ezb_readme_page/journal/periods/period');

    my $periods_ref = [];

    foreach my $period_node (@periods_nodes){
        my $this_period_ref = {};

        $this_period_ref->{color}       = decode_utf8($period_node->findvalue('journal_color/@color'));
        $this_period_ref->{label}       = decode_utf8($period_node->findvalue('label'));
        $this_period_ref->{readme_link} = decode_utf8($period_node->findvalue('readme_link/@url'));
        $this_period_ref->{warpto_link} = decode_utf8($period_node->findvalue('warpto_link/@url'));

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
