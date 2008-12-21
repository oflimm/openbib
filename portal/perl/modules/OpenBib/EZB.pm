#####################################################################
#
#  OpenBib::EZB.pm
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

package OpenBib::EZB;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

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

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);
    
    $self->{bibid}      = (defined $bibid)?$bibid:(defined $config->{ezb_bibid})?$config->{ezb_bibid}:undef;
    $self->{colors}     = (defined $colors)?$colors:(defined $config->{ezb_colors})?$config->{ezb_colors}:undef;
    $self->{client_ip}  = (defined $client_ip )?$client_ip:undef;

    $self->{client}  = LWP::UserAgent->new;            # HTTP client

    return $self;
}

sub get_subjects {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/fl.phtml?notation=&colors=".((defined $self->{colors})?$self->{colors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&xmloutput=1";

    my $subjects_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    foreach my $subject_node ($root->findnodes('/ezb_page/ezb_subject_list/subject')) {        
        my $singlesubject_ref = {} ;

        $singlesubject_ref->{notation}   = $subject_node->findvalue('@notation');
        $singlesubject_ref->{count}      = $subject_node->findvalue('@journalcount');
        $singlesubject_ref->{desc}       = decode_utf8($subject_node->textContent());

        push @{$subjects_ref}, $singlesubject_ref;
    }

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
        ? $arg_ref->{sindex}       : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx1.uni-regensburg.de/ezeit/fl.phtml?notation=$notation&colors=".((defined $self->{colors})?$self->{colors}:"")."&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&sc=$sc&lc=$lc&sindex=$sindex&xmloutput=1";

    my $titles_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    my $subjectinfo_ref = {};

    $subjectinfo_ref->{notation} = $root->findvalue('/ezb_page/ezb_alphabetical_list/subject/@notation');

    my $nav_ref = [];

    foreach my $nav_node ($root->findnodes('/ezb_page/ezb_alphabetical_list/first_fifty')){
        my $current_nav_ref = {};
        $current_nav_ref->{sc}     = $nav_node->findvalue('@sc');
        $current_nav_ref->{lc}     = $nav_node->findvalue('@lc');
        $current_nav_ref->{sindex} = $nav_node->findvalue('@sindex');
        push @{$nav_ref}, $current_nav_ref;
    }

    foreach my $nav_node ($root->findnodes('/ezb_page/ezb_alphabetical_list/next_fifty')){
        my $current_nav_ref = {};
        $current_nav_ref->{sc}     = $nav_node->findvalue('@sc');
        $current_nav_ref->{lc}     = $nav_node->findvalue('@lc');
        $current_nav_ref->{sindex} = $nav_node->findvalue('@sindex');
        push @{$nav_ref}, $current_nav_ref;
    }
    
    my $alphabetical_nav_ref = [];

    my $current_page_ref = {};
    
    foreach my $nav_node ($root->findnodes('/ezb_page/ezb_alphabetical_list/navlist/current_page')) {        
        $current_page_ref->{desc}   = decode_utf8($nav_node->textContent);
    }

    foreach my $nav_node ($root->findnodes('/ezb_page/page_vars')) {        
        $current_page_ref->{sc}   = $nav_node->findvalue('sc/@value');
        $current_page_ref->{lc}   = $nav_node->findvalue('lc/@value');
        $current_page_ref->{sindex}   = $nav_node->findvalue('sindex/@value');
        $current_page_ref->{sindex}   = $nav_node->findvalue('sindex/@value');
    }

    my @nav_nodes = $root->findnodes('/ezb_page/ezb_alphabetical_list/navlist');
    foreach my $this_node ($nav_nodes[0]->childNodes){
        my $singlenav_ref = {} ;

        $logger->debug($this_node->toString);
        $singlenav_ref->{sc}   = $this_node->findvalue('@sc');
        $singlenav_ref->{lc}   = $this_node->findvalue('@lc');
        $singlenav_ref->{desc} = $this_node->textContent;

        push @{$alphabetical_nav_ref}, $singlenav_ref if ($singlenav_ref->{desc});
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

sub DESTROY {
    my $self = shift;

    return;
}


1;
