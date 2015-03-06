#####################################################################
#
#  OpenBib::Search::Backend::EZB.pm
#
#  Objektorientiertes Interface zum EZB XML-API
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Backend::EZB;

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
use XML::LibXML;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::Catalog::Factory;
use OpenBib::Container;

use base qw(OpenBib::Search);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    # Set defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : $config->{ezb_bibid};

    my $lang      = exists $arg_ref->{l}
        ? $arg_ref->{l}           : undef;

    my $sc      = exists $arg_ref->{sc}
        ? $arg_ref->{sc}           : undef;

    my $lc       = exists $arg_ref->{lc}
        ? $arg_ref->{lc}           : undef;

    my $sindex   = exists $arg_ref->{sindex}
        ? $arg_ref->{sindex}           : undef;
    
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

        my $colors_mask  = OpenBib::Common::Util::dec2bin($colors);

        $logger->debug("Access: mask($colors_mask)");
        
        $access_green  = ($colors_mask & 0b001)?1:0;
        $access_yellow = ($colors_mask & 0b010)?1:0;
        $access_red    = ($colors_mask & 0b100)?1:0;
    }

    my $self = { };

    bless ($self, $class);

    $logger->debug("Initializing with colors = ".(defined $colors || '')." and lang = ".(defined $lang || ''));

    $self->{client}     = LWP::UserAgent->new;            # HTTP client
    $self->{_database}      = $database if ($database);

    # Backend Specific Attributes
    $self->{access_green}  = $access_green;
    $self->{access_yellow} = $access_yellow;
    $self->{access_red}    = $access_red;
    $self->{bibid}         = $bibid;
    $self->{lang}          = $lang if ($lang);
    $self->{colors}        = $colors if ($colors);
    $self->{sc}            = $sc if ($sc);
    $self->{lc}            = $lc if ($lc);
    $self->{sindex}        = $sindex if ($sindex);
    $self->{args}          = $arg_ref;


    return $self;
}

sub search {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = OpenBib::Config->new;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;

    # Pagination parameters
    my $page              = $queryoptions->get_option('page');
    my $num               = $queryoptions->get_option('num');

    my $offset            = $page*$num-$num;

    $self->parse_query($searchquery);

    my $url="http://rzblx1.uni-regensburg.de/ezeit/searchres.phtml?colors=$self->{colors}&bibid=$self->{bibid}&sc=$self->{sc}&lc=$self->{lc}&sindex=$self->{sindex}&".$self->querystring."&hits_per_page=$num&offset=$offset&lang=".((defined $self->{lang})?$self->{lang}:"de")."&xmloutput=1";

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

    $logger->debug("Found $search_count titles");
    
    $self->{resultcount}   = $search_count;
    $self->{_matches}      = $journals_ref;
    
    return $self;
}

sub get_records {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = OpenBib::Config->new;

    my $catalog = OpenBib::Catalog::Factory->create_catalog($self->{args});
    
    my $classifications_ref = $catalog->get_classifications;

    my $container = OpenBib::Container->instance;

    $container->register('classifications',$classifications_ref);

    my $recordlist = new OpenBib::RecordList::Title;

    my @matches = $self->matches;
    
    foreach my $match_ref (@matches) {        
        $logger->debug("Record: ".$match_ref );
        
        my $record = new OpenBib::Record::Title({id => $match_ref->{id}, database => 'ezb', generic_attributes => { color => $match_ref->{color}}});
        $logger->debug("Title is ".$match_ref->{title});
        
        $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $match_ref->{title}});

        if ($logger->is_debug){
            $logger->debug("Adding Record with ".YAML::Dump($record->get_fields));
        }
        
        $recordlist->add($record);
    }

    return $recordlist;
}

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    my @searchterms = ();
    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{norm})?$searchquery->get_searchfield($field)->{norm}:'';
        if ($searchtermstring) {
            # Freie Suche einfach uebernehmen
            if    ($field eq "title" && $searchtermstring) {
                push @searchterms, {
                    field   => 'KT',
                    content => $searchtermstring
                };
            }
            elsif ($field eq "titlestring" && $searchtermstring) {
                push @searchterms, {
                    field   => 'KS',
                    content => $searchtermstring
                };
            }
            elsif ($field eq "subject" && $searchtermstring) {
                push @searchterms, {
                    field   => 'KW',
                    content => $searchtermstring
                };
            }
            elsif ($field eq "classification" && $searchtermstring) {
                push @searchterms, {
                    string   => 'Notations[]=$searchtermstring',
                };
            }
            elsif ($field eq "publisher" && $searchtermstring) {
                push @searchterms, {
                    field   => 'PU',
                    content => $searchtermstring
                };
            }
        }
    }

    my @searchstrings = ();
    my $i = 1;
    foreach my $search_ref (@searchterms){
        last if ($i > 3);

        if ($search_ref->{field} && $search_ref->{content}){
            push @searchstrings, "jq_type${i}=$search_ref->{field}&jq_term${i}=$search_ref->{content}&jq_bool${i}=AND";
            $i++;
        }
    }
    
    if (defined $searchquery->get_searchfield('classification')->{val} && $searchquery->get_searchfield('classification')->{val}){
        push @searchstrings, "Notations[]=".$searchquery->get_searchfield('classification')->{val};
    }
    else {
        push @searchstrings, "Notations[]=all";
    }

    my $ezbquerystring = join("&",@searchstrings);
    $logger->debug("EZB-Querystring: $ezbquerystring");
    $self->{_querystring} = $ezbquerystring;

    return $self;
}

1;
__END__

=head1 NAME

OpenBib::Search::Backend::EZB - Objektorientiertes Interface zum EZB XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API der
Elektronischen Zeitschriftenbibliothek (EZB) in Regensburg zugegriffen werden.

=head1 SYNOPSIS

=head1 METHODS

=over 4

=item XXX

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
