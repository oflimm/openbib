#####################################################################
#
#  OpenBib::Search::Backend::DBIS.pm
#
#  Objektorientiertes Interface zum DBIS XML-API
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

package OpenBib::Search::Backend::DBIS;

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

use base qw(OpenBib::Search);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : undef;

    my $client_ip = exists $arg_ref->{client_ip}
        ? $arg_ref->{client_ip}   : undef;

    my $lang      = exists $arg_ref->{lang}
        ? $arg_ref->{lang}        : undef;

    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;

    my $options            = exists $arg_ref->{options}
        ? $arg_ref->{options}                 : {};

    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;

    my $access_green           = exists $arg_ref->{access_green}
        ? $arg_ref->{access_green}            :
            ($options->{access_green})?$options->{access_green}:0;

    my $access_yellow          = exists $arg_ref->{access_yellow}
        ? $arg_ref->{access_yellow}           :
            ($options->{access_yellow})?$options->{access_yellow}:0;

    my $access_red             = exists $arg_ref->{access_red}
        ? $arg_ref->{access_red}              :
            ($options->{access_red})?$options->{access_red}:0;

    my $access_national        = exists $arg_ref->{access_national}
        ? $arg_ref->{access_national}         :
            ($options->{access_national})?$options->{access_national}:0;
    
    my $colors  = $access_green + $access_yellow*44;
    my $ocolors = $access_red*8 + $access_national*32;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;

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
        $logger->debug("access_red: $access_red - access_national: $access_national - access_green: $access_green - access_yellow: $access_yellow");

        $colors = "" unless ($colors);
        $ocolors = "" unless ($ocolors);
    }

    my $self = { };

    bless ($self, $class);

    $logger->debug("Initializing with colors = $colors, ocolors = $ocolors and lang = ".(defined $lang || ''));

    $self->{bibid}      = (defined $bibid)?$bibid:(defined $config->{ezb_bibid})?$config->{ezb_bibid}:undef;
    $self->{colors}     = (defined $colors)?$colors:(defined $config->{dbis_colors})?$config->{dbis_colors}:undef;
    $self->{ocolors}    = (defined $ocolors)?$ocolors:(defined $config->{dbis_ocolors})?$config->{dbis_ocolors}:undef;
    $self->{client_ip}  = (defined $client_ip )?$client_ip:undef;
    $self->{lang}       = (defined $lang )?$lang:undef;

    $self->{client}     = LWP::UserAgent->new;            # HTTP client
    $self->{_database}  = $database if ($database);
    $self->{args}          = $arg_ref;

    if ($options){
        $self->{_options}       = $options;
    }

    if ($queryoptions){
        $self->{_queryoptions}  = $queryoptions;
    }

    if ($searchquery){    
        $self->{_searchquery}   = $searchquery;
    }

    
    return $self;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Set defaults search parameters
    my $options_ref          = exists $arg_ref->{options}
        ? $arg_ref->{options}        : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = OpenBib::Config->new;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;

    # Used Parameters
    my $sorttype          = (defined $self->{_options}{srt})?$self->{_options}{srt}:$queryoptions->get_option('srt');
    my $sortorder         = (defined $self->{_options}{srto})?$self->{_options}{srto}:$queryoptions->get_option('srto');
    my $defaultop         = (defined $self->{_options}{dop})?$self->{_options}{dop}:$queryoptions->get_option('dop');
    my $facets            = (defined $self->{_options}{facets})?$self->{_options}{facets}:$queryoptions->get_option('facets');
    my $gen_facets        = ($facets eq "none")?0:1;
    
    if ($logger->is_debug){
        $logger->debug("Options: ".YAML::Dump($options_ref));
    }
    
    # Pagination parameters
    my $page              = (defined $self->{_options}{page})?$self->{_options}{page}:$queryoptions->get_option('page');
    my $num               = (defined $self->{_options}{num})?$self->{_options}{num}:$queryoptions->get_option('num');
    my $collapse          = (defined $self->{_options}{clp})?$self->{_options}{clp}:$queryoptions->get_option('clp');

    my $offset            = $page*$num-$num;

    $self->parse_query($searchquery);

    my $url="http://rzblx10.uni-regensburg.de/dbinfo/dbliste.php?bib_id=$self->{bibid}&colors=$self->{colors}&ocolors=$self->{ocolors}&lett=k&".$self->querystring."&hits_per_page=$num&offset=$offset&lang=$self->{lang}&xmloutput=1";
    
    my $titles_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'latin1');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

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
    my $dbs_ref                  = [];
    my $have_group_ref           = {};
    $db_group_ref->{group_order} = [];

    my $search_count = 0;
    foreach my $dbs_node ($root->findnodes('/dbis_page/list_dbs/dbs')) {
        $search_count = $dbs_node->findvalue('@db_count');
        my $i=0;
        foreach my $db_node ($dbs_node->findnodes('db')) {
            $i++;
            # DBIS-Suche verfuegt ueber kein Paging
            next if ($i <= $offset || $i > $offset+$page*$num);
            
            my $single_db_ref = {};

            $single_db_ref->{id}       = $db_node->findvalue('@title_id');
            $single_db_ref->{access}   = $db_node->findvalue('@access_ref');
            my @types = split(" ",$db_node->findvalue('@db_type_refs'));

            $single_db_ref->{db_types} = \@types;
            $single_db_ref->{title}     = decode_utf8($db_node->textContent);

            push @{$dbs_ref}, $single_db_ref;
        }
    }

#     foreach my $db_group_node ($root->findnodes('/dbis_page/list_dbs/dbs')) {
#         my $db_type                 = $db_group_node->findvalue('@db_type_ref');
#         my $topdb                   = $db_group_node->findvalue('@top_db') || 0;

#         $db_type = "topdb" if (!$db_type && $topdb);
#         $db_type = "all" if (!$db_type && !$topdb);

#         push @{$db_group_ref->{group_order}}, $db_type unless $have_group_ref->{$db_type};
#         $have_group_ref->{$db_type} = 1;

#         $db_group_ref->{$db_type}{count} = decode_utf8($db_group_node->findvalue('@db_count'));
#         $db_group_ref->{$db_type}{dbs} = [];
        
#         foreach my $db_node ($db_group_node->findnodes('db')) {
#             my $single_db_ref = {};

#             $single_db_ref->{id}       = $db_node->findvalue('@title_id');
#             $single_db_ref->{access}   = $db_node->findvalue('@access_ref');
#             my @types = split(" ",$db_node->findvalue('@db_type_refs'));

#             $single_db_ref->{db_types} = \@types;
#             $single_db_ref->{title}     = decode_utf8($db_node->textContent);

#             push @{$db_group_ref->{$db_type}{dbs}}, $single_db_ref;
#         }
#     }
    
#     $btime       = new Benchmark;
#     $timeall     = timediff($btime,$atime);
#     $logger->debug("Time: ".timestr($timeall,"nop"));

    $self->{resultcount}   = $search_count;
    $self->{_access_info}  = $access_info_ref;
    $self->{_db_type}      = $db_type_ref;
    $self->{_matches}      = $dbs_ref;
    
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
    
    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;

    if ($logger->is_debug){
        $logger->debug("Getting Matches ".YAML::Dump(\@matches));
    }
    
    foreach my $match_ref (@matches) {        
        $logger->debug("Record: ".$match_ref );

        my $access_info = $self->{_access_info}{$match_ref->{access}};
        
        my $record = new OpenBib::Record::Title({id => $match_ref->{id}, database => 'dbis', generic_attributes => { access => $access_info }});

        $logger->debug("Title is ".$match_ref->{title});
        
        $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $match_ref->{title}});

        my $mult = 1;
        if (defined $match_ref->{db_types}){
            foreach my $type (@{$match_ref->{db_types}}){
                my $dbtype       =  $self->{_db_type}{$type}{desc};
                my $dbtype_short =  $self->{_db_type}{$type}{desc_short}; 
                $record->set_field({field => 'T0517', subfield => '', mult => $mult, content => $dbtype});
                $record->set_field({field => 'T0800', subfield => '', mult => $mult, content => $dbtype_short});
                $mult++;
            }
        }
        
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
#        my $searchtermop     = (defined $searchquery->get_searchfield($field)->{bool} && defined $ops_ref->{$searchquery->get_searchfield($field)->{bool}})?$ops_ref->{$searchquery->get_searchfield($field)->{bool}}:'';
        if ($searchtermstring) {
            # Freie Suche einfach uebernehmen
            if    ($field eq "freesearch" && $searchtermstring) {
                push @searchterms, {
                    field   => 'AL',
                    content => $searchtermstring
                };
            }
            elsif    ($field eq "title" && $searchtermstring) {
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
            elsif ($field eq "content" && $searchtermstring) {
                push @searchterms, {
                    field   => 'CO',
                    content => $searchtermstring
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
        last if ($i > 4);

        if ($search_ref->{field} && $search_ref->{content}){
            push @searchstrings, "jq_type${i}=$search_ref->{field}&jq_term${i}=$search_ref->{content}&jq_bool${i}=AND";
            $i++;
        }
    }
    
    if (defined $searchquery->get_searchfield('classification')->{val} && $searchquery->get_searchfield('classification')->{val}){
        push @searchstrings, "gebiete[]=".$searchquery->get_searchfield('classification')->{val};
    }
    else {
        push @searchstrings, "gebiete[]=all";
    }

    my $dbisquerystring = join("&",@searchstrings);
    $logger->debug("DBIS-Querystring: $dbisquerystring");
    $self->{_querystring} = $dbisquerystring;

    return $self;
}

1;
__END__

=head1 NAME

OpenBib::Search::Backend::DBIS - Objektorientiertes Interface zum DBIS XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API des
Datenbankinformationssystems (DBIS) in Regensburg für Rechercheanfragen zugegriffen werden.

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
