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

    my $access_ppu             = exists $arg_ref->{access_ppu}
        ? $arg_ref->{access_ppu}              : 0;
    
    my $access_national        = exists $arg_ref->{access_national}
        ? $arg_ref->{access_national}         : 0;

    # access_yellow = Hochschulnetz = online (4) + CD/DVD (8) + eingeschraenkt (32) = 44
    my $colors  = $access_green*1 + $access_yellow*4 + $access_yellow*8 + $access_yellow*32;
    my $ocolors = $access_ppu*8 + $access_national*32;

    $logger->debug("green: $access_green ; yellow: $access_yellow ; red: $access_red ; ppu: $access_ppu ; national: $access_national");
    $logger->debug("colors: $colors ; ocolors: $ocolors");
    
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
    # Eins von colors oder ocolors ist besetzt (oder auch beides)
    else {
        $logger->debug("Using CGI values for color and ocolor");
        $logger->debug("access_red: $access_red - access_national: $access_national - access_green: $access_green - access_yellow: $access_yellow");

        $colors = "" unless ($colors);
        $ocolors = "" unless ($ocolors);
    }

    $logger->debug("Postprocessed colors: $colors ; ocolors: $ocolors");
    
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
    $self->{ocolors}         = $ocolors if ($ocolors);
    
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

    my $dbis_base = $config->get('dbis_baseurl');
    
    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });
    
    my $url = $dbis_base."detail.php?colors=".((defined $self->{colors})?$self->{colors}:"")."&ocolors=".((defined $self->{ocolors})?$self->{ocolors}:"")."&lett=f&titel_id=$id&bib_id=".((defined $self->{bibid})?$self->{bibid}:"")."&xmloutput=1";

    my $memc_key = "dbis:title:$url";

    my $memc = $config->get_memc;
    
    if ($memc){
        my $fields_ref = $memc->get($memc_key);

	if ($fields_ref){
	    if ($logger->is_debug){
		$logger->debug("Got fields for key $memc_key from memcached");
	    }

	    $record->set_fields($fields_ref);
	    $record->set_holding([]);
	    $record->set_circulation([]);

	    return $record;
	}
    }
    
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

    my $xmlresponse = $response->content;
    $xmlresponse =~s/^.*?<\?xml/<\?xml/ms;
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($xmlresponse);
    my $root   = $tree->getDocumentElement;

    my $access_info_ref = {};
    
    $access_info_ref->{id}         = $root->findvalue('/dbis_page/details/db_access_info/@access_id');
    $access_info_ref->{icon_url}   = $root->findvalue('/dbis_page/details/db_access_info/@access_icon');
    $access_info_ref->{desc}       = $root->findvalue('/dbis_page/details/db_access_info/db_access');
    $access_info_ref->{desc_short} = $root->findvalue('/dbis_page/details/db_access_info/db_access_short_text');

    # Zugriffstatus
    #
    # '' : Keine Ampel
    # ' ': Unbestimmt g oder y oder r
    # 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
    # 'g': Freier Zugriff (green)
    # 'y': Lizensierter Zugriff (yellow)
    # 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
    # 'r': Kein Zugriff (red)
    
    my $type_mapping_ref = {
        'access_0'    => 'g', # green
        'access_2'    => 'y', # yellow
        'access_3'    => 'y', # yellow
        'access_5'    => 'l', # yellow red
        'access_500'  => 'n', # national license
    };
    
    my $access_type = "";

    if ($access_info_ref->{id} =~m/^access/){
	$access_type = $type_mapping_ref->{$access_info_ref->{id}};
    }

    # Fix: z.T. falsche type_mapping-Werte in den Daten, daher zusaetzlich mit desc unterscheiden
    if ($access_info_ref->{desc} =~m/Online Uninetz/){
	$access_type = "y";
    }
    elsif ($access_info_ref->{desc} =~m/Nationallizenz/){
	$access_type = "n";
    }
    elsif (!$access_info_ref->{desc} || $access_info_ref->{desc} =~m/frei im Web/){
	$access_type = "g";
    }

    my $db_type_ref = [];
    my @db_type_nodes = $root->findnodes('/dbis_page/details/db_type_infos/db_type_info');
    my $mult = 1;
    foreach my $db_type_node (@db_type_nodes){
        my $this_db_type_ref = {};

        $this_db_type_ref->{desc}       = $db_type_node->findvalue('db_type_long_text');
        $this_db_type_ref->{desc_short} = $db_type_node->findvalue('db_type');
        $this_db_type_ref->{desc}=~s/\|/<br\/>/g;
	
	$record->set_field({field => 'T0800', subfield => '', mult => $mult++, content => $this_db_type_ref->{desc_short}}) if ($this_db_type_ref->{desc_short});
	
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
	if ($this_node->findvalue('@main') eq "Y"){
	    $access_ref->{main}      =  $this_node->findvalue('@href');
	    $access_ref->{main_type} =  $this_node->findvalue('@type');
	}
	elsif ($this_node->findvalue('@main') eq "N"){
	    my $others_ref = {};
	    
	    if ($this_node->findvalue('@href')){
		$others_ref->{url} = $this_node->findvalue('@href');
	    }
	    if ( $this_node->findvalue('@type')){
		$others_ref->{type} = $this_node->findvalue('@type');
	    }

	    push @{$access_ref->{other}}, $others_ref;
	}
    }
    
    my $hints   =  $root->findvalue('/dbis_page/details/hints');
    my $content =  $root->findvalue('/dbis_page/details/content');
    my $content_eng =  $root->findvalue('/dbis_page/details/content_eng');
    my $instruction =  $root->findvalue('/dbis_page/details/instruction');
    my $publisher =  $root->findvalue('/dbis_page/details/publisher');
    my $report_periods =  $root->findvalue('/dbis_page/details/report_periods');
    my $appearence =  $root->findvalue('/dbis_page/details/appearence');
    my $isbn =  $root->findvalue('/dbis_page/details/isbn');
    my $year =  $root->findvalue('/dbis_page/details/year');
    my $remarks = $root->findvalue('/dbis_page/details/remarks');
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

    $mult=1;
    if (defined $title_ref->{other}){
        foreach my $othertitle (@{$title_ref->{other}}){
            $record->set_field({field => 'T0370', subfield => '', mult => $mult, content => $othertitle});
            $mult++;
        }
    }

    $mult=1;
    if (defined $access_ref->{main}){
	if ($access_ref->{main}){
	    $record->set_field({field => 'T0662', subfield => $access_type, mult => $mult, content => $config->{dbis_baseurl}.$access_ref->{main}});
		
	    $record->set_field({field => 'T4120', subfield => $access_type, mult => $mult, content => $config->{dbis_baseurl}.$access_ref->{main}});
		
	    $mult++;
	}
    }

    if (defined $access_ref->{other}){
        foreach my $access_ref (@{$access_ref->{other}}){
            $record->set_field({field => 'T2662', subfield => '', mult => $mult, content => $config->{dbis_baseurl}.$access_ref->{url} }) if ($access_ref->{url});
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

    $record->set_field({field => 'T0751', subfield => '', mult => 1, content => $content_eng}) if ($content_eng);
    
    $record->set_field({field => 'T0412', subfield => '', mult => 1, content => $publisher}) if ($publisher);

    $record->set_field({field => 'T0600', subfield => '', mult => 1, content => $remarks}) if ($remarks);

    $record->set_field({field => 'T0523', subfield => '', mult => 1, content => $report_periods}) if ($report_periods);

    $record->set_field({field => 'T0508', subfield => '', mult => 1, content => $appearence}) if ($appearence);

    $record->set_field({field => 'T0540', subfield => '', mult => 1, content => $isbn}) if ($isbn);

    $record->set_field({field => 'T0425', subfield => '', mult => 1, content => $year}) if ($year);
    
    $mult=1;
    if ($access_info_ref->{desc_short}){
        $record->set_field({field => 'T0501', subfield => '', mult => $mult, content => $access_info_ref->{desc_short}});
        $mult++;
    }
    
    $record->set_field({field => 'T0511', subfield => '', mult => $mult, content => $instruction}) if ($instruction);

    $record->set_field({field => 'T0510', subfield => '', mult => $mult, content => $hints}) if ($hints);
    
    $record->set_holding([]);
    $record->set_circulation([]);

    if ($memc){
	$memc->set($memc_key,$record->get_fields,$config->{memcached_expiration}{'dbis:title'});
    }
    
    return $record;
}

sub get_classifications {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $dbis_base = $config->get('dbis_baseurl');
    
    my $url=$dbis_base."fachliste.php?colors=$self->{colors}&ocolors=$self->{ocolors}&bib_id=$self->{bibid}&lett=l&xmloutput=1";

    my $classifications_ref = [];

    my $memc_key = "dbis:classifications:$url";

    my $memc = $config->get_memc;
    
    $logger->debug("Memc: ".$memc);
    $logger->debug("Memcached: ".$config->{memcached});    
    
    if ($memc){
        my $classifications_ref = $memc->get($memc_key);

	if ($classifications_ref){
	    if ($logger->is_debug){
		$logger->debug("Got classifications for key $memc_key from memcached");
	    }

	    return $classifications_ref if (defined $classifications_ref);
	}
    }
    
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

    my $xmlresponse = $response->content;
    $xmlresponse =~s/^.*?<\?xml/<\?xml/ms;
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($xmlresponse);
    my $root   = $tree->getDocumentElement;

    my $maxcount=0;
    my $mincount=999999999;

    foreach my $classification_node ($root->findnodes('/dbis_page/list_subjects_collections/list_subjects_collections_item')) {
        my $singleclassification_ref = {} ;

        $singleclassification_ref->{name}    = $classification_node->findvalue('@notation');
        $singleclassification_ref->{count}   = $classification_node->findvalue('@number');
        #$singleclassification_ref->{lett}    = $classification_node->findvalue('@lett');
        $singleclassification_ref->{desc}    = $classification_node->textContent();

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

    if ($memc){
	$memc->set($memc_key,$classifications_ref,$config->{memcached_expiration}{'dbis:classifications'});
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

    my $config = $self->get_config;
    my $ua     = $self->get_client;

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

    my $dbis_base = $config->get('dbis_baseurl');

    my $url=$dbis_base."dbliste.php?bib_id=$self->{bibid}&colors=$self->{colors}&ocolors=$self->{ocolors}&lett=k&".$self->querystring."&hits_per_page=$num&offset=$offset&sort=alph&xmloutput=1";

    my $memc_key = "dbis:search:$url";

    my $memc = $config->get_memc;
    
    if ($memc){
        my $result_ref = $memc->get($memc_key);

	if (defined $result_ref->{_matches}){
	    if ($logger->is_debug){
		$logger->debug("Got search result for key $memc_key from memcached");
	    }

	    $self->{resultcount}   = $result_ref->{resultcount};
	    $self->{_access_info}  = $result_ref->{_access_info};
	    $self->{_db_type}      = $result_ref->{_db_type};
	    $self->{_matches}      = $result_ref->{_matches};

	    return $self; 
	}
    }
    
    my $titles_ref = [];
    
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

    my $xmlresponse = $response->decoded_content(charset => 'latin1');
    $xmlresponse =~s/^.*?<\?xml/<\?xml/ms;
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($xmlresponse);
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
    foreach my $dbs_node ($root->findnodes('/dbis_page/list_dbs/dbs[not(@top_db)]')) {
        $search_count = $dbs_node->findvalue('@db_count');
	$logger->debug("DBIS searchcount is $search_count");
        my $i=0;
        foreach my $db_node ($dbs_node->findnodes('db')) {
            $i++;
            # DBIS-Suche verfuegt ueber kein Paging
#            next if ($i <= $offset || $i > $page*$num);
            
            my $single_db_ref = {};

            $single_db_ref->{id}            = $db_node->findvalue('@title_id');
            $single_db_ref->{access}        = $db_node->findvalue('@access_ref');
            $single_db_ref->{traffic_light} = $db_node->findvalue('@traffic_light');
            my @types = split(" ",$db_node->findvalue('@db_type_refs'));

            $single_db_ref->{db_types} = \@types;
            $single_db_ref->{title}     = decode_utf8($db_node->textContent);

            $single_db_ref->{url}       = $config->get("dbis_baseurl").$db_node->findvalue('@href');
	    
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

    if ($memc){
	my $result_ref = {
	    'resultcount'  => $search_count,
	    '_access_info' => $access_info_ref,
	    '_db_type'     => $db_type_ref,
	    '_matches'     => $dbs_ref,
	};

	$logger->debug("Storing search result to memcached to $memc_key");
	$memc->set($memc_key,$result_ref,$config->{memcached_expiration}{'dbis:search'});
    }

    
    $self->{resultcount}   = $search_count;
    $self->{_access_info}  = $access_info_ref;
    $self->{_db_type}      = $db_type_ref;
    $self->{_matches}      = $dbs_ref;
    
    return $self;
}

# Spezifisch fuer DBIS
sub get_popular_records {
    my ($self,$gebiet) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $dbis_base = $config->get('dbis_baseurl');
    
    my $url=$dbis_base."dbliste.php?colors=$self->{colors}&ocolors=$self->{ocolors}&bib_id=$self->{bibid}&lett=f&gebiete=$gebiet&sort=alph&xmloutput=1";

    my $recordlist = new OpenBib::RecordList::Title;

    my $memc_key = "dbis:classifications:$url";

    my $memc = $config->get_memc;
    
    $logger->debug("Memc: ".$memc);
    $logger->debug("Memcached: ".$config->{memcached});    
    
    if ($memc){
        my $recordlist_ref = $memc->get($memc_key);
	
	if ($recordlist_ref){
	    if ($logger->is_debug){
		$logger->debug("Got popular records for key $memc_key from memcached");
	    }

	    $recordlist->from_serialized_referende($recordlist_ref);
	    return $recordlist;
	}
    }
    
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

    my $xmlresponse = $response->content;
    $xmlresponse =~s/^.*?<\?xml/<\?xml/ms;
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($xmlresponse);
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

    # Zugriffstatus
    #
    # '' : Keine Ampel
    # ' ': Unbestimmt g oder y oder r
    # 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
    # 'g': Freier Zugriff (green)
    # 'y': Lizensierter Zugriff (yellow)
    # 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
    # 'r': Kein Zugriff (red)
    
    my $type_mapping_ref = {
	'yellow'      => 'y', # yellow
	'green'       => 'g', # green
	'red'         => 'r', # red
	'access_0'    => 'g', # green
	'access_2'    => 'y', # yellow
	'access_3'    => 'y', # yellow
	'access_5'    => 'l', # yellow red
	'access_500'  => 'n', # national license
    };
    
    my $search_count = 0;

    # Default: top_db in dbs
    my @nodes = $root->findnodes('/dbis_page/list_dbs/dbs[@top_db=1]/db');

    # Sonst top_db in db
    @nodes = $root->findnodes('/dbis_page/list_dbs/dbs/db[@top_db=1]') unless (@nodes);
    
    foreach my $db_node (@nodes) {

	my $id            = $db_node->findvalue('@title_id');
	my $access        = $db_node->findvalue('@access_ref');
	my $traffic_light = $db_node->findvalue('@traffic_light');
	my @types  = split(" ",$db_node->findvalue('@db_type_refs'));
	
	my $db_types_ref = \@types;
	my $title   = $db_node->textContent;
	
	my $url     = $config->get("dbis_baseurl").$db_node->findvalue('@href');

        my $access_info = $access_info_ref->{$access};

	my $access_type = (defined $type_mapping_ref->{$traffic_light})?$type_mapping_ref->{$traffic_light}:
	    (defined $type_mapping_ref->{$access})?$type_mapping_ref->{$access}:'';
	
	if ($logger->is_debug){
	    $logger->debug("Access Type:".YAML::Dump($access_type));
	}
	
	my $record = new OpenBib::Record::Title({id => $id, database => 'dbis', generic_attributes => { access => $access_info }});
	
	$logger->debug("Title is $title");
	
	$record->set_field({field => 'T0331', subfield => '', mult => 1, content => $title});
	
	$record->set_field({field => 'T4120', subfield => $access_type, mult => 1, content => $url});
	    
	my $mult = 1;
	if (@types){
	    foreach my $type (@types){
		my $dbtype       =  $db_type_ref->{$type}{desc};
		my $dbtype_short =  $db_type_ref->{$type}{desc_short}; 
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

    if ($memc){
	$memc->set($memc_key,$recordlist->to_serialized_reference,$config->{memcached_expiration}{'dbis:classifications'});
    }
    
    return $recordlist;
}

sub get_search_resultlist {
    my $self=shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $recordlist = new OpenBib::RecordList::Title;

    # Zugriffstatus
    #
    # '' : Keine Ampel
    # ' ': Unbestimmt g oder y oder r
    # 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
    # 'g': Freier Zugriff (green)
    # 'y': Lizensierter Zugriff (yellow)
    # 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
    # 'r': Kein Zugriff (red)
    
    my $type_mapping_ref = {
	'yellow'      => 'y', # yellow
	'green'       => 'g', # green
	'red'         => 'r', # red
	'access_0'    => 'g', # green
	'access_2'    => 'y', # yellow
	'access_3'    => 'y', # yellow
	'access_5'    => 'l', # yellow red
	'access_500'  => 'n', # national license
    };
    
    my @matches = $self->matches;
    
    foreach my $match_ref (@matches) {
        if ($logger->is_debug){
	    $logger->debug("Record: ".YAML::Dump($match_ref) );
	}

        my $access_info = $self->{_access_info}{$match_ref->{access}};

	my $access_type = (defined $type_mapping_ref->{$match_ref->{traffic_light}})?$type_mapping_ref->{$match_ref->{traffic_light}}:
	    (defined $type_mapping_ref->{$match_ref->{access}})?$type_mapping_ref->{$match_ref->{access}}:'';
        
        my $record = new OpenBib::Record::Title({id => $match_ref->{id}, database => 'dbis', generic_attributes => { access => $access_info }});

        $logger->debug("Title is ".$match_ref->{title});
        
        $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $match_ref->{title}});

        $record->set_field({field => 'T4120', subfield => $access_type, mult => 1, content => $match_ref->{url}});
	
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
        push @searchstrings, "gebiete=".$searchquery->get_searchfield('classification')->{val};
    }
#    else {
#        push @searchstrings, "gebiete=all";
#    }

    if (defined $searchquery->get_searchfield('mediatype')->{val} && $searchquery->get_searchfield('mediatype')->{val}){
        push @searchstrings, "db_type[]=".$searchquery->get_searchfield('mediatype')->{val};
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
