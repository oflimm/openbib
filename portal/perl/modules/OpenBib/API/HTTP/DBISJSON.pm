#####################################################################
#
#  OpenBib::API::HTTP::DBISJSON.pm
#
#  Objektorientiertes Interface zum DBIS JSON-API
#
#  Dieses File ist (C) 2008-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::API::HTTP::DBISJSON;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode qw/decode decode_utf8/;
use HTML::Entities;
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger :levels);
use Mojo::UserAgent;
use Storable;
use XML::LibXML;
use JSON::XS;
use URI::Escape;
use YAML ();
use Mojo::Base -strict, -signatures;

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

    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;
    
    # Set API specific defaults
    my $bibid     = exists $arg_ref->{bibid}
        ? $arg_ref->{bibid}       : $config->{dbis}{bibid};

    my $client_ip = exists $arg_ref->{client_ip}
        ? $arg_ref->{client_ip}   : undef;

    my $lang      = exists $arg_ref->{l}
        ? $arg_ref->{l}           : 'de';

    my $options            = exists $arg_ref->{options}
        ? $arg_ref->{options}                 : {};
    
    my $access_all           = exists $arg_ref->{access_all}
        ? $arg_ref->{access_all}            : 'false';
    
    my $self = { };

    bless ($self, $class);
    
    $self->{database}      = $database;

    my $ua = Mojo::UserAgent->new();
    $ua->transactor->name('USB Koeln/1.0');
    $ua->connect_timeout(5);
    $ua->request_timeout($config->{'dbis'}{'api_timeout'});
    $ua->max_redirects(2);

    $self->{client}        = $ua;
   
    $self->{sessionID}     = $sessionID;

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

    $access_all = 'false' if ($access_all ne "true");
    
    # Backend Specific Attributes
    $self->{access_all}      = $access_all;
    $self->{bibid}           = $bibid;
    $self->{lang}            = $lang if ($lang);
    
    return $self;
}

sub get_titles_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
    ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : $self->{database};
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $dbis_base  = $config->{dbis}{baseurl};
    my $dbis_bibid = $self->{'bibid'};
    
    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });
    
    my $url = $dbis_base."api/v1/resource/$id/organization/$dbis_bibid?language=$self->{lang}";

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

    my $json_ref = {};

    my $atime = new Benchmark;
    
    my $response = $ua->get($url)->result;

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    $resulttime = $resulttime * 1000.0; # to ms
    
    if ($resulttime > $config->{'dbis'}{'api_logging_threshold'}){
	$logger->error("DBIS API call $url took $resulttime ms");
    }
    
    if ($response->is_success){
	eval {
	    $json_ref = decode_json $response->body;
	};
	if ($@){
	    $logger->error('Decoding error: '.$@);
	    return $record;
	}	
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return $record;
    }

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }

    if ($logger->is_debug){
	$logger->debug("Got JSON fields: ".YAML::Dump($json_ref));
    }
    
    my $traffic_light              = $json_ref->{traffic_light};
    my $is_free                    = $json_ref->{is_free};
    
    #
    # '' : Keine Ampel
    # ' ': Unbestimmt g oder y oder r
    # 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
    # 'g': Freier Zugriff (green)
    # 'y': Lizensierter Zugriff (yellow)
    # 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
    # 'r': Kein Zugriff (red)
    
    my $type_mapping_ref = {
        'green'     => 'g', # green
        'yellow'    => 'y', # yellow
        'red '      => 'r', # red
        'national'  => 'n', # national license
    };
    
    my $access_type = "";

    if ($traffic_light && defined $type_mapping_ref->{$traffic_light}){
	$access_type = $type_mapping_ref->{$traffic_light};
    }
    elsif ($is_free){
	$access_type = 'g';
    }
    
    if (defined $json_ref->{types} && ref $json_ref->{types} eq "ARRAY"){
	my $mult = 1;
	foreach my $db_type_ref (@{$json_ref->{types}}){
	    my $dbtype       =  $db_type_ref->{description};
	    my $dbtype_short =  $db_type_ref->{title}; 
	    
	    $record->set_field({field => 'T0517', subfield => '', mult => $mult, content => $dbtype}) if ($dbtype);
	    $record->set_field({field => 'T0800', subfield => '', mult => $mult++, content => $dbtype_short}) if ($dbtype_short);
	    
	}
    }

    my $title          = $json_ref->{title};
    my $hints          = '';
    my $content        = $json_ref->{description};
    my $instruction    = $json_ref->{instructions};
    my $report_periods = ''; # werden noch nicht geliefert
    my $isbn           = (defined $json_ref->{isbn_issn} && length $json_ref->{isbn_issn} > 9)?$json_ref->{isbn_issn}:'';
    my $issn           = (defined $json_ref->{isbn_issn} && length $json_ref->{isbn_issn} <= 9)?$json_ref->{isbn_issn}:'';
    my $year           = ''; # wird noch nicht geliefert
    my $remarks        = $json_ref->{note};
    my $local_remarks  = $json_ref->{local_note};

    $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $title}) if ($title);

    if (defined $json_ref->{alternative_titles}){
	my $mult=1;

        foreach my $title_ref (@{$json_ref->{alternative_titles}}){
            $record->set_field({field => 'T0370', subfield => '', mult => $mult, content => $title_ref->{title}, id => $title_ref->{id}});
            $mult++;
        }
    }

    my @externalNotes     = ();
    my @publishers        = ();
    my @publication_forms = ();
    my @local_licenseinfo = ();

    push @externalNotes, $remarks if ($remarks && $remarks =~m/\w/);
    push @externalNotes, $local_remarks if ($local_remarks && $local_remarks =~m/\w/);    

    if ($traffic_light ne "red" && defined $json_ref->{licenses} && ref $json_ref->{licenses} eq "ARRAY"){
	
	
	foreach my $license_ref (@{$json_ref->{licenses}}){

	    if (defined $license_ref->{externalNotes}){
		push @externalNotes, $license_ref->{externalNotes} if ($license_ref->{externalNotes} && $license_ref->{externalNotes} =~m/\w/);
	    }
	    
	    if (defined $license_ref->{publisher} && defined $license_ref->{publisher}{title}){
		push @publishers, $license_ref->{publisher}{title} if ($license_ref->{publisher}{title} && $license_ref->{publisher}{title} =~m/\w/);
	    }


	    if (defined $license_ref->{publicationForm} && defined $license_ref->{publicationForm}{title}){
		push @publication_forms, $license_ref->{publicationForm}{title} if ($license_ref->{publicationForm}{title} && $license_ref->{publicationForm}{title} =~m/\w/);
	    }

	    if (defined $license_ref->{licenseLocalisation} && defined $license_ref->{licenseLocalisation}{externalNotes}){
		push @local_licenseinfo, $license_ref->{licenseLocalisation}{externalNotes} if ($license_ref->{licenseLocalisation}{externalNotes} && $license_ref->{licenseLocalisation}{externalNotes} =~m/\w/);
	    }
	    
	    if (defined $license_ref->{accesses} && ref $license_ref->{accesses} eq "ARRAY"){
		my $mult=1;
		
		foreach my $access_ref (@{$license_ref->{accesses}}){
		    my $this_access_url   = $access_ref->{accessUrl};
		    
		    my $this_access_label         = $access_ref->{label};
		    my $this_access_label_long    = $access_ref->{labelLongest} || $access_ref->{labelLong};
		    
		    my $this_access_id    = $access_ref->{id};
		    my $this_access_type  = $access_ref->{type}{id};
		    
		    my $this_license_type = $license_ref->{type}{id};
		    my $this_license_form = $license_ref->{form}{id};
		    		    
		    $this_access_url = 'warpto?ubr_id='.$self->{bibid}.'&amp;resource_id='.$id.'&amp;access_id='.$this_access_id.'&amp;license_type='.$this_license_type.'&amp;license_form='.$this_license_form.'&amp;access_type='.$this_access_type.'&amp;url='.uri_escape($this_access_url);

		    my $this_access = $access_type;
		    
		    if ($this_license_type == 1){
			$this_access = "g";
		    }
		    else {
			$this_access = "y";
		    }

		    if ($url){
			# URL
			$record->set_field({field => 'T0662', subfield => $this_access, mult => $mult, content => $config->{dbis}{baseurl}.$this_access_url});

			# Beschreibung zum URL
			$record->set_field({field => 'T0663', subfield => '', mult => $mult, content => $this_access_label}) if ($this_access_label);
			$record->set_field({field => 'T0664', subfield => '', mult => $mult, content => $this_access_label_long}) if ($this_access_label_long);

			# Expliziter URL zum Volltext
			$record->set_field({field => 'T4120', subfield => $this_access, mult => $mult, content => $config->{'dbis'}{'baseurl'}.$this_access_url});
			$mult++;
		    }
		}
	    }
	}
    }

    if (defined $json_ref->{subjects} && ref $json_ref->{subjects} eq "ARRAY"){
	my $mult=1;
	foreach my $subject_ref (@{$json_ref->{subjects}}){
	    $record->set_field({field => 'T0700', subfield => '', mult => $mult, content => $subject_ref->{title}, id => $subject_ref->{title}});
	    $mult++;
	}
    }

    if (defined $json_ref->{keywords} && ref $json_ref->{keywords} eq "ARRAY"){
	my $mult=1;
	foreach my $keyword_ref (@{$json_ref->{keywords}}){
	    $record->set_field({field => 'T0710', subfield => '', mult => $mult, content => $keyword_ref->{title}});
	    $mult++;
	}
    }
    
    $record->set_field({field => 'T0750', subfield => '', mult => 1, content => $content}) if ($content);

#    $record->set_field({field => 'T0600', subfield => '', mult => 1, content => $remarks}) if ($remarks);

    $record->set_field({field => 'T0523', subfield => '', mult => 1, content => $report_periods}) if ($report_periods);

    $record->set_field({field => 'T0540', subfield => '', mult => 1, content => $isbn}) if ($isbn);

    $record->set_field({field => 'T0543', subfield => '', mult => 1, content => $issn}) if ($issn);
	
    $record->set_field({field => 'T0425', subfield => '', mult => 1, content => $year}) if ($year);
    
    $record->set_field({field => 'T0511', subfield => '', mult => 1, content => $instruction}) if ($instruction);

    my $notes_mult = 1;

    if ($logger->is_debug){
	$logger->debug("externalNotes: ".YAML::Dump(\@externalNotes));
	$logger->debug("local_licenseinfo: ".YAML::Dump(\@local_licenseinfo));
    }
    
    push @externalNotes, @local_licenseinfo;
    @externalNotes = uniq map { decode_entities($_) } @externalNotes;
    
    foreach my $externalNote (@externalNotes){	
	$record->set_field({field => 'T0510', subfield => '', mult => $notes_mult, content => $externalNote});
	$notes_mult++;
    }

    my $publishers_mult = 1;
    foreach my $publisher (@publishers){
	$record->set_field({field => 'T0412', subfield => '', mult => $publishers_mult, content => $publisher});
	$publishers_mult++;
    }

    my $pubforms_mult = 1;
    foreach my $publication_form (@publication_forms){
	$record->set_field({field => 'T0508', subfield => '', mult => $pubforms_mult, content => $publication_form});
	$pubforms_mult++;
    }
	    
    # Gesamtresponse in dbisjson_source
    $record->set_field({field => 'dbisjson_source', subfield => '', mult => 1, content => $json_ref});

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

    my $dbis_base  = $config->{'dbis'}{'baseurl'};
    my $dbis_bibid = $self->{'bibid'};
    
    my $classifications_ref = [];

    my $memc_key = "dbis:classifications:all";

    my $memc = $config->get_memc;
    
    $logger->debug("Memc: ".$memc);
    $logger->debug("Memcached: ".$config->{memcached});    
    
    if ($memc){
        my $response_ref = $memc->get($memc_key);
	
	if ($response_ref){
	    if ($logger->is_debug){
		$logger->debug("Got classifications for key $memc_key from memcached");
	    }
	    
	    return $response_ref if (defined $response_ref);
	}
    }
    
    my $maxcount=0;
    my $mincount=999999999;
    
    my $url = $dbis_base."api/v1/subjects/organization/$dbis_bibid?resource_count=true&language=$self->{lang}";
    
    $logger->debug("Request: $url");
    
    my $json_ref = {};

    my $atime = new Benchmark;
    
    my $response = $ua->get($url)->result;

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    $resulttime = $resulttime * 1000.0; # to ms
    
    if ($resulttime > $config->{'dbis'}{'api_logging_threshold'}){
	$logger->error("DBIS API call $url took $resulttime ms");
    }
    
    if ($response->is_success){
	eval {
	    $json_ref = decode_json $response->body;
	};
	if ($@){
	    $logger->error('Decoding error: '.$@);
	    return $json_ref;
	}	
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return {
	    items => [],
	    hits  => 0,
	    error => 1,
	};

    }
    
    if ($logger->is_debug){
	$logger->debug("Subjects: ".YAML::Dump($json_ref));
    }
	
    foreach my $classification_ref (@{$json_ref}) {
	my $singleclassification_ref = {} ;
	
	$singleclassification_ref->{name}          = $classification_ref->{id};
	$singleclassification_ref->{count}         = $classification_ref->{resource_count};
	$singleclassification_ref->{desc}          = $classification_ref->{title};
	# $singleclassification_ref->{is_collection} = 1 if ($classification_ref->{is_collection});
	
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

    # Sortierung nach Beschreibungen
    @$classifications_ref = sort {$a->{desc} cmp $b->{desc}} @$classifications_ref;
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($classifications_ref));
    }

    my $hits = scalar @$classifications_ref;
    
    my $response_ref = {
	items => $classifications_ref,
	hits => $hits,
    };
    
    if ($memc){
	$memc->set($memc_key,$response_ref,$config->{memcached_expiration}{'dbis:classifications'});
    }

    return $response_ref;
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
    
    my $dbis_base = $config->{'dbis'}{'baseurl'};

    my $dbis_sort = "";

    $logger->debug("Sorttype: $sorttype");
    
    unless ($sorttype eq "relevance"){
	$dbis_sort = '&sort=alph';
    }
    
    my $url=$dbis_base."dbliste.php?bib_id=$self->{bibid}&include%5B%5D=licenses&lett=a&all=".$self->{access_all}."&".$self->querystring."&hits_per_page=$num&offset=$offset".$dbis_sort."&xmloutput=1";

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

    my $atime = new Benchmark;
    
    my $response = $ua->get($url)->result;

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    $resulttime = $resulttime * 1000.0; # to ms
    
    if ($resulttime > $config->{'dbis'}{'api_logging_threshold'}){
	$logger->error("DBIS API call $url took $resulttime ms");
    }
    
    my $xmlresponse = "";
    
    if ($response->is_success){
	$xmlresponse = $response->body;
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }
    
    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }
    
    $xmlresponse = decode('latin1',$xmlresponse);
    
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
    foreach my $dbs_node ($root->findnodes('/dbis_page/list_dbs/dbs[not(@top_db)]')) {
        $search_count = $dbs_node->findvalue('@db_count');
	$logger->debug("DBIS searchcount is $search_count");
	
        my $i=0;
        foreach my $db_node ($dbs_node->findnodes('db')) {
            $i++;
            # DBIS-Suche verfuegt ueber kein Paging
#            next if ($i <= $offset || $i > $page*$num);
            
            my $single_db_ref = {};

            $single_db_ref->{id}        = $db_node->findvalue('@title_id');
            $single_db_ref->{title}     = decode_utf8($db_node->textContent);

            $single_db_ref->{traffic_light} = $db_node->findvalue('licenses/@traffic_light');

	    $single_db_ref->{access_type} = (defined $type_mapping_ref->{ $single_db_ref->{traffic_light}})?$type_mapping_ref->{ $single_db_ref->{traffic_light}}:'';
	    
            my @types = split(" ",$db_node->findvalue('@db_type_refs'));
            $single_db_ref->{db_types} = \@types;
	    
	    my @urls = ();
	    
	    my @licenses      = $db_node->findnodes('licenses/license');
	    
	    foreach my $license_node (@licenses){
		my $license_id = $license_node->findvalue('@id');

		$logger->debug("License-ID: $license_id");
		
		my @accesses = $license_node->findnodes('access');
		
		foreach my $access_node (@accesses){
		    my $access_id = $access_node->findvalue('@id');
		    
		    $logger->debug("Access-ID: $access_id");
		    
		    my $access_url = $access_node->findvalue('@access_url');
		    $logger->debug("Access url: $access_url");
		    push @urls, $config->get("dbis_baseurl").$access_url if ($access_url);
		}
	    }
	    
	    foreach my $url (@urls){    
		$single_db_ref->{url}       = $url;
		last;  # Nur erster URL zaehlt in Kurztrefferliste
	    }
	    
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

    my $dbis_base = $config->{'dbis'}{'baseurl'};
    
    my $url=$dbis_base."dbliste.php?bib_id=$self->{bibid}&include%5B%5D=licenses&lett=a&all=".$self->{access_all}."&gebiete=$gebiet&sort=alph&xmloutput=1";

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

    my $atime = new Benchmark;
    
    my $response = $ua->get($url)->result;

    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;
    $resulttime = $resulttime * 1000.0; # to ms
    
    if ($resulttime > $config->{'dbis'}{'api_logging_threshold'}){
	$logger->error("DBIS API call $url took $resulttime ms");
    }
    
    my $xmlresponse = "";
    
    if ($response->is_success){
	$xmlresponse = $response->body;
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }
    
    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }
    
    $xmlresponse = decode('latin1',$xmlresponse);
    
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
	my $title         = decode_utf8($db_node->textContent);
	my @types         = split(" ",$db_node->findvalue('@db_type_refs'));
	my $db_types_ref  = \@types;
	
	my $traffic_light = $db_node->findvalue('licenses/@traffic_light');
	
	my $access_type = (defined $type_mapping_ref->{$traffic_light})?$type_mapping_ref->{$traffic_light}:'';
	
	my @urls = ();

	my @licenses      = $db_node->findnodes('licenses/license');
	
	foreach my $license_node (@licenses){
	    my @accesses = $license_node->findnodes('access');

	    foreach my $access_node (@accesses){
		my $access_url = $access_node->findvalue('@access_url');
		push @urls, $config->{'dbis'}{'baseurl'}.$access_url if ($access_url);
	    }
	}

	if ($logger->is_debug){
	    $logger->debug("Title: $title");	    
	    $logger->debug("Traffic light: $traffic_light");
	    $logger->debug("Access Type: $access_type");
	    $logger->debug("URLs: ".join(' ',@urls));
	}
	
	my $record = new OpenBib::Record::Title({id => $id, database => $self->{database}, generic_attributes => { access_type => $access_type }});
	
	$logger->debug("Title is $title");
	
	$record->set_field({field => 'T0331', subfield => '', mult => 1, content => $title});

	foreach my $url (@urls){    
	    $record->set_field({field => 'T4120', subfield => $access_type, mult => 1, content => $url});
	    last; # Nur erster URL zaehlt in Kurztrefferliste
	}
	
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

	my $access_type = $match_ref->{access_type};
        
        my $record = new OpenBib::Record::Title({id => $match_ref->{id}, database => $self->{database}, generic_attributes => { access_type => $access_type }});

        $logger->debug("Title is ".$match_ref->{title});
        
        $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $match_ref->{title}});

        $record->set_field({field => 'T4120', subfield => $access_type, mult => 1, content => $match_ref->{url}}) if ($match_ref->{url});
	
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
