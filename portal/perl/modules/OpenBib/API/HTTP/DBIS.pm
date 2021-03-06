#####################################################################
#
#  OpenBib::API::HTTP::DBIS.pm
#
#  Objektorientiertes Interface zum DBIS XML-API
#
#  Dieses File ist (C) 2008- Oliver Flimm <flimm@openbib.org>
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

package OpenBib::API::HTTP::DBIS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Storable;
use XML::LibXML;
use JSON::XS;
use URI::Escape;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;

use base qw(OpenBib::API::HTTP);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Set defaults
    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}               : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;
    
    my $session            = exists $arg_ref->{session}
        ? $arg_ref->{session}                 : undef;

    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;

    # Set API specific defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : $config->{ezb_bibid};

    my $client_ip = exists $arg_ref->{client_ip}
        ? $arg_ref->{client_ip}   : undef;

    my $lang      = exists $arg_ref->{l}
        ? $arg_ref->{l}           : undef;

    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}         : undef;

    my $options            = exists $arg_ref->{options}
        ? $arg_ref->{options}                 : {};
    
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
        $logger->debug("access_red: $access_red - access_national: $access_national - access_green: $access_green - access_yellow: $access_yellow");

        $colors = "" unless ($colors);
        $ocolors = "" unless ($ocolors);
    }
    
    my $self = { };

    bless ($self, $class);
    
    $self->{database}      = $database;

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    $self->{client}        = $ua;
        
    $self->{sessionID} = $sessionID;

    if ($options){
        $self->{_options}       = $options;
    }
    
    if ($config){
        $self->{_config}        = $config;
    }

    if ($queryoptions){
        $self->{_queryoptions}  = $queryoptions;
    }

    if ($searchquery){    
        $self->{_searchquery}   = $searchquery;
    }

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

sub get_titles_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
    ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : 'dbis';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });
    
    my $url="http://rzblx10.uni-regensburg.de/dbinfo/detail.php?colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&lett=f&titel_id=$id&bibid=".((defined $self->{bibid})?$self->{bibid}:"")."&lang=".((defined $self->{lang})?$self->{lang}:"")."&xmloutput=1";

    $logger->debug("Request: $url");

    my $request = HTTP::Request->new('GET' => $url);
    
    my $response = $ua->request($request);

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success) {
	$logger->info($response->code . ' - ' . $response->message);
	return $record;
    }
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response->content);
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
        $title_ref->{main}     =  $this_node->textContent if ($this_node->findvalue('@main') eq "Y");
        push @{$title_ref->{other}}, $this_node->textContent if ($this_node->findvalue('@main') eq "N");
    }

    my $access_ref = {};
    $access_ref->{other} = [];

    my @access_nodes = $root->findnodes('/dbis_page/details/accesses/access');

    foreach my $this_node (@access_nodes){
        $access_ref->{main}     =  $this_node->findvalue('@href') if ($this_node->findvalue('@main') eq "Y");
        push @{$access_ref->{other}}, $this_node->findvalue('@href') if ($this_node->findvalue('@main') eq "N");
    }
    
    my $hints   =  $root->findvalue('/dbis_page/details/hints');
    my $content =  $root->findvalue('/dbis_page/details/content');
    my $instructions =  $root->findvalue('/dbis_page/details/instructions');

    my @subjects_nodes =  $root->findnodes('/dbis_page/details/subjects/subject');

    my $subjects_ref = [];

    foreach my $subject_node (@subjects_nodes){
        push @{$subjects_ref}, $subject_node->textContent;
    }

    my @keywords_nodes =  $root->findnodes('/dbis_page/details/keywords/keyword');

    my $keywords_ref = [];

    foreach my $keyword_node (@keywords_nodes){
        push @{$keywords_ref}, $keyword_node->textContent;
    }

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

sub get_classifications {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $ua     = $self->get_client;
    
    my $url="http://rzblx10.uni-regensburg.de/dbinfo/fachliste.php?colors=$self->{colors}&ocolors=$self->{ocolors}&bib_id=$self->{dbis_bibid}&lett=l&lang=$self->{lang}&xmloutput=1";

    my $classifications_ref = [];
    
    $logger->debug("Request: $url");

    my $request = HTTP::Request->new('GET' => $url);
    
    my $response = $ua->request($request);

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success) {
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }

#    my $response = $ua->get($url)->decoded_content(charset => 'utf8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response->content);
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

sub search {
    my ($self,$arg_ref) = @_;

    # Set defaults search parameters
    my $options_ref          = exists $arg_ref->{options}
        ? $arg_ref->{options}        : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
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

    if ($logger->is_debug){
	$logger->debug("Results found: $search_count");
	$logger->debug(YAML::Dump($dbs_ref));
    }
    
    $self->{resultcount}   = $search_count;
    $self->{_access_info}  = $access_info_ref;
    $self->{_db_type}      = $db_type_ref;
    $self->{_matches}      = $dbs_ref;
    
    return $self;
}

sub get_search_resultlist {
    my $self=shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $recordlist = new OpenBib::RecordList::Title;

    my @matches = $self->matches;
    
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

    my $config = $self->get_config;

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

sub DESTROY {
    my $self = shift;

    return;
}


1;
__END__

=head1 NAME

 OpenBib::API::HTTP::EDS - Objekt zur Interaktion mit EDS

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib über das API von EDS auf diesen Web-Dienst zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::API::HTTP::EDS;

 my $eds = new OpenBib::EDS({ api_key => $api_key, api_user => $api_user});

 my $search_result_json = $eds->search({ searchquery => $searchquery, queryoptions => $queryoptions });

 my $single_record_json = $eds->get_record({ });

=head1 METHODS

=over 4

=item new({ api_key => $api_key, api_user => $api_user })

Anlegen eines neuen EDS-Objektes. Für den Zugriff über das
EDS-API muss ein API-Key $api_key und ein API-Nutzer $api_user
vorhanden sein. Diese können direkt bei der Objekt-Erzeugung angegeben
werden, ansonsten werden die Standard-Keys unter eds aus OpenBib::Config 
respektive portal.yml verwendet.

=item search({ searchquery => $searchquery, queryoptions => $queryoptions })

Liefert die EDS Antwort in JSON zurueck.

=item get_record({ })

Liefert die EDS Antwort in JSON zurueck.
=back

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
