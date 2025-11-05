#####################################################################
#
#  OpenBib::API::HTTP::EZB.pm
#
#  Objektorientiertes Interface zum EZB XML-API
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

package OpenBib::API::HTTP::EZB;

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

    my $sc      = exists $arg_ref->{sc}
        ? $arg_ref->{sc}           : undef;

    my $lc       = exists $arg_ref->{lc}
        ? $arg_ref->{lc}           : undef;

    my $sindex   = exists $arg_ref->{sindex}
        ? $arg_ref->{sindex}           : undef;    
    
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

    my $colors = $access_green + $access_yellow*2 + $access_red*4;

    $logger->debug("green: $access_green ; yellow: $access_yellow ; red: $access_red");
    $logger->debug("colors: $colors");

    
    if (!$colors){
        $colors=$config->{ezb_colors};

        my $colors_mask  = OpenBib::Common::Util::dec2bin($colors);

        $logger->debug("Access: mask($colors_mask)");
        
        $access_green  = ($colors_mask & 0b001)?1:0;
        $access_yellow = ($colors_mask & 0b010)?1:0;
        $access_red    = ($colors_mask & 0b100)?1:0;
    }

    $logger->debug("Postprocessed colors: $colors");
    
    my $self = { };

    bless ($self, $class);
    
    $self->{database}      = $database;

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(5);

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
    $self->{bibid}           = $bibid;
    $self->{lang}            = $lang if ($lang);
    $self->{colors}          = $colors if ($colors);
    $self->{sc}            = $sc if ($sc);
    $self->{lc}            = $lc if ($lc);
    $self->{sindex}        = $sindex if ($sindex);
    $self->{args}          = $arg_ref;
    
    return $self;
}

sub get_titles_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
             ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : 'ezb';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });

    my $memc = $config->get_memc;
	    
    # Referenzierung mit zdbid? Dann zuerst die EZB-ID bestimmen

    if ($id=~m/^zdb:(.+?)$/){
	my $zdbid=$1;

	my $jourid = "";
	
	my $url="http://ezb.ur.de/ezeit/searchres.phtml?colors=$self->{colors}&bibid=$self->{bibid}&jq_type1=ZD&jq_term1=$zdbid&hits_per_page=1&offset=0&lang=de&xmloutput=1";

	my $memc_key = "ezb:title:$url";
	
	if ($memc){
	    $jourid = $memc->get($memc_key);	    
	}

	if (!$jourid){
	
	    $logger->debug("Lookup-URL: $url");
	    
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
	    
	    foreach my $journal_node ($root->findnodes('/ezb_page/ezb_alphabetical_list_searchresult/alphabetical_order/journals/journal')){
		$jourid = $journal_node->findvalue('@jourid');
		last;
	    }
	    
	    return $record unless ($jourid);
	    
	    $logger->debug("Found EZB-ID $jourid for ZDB-ID $zdbid");
	    
	    if ($memc){
		$memc->set($memc_key,$jourid,$config->{memcached_expiration}{'ezb:title'});
	    }
	}

	$id = $jourid;
    }
    
    my $url="http://ezb.ur.de/ezeit/detail.phtml?colors=".((defined $arg_ref->{colors})?$arg_ref->{colors}:$config->{ezb_colors})."&bibid=".((defined $arg_ref->{bibid})?$arg_ref->{bibid}:$config->{ezb_bibid})."&lang=".((defined $arg_ref->{lang})?$arg_ref->{lang}:"de")."&jour_id=$id&xmloutput=1";
        
    my $titles_ref = [];

    my $memc_key = "ezb:title:$url";

    $logger->debug("Memc: ".$memc);
    $logger->debug("Memcached: ".$config->{memcached});    
    
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

    eval {
	my $content = $response->content;

	$content =~s/^.+?<\?xml/<\?xml/sm;

	if ($logger->is_debug){
	    $logger->debug("Cleanedup content: $content");
	}
	my $parser = XML::LibXML->new();
	my $tree   = $parser->parse_string($content);
	my $root   = $tree->getDocumentElement;
	
	my $title     =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/title');
	my $publisher =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/publisher');
	my @zdb_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/ZDB_number');

	my $zdb_node_ref = {};
	
	foreach my $zdb_node (@zdb_nodes){
	    $zdb_node_ref->{ZDB_number}{url} = $zdb_node->findvalue('@url');
	    $zdb_node_ref->{ZDB_number}{content} = $zdb_node->textContent;
	}

	my @classifications_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/subjects/subject');

	my $classifications_ref = [];

	foreach my $classification_node (@classifications_nodes){
	    push @{$classifications_ref}, $classification_node->textContent;
	}

	my @subjects_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/keywords/keyword');

	my $subjects_ref = [];

	foreach my $subject_node (@subjects_nodes){
	    push @{$subjects_ref}, $subject_node->textContent;
	}

	my @homepages_nodes =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/homepages/homepage');

	my $homepages_ref = [];

	foreach my $homepage_node (@homepages_nodes){
	    push @{$homepages_ref}, $homepage_node->textContent;
	}
	
	my $firstvolume    =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/first_fulltext_issue/first_volume');
	my $firstdate      =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/first_fulltext_issue/first_date');
	my $appearence     =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/appearence');
	my $costs          =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/costs');
	my $remarks        =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/remarks');
	my $journal_color  =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/journal_color/@color');
	my $fulltext_url   =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/detail/fulltext');
	
	my @periods =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/periods/period');

	my @issns =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/P_ISSNs/P_ISSN');

	my @eissns =  $root->findnodes('/ezb_page/ezb_detail_about_journal/journal/detail/E_ISSNs/E_ISSN');
	
	my $issns_ref = [];

	foreach my $issn_node (@issns){
	    push @{$issns_ref}, $issn_node->textContent;
	}

	foreach my $issn_node (@eissns){
	    push @{$issns_ref}, $issn_node->textContent;
	}
	
	$record->set_field({field => 'T0331', subfield => '', mult => 1, content => $title}) if ($title);
	$record->set_field({field => 'T0412', subfield => '', mult => 1, content => $publisher}) if ($publisher);

	my $erscheinungsverlauf = "";

	if ($firstvolume){
	    $erscheinungsverlauf.="Jg. $firstvolume";
	}
	if ($firstdate){
	    $erscheinungsverlauf.=" ($firstdate)";
	}

	if ($erscheinungsverlauf){
	    $record->set_field({field => 'T0405', subfield => '', mult => 1, content => $erscheinungsverlauf});
	}
	
	if ($zdb_node_ref->{ZDB_number}{url}){
	    $record->set_field({field => 'T0662', subfield => '', mult => 1, content => $zdb_node_ref->{ZDB_number}{url}})
	}
	if ($zdb_node_ref->{ZDB_number}{content}){
	    $record->set_field({field => 'T0663', subfield => '', mult => 1, content => $zdb_node_ref->{ZDB_number}{content}}) ;
	}
	else {
	    $record->set_field({field => 'T0663', subfield => '', mult => 1, content => 'Weiter zur Zeitschrift' }) ;
	}

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

	$mult=1;
	foreach my $issn (@$issns_ref){
	    $record->set_field({field => 'T0543', subfield => '', mult => $mult, content => $issn});
	    $mult++;
	}
	
	$record->set_field({field => 'T0523', subfield => '', mult => 1, content => $appearence}) if ($appearence);
	$record->set_field({field => 'T0511', subfield => '', mult => 1, content => $costs}) if ($costs);
	$record->set_field({field => 'T0501', subfield => '', mult => 1, content => $remarks}) if ($remarks);

	my $type_mapping_ref = {
	    'green'    => 'g', # green
		'yellow'   => 'y', # yellow
		'red'      => 'r', # red
	};

	$record->set_field({field => 'T0517', subfield => '', mult => 1, content => $journal_color}) if ($journal_color);

	my $access_type = $type_mapping_ref->{$journal_color};

	$logger->debug("journal_color: $journal_color ; access_type: $access_type");

	if ($logger->is_debug){
	    $logger->debug("Homepages: ".YAML::Dump($homepages_ref));
	}

	my $mult_homepage = 1;
	my $mult_fulltext = 1;

	if ($fulltext_url){
	    $record->set_field({field => 'T4120', subfield => $access_type, mult => $mult_fulltext++, content => $fulltext_url });
	}
	
	foreach my $homepage (@$homepages_ref){
	    $record->set_field({field => 'T4120', subfield => $access_type, mult => $mult_fulltext++, content => $homepage }) if ($journal_color eq "green");

	    $record->set_field({field => 'T2662', subfield => '', mult => $mult_homepage++, content => $homepage});
	}

	$mult = 2;
	foreach my $period (@periods){
	    my $color      = $period->findvalue('journal_color/@color');
	    my $color_code = $period->findvalue('journal_color/@color_code');
	    
	    $logger->debug("Color: $color");

	    my $image = $config->get('dbis_green_yellow_red_img');
	    
	    if    ($color eq 'green'){
		$image = $config->get('dbis_green_img');
		$access_type = "g";
	    }
	    elsif ($color eq 'yellow'){
		$image = $config->get('dbis_yellow_img');
		$access_type = "y";
	    }
	    elsif ($color_code == 3){
		$image = $config->get('dbis_green_yellow_img');
		$access_type = "f"; # fulltext available
	    }
	    elsif ($color eq 'red'){
		$image = $config->get('dbis_red_img');
		$access_type = "r";	    
	    }
	    elsif ($color_code == 5){
		$image = $config->get('dbis_green_green_red_img');
	    }
	    elsif ($color eq 'yellow_red'){
		$image = $config->get('dbis_yellow_red_img');
		$access_type = "l";	    
	    }

	    my $label = $period->findvalue('label');

	    $label=~s/\s+/ /g;
	    
	    my $warpto_link = $period->findvalue('warpto_link/@url');
	    my $readme_link = $period->findvalue('readme_link/@url');

	    $warpto_link = uri_unescape($warpto_link);
	    
	    if ($logger->is_debug){
		$logger->debug("L: $label WL: $warpto_link RL: $readme_link");
	    }

	    #	$record->set_field({field => 'T0663', subfield => '', mult => $mult, content => "<img src=\"$image\" alt=\"$color\"/> $label" });

	    $logger->debug("Final Accesstype: $access_type");
	    
	    #$record->set_field({field => 'T4120', subfield => $access_type, mult => $mult, content => $warpto_link }) if ($warpto_link);

	    my $period_ref = {
		readme_link => $readme_link,
		warpto_link => $warpto_link,
		label       => $label,
	    };
	    
	    $record->set_field({field => 'T3662', subfield => $access_type, mult => $mult, content => $period_ref });
	    $mult++;
	}


    };

    if ($@){
    }
    # # Readme-Informationen verarbeiten


    
    # my $readme     =  $root->findvalue('/ezb_page/ezb_detail_about_journal/journal/');

    
    # my $readme = $self->_get_readme({id => $id});

    # $mult=2;
    # if ($readme->{location}){
    #     $record->set_field({field => 'T0662', subfield => '', mult => $mult, content => $readme->{location} });
    #     $record->set_field({field => 'T0663', subfield => '', mult => $mult, content => 'ReadMe'});
    # }
    # elsif ($readme->{periods}){
    #     foreach my $period (@{$readme->{periods}}){
    #         my $color = $period->{color};

    #         $logger->debug("Color: $color");
            
    #         my $image = $config->get('dbis_green_yellow_red_img');

    #         if    ($color == 'green'){
    #             $image = $config->get('dbis_green_img');
    #         }
    #         elsif ($color == 'yellow'){
    #             $image = $config->get('dbis_yellow_img');
    #         }
    #         elsif ($color == 3){
    #             $image = $config->get('dbis_green_yellow_img');
    #         }
    #         elsif ($color == 'red'){
    #             $image = $config->get('dbis_red_img');
    #         }
    #         elsif ($color == 5){
    #             $image = $config->get('dbis_green_green_red_img');
    #         }
    #         elsif ($color == 6){
    #             $image = $config->get('dbis_yellow_red_img');
    #         }
            
    #         $record->set_field({field => 'T0663', subfield => '', mult => $mult, content => "<img src=\"$image\" alt=\"$period->{color}\"/>&nbsp;$period->{label}" });
    #         $record->set_field({field => 'T0662', subfield => '', mult => $mult, content => $period->{warpto_link} });
    #         $mult++;
    #         $record->set_field({field => 'T0663', subfield => '', mult => $mult, content => "ReadMe: $period->{label}" });
    #         $record->set_field({field => 'T0662', subfield => '', mult => $mult, content => $period->{readme_link} });
    #         $mult++;
    #     }
    # }

    $record->set_holding([]);
    $record->set_circulation([]);

    if ($memc){
	$memc->set($memc_key,$record->get_fields,$config->{memcached_expiration}{'ezb:title'});
    }
    
    return $record;
}

sub _get_readme {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $ua     = $self->get_client;
    
    my $url="https://ezb.ur.de/ezeit/show_readme.phtml?bibid=$self->{bibid}&lang=$self->{lang}&jour_id=$id&xmloutput=1";

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
    
    # Fehlermeldungen im XML entfernen

    $response = $response->content;
    
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
            $location="https://ezb.ur.de/ezeit/$location";
        }
        
        return {
            location => $location
        };
    }

    my $title    =  $root->findvalue('/ezb_page/ezb_readme_page/journal/title');

    my @periods_nodes =  $root->findnodes('/ezb_page/ezb_readme_page/journal/periods/period');

    my $periods_ref = [];

    foreach my $period_node (@periods_nodes){
        my $this_period_ref = {};

        $this_period_ref->{color}       = $period_node->findvalue('journal_color/@color');
        $this_period_ref->{label}       = $period_node->findvalue('label');
        $this_period_ref->{readme_link} = uri_unescape($period_node->findvalue('readme_link/@url'));
        $this_period_ref->{warpto_link} = uri_unescape($period_node->findvalue('warpto_link/@url'));

        unless ($this_period_ref->{readme_link}=~m/^http/){
            $this_period_ref->{readme_link}="https://ezb.ur.de/ezeit/$this_period_ref->{readme_link}";
        }
        unless ($this_period_ref->{warpto_link}=~m/^http/){
            $this_period_ref->{warpto_link}="https://ezb.ur.de/ezeit/$this_period_ref->{readme_link}";
        }

        if ($logger->is_debug){
            $logger->debug(YAML::Dump($this_period_ref));
        }
        
        push @{$periods_ref}, $this_period_ref;
    }

    return {
        periods  => $periods_ref,
        title    => $title,
    };
}

sub get_classifications {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $url="https://ezb.ur.de/ezeit/fl.phtml?colors=$self->{colors}&bibid=$self->{bibid}&lang=$self->{lang}&xmloutput=1";

    my $classifications_ref = [];

    my $memc_key = "ezb:classifications:$url";

    my $memc = $config->get_memc;
    
    $logger->debug("Memc: ".$memc);
    $logger->debug("Memcached: ".$config->{memcached});    
    
    if (0 == 1 && $memc){
        my $classifications_ref = $memc->get($memc_key);

	if ($classifications_ref){
	    if ($logger->is_debug){
		$logger->debug("Got classifications for key $memc_key from memcached");
	    }

	    return $classifications_ref;
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
	return $classifications_ref;
    }
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response->content);
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
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($classifications_ref));
    }

    if ($memc){
	$memc->set($memc_key,$classifications_ref,$config->{memcached_expiration}{'ezb:classifications'});
    }

    my $hits = scalar @$classifications_ref;
    
    return {
	items => $classifications_ref,
	hits => $hits,
    };
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

    my $url="https://ezb.ur.de/ezeit/searchres.phtml?colors=$self->{colors}&bibid=$self->{bibid}&sc=$self->{sc}&lc=$self->{lc}&sindex=$self->{sindex}&".$self->querystring."&hits_per_page=$num&offset=$offset&lang=".((defined $self->{lang})?$self->{lang}:"de")."&xmloutput=1";

    my $titles_ref = [];

    my $memc_key = "ezb:search:$url";

    my $memc = $config->get_memc;
    
    if ($memc){
        my $result_ref = $memc->get($memc_key);

	if (defined $result_ref->{_matches}){
	    if ($logger->is_debug){
		$logger->debug("Got search result for key $memc_key from memcached");
	    }

	    $self->{resultcount}   = $result_ref->{resultcount};
	    $self->{_matches}      = $result_ref->{_matches};

	    return $self; 
	}
    }
    
    $logger->debug("Request: $url");

    my $ua      = $self->get_client;
    
    my $request = HTTP::Request->new('GET' => $url);
    
    my $response = $ua->request($request);

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success) {
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }

    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response->content);
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
        $current_page_ref->{desc}   = $nav_node->textContent;
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
        $singlejournal_ref->{title}       = $journal_node->findvalue('title');
        $singlejournal_ref->{color}{code} = $journal_node->findvalue('journal_color/@color_code');
        $singlejournal_ref->{color}{desc} = $journal_node->findvalue('journal_color/@color');

        push @{$journals_ref}, $singlejournal_ref;
    }

    $logger->debug("Found $search_count titles");

    if ($memc){
	my $result_ref = {
	    'resultcount'  => $search_count,
	    '_matches'     => $journals_ref,
	};

	$logger->debug("Storing search result to memcached to $memc_key");
	$memc->set($memc_key,$result_ref,$config->{memcached_expiration}{'ezb:search'});
    }
    
    $self->{resultcount}   = $search_count;
    $self->{_matches}      = $journals_ref;
    
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

    my $config = $self->get_config;

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
            elsif ($field eq "issn" && $searchtermstring) {
                push @searchterms, {
                    field   => 'IS',
                    content => $searchtermstring
                };
            }
            elsif ($field eq "zdbid" && $searchtermstring) {
                push @searchterms, {
                    field   => 'ZD',
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
