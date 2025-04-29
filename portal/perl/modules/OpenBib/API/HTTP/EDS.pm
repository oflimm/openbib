#####################################################################
#
#  OpenBib::API::HTTP::EDS.pm
#
#  Objektorientiertes Interface zum EDS API
#
#  Dieses File ist (C) 2020-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::API::HTTP::EDS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use HTML::Entities;
use Log::Log4perl qw(get_logger :levels);
use Mojo::UserAgent;
use Storable;
use JSON::XS;
use URI::Escape;
use YAML ();
use Mojo::Base -strict, -signatures;

use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::API::HTTP);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $api_password   = exists $arg_ref->{api_password}
        ? $arg_ref->{api_password}       : undef;

    my $api_user  = exists $arg_ref->{api_user}
        ? $arg_ref->{api_user}      : undef;

    my $api_profile = exists $arg_ref->{api_profile}
        ? $arg_ref->{api_profile}   : undef;
    
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}      : '';

    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}     : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;
    
    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);
    
    my $ua = Mojo::UserAgent->new();
    $ua->transactor->name('USB Koeln/1.0');
    $ua->connect_timeout(10);
    $ua->max_redirects(2);

    $self->{client}        = $ua;
        
    $self->{api_user}     = (defined $api_user)?$api_user:(defined $config->{eds}{default_user})?$config->{eds}{default_user}:undef;
    $self->{api_password} = (defined $api_password )?$api_password :(defined $config->{eds}{default_password} )?$config->{eds}{default_password} :undef;
    $self->{api_profile}  = (defined $api_profile )?$api_profile :(defined $config->{eds}{default_profile} )?$config->{eds}{default_profile} :undef;
    
    $self->{sessionID} = $sessionID;

    if ($config){
        $self->{_config}        = $config;
    }

    if ($database){
        $self->{_database}      = $database;
    }

    if ($queryoptions){
        $self->{_queryoptions}  = $queryoptions;
    }

    if ($searchquery){    
        $self->{_searchquery}   = $searchquery;
    }
    
    return $self;
}

sub send_retrieve_request {
    my ($self,$arg_ref) = @_;
    
    # Set defaults
    my $id       = exists $arg_ref->{id}
    ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my ($edsdatabase,$edsid)=$id=~m/^(.+?)::(.+)$/;    
        
    my $url = $config->get('eds')->{'retrieve_url'};

    $logger->debug("DB - ID: $edsdatabase - $edsid");
    
    $url.="?dbid=".$edsdatabase."&an=".$edsid;

    if ($logger->is_debug()){
	$logger->debug("Request URL: $url");
    }

    my $threshold_starttime=new Benchmark;

    my $header_ref = {'Content-Type' => 'application/json', 'x-authenticationToken' => $self->{authtoken}, 'x-sessionToken' => $self->{sessiontoken}};

    if ($logger->is_debug){
	$logger->debug("Setting default header with x-authenticationToken: ".$self->{authtoken}." and x-sessionToken: ".$self->{sessiontoken});
    }
    
    my $json_result_ref = {};
    
    my $response = $ua->get($url => $header_ref)->result;

    if ($response->is_success){
	eval {
	    $json_result_ref = decode_json $response->body;
	};
	if ($@){
	    $logger->error('Decoding error: '.$@);
	    return $json_result_ref;
	}
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return $json_result_ref;
    }

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }

    my $threshold_endtime      = new Benchmark;
    my $threshold_timeall    = timediff($threshold_endtime,$threshold_starttime);
    my $threshold_resulttime = timestr($threshold_timeall,"nop");
    $threshold_resulttime    =~s/(\d+\.\d+) .*/$1/;
    $threshold_resulttime = $threshold_resulttime * 1000.0; # to ms
    
    if (defined $config->get('eds')->{'api_logging_threshold'} && $threshold_resulttime > $config->get('eds')->{'api_logging_threshold'}){
	$url =~s/\?.+$//; # Don't log args
	$logger->error("EDS API call $url took $threshold_resulttime ms");
    }
    
    return $json_result_ref;
}

sub send_search_request {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->get_config;
    my $ua           = $self->get_client;
    my $searchquery  = $self->get_searchquery;
    my $queryoptions = $self->get_queryoptions;
    
    # Used Parameters
    my $sorttype          = $queryoptions->get_option('srt');
    my $sortorder         = $queryoptions->get_option('srto');
    my $defaultop         = $queryoptions->get_option('dop');
    my $drilldown         = $queryoptions->get_option('dd');
    my $searchft          = $queryoptions->get_option('searchft');
    my $showft            = $queryoptions->get_option('showft');
    my $showft1           = $queryoptions->get_option('showft1');

    # Pagination parameters
    my $page              = $queryoptions->get_option('page');
    my $num               = $queryoptions->get_option('num');

    my $from              = ($page - 1)*$num;

    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $url = $config->get('eds')->{'search_url'};

    # search options
    my @search_options = ();

    # Default
    my $eds_reverse_sort_mapping_ref = $config->get('eds_reverse_sort_mapping');

    my $sort_eds = $eds_reverse_sort_mapping_ref->{$sorttype."_".$sortorder} ? $eds_reverse_sort_mapping_ref->{$sorttype."_".$sortorder} : "relevance" ;
    
    push @search_options, "sort=$sort_eds";
    push @search_options, "searchmode=all";
    push @search_options, "highlight=n";
    push @search_options, "includefacets=y";
    push @search_options, "autosuggest=n";
    #push @search_options, "view=brief";
    push @search_options, "view=detailed";    

    # necessary to make the fulltext limiter work
    if ($searchft) {
	push @search_options, "expander=fulltext";
    }
    elsif ($showft) {
	push @search_options, "limiter=FT:y";
    }
    elsif ($showft1) {
	push @search_options, "limiter=FT1:y"; # Ehemals FT:y
    }

    push @search_options, "resultsperpage=$num" if ($num);
    push @search_options, "pagenumber=$page" if ($page);

    $self->parse_query($searchquery);

    my $query_ref  = $self->get_query;
    my $filter_ref = $self->get_filter;

    push @$query_ref, @$filter_ref;    
    push @$query_ref, @search_options;
    
    my $args = join('&',@$query_ref);
    
    $url = $url."?$args";

    if ($logger->is_debug()){
	$logger->debug("Request URL: $url");
    }

    my $threshold_starttime=new Benchmark;

    my $json_result_ref = {};

    my $header_ref = {'Content-Type' => 'application/json', 'x-authenticationToken' => $self->{authtoken}, 'x-sessionToken' => $self->{sessiontoken}};
    
    if ($logger->is_debug){
	$logger->debug("Setting default header with x-authenticationToken: ".$self->{authtoken}." and x-sessionToken: ".$self->{sessiontoken});
    }
    
    my $response = $ua->get($url => $header_ref)->result;

    if ($response->is_success){
	eval {
	    $json_result_ref = decode_json $response->body;
	};
	if ($@){
	    $logger->error('Decoding error: '.$@);
	    return $json_result_ref;
	}
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return $json_result_ref;
    }

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }

    my $threshold_endtime      = new Benchmark;
    my $threshold_timeall    = timediff($threshold_endtime,$threshold_starttime);
    my $threshold_resulttime = timestr($threshold_timeall,"nop");
    $threshold_resulttime    =~s/(\d+\.\d+) .*/$1/;
    $threshold_resulttime = $threshold_resulttime * 1000.0; # to ms
    
    if (defined $config->get('eds')->{'api_logging_threshold'} && $threshold_resulttime > $config->get('eds')->{'api_logging_threshold'}){
	$url =~s/\?.+$//; # Don't log args
	$logger->error("EDS API call $url took $threshold_resulttime ms");
    }
  
    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $searchtime   = timestr($stimeall,"nop");
	$searchtime      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Zeit fuer EDS HTTP-Request $searchtime");
    }
        
    return $json_result_ref;
}


sub get_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id       = exists $arg_ref->{id}
        ? $arg_ref->{id}        : '';

    my $database = exists $arg_ref->{database}
        ? $arg_ref->{database}  : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $record = new OpenBib::Record::Title({ database => $database, id => $id });
    
    my $memc_key = "eds:title:$database:$id";

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
        
    $self->connect_eds;

    my $json_result_ref = $self->send_retrieve_request($arg_ref);

    if (defined $json_result_ref->{ErrorNumber} && $json_result_ref->{ErrorNumber}){
	$self->{authtoken}    = $self->_create_authtoken;
	$self->{sessiontoken} = $self->_create_sessiontoken;

	$json_result_ref = $self->send_retrieve_request($arg_ref);		
    }

    my $fields_ref = ();

    # Gesamtresponse in eds_source
    push @{$fields_ref->{'eds_source'}}, {
	content => $json_result_ref
    };


    my $is_electronic_ressource = 0;
    my $link_mult = 1;


    # Allgemeine Trefferinformationen
    {
	push @{$fields_ref->{'T0501'}}, {
	    content => "Datenquelle: " . $json_result_ref->{'Record'}{'Header'}{'DbLabel'},
	} if ($json_result_ref->{'Record'}{'Header'}{'DbLabel'});

	push @{$fields_ref->{'T0501'}}, {
	    content => "Bei etwa 70% der in BASE enthaltenen Dokumente sind die Volltexte frei zugänglich (Open Access), die restlichen 30% sind Dokumente ohne Volltext oder Dokumente, bei denen der Volltext nicht frei zugänglich ist.",
	} if ($json_result_ref->{'Record'}{'Header'}{'DbId'} eq "edsbas");

	
	push @{$fields_ref->{'T0662'}}, {
	    subfield => '', 
	    mult     => $link_mult, 
	    content  => $json_result_ref->{'Record'}{'PLink'}
	} if ($json_result_ref->{'Record'}{'PLink'});
    
	push @{$fields_ref->{'T0663'}},{
	    subfield => '', 
	    mult     => $link_mult, 
	    content  => $json_result_ref->{'Record'}{'Header'}{'DbLabel'}
	} if ($json_result_ref->{'Record'}{'Header'}{'DbLabel'});
	
	$link_mult++;
    }
    
    # Volltextlinks
    {


	# Zugriffstatus
	#
	# '' : Keine Ampel
	# ' ': Unbestimmt g oder y oder r
	# 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
	# 'g': Freier Zugriff (green)
	# 'y': Lizensierter Zugriff (yellow)
	# 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
	# 'r': Kein Zugriff (red)
		
	my $url = "";
	
	eval { 	
	    $url = $json_result_ref->{'Record'}{'FullText'}{'Links'}[0]{'Link'}[0]{'Url'};
	};
	
	if ($url) { # ID=bth:94617232
	    push @{$fields_ref->{'T4120'}}, {
		subfield => 'y', # Eingeschraenkter Zugang / yellow
		mult     => $link_mult, 
		content  => $url};
	    
	    push @{$fields_ref->{'T0662'}}, {
		subfield => '', 
		mult     => $link_mult, 
		content  => $url};
	    
	    push @{$fields_ref->{'T0663'}}, {
		subfield => '',
		mult     => $link_mult, 
		content  => "Volltext"};
	    # Todo: Zugriffstatus 'yellow' hinzufuegen

	    $link_mult++;
	}
	else { 
	    my $available = '';
	    
	    eval {
		$available = $json_result_ref->{'Record'}{'FullText'}{'Text'}{'Availability'}
	    };
	    
	    if ($available == 1 && $json_result_ref->{'Record'}{PLink}) {
		push @{$fields_ref->{'T4120'}}, {
		    subfield => 'y', # Eingeschraenkter Zugang / yellow
		    mult     => $link_mult, 
		    content  => $json_result_ref->{'Record'}{PLink}};
		
		push @{$fields_ref->{'T0662'}}, {
		    subfield => '', 
		    mult     => $link_mult, 
		    content  => $json_result_ref->{'Record'}{PLink}};
		
		push @{$fields_ref->{'T0663'}}, {
		    subfield => '', 
		    mult     => $link_mult, 
		    content  => "HTML-Volltext"};
		# Todo: Zugriffstatus 'yellow' hinzufuegen
		$link_mult++;
	    }
	}

	my @links = ();
	
	eval {
	    @links = @{$json_result_ref->{'Record'}{'FullText'}{'Links'}};
	};

	if (@links){
	    foreach my $link_ref (@links){
		my $url = (defined $link_ref->{'Url'})?$link_ref->{'Url'}:'';

		if (defined $link_ref->{'Type'} && $link_ref->{'Type'} =~m/^(ebook|pdflink|other)$/){
		    push @{$fields_ref->{'T4120'}}, {
			subfield => 'y', # Eingeschraenkter Zugang / yellow
			mult     => $link_mult, 
			content  => $url,
		    };
		    
		    push @{$fields_ref->{'T0662'}}, {
			subfield => '', 
			mult     => $link_mult, 
			content  => $url,
		    };
		    
		    push @{$fields_ref->{'T0663'}}, {
			subfield => '', 
			mult     => $link_mult, 
			content  => "Volltext"
		    };
		    # Todo: Zugriffstatus 'yellow' hinzufuegen
		    $link_mult++;
		}
	    }
	}
	
	# arXiv, DOAJ und OAIster: Publikationstyp einfuegen und CustomLink auslesen
	if ($json_result_ref->{Record}{Header}{DbId} =~ /^(edsarx|edsdoj|edsoai)$/) {
	    unless ($json_result_ref->{'Record'}{'Header'}{'PubType'}) {
		push @{$fields_ref->{'T0800'}}, {
		    subfield => '', 
		    mult     => 1, 
		    content  => "electronic resource"};
		$is_electronic_ressource = 1;
	    }
	    
	    $url = '';
	    
	    eval {
		$url = $json_result_ref->{'Record'}{'FullText'}{'CustomLinks'}[0]{'Url'};
	    };
	    
	    if ($url) {
		$url =~ s!(.*)\#\?$!$1!; # OAIster: "#?" am Ende entfernen, z.B. ID=edsoai:edsoai.859893876 ; ID=edsoai:edsoai.690666320
		$url =~ s!(http://etheses.bham.ac.uk/[^/]+/).*ThumbnailVersion.*\.pdf!$1!; # Sonderanpassung fuer etheses.bham.ac.uk, z.B. ID=edsoai:edsoai.690666320

		my $color    = "g";
                my $linktext = "Volltext";
		if ($json_result_ref->{Record}{Header}{DbId} eq "edsoai") {
		    $color = " " ; # urspruenglich green_on_red / Volltext eventuell nicht zugänglich (s. Hinweise)
		    $linktext = "Volltext eventuell nicht zugänglich (s. Hinweise)";
		}
		
		push @{$fields_ref->{'T4120'}}, {
		    subfield => $color,
		    mult     => $link_mult, 
		    content  => $url
		};
		
		push @{$fields_ref->{'T0662'}}, {
		    subfield => '', 
		    mult     => $link_mult, 
		    content  => $url
		};
		
		push @{$fields_ref->{'T0663'}}, {
		    subfield => '', 
		    mult     => $link_mult, 
		    content  => $linktext
		};
		$link_mult++;
	    }
	}
	
	
	# Science cititation index: hart verlinken
	# Hinweis pkostaedt: Der Link "Citing Articles" funktioniert nicht in jedem Fall, z.B. ID=edswss:000312205100002
	if ($json_result_ref->{Record}{Header}{DbId} =~ /^(edswsc|edswss)$/ && $json_result_ref->{Record}{Header}{An}) {
	    my $url = "http://gateway.isiknowledge.com/gateway/Gateway.cgi?&GWVersion=2&SrcAuth=EBSCO&SrcApp=EDS&DestLinkType=CitingArticles&KeyUT=" . $json_result_ref->{Record}{Header}{An} . "&DestApp=WOS";
	    
	    push @{$fields_ref->{'T0662'}}, {
		subfield => '', 
		mult     => $link_mult, 
		content  => $url
	    };
	    
	    push @{$fields_ref->{'T0663'}}, {
		subfield => '', 
		mult => $link_mult, 
		content => "Citing Articles (via Web of Science)"
	    };

	    $link_mult++;
	}
    }

    # BibEntity
    
    my $pagerange = "";
    
    {
	foreach my $thisfield (keys %{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}}){
	    
	    if ($thisfield eq "Titles"){
		foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		    
		    if ($item->{Type} eq "main" && ! $self->have_field_content('T0331',$item->{TitleFull})){
			push @{$fields_ref->{'T0331'}}, {
			    content => $item->{TitleFull}
			};
		    }
		}
	    }
	    
	    if ($thisfield eq "Subjects"){
		foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		    
		    push @{$fields_ref->{'T0710'}}, {
			content => $item->{SubjectFull}
		    } if (! $self->have_field_content('T0710',$item->{SubjectFull} ));
		}
	    }
	    
	    if ($thisfield eq "Languages"){
		foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		    push @{$fields_ref->{'T0015'}}, {
			content => $item->{Text}
		    } if (!$self->have_field_content('T0015',$item->{Text} ));
		}
	    }
	    
	    # DOI in 0552
	    if ($thisfield eq "Identifiers"){
		foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		    next unless ($item->{Type} eq "doi");
		    
		    push @{$fields_ref->{'T0552'}}, {
			subfield => '', 			
			content  => $item->{Value}
		    } if (!$self->have_field_content('T0552',$item->{Value} ));
		}
	    }
	    
	    
	    if ($thisfield eq "PhysicalDescription"){
		my $startpage;
		my $endpage;
		my $pagecount;
		
		eval {
		    $startpage = $json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}{Pagination}{StartPage};
		};
		
		eval {
		    $pagecount = $json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}{Pagination}{PageCount};
		};
		
		if ($startpage){
		    $startpage=~s{^0+}{}g;
		    
		    if ($pagecount && $pagecount > 1){
			$endpage = $startpage + $pagecount - 1;
		    }
		}
		
		$pagerange = $startpage if ($startpage);
		$pagerange .= " - $endpage" if ($endpage);
		
		$pagerange = "S. ".$pagerange if ($pagerange);
		
		
		if ($pagerange){
		    push @{$fields_ref->{'T0596'}}, {
			content => $pagerange,
			subfield => "s",
		    };
		}
	    }
	    
	}
    }

    # BibRelationships

    my $issue   = "";    
    my $volume  = "";
    my $journal = "";
    my $year    = "";
    { 
	if (defined $json_result_ref->{Record}{RecordInfo}{BibRecord} && defined $json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}){
	    
	    
	    if (defined $json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}){
		foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}}){
		    if ($logger->is_debug){
			$logger->debug("DebugRelationShips".YAML::Dump($item));
		    }
		    if (defined $item->{PersonEntity} && defined $item->{PersonEntity}{Name} && defined $item->{PersonEntity}{Name}{NameFull}){
			my $name = $item->{PersonEntity}{Name}{NameFull};
			
			$name =~ s{([^\(]+)\, (Verfasser|Herausgeber|Mitwirkender|Sonstige).*}{$1}; # Hinweis pkostaedt: GND-Zusaetze abschneiden, z.B. ID=edswao:edswao.47967597X
			$name =~ s{([^\(]+)\, \(DE\-.*}{$1}; # Hinweis pkostaedt: GND-ID abschneiden, z.B. ID=edswao:edswao.417671822
			
			
			push @{$fields_ref->{'T0100'}}, {
			    content => $name,
			} if (!$self->have_field_content('T0100',$name ));
		    }
		}
	    }
	    
	    if (defined $json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}{IsPartOfRelationships}){
		
		foreach my $partof_item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}{IsPartOfRelationships}}){	
		    if (defined $partof_item->{BibEntity}){
			
			foreach my $thisfield (keys %{$partof_item->{BibEntity}}){
			    
			    if ($thisfield eq "Titles"){
			    	foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    $journal = $item->{TitleFull};
			    	    push @{$fields_ref->{'T0376'}}, {
			    		content => $item->{TitleFull}
			    	    } if (!$self->have_field_content('T0376',$item->{TitleFull} ));
				    
			    	}
			    }
			    
			    if ($thisfield eq "Dates"){
				foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    $year = $item->{'Y'};
				    push @{$fields_ref->{'T0425'}}, {
					content => $item->{'Y'}
				    } if (!$self->have_field_content('T0425',$item->{Y} ));
				    
				}
			    }
			    
			    if ($thisfield eq "Numbering"){
				foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    my $type  = $item->{Type};
				    my $value = $item->{Value};
				    
				    if ($value && $type eq "volume"){
					$volume = $value;
					
					push @{$fields_ref->{'T0089'}}, {
					    content => $value,
					} if (!$self->have_field_content('T0089',$value ));
					push @{$fields_ref->{'T0596'}}, {
					    content => $value,
					    subfield => "b",
					} if (!$self->have_field_content('T0596b',$value ));
				    }
				    elsif ($value && $type eq "issue"){
					$issue = $value;
					push @{$fields_ref->{'T0596'}}, {
					    content => $value,
					    subfield => "h",
					} if (!$self->have_field_content('T0596h',$value ));
					
				    }
				    
				}
			    }
			    
			    if ($thisfield eq "Identifiers"){
				foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    my $type  = $item->{Type};
				    my $value = $item->{Value};
				    
				    if ($value && $type eq "issn-print"){
					# Normieren
					$value =~ s/^(\d{4})(\d{3}[0-9xX])$/$1-$2/;
					
					# Todo: 543 oder 585
					push @{$fields_ref->{'T0585'}}, {
					    content => $value,
					} if ($value =~m/^\d{4}\-?\d{3}[0-9xX]$/  && !$self->have_field_content('T0585',$value ));
				    }
				    elsif ($type =~/^issn-([0-9xX]{8})$/){
					$value = $1;
					
					# Normieren
					$value =~ s/^(\d{4})(\d{3}[0-9xX])$/$1-$2/;
					
					# Todo: 543 oder 585
					push @{$fields_ref->{'T0585'}}, {
					    content => $value,
					} if ($value =~m/^\d{4}\-?\d{3}[0-9xX]$/  && !$self->have_field_content('T0585',$value ));			      
				    }
				    elsif ($value && $type eq "isbn-print"){
					# Todo: 540
					push @{$fields_ref->{'T0540'}}, {
					    content => $value,
					} if (!$self->have_field_content('T0540',$value));
				    }
				}
			    }
			}
		    }
		}
	    }
	}
    }
    
    # Todo: 
    # Jahr und Heft nicht verwenden, wenn DbId = edsarx
    # Serial nicht anwenden, wenn DbId = rih

    # Items

    {

	if (defined  $json_result_ref->{'Record'}{'Items'}){

	    my $items_field_map_ref = {
		ItemTitle       => 'T0590',
		ItemAuthor      => 'T0591',
		ItemLanguage    => 'T0516',
		Abstract        => 'T0750',
		AbstractNonEng  => 'T0750',
		TitleSource     => 'T0590',
		TitleSourceBook => 'T0451',
		Publisher       => 'T0419',
		DatePubCY       => 'T0425',
		ISBN            => 'T0540',
		ISSN	        => 'T0585',
		TypeDocument    => 'T4410',
	    };

	    
	    foreach my $item (@{$json_result_ref->{'Record'}{'Items'}}){
		my $label = $item->{Label};
		my $data  = $item->{Data};
		my $name  = $item->{Name};

		$logger->debug("Data pre:$data");

		# &gt; &lt; auf <,> vereinfachen
		$data =~ s{&lt;}{<}g;
		$data =~ s{&gt;}{>}g;
		
		# Data breinigen. Hinweise pkostaedt
		$data =~ s{<br \/>}{ ; }g;
		$data =~ s{<relatesTo>[^<]+<\/relatesTo><i>[^<]+<\/i>}{}g; # z.B. <relatesTo>2</relatesTo><i> javierm@electrica.cujae.edu.cu</i>
		$data =~ s{<i>([^<]+)<\/i>}{$1}g;
		$data =~ s{<[^>]+>([^<]+)<\/[^>]+>}{$1}g;                  # z.B. <searchLink fieldCode="JN" term="%22Linux%22">Linux</searchLink>
		$data =~ s{&lt;.+?&gt;}{}g;                                # z.B. rih:2012-09413, pdx:0209854
		$data =~ s{&amp;amp;}{&amp;}g;                             # z.B. pdx:0209854

		$logger->debug("Item - Label:$label - Name:$name Data:$data");
		
		if ($name =~ /^(Title|Author|Language|Abstract|AbstractNonEng|TitleSource|TitleSourceBook|Publisher|DatePubCY|ISBN|ISSN|TypeDocument)$/) {

		    if ($name eq 'Publisher') {
			$data =~ s/,\s+\d{4}$//;                          # z.B. edsgsl:solis.00547468 (Hamburg : Diplomica Verl., 2009 -> Hamburg : Diplomica Verl.)
		    } 
		    elsif ($name eq 'TitleSource' && $json_result_ref->{Record}{Header}{DbId} eq 'edsoai' && $data =~ /urn:/) {
			next;                                             # z.B. edsoai:edsoai.824612814
		    }
		    elsif ($name eq 'ISSN'){
			# Normieren, hier spezielle wegen Dubletten zu  BibRelationShips
			$data =~ s/^(\d{4})(\d{3}[0-9xX])$/$1-$2/;
		    }
		    elsif ($name eq 'TypeDocument'){
			if ($data eq "Article"){
			    $data = "Aufsatz";
			}
		    }

		    if (defined $items_field_map_ref->{$name}){
			push @{$fields_ref->{$items_field_map_ref->{$name}}}, {
			    content => $data,
			} if (!$self->have_field_content($items_field_map_ref->{$name},$data));
			
		    }
		    # if ($Result{$name}) {
		    #     if ($name eq 'Abstract') {
		    # 	$Result{$name} .= '<br/>';
		    # 	$Result{$name} .= '<br/>' if length($data) > 100;
		    #     } else {
		    # 	$Result{$name} .= ' ; ';
		    #     }
		    # }
		    # $Result{$name} .= $data;
		}
		elsif ($name eq 'Subject') {
		    if ($label eq 'Time') {
			push @{$fields_ref->{'T0501'}}, {
			    content => "Zeitangabe: " . $data, # z.B. Geburtsdaten, ID=edsoao:oao.T045764
			};
		    } 
		    else { 
			my @subjects = split(' ; ', $data);
			foreach my $subject (@subjects) {
			    push @{$fields_ref->{'T0710'}}, {
				content => $subject,
			    } if (!$self->have_field_content('T0710',$data));
			}
		    }
		}
		elsif ($name eq 'DOI') {
		    if ($data !~ /http/){
			$data = "https://doi.org/".$data;
		    }
		    
		    push @{$fields_ref->{'T0662'}}, {
			subfield     => '', 
			mult         => $link_mult, 
			content      => $data,
			availability => 'unknown',
		    };
		    push @{$fields_ref->{'T0663'}}, {
			subfield => '', 
			mult     => $link_mult, 
			content  => "DOI"
		    };
		    $link_mult++;
		} 
		elsif ($name eq 'URL' && $label eq 'Access URL' && ! $is_electronic_ressource) { 
		    my $url = '';
		    
		    if ($data =~ /linkTerm=.*(http.*)&lt;/ or $data =~ /^(http[^\s]+)/){
			$url = $1;
		    }
		    
		    if ($json_result_ref->{Record}{Header}{DbId} =~ /^(edsfis|edswao)$/) { # z.B. ID=edswao:edswao.035502584

			if ($url =~m/.*pdf$/g && $json_result_ref->{Record}{Header}{PubType} eq "Academic Journal"){ # Problem bei z.B. edsfis:edsfis.68604
			    
			    push @{$fields_ref->{'T4120'}}, {
				subfield => 'g', # Freier Zugang / green
				mult     => $link_mult, 
				content  => $url};
			    
			    push @{$fields_ref->{'T0662'}}, {
				subfield     => '', 
				mult         => $link_mult, 
				content      => $url,
				availability => 'green',
			    };
			    # Todo: Zugriffstatus 'green' hinzufuegen
			    $link_mult++;
			}
		    } 
		    else {
			# SSOAR, BASE, OLC, ...: Volltext-Link auslesen, z.B. ID=edsbas:edsbas.ftunivdortmund.oai.eldorado.tu.dortmund.de.2003.30139, ID=edsgoc:edsgoc.197587160X
			if ($url && $url !~ /gesis\.org\/sowiport/) { # Sowiport-Links funktionieren nicht mehr, z.B. ID=edsgsl:edsgsl.793796
			    push @{$fields_ref->{'T4120'}}, {
				subfield => 'y', # Eingeschraenkter Zugang / yellow
				mult     => $link_mult, 
				content  => $url};
			    
			    push @{$fields_ref->{'T0662'}}, {
				subfield     => '', 
				mult         => $link_mult, 
				content      => $url,
				availability => 'yellow',

			    };
			    push @{$fields_ref->{'T0663'}}, {
				subfield => '', 
				mult     => $link_mult, 
				content  => "Volltext"
			    };
			    # Todo: Zugriffstatus 'yellow' hinzufuegen
			    $link_mult++;
			    
			    if ($json_result_ref->{Record}{Header}{DbId} eq 'edsgso') { # SSOAR
				# Todo: Zugriffsstatus 'green' hinzufuegen
				push @{$fields_ref->{'T0800'}}, {
				    subfield => '', 
				    mult     => 1, 
				    content  => "electronic resource"
				};
				$is_electronic_ressource = 1;
			    } 
			    else {
				# Todo: Zugriffsstatus 'unknown' hinzufuegen
			    }
			    push @{$fields_ref->{'T0800'}}, {
				subfield => '', 
				mult     => 1, 
				content  => "electronic resource"
			    } unless ($is_electronic_ressource);
			}
		    }
		}
		elsif ($name eq 'URL' && $label eq 'Availability') {

		    $logger->debug("URL - Label:$label - Name:$name Data:$data");
		    
		    my @urls = split(' ; ', $data);
		    my $i = 2;
		    foreach my $url (@urls) {
			if ($url =~ /doi\.org/) {
			    my ($doi) = $url =~m/doi\.org\/(.+)$/ ;
			    push @{$fields_ref->{'T0552'}}, {
				subfield => '', 
				content  => $doi
			    };
			    push @{$fields_ref->{'T0662'}}, {
				subfield => '', 
				mult     => $link_mult, 
				content  => $url
			    };
			    push @{$fields_ref->{'T0663'}}, {
				subfield => '', 
				mult => $link_mult, 
				content => "DOI"
			    };
			    $link_mult++;
			} 
			else {
			    if ($json_result_ref->{Record}{Header}{DbId} =~ /^(edsbl)$/) {
				next;
			    }

			    my $availability = "";

			    if ($json_result_ref->{Record}{Header}{DbId} =~ /^(edsoao|edsomo|edsebo|edssvl)$/) { # Links aus Grove Art und Britannica Online, z.B. ID=edsoao:oao.T045764
				# Todo: Zugriffstatus 'yellow' hinzufuegen
				$availability = "yellow";
				
				push @{$fields_ref->{'T0800'}}, {
				    subfield => '', 
				    mult     => 1, 
				    content  => "electronic resource"
				};
			    } 
			    else {
				$availability = "unknown";
			    }

			    my $thisfield_ref = {
				subfield => '', 
				mult     => $link_mult, 
				content  => $url
			    };

			    if ($availability){
				$thisfield_ref->{availability} = $availability;
			    }

			    my $availability_map_ref = {green => 'g', yellow => 'y', unknown => ' '};
			    push @{$fields_ref->{'T4120'}}, {
				subfield => $availability_map_ref->{$availability}, # Dynamisch
				mult     => $link_mult, 
				content  => $url};
			    
			    
			    push @{$fields_ref->{'T0662'}}, $thisfield_ref; 
			    push @{$fields_ref->{'T0663'}}, {
				subfield => '', 
				mult     => $link_mult, 
				content  => "Volltext"
			    };
			    
			    $link_mult++;
			}
			$i++;
		    }
		} 
		elsif ($name !~ /^(AbstractSuppliedCopyright|AN|URL)$/) {
		    push @{$fields_ref->{'T0501'}}, {
			content => $label . ': ' . $data,
		    };
		}
	    }
	}
	
    }

    # Spezifische Angaben, dann wird TitleSource (0590) ersetzt.
    if ($journal && $pagerange){
	my @contents = ();
	push @contents, $journal;

	my $thiscontent = "";
	if ($year){
	    $thiscontent = "($year)";
	}

	if ($issue){
	    $thiscontent .= " Nr. $issue";
	}

	if ($thiscontent){
	    push @contents, $thiscontent;
	}

	push @contents, $pagerange;

	$fields_ref->{"T0590"} = [{
	    content => join(', ',@contents),
		mult => 1,
		subfield => "",
				  }];
    }

    
    $record->set_fields_from_storable($fields_ref);
    
    $record->set_holding([]);
    $record->set_circulation([]);

    if ($memc){
	$memc->set($memc_key,$fields_ref,$config->{memcached_expiration}{'eds:title'});
    }
    
    return $record;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);

    my $config=$self->get_config;
    
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    $self->connect_eds;

    my $json_result_ref = $self->send_search_request($arg_ref);

    if (defined $json_result_ref->{ErrorNumber} && $json_result_ref->{ErrorNumber}){
	$self->{authtoken}    = $self->_create_authtoken;
	$self->{sessiontoken} = $self->_create_sessiontoken;

	$json_result_ref = $self->send_search_request($arg_ref);		
    }

    my @matches = $self->process_matches($json_result_ref);

    $self->process_facets($json_result_ref);
        
    my $resultcount = $json_result_ref->{SearchResult}{Statistics}{TotalHits};

    if ($logger->is_debug){
         $logger->info("Found ".$resultcount." titles");
    }
    
    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $searchtime   = timestr($stimeall,"nop");
	$searchtime      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Gesamtzeit fuer EDS-Suche $searchtime");
    }

    $self->{resultcount} = $resultcount;
    $self->{_matches}     = \@matches;
    
    return $self;
}

sub get_search_resultlist {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;

    my $recordlist = new OpenBib::RecordList::Title();

    my @matches = $self->matches;

    foreach my $match_ref (@matches) {

        my $id            = OpenBib::Common::Util::encode_id($match_ref->{database}."::".$match_ref->{id});
	my $fields_ref    = $match_ref->{fields};

        $recordlist->add(OpenBib::Record::Title->new({database => $self->get_database, id => $id })->set_fields_from_storable($fields_ref));
    }

    # if ($logger->is_debug){
    # 	$logger->debug("Result-Recordlist: ".YAML::Dump($recordlist->to_list))
    # }
    
    return $recordlist;
}


sub get_authtoken {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    my $database = $self->get_database;
    
    $config->connectMemcached;
    
    my $memc_key = "eds:authtoken:$database";

    if ($config->{memc}){
        my $authtoken = $config->{memc}->get($memc_key);

	if ($authtoken){
	    if ($logger->is_debug){
		$logger->debug("Got eds authtoken $authtoken for key $memc_key from memcached");
	    }

	    $config->disconnectMemcached;
	    	    
	    $self->{authtoken} = $authtoken;
	}
	else {
	    if ($logger->is_debug){
		$logger->debug("No eds authtoken for key $memc_key from memcached found");
	    }

	    $self->{authtoken} = $self->_create_authtoken();

	}
    }    
    else {
	$logger->debug("Weiter ohne memcached");
	
	$self->{authtoken} = $self->_create_authtoken();
    }
    
    return $self->{authtoken};
}

sub get_sessiontoken {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    $config->connectMemcached;

    if (defined $self->{sessionID}){
	$logger->debug("Getting sessiontoken for sessionid ".$self->{sessionID});
    }
    else {
	$logger->debug("No sessionid to get sessiontoken");
    }
    
    if ($config->{memc} && defined $self->{sessionID}){

	my $memc_key = "eds:sessiontoken:".$self->{sessionID};

        my $sessiontoken = $config->{memc}->get($memc_key);

	if ($sessiontoken){
	    if ($logger->is_debug){
		$logger->debug("Got eds sessiontoken $sessiontoken for key $memc_key from memcached");
	    }

	    $config->disconnectMemcached;
	    
	    $self->{sessiontoken} = $sessiontoken;
	}
	else {
	    if ($logger->is_debug){
		$logger->debug("No eds sessiontoken for key $memc_key from memcached found");
	    }

	    $self->{sessiontoken} = $self->_create_sessiontoken;
	    if (!$self->{sessiontoken}){
		$self->{authtoken}    = $self->_create_authtoken;
		$self->{sessiontoken} = $self->_create_sessiontoken;
	    }

	}
    }
    else {	
	$logger->debug("Weiter ohne memcached");
	
	$self->{sessiontoken} = $self->_create_sessiontoken;
	if (!$self->{sessiontoken}){
	    $self->{authtoken}    = $self->_create_authtoken;
	    $self->{sessiontoken} = $self->_create_sessiontoken;
	}
    }    
    
    return $self->{sessiontoken};
}

sub _create_authtoken {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $database = $self->get_database;
    
    my $memc_key = "eds:authtoken:$database";

    my $url = $config->get('eds')->{auth_url};
    
    my $header_ref = {'Content-Type' => 'application/json'};
    
    my $json_result_ref = {};

    my $json_request_ref = {
	'UserId'   => $self->{api_user},
	'Password' => $self->{api_password},
    };

    if ($logger->is_debug){
	$logger->info("JSON-Request: ".encode_json($json_request_ref));
    }

    my $body = "";

    eval {
	$body = encode_json($json_request_ref); 
    };
    
    if ($@){
	$logger->error('Encoding error: '.$@);
	return $json_result_ref;
    }
    
    my $response = $ua->post($url => $header_ref, $body)->result;

    if ($response->is_success){
	eval {
	    $json_result_ref = decode_json $response->body;
	};
	if ($@){
	    $logger->error('Decoding error: '.$@);
	    return;
	}
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }    
	
    if ($json_result_ref->{AuthToken}){
	$config->connectMemcached;
	
	if ($config->{memc}){
	    $config->{memc}->set($memc_key,$json_result_ref->{AuthToken},$self->{memcached_expiration}{$memc_key});
	    
	    if ($logger->is_debug){
		$logger->debug("Saved eds authtoken ".$json_result_ref->{AuthToken}." to key $memc_key in memcached");
	    }
	}
	
	$config->disconnectMemcached;
	
	return $json_result_ref->{AuthToken};
    }
    else {
	$logger->error('No AuthToken received'.$response->body);
    }
    
    return;
}

sub _create_sessiontoken {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;
    my $ua     = $self->get_client;

    $config->connectMemcached;
    
    my $guest = 'n';

    my $json_request_ref = {
	'Profile' => $self->{api_profile},
	'Guest'   => $guest,
    };

    if ($logger->is_debug){
	$logger->info("JSON-Request: ".encode_json($json_request_ref));
    }
        
    my $url = $config->get('eds')->{session_url};

    my $header_ref = {'Content-Type' => 'application/json', 'x-authenticationToken' => $self->{authtoken}};
    
    my $json_result_ref = {};

    my $body = "";

    eval {
	$body = encode_json($json_request_ref); 
    };
    
    if ($@){
	$logger->error('Encoding error: '.$@);
	return $json_result_ref;
    }
    
    my $response = $ua->post($url => $header_ref, $body)->result;

    if ($response->is_success){
	eval {
	    $json_result_ref = decode_json $response->body;
	};
	if ($@){
	    $logger->error('Decoding error: '.$@);
	    return;
	}
    }
    else {        
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->body);
    }
    
	
    if ($json_result_ref->{SessionToken}){
	if ($config->{memc} && defined $self->{sessionID}){
	    my $memc_key = "eds:sessiontoken:".$self->{sessionID};
	    
	    $config->{memc}->set($memc_key,$json_result_ref->{SessionToken},$self->{memcached_expiration}{'eds:sessiontoken'});
	    
	    if ($logger->is_debug){
		$logger->debug("Saved eds sessiontoken ".$json_result_ref->{SessionToken}." to key $memc_key in memcached");
	    }
	}
	
	$config->disconnectMemcached;
	
	return $json_result_ref->{SessionToken};
    }
    else {
	$logger->error('No SessionToken received'.$response->body);
    }

    $config->disconnectMemcached;
    
    return;
}

sub connect_eds {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    $self->get_authtoken;

    # second try... just in case ;-)
    if (!$self->{authtoken}){
	$logger->error("2nd try to get authtoken necessary");
	$self->{authtoken} = $self->_create_authtoken();
    }

    if (!$self->{authtoken}){
	$logger->error('No AuthToken available. Exiting...');
	return;	
    }

    $self->get_sessiontoken;

    # second try... und zur Sicherheit noch ein neues Authtoken holen just in case ;-)
    if (!$self->{sessiontoken}){
	$logger->error("2nd try to get sessiontoken necessary");	
	$self->{authtoken}    = $self->_create_authtoken;	
	$self->{sessiontoken} = $self->_create_sessiontoken;
    }

    if (!$self->{sessiontoken}){
	$logger->error('No SessionToken available. Exiting...');
	return;	
    }

    return;
};

sub process_matches {
    my ($self,$json_result_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config     = $self->get_config;
    
    my @matches = ();
    
    foreach my $match (@{$json_result_ref->{SearchResult}{Data}{Records}}){
	my $fields_ref = {};

	my ($atime,$btime,$timeall);
	
	if ($config->{benchmark}) {
	    $atime=new Benchmark;
	}


	# Gesamtresponse in eds_source
	push @{$fields_ref->{'eds_source'}}, {
	    content => $match
	};
	
	# $logger->debug("Processing Record ".YAML::Dump($json_result_ref->{SearchResult}{Data}{Records}));

	# Online Verfuegbarkeit

	my $available = "";
	my $plink = "";
	my $is_electronic_ressource = 0;
	my $pubtype = "";
	
	eval {
	    $available = $match->{'FullText'}{'Text'}{'Availability'};
	    $plink = $match->{'PLink'};
	    $pubtype = $match->{'Header'}{'PubType'};
	};

	my $link_mult = 1;
	    
	# Volltextlinks
	{

	    # Zugriffstatus
	    #
	    # '' : Keine Ampel
	    # ' ': Unbestimmt g oder y oder r
	    # 'f': Unbestimmt, aber Volltext Zugriff g oder y (fulltext)
	    # 'g': Freier Zugriff (green)
	    # 'y': Lizensierter Zugriff (yellow)
	    # 'l': Unbestimmt Eingeschraenkter Zugriff y oder r (limited)
	    # 'r': Kein Zugriff (red)
	    
	    my $url = "";
	    
	    eval { 	
		$url = $match->{'FullText'}{'Links'}[0]{'Link'}[0]{'Url'} || '';
		$logger->debug("Got first URL $url");
	    };
	    
	    if ($url) { # ID=bth:94617232
		push @{$fields_ref->{'T4120'}}, {
		    subfield => 'y', # Eingeschraenkter Zugang / yellow
		    mult     => $link_mult, 
		    content  => $url};
		
		push @{$fields_ref->{'T0662'}}, {
		    subfield => '', 
		    mult     => $link_mult, 
		    content  => $url};
		
		push @{$fields_ref->{'T0663'}}, {
		    subfield => '',
		    mult     => $link_mult, 
		    content  => "Volltext"};
		# Todo: Zugriffstatus 'yellow' hinzufuegen

		$link_mult++;
	    }
	    else { 		
		if ($available == 1 && $plink) {
		    push @{$fields_ref->{'T4120'}}, {
			subfield => 'y', # Eingeschraenkter Zugang / yellow
			mult     => $link_mult, 
			content  => $plink};
		    
		    push @{$fields_ref->{'T0662'}}, {
			subfield => '', 
			mult     => $link_mult, 
			content  => $plink};
		    
		    push @{$fields_ref->{'T0663'}}, {
			subfield => '', 
			mult     => $link_mult, 
			content  => "HTML-Volltext"};
		    # Todo: Zugriffstatus 'yellow' hinzufuegen
		    $link_mult++;
		}
	    }

	    my @links = ();
	    
	    eval {
		@links = @{$match->{'FullText'}{'Links'}};
	    };

	    if (@links){
		$logger->debug("Iterating links");
		foreach my $link_ref (@links){
		    my $url = (defined $link_ref->{'Url'})?$link_ref->{'Url'}:'';

		    $logger->debug("Got URL $url");
		    
		    if (defined $link_ref->{'Type'} && $link_ref->{'Type'} =~m/^(ebook|pdflink|other)$/){
			push @{$fields_ref->{'T4120'}}, {
			    subfield => 'y', # Eingeschraenkter Zugang / yellow
			    mult     => $link_mult, 
			    content  => $url,
			};
			
			push @{$fields_ref->{'T0662'}}, {
			    subfield => '', 
			    mult     => $link_mult, 
			    content  => $url,
			};
			
			push @{$fields_ref->{'T0663'}}, {
			    subfield => '', 
			    mult     => $link_mult, 
			    content  => "Volltext"
			};
			# Todo: Zugriffstatus 'yellow' hinzufuegen
			$link_mult++;
		    }
		}
	    }
	    
	    # arXiv, DOAJ und OAIster: Publikationstyp einfuegen und CustomLink auslesen
	    if ($match->{Header}{DbId} =~ /^(edsarx|edsdoj|edsoai)$/) {
		$logger->debug("Checking edsarx, edsdoj, edsoai");
		
		unless ($match->{'Header'}{'PubType'}) {
		    push @{$fields_ref->{'T0800'}}, {
			subfield => '', 
			mult     => 1, 
			content  => "electronic resource"};
		    $is_electronic_ressource = 1;
		}
		
		$url = '';
		
		eval {
		    $url = $match->{'FullText'}{'CustomLinks'}[0]{'Url'};
		};
		
		if ($url) {
		    $logger->debug("Got URL $url");
		    $url =~ s!(.*)\#\?$!$1!; # OAIster: "#?" am Ende entfernen, z.B. ID=edsoai:edsoai.859893876 ; ID=edsoai:edsoai.690666320
		    $url =~ s!(http://etheses.bham.ac.uk/[^/]+/).*ThumbnailVersion.*\.pdf!$1!; # Sonderanpassung fuer etheses.bham.ac.uk, z.B. ID=edsoai:edsoai.690666320

		    my $color    = "g";
		    my $linktext = "Volltext";
		    if ($match->{Header}{DbId} eq "edsoai") {
			$color = " " ; # urspruenglich green_on_red / Volltext eventuell nicht zugänglich (s. Hinweise)
			$linktext = "Volltext eventuell nicht zugänglich (s. Hinweise)";
		    }
		    
		    push @{$fields_ref->{'T4120'}}, {
			subfield => $color,
			mult     => $link_mult, 
			content  => $url
		    };
		    
		    push @{$fields_ref->{'T0662'}}, {
			subfield => '', 
			mult     => $link_mult, 
			content  => $url
		    };
		    
		    push @{$fields_ref->{'T0663'}}, {
			subfield => '', 
			mult     => $link_mult, 
			content  => $linktext
		    };
		    $link_mult++;
		}
	    }
	    
	    
	    # Science cititation index: hart verlinken
	    # Hinweis pkostaedt: Der Link "Citing Articles" funktioniert nicht in jedem Fall, z.B. ID=edswss:000312205100002
	    if ($match->{Header}{DbId} =~ /^(edswsc|edswss)$/ && $match->{Header}{An}) {
		my $url = "http://gateway.isiknowledge.com/gateway/Gateway.cgi?&GWVersion=2&SrcAuth=EBSCO&SrcApp=EDS&DestLinkType=CitingArticles&KeyUT=" . $match->{Header}{An} . "&DestApp=WOS";
		
		push @{$fields_ref->{'T0662'}}, {
		    subfield => '', 
		    mult     => $link_mult, 
		    content  => $url
		};
		
		push @{$fields_ref->{'T0663'}}, {
		    subfield => '', 
		    mult => $link_mult, 
		    content => "Citing Articles (via Web of Science)"
		};

		$link_mult++;
	    }

	}

	# Titelfelder
	{

	    my $title_source = "";
	    
	    if (defined $match->{'Items'}){
		foreach my $item (@{$match->{Items}}){
		    my $label = $item->{Label};
		    my $data  = $item->{Data};
		    my $name  = $item->{Name};

		    $logger->debug("Data pre:$data");
		    
		    # &gt; &lt; auf <,> vereinfachen
		    $data =~ s{&lt;}{<}g;
		    $data =~ s{&gt;}{>}g;
		    
		    # Data breinigen. Hinweise pkostaedt
		    $data =~ s{<br \/>}{ ; }g;
		    $data =~ s{<relatesTo>[^<]+<\/relatesTo><i>[^<]+<\/i>}{}g; # z.B. <relatesTo>2</relatesTo><i> javierm@electrica.cujae.edu.cu</i>
		    $data =~ s{<i>([^<]+)<\/i>}{$1}g;
		    $data =~ s{<[^>]+>([^<]+)<\/[^>]+>}{$1}g;                  # z.B. <searchLink fieldCode="JN" term="%22Linux%22">Linux</searchLink>
		    $data =~ s{&lt;.+?&gt;}{}g;                                # z.B. rih:2012-09413, pdx:0209854
		    $data =~ s{&amp;amp;}{&amp;}g;                             # z.B. pdx:0209854
		    
		    $logger->debug("Item - Label:$label - Name:$name Data:$data");

		    next if ($name eq 'TitleSource' && $match->{Header}{DbId} eq 'edsoai' && $data =~ /urn:/);  # z.B. edsoai:edsoai.824612814


		    if ($name eq "TitleSource"){
			$title_source = $data;
		    }
		    elsif ($name eq 'URL' && $label eq 'Access URL' && ! $is_electronic_ressource) { 
			my $url = '';
			
			if ($data =~ /linkTerm=.*(http.*)&lt;/ or $data =~ /^(http[^\s]+)/){
			    $url = $1;
			}
			
			if ($match->{Header}{DbId} =~ /^(edsfis|edswao)$/) { # z.B. ID=edswao:edswao.035502584

			    if ($url =~m/.*pdf$/g && $pubtype eq "Academic Journal"){ # Problem bei z.B. edsfis:edsfis.68604
				push @{$fields_ref->{'T4120'}}, {
				    subfield => 'g', # Freier Zugang / green
				    mult     => $link_mult, 
				    content  => $url};
				
				push @{$fields_ref->{'T0662'}}, {
				    subfield     => '', 
				    mult         => $link_mult, 
				    content      => $url,
				    availability => 'green',
				};
				# Todo: Zugriffstatus 'green' hinzufuegen
				$link_mult++;
			    }
			} 
			else {
			    # SSOAR, BASE, OLC, ...: Volltext-Link auslesen, z.B. ID=edsbas:edsbas.ftunivdortmund.oai.eldorado.tu.dortmund.de.2003.30139, ID=edsgoc:edsgoc.197587160X
			    if ($url && $url !~ /gesis\.org\/sowiport/) { # Sowiport-Links funktionieren nicht mehr, z.B. ID=edsgsl:edsgsl.793796
				push @{$fields_ref->{'T4120'}}, {
				    subfield => 'y', # Eingeschraenkter Zugang / yellow
				    mult     => $link_mult, 
				    content  => $url};
				
				push @{$fields_ref->{'T0662'}}, {
				    subfield     => '', 
				    mult         => $link_mult, 
				    content      => $url,
				    availability => 'yellow',
				    
				};
				push @{$fields_ref->{'T0663'}}, {
				    subfield => '', 
				    mult     => $link_mult, 
				    content  => "Volltext"
				};
				# Todo: Zugriffstatus 'yellow' hinzufuegen
				$link_mult++;
				
				if ($match->{Header}{DbId} eq 'edsgso') { # SSOAR
				    # Todo: Zugriffsstatus 'green' hinzufuegen
				    push @{$fields_ref->{'T0800'}}, {
					subfield => '', 
					mult     => 1, 
					content  => "electronic resource"
				    };
				    $is_electronic_ressource = 1;
				} 
				else {
				    # Todo: Zugriffsstatus 'unknown' hinzufuegen
				}
				push @{$fields_ref->{'T0800'}}, {
				    subfield => '', 
				    mult     => 1, 
				    content  => "electronic resource"
				} unless ($is_electronic_ressource);
			    }
			}
		    }
		    elsif ($name eq 'URL' && $label eq 'Availability') {
			
			$logger->debug("URL - Label:$label - Name:$name Data:$data");
			
			my @urls = split(' ; ', $data);
			my $i = 2;
			foreach my $url (@urls) {
			    if ($url =~ /doi\.org/) {
				my ($doi) = $url =~m/doi\.org\/(.+)$/ ;
				push @{$fields_ref->{'T0552'}}, {
				    subfield => '', 
				    content  => $doi
				};
				push @{$fields_ref->{'T0662'}}, {
				    subfield => '', 
				    mult     => $link_mult, 
				    content  => $url
				};
				push @{$fields_ref->{'T0663'}}, {
				    subfield => '', 
				    mult => $link_mult, 
				    content => "DOI"
				};
				$link_mult++;
			    } 
			    else {
				if ($match->{Header}{DbId} =~ /^(edsbl)$/) {
				    next;
				}
				
				my $availability = "";
				
				if ($match->{Header}{DbId} =~ /^(edsoao|edsomo|edsebo|edssvl)$/) { # Links aus Grove Art und Britannica Online, z.B. ID=edsoao:oao.T045764
				    # Todo: Zugriffstatus 'yellow' hinzufuegen
				    $availability = "yellow";
				    
				    push @{$fields_ref->{'T0800'}}, {
					subfield => '', 
					mult     => 1, 
					content  => "electronic resource"
				    };
				} 
				else {
				    $availability = "unknown";
				}
				
				my $thisfield_ref = {
				    subfield => '', 
				    mult     => $link_mult, 
				    content  => $url
				};
				
				if ($availability){
				    $thisfield_ref->{availability} = $availability;
				}
				
				my $availability_map_ref = {green => 'g', yellow => 'y', unknown => ' '};
				push @{$fields_ref->{'T4120'}}, {
				    subfield => $availability_map_ref->{$availability}, # Dynamisch
				    mult     => $link_mult, 
				    content  => $url};
				
				
				push @{$fields_ref->{'T0662'}}, $thisfield_ref; 
				push @{$fields_ref->{'T0663'}}, {
				    subfield => '', 
				    mult     => $link_mult, 
				    content  => "Volltext"
				};
				
				$link_mult++;
			    }
			    $i++;
			}
		    } 

		}
	    }
	    
	    my $pagerange = "";
	    
	    foreach my $thisfield (keys %{$match->{RecordInfo}{BibRecord}{BibEntity}}){
		
		if ($thisfield eq "Titles"){
		    foreach my $item (@{$match->{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
			push @{$fields_ref->{'T0331'}}, {
			    content => $item->{TitleFull}
			} if ($item->{Type} eq "main");
			
		    }
		}

		if ($thisfield eq "PhysicalDescription"){
		    my $startpage;
		    my $endpage;
		    my $pagecount;
		    
		    eval {
			$startpage = $match->{RecordInfo}{BibRecord}{BibEntity}{$thisfield}{Pagination}{StartPage};
		    };
		    
		    eval {
			$pagecount = $match->{RecordInfo}{BibRecord}{BibEntity}{$thisfield}{Pagination}{PageCount};
		    };
		    
		    if ($startpage){
			$startpage=~s{^0+}{}g;
			
			if ($pagecount && $pagecount > 1){
			    $endpage = $startpage + $pagecount - 1;
			}
		    }
		    
		    $pagerange = $startpage if ($startpage);
		    $pagerange .= " - $endpage" if ($endpage);
		    
		    $pagerange = "S. ".$pagerange if ($pagerange);
		}
	    }

	    if (defined $match->{RecordInfo}{BibRecord} && defined $match->{RecordInfo}{BibRecord}{BibRelationships}){

		if (defined $match->{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}){
		    foreach my $item (@{$match->{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}}){
			#		    $logger->debug("DebugRelationShips".YAML::Dump($item));
			if (defined $item->{PersonEntity} && defined $item->{PersonEntity}{Name} && defined $item->{PersonEntity}{Name}{NameFull}){
			    
			    push @{$fields_ref->{'P0100'}}, {
				content => $item->{PersonEntity}{Name}{NameFull},
			    }; 
			    
			    push @{$fields_ref->{'PC0001'}}, {
				content => $item->{PersonEntity}{Name}{NameFull},
			    }; 
			}
		    }
		}


		if (defined $match->{RecordInfo}{BibRecord}{BibRelationships}{IsPartOfRelationships}){
		    
		    my $issue   = "";    
		    my $volume  = "";
		    my $journal = "";
		    my $year    = "";
		    
		    foreach my $partof_item (@{$match->{RecordInfo}{BibRecord}{BibRelationships}{IsPartOfRelationships}}){
			if (defined $partof_item->{BibEntity}){
			    
			    foreach my $thisfield (keys %{$partof_item->{BibEntity}}){
				
				if ($thisfield eq "Titles"){
				    foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
					$journal = $item->{TitleFull};
				    }
				}
				
				if ($thisfield eq "Dates"){
				    foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
					$year = $item->{'Y'};
					push @{$fields_ref->{'T0425'}}, {
					    content => $item->{'Y'}
					};
				    }
				}
				
				if ($thisfield eq "Numbering"){
				    foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
					my $type  = $item->{Type};
					my $value = $item->{Value};
					
					if ($value && $type eq "volume"){
					    $volume = $value;
					}
					elsif ($value && $type eq "issue"){
					    $issue = $value;
					}
					
				    }
				    
				    # if ($thisfield eq "Titles"){
				    #     foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    # 	push @{$fields_ref->{'T0451'}}, {
				    # 	    content => $item->{TitleFull}
				    # 	};
				    
				    #     }
				    # }
				    
				    # if ($thisfield eq "Dates"){
				    #     foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
				    # 	push @{$fields_ref->{'T0425'}}, {
				    # 	    content => $item->{'Y'}
				    # 	};
				    
				    #     }
				    # }
				}
			    }
			    
			    
			}
			
		    }

		    # T0590 erzeugen
		    my $field_0590 = "";
		    if ($journal){
			$field_0590 = $journal;

			if ($year){
			    $field_0590.=", $year";
			}

			if ($volume){
			    $field_0590.=", Vol. $volume";
			}

			if ($issue){
			    $field_0590.=" ($issue)";
			}

			if ($pagerange){
			    $field_0590.=", $pagerange";
			}
		    }

		    if ($field_0590){
			push @{$fields_ref->{'T0590'}}, {
			    content => $field_0590,
			};
		    }
		    elsif ($title_source){
			push @{$fields_ref->{'T0590'}}, {
			    content => $title_source,
			};
		    }
		    
		}
	    }
	}	
        push @matches, {
            database => $match->{Header}{DbId},
            id       => $match->{Header}{An},
            fields   => $fields_ref,
        };

	if ($config->{benchmark}) {
	    my $stime        = new Benchmark;
	    my $stimeall     = timediff($stime,$atime);
	    my $parsetime   = timestr($stimeall,"nop");
	    $parsetime      =~s/(\d+\.\d+) .*/$1/;
	    
	    $logger->info("Zeit um Treffer zu parsen $parsetime");
	}

    }

    return @matches;
}

sub process_facets {
    my ($self,$json_result_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $ddatime   = new Benchmark;

    my $fields_ref = {};
    
    my $category_map_ref     = ();
    
    # Transformation Hash->Array zur Sortierung

    if ($logger->is_debug){
	$logger->debug("Start processing facets: ".YAML::Dump($json_result_ref->{SearchResult}{AvailableFacets}));
    }
    
    foreach my $eds_facet (@{$json_result_ref->{SearchResult}{AvailableFacets}}){

	my $id   = $eds_facet->{Id};
	my $type = $config->get('eds_facet_mapping')->{$id};

	next unless (defined $type) ;
		
	$logger->debug("Process Id $id and type $type");
	
        my $contents_ref = [] ;
        foreach my $item_ref (@{$eds_facet->{AvailableFacetValues}}) {
            push @{$contents_ref}, [
                $item_ref->{Value},
                $item_ref->{Count},
            ];
        }
        
        if ($logger->is_debug){
            $logger->debug("Facet for type $type ".YAML::Dump($contents_ref));
        }
        
        # Schwartz'ian Transform

        @{$category_map_ref->{$type}} = map { $_->[0] }
            sort { $b->[1] <=> $a->[1] }
                map { [$_, $_->[1]] }
                    @{$contents_ref};
    }

    if ($logger->is_debug){
	$logger->debug("All Facets ".YAML::Dump($category_map_ref));
    }

    my $ddbtime       = new Benchmark;
    my $ddtimeall     = timediff($ddbtime,$ddatime);
    my $drilldowntime    = timestr($ddtimeall,"nop");
    $drilldowntime    =~s/(\d+\.\d+) .*/$1/;
    
    $logger->info("Zeit fuer categorized drilldowns $drilldowntime");

    $self->{_facets} = $category_map_ref;
    
    return; 
}

sub get_config {
    my ($self) = @_;

    return $self->{_config};
}

sub get_client {
    my ($self) = @_;

    return $self->{client};
}

sub get_searchquery {
    my ($self) = @_;

    return $self->{_searchquery};
}

sub get_queryoptions {
    my ($self) = @_;

    return $self->{_queryoptions};
}

sub have_field_content {
    my ($self,$field,$content)=@_;

    my $have_field = 0;
    
    eval {
	$have_field = $self->{have_field_content}{$field}{$content};
    };

    $self->{have_field_content}{$field}{$content} = 1;

    return $have_field;
}

sub parse_query {
    my ($self,$searchquery)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    # Aufbau des eds searchquerystrings
    my @eds_querystrings = ();
    my $eds_querystring  = "";

    # Aufbau des eds_filterstrings
    my @eds_filterstrings = ();
    my $eds_filterstring  = "";

    my $ops_ref = {
        'AND'     => 'AND ',
        'AND NOT' => 'NOT ',
        'OR'      => 'OR ',
    };

    my $query_count = 1;
    
    my $query_ref = [];

    my $mapping_ref = $config->get('eds_searchfield_mapping');
    
    foreach my $field (keys %{$config->{searchfield}}){
        my $searchtermstring = (defined $searchquery->get_searchfield($field)->{val})?$searchquery->get_searchfield($field)->{val}:'';

        my $searchtermstring_from = (defined $searchquery->get_searchfield("${field}_from")->{norm})?$searchquery->get_searchfield("${field}_from")->{norm}:'';
        my $searchtermstring_to = (defined $searchquery->get_searchfield("${field}_to")->{norm})?$searchquery->get_searchfield("${field}_to")->{norm}:'';

	
		
	

	if ($field eq "year" && ($searchtermstring_from || $searchtermstring_to)){
	    if ($searchtermstring_from && $searchtermstring_to){
		push @$query_ref, "query-".$query_count."=AND%2CDT:".cleanup_eds_query($searchtermstring_from."-".$searchtermstring_to);
	    }
	    elsif ($searchtermstring_from){
		push @$query_ref, "query-".$query_count."=AND%2CDT:".cleanup_eds_query($searchtermstring_from."-9999");
	    }
	    elsif ($searchtermstring_to){
		# Keine Treffer im API, wenn aelter als 1800
		push @$query_ref, "query-".$query_count."=AND&2CDT:".cleanup_eds_query("1800-".$searchtermstring_to);
	    }
    	}	
        elsif ($searchtermstring) {
	    
	    if (defined $mapping_ref->{$field}){
		if ($mapping_ref->{$field} eq "TX"){
		    push @$query_ref, "query-".$query_count."=AND%2C".cleanup_eds_query($searchtermstring);
		}
		else {
			if ($field ne 'fulltext'){
		    push @$query_ref, "query-".$query_count."=AND%2C".$mapping_ref->{$field}.":".cleanup_eds_query($searchtermstring);
			}
		}
		
		#push @$query_ref, "query-".$query_count."=AND%2C".cleanup_eds_query($mapping_ref->{$field}.":".$searchtermstring);
		$query_count++;
	    }
        }
    }

    # Filter

    my $filter_count = 1;
    
    my $filter_ref = [];

    if ($logger->is_debug){
        $logger->debug("All filters: ".YAML::Dump($searchquery->get_filter));
    }

    my $eds_reverse_facet_mapping_ref = $config->get('eds_reverse_facet_mapping');
    
    if (@{$searchquery->get_filter}){
        $filter_ref = [ ];
        foreach my $thisfilter_ref (@{$searchquery->get_filter}){
            my $field = $eds_reverse_facet_mapping_ref->{$thisfilter_ref->{field}};
            my $term  = $thisfilter_ref->{term};
#            $term=~s/_/ /g;
            
            $logger->debug("Facet: $field / Term: $term (Filter-Field: ".$thisfilter_ref->{field}.")");

	    if ($field && $term){
		push @$filter_ref, "facetfilter=".cleanup_eds_filter($filter_count.",$field:$term");
		$filter_count++;
	    }
        }
	
    }
	
    if ($logger->is_debug){
        $logger->debug("Query: ".YAML::Dump($query_ref));
        $logger->debug("Filter: ".YAML::Dump($filter_ref));
    }

    $self->{_query}  = $query_ref;
    $self->{_filter} = $filter_ref;

    return $self;
}

sub cleanup_eds_query {
    my $content = shift;

    $content = decode_entities($content);
    
    $content =~ s{(,|\:|\(|\))}{\\$1}g;
 #   $content =~ s{\[}{%5B}g;
 #   $content =~ s{\]}{%5D}g;
    $content =~ s{\s+\-\s+}{ }g;
    $content =~ s{\s\s}{ }g;
    $content =~ s{^\s+|\s+$}{}g;
    $content =~ s{\s+(and|or|not)\s+}{ }gi;
#    $content =~ s{ }{\+}g;

    $content = uri_escape_utf8($content);
    
    return $content;
}

sub cleanup_eds_filter {
    my $content = shift;

    $content = decode_entities($content);
    
    $content = uri_escape_utf8($content);
    
    # Runde Klammern in den Facetten duerfen nicht escaped und URL-encoded werden!
    $content =~ s{\%5C\%28}{(}g; 
    $content =~ s{\%5C\%29}{)}g;

    
    return $content;
}

sub get_query {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_query};
}

sub get_filter {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_filter};
}

sub get_database {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->{_database};
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

 my $eds = new OpenBib::EDS({ api_password => $api_password, api_user => $api_user});

 my $search_result_json = $eds->search({ searchquery => $searchquery, queryoptions => $queryoptions });

 my $single_record_json = $eds->get_record({ });

=head1 METHODS

=over 4

=item new({ api_password => $api_password, api_user => $api_user })

Anlegen eines neuen EDS-Objektes. Für den Zugriff über das
EDS-API muss ein API-Passwort $api_password und ein API-Nutzer $api_user
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
