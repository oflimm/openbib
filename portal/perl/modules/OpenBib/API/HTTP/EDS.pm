#####################################################################
#
#  OpenBib::API::HTTP::EDS.pm
#
#  Objektorientiertes Interface zum EDS API
#
#  Dieses File ist (C) 2020- Oliver Flimm <flimm@openbib.org>
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
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Storable;
use JSON::XS;
use URI::Escape;
use YAML ();

use OpenBib::Config;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $api_key   = exists $arg_ref->{api_key}
        ? $arg_ref->{api_key}       : undef;

    my $api_user  = exists $arg_ref->{api_user}
        ? $arg_ref->{api_user}      : undef;

    my $sessionID = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}     : undef;

    my $config             = exists $arg_ref->{config}
        ? $arg_ref->{config}                  : OpenBib::Config->new;
    
    my $session            = exists $arg_ref->{session}
        ? $arg_ref->{session}                 : undef;

    my $searchquery        = exists $arg_ref->{searchquery}
        ? $arg_ref->{searchquery}             : OpenBib::SearchQuery->new;

    my $queryoptions       = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}            : OpenBib::QueryOptions->new;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);
    
    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    $self->{client}        = $ua;
        
    $self->{api_user} = (defined $api_user)?$api_user:(defined $config->{eds}{userid})?$config->{eds}{userid}:undef;
    $self->{api_key}  = (defined $api_key )?$api_key :(defined $config->{eds}{passwd} )?$config->{eds}{passwd} :undef;
    
    $self->{sessionID} = $sessionID;

    if ($config){
        $self->{_config}        = $config;
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

    if ($logger->is_debug){
	$logger->debug("Setting default header with x-authenticationToken: ".$self->{authtoken}." and x-sessionToken: ".$self->{sessiontoken});
    }

    $ua->default_header('x-authenticationToken' => $self->{authtoken}, 'x-sessionToken' => $self->{sessiontoken});
    
    my $url = $config->get('eds')->{'retrieve_url'};

    $url.="?dbid=".$database."&an=".$id;

    if ($logger->is_debug()){
	$logger->debug("Request URL: $url");
    }
    
    my $request = HTTP::Request->new('GET' => $url);
    $request->content_type('application/json');
    
    my $response = $ua->request($request);

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success && $response->code != 400) {
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }

    my $json_result_ref = {};
    
    eval {
	$json_result_ref = decode_json $response->content;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
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

    # Pagination parameters
    my $page              = $queryoptions->get_option('page');
    my $num               = $queryoptions->get_option('num');

    my $from              = ($page - 1)*$num;

    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    if ($logger->is_debug){
	$logger->debug("Setting default header with x-authenticationToken: ".$self->{authtoken}." and x-sessionToken: ".$self->{sessiontoken});
    }

    $ua->default_header('x-authenticationToken' => $self->{authtoken}, 'x-sessionToken' => $self->{sessiontoken});

    my $url = $config->get('eds')->{'search_url'};

    # search options
    my @search_options = ();

    # Default
    push @search_options, "sort=relevance";
    push @search_options, "searchmode=all";
    push @search_options, "highlight=n";
    push @search_options, "includefacets=y";
    push @search_options, "autosuggest=n";
    push @search_options, "view=brief";
    #push @search_options, "view=detailed";    
    
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

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $request = HTTP::Request->new('GET' => $url);
    $request->content_type('application/json');
    
    my $response = $ua->request($request);

  
    if ($config->{benchmark}) {
	my $stime        = new Benchmark;
	my $stimeall     = timediff($stime,$atime);
	my $searchtime   = timestr($stimeall,"nop");
	$searchtime      =~s/(\d+\.\d+) .*/$1/;
	
	$logger->info("Zeit fuer EDS HTTP-Request $searchtime");
    }
    
    if (!$response->is_success && $response->code != 400) {
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }
    
    $logger->info('ok');

    my $json_result_ref = {};
    
    eval {
	$json_result_ref = decode_json $response->content;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
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

    $self->connect_eds;

    my $json_result_ref = $self->send_retrieve_request($arg_ref);

    if (defined $json_result_ref->{ErrorNumber} && $json_result_ref->{ErrorNumber}){
	$self->{authtoken}    = $self->_create_authtoken;
	$self->{sessiontoken} = $self->_create_sessiontoken;

	$json_result_ref = $self->send_retrieve_request($arg_ref);		
    }

    my $record = new OpenBib::Record::Title({ 'eds', id => $id });

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
	
	my $url = "";
	
	eval { 	
	    $url = $json_result_ref->{'Record'}{'FullText'}{'Links'}[0]{'Link'}[0]{'Url'};
	};
	
	if ($url) { # ID=bth:94617232
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
	
	# arXiv, DOAJ und OAIster: Publikationstyp einfuegen und CustomLink auslesen
	if ($json_result_ref->{Header}{DbId} =~ /^(edsarx|edsdoj|edsoai)$/) {
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
		push @{$fields_ref->{'T0662'}}, {
		    subfield => '', 
		    mult => $link_mult, 
		    content => $url};
		
		push @{$fields_ref->{'T0663'}}, {
		    subfield => '', 
		    mult => $link_mult, 
		    content => "Volltext"};
		# Todo: Zugriffstatus 'green' hinzufuegen
		$link_mult++;
	    }
	}
	
	
	# Science cititation index: hart verlinken
	# Hinweis pkostaedt: Der Link "Citing Articles" funktioniert nicht in jedem Fall, z.B. ID=edswss:000312205100002
	if ($json_result_ref->{Header}{DbId} =~ /^(edswsc|edswss)$/ && $json_result_ref->{Header}{An}) {
	    my $url = "http://gateway.isiknowledge.com/gateway/Gateway.cgi?&GWVersion=2&SrcAuth=EBSCO&SrcApp=EDS&DestLinkType=CitingArticles&KeyUT=" . $json_result_ref->{Header}{An} . "&DestApp=WOS";
	    
	    push @{$fields_ref->{'T0662'}}, {
		subfield => '', 
		mult     => $link_mult, 
		content  => $url};
	    push @{$fields_ref->{'T0663'}}, {
		subfield => '', 
		mult => $link_mult, 
		content => "Citing Articles (via Web of Science)"};
	    # Todo: Zugriffstatus 'yellow' hinzufuegen
	    $link_mult++;
	}
	
    }

    # BibEntity
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
	    
	    # z.B. DOI in 0010
	    if ($thisfield eq "Identifiers"){
		foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		    
		    push @{$fields_ref->{'T0010'}}, {
			content => $item->{Value}
		    } if (!$self->have_field_content('T0010',$item->{Value} ));
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
		
		my $pagerange = "";
		
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
    
    { # BibRelationships
	if (defined $json_result_ref->{Record}{RecordInfo}{BibRecord} && defined $json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}){
	    
	    
	    if (defined $json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}){
		foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibRelationships}{HasContributorRelationships}}){
		    $logger->debug("DebugRelationShips".YAML::Dump($item));
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
				    push @{$fields_ref->{'T0451'}}, {
					content => $item->{TitleFull}
				    } if (!$self->have_field_content('T0451',$item->{TitleFull} ));
				    
				}
			    }
			    
			    if ($thisfield eq "Dates"){
				foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
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
					push @{$fields_ref->{'T0089'}}, {
					    content => $value,
					} if (!$self->have_field_content('T0089',$value ));
					push @{$fields_ref->{'T0596'}}, {
					    content => $value,
					    subfield => "b",
					} if (!$self->have_field_content('T0596b',$value ));
				    }
				    elsif ($value && $type eq "issue"){
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
		TitleSource     => 'T0451',
		TitleSourceBook => 'T0451',
		Publisher       => 'T0419',
		DatePubCY       => 'T0425',
		ISBN            => 'T0540',
		ISSN	        => 'T0585',
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
		
		if ($name =~ /^(Title|Author|Language|Abstract|AbstractNonEng|TitleSource|TitleSourceBook|Publisher|DatePubCY|ISBN|ISSN)$/) {

		    if ($name eq 'Publisher') {
			$data =~ s/,\s+\d{4}$//;                          # z.B. edsgsl:solis.00547468 (Hamburg : Diplomica Verl., 2009 -> Hamburg : Diplomica Verl.)
		    } 
		    elsif ($name eq 'TitleSource' && $json_result_ref->{Header}{DbId} eq 'edsoai' && $data =~ /urn:/) {
			next;                                             # z.B. edsoai:edsoai.824612814
		    }
		    elsif ($name eq 'ISSN'){
			# Normieren, hier spezielle wegen Dubletten zu  BibRelationShips
			$data =~ s/^(\d{4})(\d{3}[0-9xX])$/$1-$2/;
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
		    
		    if ($json_result_ref->{Header}{DbId} =~ /^(edsfis|edswao)$/) { # z.B. ID=edswao:edswao.035502584
			push @{$fields_ref->{'T0662'}}, {
			    subfield     => '', 
			    mult         => $link_mult, 
			    content      => $url,
			    availability => 'green',
			};
			# Todo: Zugriffstatus 'green' hinzufuegen
			$link_mult++;
		    } 
		    else {
			# SSOAR, BASE, OLC, ...: Volltext-Link auslesen, z.B. ID=edsbas:edsbas.ftunivdortmund.oai.eldorado.tu.dortmund.de.2003.30139, ID=edsgoc:edsgoc.197587160X
			if ($url && $url !~ /gesis\.org\/sowiport/) { # Sowiport-Links funktionieren nicht mehr, z.B. ID=edsgsl:edsgsl.793796
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
			    
			    if ($json_result_ref->{Header}{DbId} eq 'edsgso') { # SSOAR
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
			    if ($json_result_ref->{Header}{DbId} =~ /^(edsbl)$/) {
				next;
			    }

			    my $availability = "";

			    if ($json_result_ref->{Header}{DbId} =~ /^(edsoao|edsomo|edsebo|edssvl)$/) { # Links aus Grove Art und Britannica Online, z.B. ID=edsoao:oao.T045764
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
    
    $record->set_fields_from_storable($fields_ref);
    
    $record->set_holding([]);
    $record->set_circulation([]);
    
    return $record;
}

sub search {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    $self->connect_eds;

    my $json_result_ref = $self->send_search_request($arg_ref);

    if (defined $json_result_ref->{ErrorNumber} && $json_result_ref->{ErrorNumber}){
	$self->{authtoken}    = $self->_create_authtoken;
	$self->{sessiontoken} = $self->_create_sessiontoken;

	$json_result_ref = $self->send_search_request($arg_ref);		
    }

    
    return $json_result_ref;
}


sub get_authtoken {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    $config->connectMemcached;
    
    my $memc_key = "eds:authtoken";

    $logger->debug("Memc: ".$config->{memcached});
    
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

    $logger->debug("Getting sessiontoken for sessionid ".$self->{sessionID});

    my $memc_key = "eds:sessiontoken:".$self->{sessionID};

    if ($config->{memc}){
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

    my $memc_key = "eds:authtoken";
    
    my $request = HTTP::Request->new('POST' => $config->get('eds')->{auth_url});
    $request->content_type('application/json');

    my $json_request_ref = {
	'UserId'   => $config->get('eds')->{userid},
	'Password' => $config->get('eds')->{passwd},
    };
    
    $request->content(encode_json($json_request_ref));

    if ($logger->is_debug){
	$logger->info("JSON-Request: ".encode_json($json_request_ref));
    }
    
    my $response = $ua->request($request);

    if ($response->is_success) {
	if ($logger->is_debug()){
	    $logger->debug($response->content);
	}
	
	my $json_result_ref = {};
	
	eval {
	    $json_result_ref = decode_json $response->content;
	};
	
	if ($@){
	    $logger->error('Decoding error: '.$@);
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
	    $logger->error('No AuthToken received'.$response->content);
	}
    } 
    else {
	$logger->error('Error in Request: '.$response->code.' - '.$response->message);
    }
    
    return;
}

sub _create_sessiontoken {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;
    my $ua     = $self->get_client;

    my $memc_key = "eds:sessiontoken:".$self->{sessionID};

    $config->connectMemcached;
    
    my $guest = 'n';

    my $request = HTTP::Request->new('POST' => $config->get('eds')->{session_url});
    $request->content_type('application/json');

    my $json_request_ref = {
	'Profile' => $config->get('eds')->{profile},
	'Guest'   => $guest,
    };

    my $json = encode_json $json_request_ref;
    
    $request->content($json);

    if ($logger->is_debug){
	$logger->info("JSON-Request: ".encode_json($json_request_ref));
    }

    $ua->default_header('x-authenticationToken' => $self->{authtoken});
    
    my $response = $ua->request($request);

    if ($response->is_success) {
	if ($logger->is_debug()){
	    $logger->debug($response->content);
	}

	my $json_result_ref = {};

	eval {
	    $json_result_ref = decode_json $response->content;
	};
	
	if ($@){
	    $logger->error('Decoding error: '.$@);
	}
	
	if ($json_result_ref->{SessionToken}){
	    if ($config->{memc}){
		$config->{memc}->set($memc_key,$json_result_ref->{SessionToken},$self->{memcached_expiration}{'eds:sessiontoken'});

		if ($logger->is_debug){
		    $logger->debug("Saved eds sessiontoken ".$json_result_ref->{SessionToken}." to key $memc_key in memcached");
		}
	    }

	    $config->disconnectMemcached;
	    
	    return $json_result_ref->{SessionToken};
	}
	else {
	    $logger->error('No SessionToken received'.$response->content);
	}

    } 
    else {
	$logger->error('Error in Request: '.$response->code.' - '.$response->message);
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

    $logger->debug("1");
    
    # second try... just in case ;-)
    if (!$self->{authtoken}){
	$logger->error("2nd try to get authtoken necessary");
	$self->{authtoken} = $self->_create_authtoken();
    }

    $logger->debug("2");
    
    if (!$self->{authtoken}){
	$logger->error('No AuthToken available. Exiting...');
	return;	
    }

    $logger->debug("3");
    
    $self->get_sessiontoken;

    # second try... und zur Sicherheit noch ein neues Authtoken holen just in case ;-)
    if (!$self->{sessiontoken}){
	$logger->error("2nd try to get sessiontoken necessary");	
	$self->{authtoken}    = $self->_create_authtoken;	
	$self->{sessiontoken} = $self->_create_sessiontoken;
    }

    $logger->debug("4");    
    if (!$self->{sessiontoken}){
	$logger->error('No SessionToken available. Exiting...');
	return;	
    }

    return;
};

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
		    push @$query_ref, "query-".$query_count."=AND%2C".$mapping_ref->{$field}.":".cleanup_eds_query($searchtermstring);
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

    $content =~ s{(,|\:|\(|\))}{\\$1}g;
 #   $content =~ s{\[}{%5B}g;
 #   $content =~ s{\]}{%5D}g;
    $content =~ s{\s+\-\s+}{ }g;
    $content =~ s{\s\s}{ }g;
    $content =~ s{^\s+|\s+$}{}g;
    $content =~ s{\s+(and|or|not)\s+}{ }gi;
#    $content =~ s{ }{\+}g;

    $content = uri_escape_utf8($content);
    
     # Runde Klammern in den Facetten duerfen nicht escaped und URL-encoded werden!
#    $content =~ s{\%5C\%28}{(}g; 
#    $content =~ s{\%5C\%29}{)}g;

    
    return $content;
}

sub cleanup_eds_filter {
    my $content = shift;

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