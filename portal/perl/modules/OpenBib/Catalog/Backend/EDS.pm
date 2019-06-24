#####################################################################
#
#  OpenBib::Catalog::Backend::EDS.pm
#
#  Objektorientiertes Interface zum EDS API
#
#  Dieses File ist (C) 2008-2019 Oliver Flimm <flimm@openbib.org>
#  basiert auf DBIS-Backend
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

package OpenBib::Catalog::Backend::EDS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use JSON::XS;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;
    
    # Set defaults
    my $lang      = exists $arg_ref->{l}
        ? $arg_ref->{l}           : undef;

    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}         : undef;

    my $self = { };

    bless ($self, $class);

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    $self->{database}      = $database;
    
    $self->{client}        = $ua;

    return $self;
}

sub load_full_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    my $edsid = OpenBib::Common::Util::decode_id($id);

    my $database;
    
    ($database,$edsid)=$edsid=~m/^(.+?)::(.+)$/;
    
    my $ua = $self->{client};
    
    $self->connect_eds($ua);
    
    if ($logger->is_debug){
	$logger->debug("Setting default header with x-authenticationToken: ".$self->get_authtoken." and x-sessionToken: ".$self->get_sessiontoken);
    }

    $ua->default_header('x-authenticationToken' => $self->get_authtoken, 'x-sessionToken' => $self->get_sessiontoken);
    
    my $url = $config->get('eds')->{'retrieve_url'};

    $url.="?dbid=".$database."&an=".$edsid;

    if ($logger->is_debug()){
	$logger->debug("Request URL: $url");
    }
    
    my $request = HTTP::Request->new('GET' => $url);
    $request->content_type('application/json');
    
    my $response = $ua->request($request);
    
    $logger->debug("Response: $response");

    if (!$response->is_success) {
	$logger->info($response->code . ' - ' . $response->message);
	return;
    }

    $logger->info('ok');
    $logger->debug($response->content);

    my $json_result_ref = {};
    
    eval {
	$json_result_ref = decode_json $response->content;
    };
    
    if ($@){
	$logger->error('Decoding error: '.$@);
    }
    
    my $record = new OpenBib::Record::Title({ 'eds', id => $id });

    my $fields_ref = ();

    # Gesamtresponse in eds_source
    push @{$fields_ref->{'eds_source'}}, {
	content => $json_result_ref
    };
    
    foreach my $thisfield (keys %{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}}){
	
	if ($thisfield eq "Titles"){
	    foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		push @{$fields_ref->{'T0331'}}, {
		    content => $item->{TitleFull}
		} if ($item->{Type} eq "main");
		
	    }
	}
	
	if ($thisfield eq "Subjects"){
	    foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		push @{$fields_ref->{'T0710'}}, {
		    content => $item->{SubjectFull}
		};
		
	    }
	}

	if ($thisfield eq "Languages"){
	    foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		push @{$fields_ref->{'T0015'}}, {
		    content => $item->{Text}
		};
		
	    }
	}

	# z.B. DOI in 0010
	if ($thisfield eq "Identifiers"){
	    foreach my $item (@{$json_result_ref->{Record}{RecordInfo}{BibRecord}{BibEntity}{$thisfield}}){
		push @{$fields_ref->{'T0010'}}, {
		    content => $item->{Value}
		};
		
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
		    };
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
				};
				
			    }
			}
			
			if ($thisfield eq "Dates"){
			    foreach my $item (@{$partof_item->{BibEntity}{$thisfield}}){
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
				    push @{$fields_ref->{'T0089'}}, {
					content => $value,
				    };
				    push @{$fields_ref->{'T0596'}}, {
					content => $value,
					subfield => "b",
				    };
				}
				elsif ($value && $type eq "issue"){
				    push @{$fields_ref->{'T0596'}}, {
					content => $value,
					subfield => "h",
				    };
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
				    } if ($value =~m/^\d{4}\-?\d{3}[0-9xX]$/);
				}
				elsif ($type =~/^issn-([0-9xX]{8})$/){
				    $value = $1;
				    
				    # Normieren
				    $value =~ s/^(\d{4})(\d{3}[0-9xX])$/$1-$2/;

				    # Todo: 543 oder 585
				    push @{$fields_ref->{'T0585'}}, {
					content => $value,
				    } if ($value =~m/^\d{4}\-?\d{3}[0-9xX]$/);
				}
				elsif ($value && $type eq "isbn-print"){
				    # Todo: 540
				    push @{$fields_ref->{'T0540'}}, {
					content => $value,
				    };
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
		DatePubCY       => 'T0595',
		ISBN            => 'T0540',
		ISSN	        => 'T0585',
	    };

	    
	    foreach my $item (@{$json_result_ref->{'Record'}{'Items'}}){
		my $label = $item->{Label};
		my $data  = $item->{Data};
		my $name  = $item->{Name};
		
		# Data breinigen. Hinweise pkostaedt
		$data =~ s{<br \/>}{ ; }g;
		$data =~ s{<relatesTo>[^<]+<\/relatesTo><i>[^<]+<\/i>}{}g; # z.B. <relatesTo>2</relatesTo><i> javierm@electrica.cujae.edu.cu</i>
		$data =~ s{<i>([^<]+)<\/i>}{$1}g;
		$data =~ s{<[^>]+>([^<]+)<\/[^>]+>}{$1}g;                  # z.B. <searchLink fieldCode="JN" term="%22Linux%22">Linux</searchLink>
		$data =~ s{&lt;.+?&gt;}{}g;                                # z.B. rih:2012-09413, pdx:0209854
		$data =~ s{&amp;amp;}{&amp;}g;                             # z.B. pdx:0209854

		if ($name =~ /^(ItemTitle|ItemAuthor|ItemLanguage|Abstract|AbstractNonEng|TitleSource|TitleSourceBook|Publisher|DatePubCY|ISBN|ISSN)$/) {

		    if ($name eq 'Publisher') {
			$data =~ s/,\s+\d{4}$//;                          # z.B. edsgsl:solis.00547468 (Hamburg : Diplomica Verl., 2009 -> Hamburg : Diplomica Verl.)
		    } 
		    elsif ($name eq 'TitleSource' && $json_result_ref->{Header}{DbId} eq 'edsoai' && $data =~ /urn:/) {
			next;                                             # z.B. edsoai:edsoai.824612814
		    }

		    if (defined $items_field_map_ref->{$name}){
			push @{$fields_ref->{$items_field_map_ref->{$name}}}, {
			    content => $data,
			};
			
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
		    elsif ($name eq 'ItemSubject') {
			if ($label eq 'Time') {
			    push @{$fields_ref->{'T0501'}}, {
				content => "Zeitangabe: " . $data, # z.B. Geburtsdaten, ID=edsoao:oao.T045764
			    };
			} 
			else { 
			    my @subjects = split(' ; ', $data);
			    foreach my $subject (@subjects) {
				push @{$fields_ref->{'T0710'}}, {
				    content => $data,
				};
			    }
			}
			
			
			
		    }
		}
	    }
	}
	
    }
    
    # Volltextlinks
    {
	my $link_mult = 1;
	
	my $url = "";
	
	eval { 	
	    $url = $json_result_ref->{'Record'}{'FullText'}{'Links'}[0]{'Link'}[0]{'Url'};
	};
	
	if ($url) { # ID=bth:94617232
	    $record->set_field({field => 'T0662', subfield => '', mult => $link_mult, content => $url});
	    $record->set_field({field => 'T0663', subfield => '', mult => $link_mult, content => "Volltext"});
	    # Todo: Zugriffstatus 'yellow' hinzufuegen
	    $link_mult++;
	}
	else { 
	    my $available = '';
	    
	    eval {
		$available = $json_result_ref->{'Record'}{'FullText'}{'Text'}{'Availability'}
	    };
		
	    if ($available == 1 && $json_result_ref->{'Record'}{PLink}) {
		$record->set_field({field => 'T0662', subfield => '', mult => $link_mult, content => $json_result_ref->{PLink}});
		$record->set_field({field => 'T0663', subfield => '', mult => $link_mult, content => "HTML-Volltext"});
		# Todo: Zugriffstatus 'yellow' hinzufuegen
		$link_mult++;
	    }
	}
	
	# arXiv, DOAJ und OAIster: Publikationstyp einfuegen und CustomLink auslesen
	if ($json_result_ref->{Header}{DbId} =~ /^(edsarx|edsdoj|edsoai)$/) {
	    $record->set_field({field => 'T0800', subfield => '', mult => 1, content => "electronic resource"}) unless $json_result_ref->{'Record'}{'Header'}{'PubType'};
	    
	    $url = '';
	    
	    eval {
		# In IPS $json_result_ref->{'FullText'}[0]{'CustomLinks'}[0]['CustomLink'][0]{'Url'};
		$url = $json_result_ref->{'Record'}{'FullText'}{'CustomLinks'}[0]{'Url'};
	    };
	    
	    if ($url) {
		$url =~ s!(.*)\#\?$!$1!; # OAIster: "#?" am Ende entfernen, z.B. ID=edsoai:edsoai.859893876 ; ID=edsoai:edsoai.690666320
		$url =~ s!(http://etheses.bham.ac.uk/[^/]+/).*ThumbnailVersion.*\.pdf!$1!; # Sonderanpassung fuer etheses.bham.ac.uk, z.B. ID=edsoai:edsoai.690666320
		$record->set_field({field => 'T0662', subfield => '', mult => $link_mult, content => $url});
		$record->set_field({field => 'T0663', subfield => '', mult => $link_mult, content => "Volltext"});
		# Todo: Zugriffstatus 'green' hinzufuegen
		$link_mult++;
	    }
	}


	# Science cititation index: hart verlinken
	# Hinweis pkostaedt: Der Link "Citing Articles" funktioniert nicht in jedem Fall, z.B. ID=edswss:000312205100002
	if ($json_result_ref->{Header}{DbId} =~ /^(edswsc|edswss)$/ && $json_result_ref->{Header}{An}) {
	    my $url = "http://gateway.isiknowledge.com/gateway/Gateway.cgi?&GWVersion=2&SrcAuth=EBSCO&SrcApp=EDS&DestLinkType=CitingArticles&KeyUT=" . $json_result_ref->{Header}{An} . "&DestApp=WOS";
	    
	    $record->set_field({field => 'T0662', subfield => '', mult => $link_mult, content => $url});
	    $record->set_field({field => 'T0663', subfield => '', mult => $link_mult, content => "Citing Articles (via Web of Science)"});
	    # Todo: Zugriffstatus 'yellow' hinzufuegen
	    $link_mult++;
	}

    }
    
    $record->set_fields_from_storable($fields_ref);
    
    $record->set_holding([]);
    $record->set_circulation([]);

    return $record;
}

sub load_brief_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->load_full_title_record($arg_ref);
}

sub get_classifications {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $url="http://rzblx10.uni-regensburg.de/dbinfo/fachliste.php?colors=$self->{colors}&ocolors=$self->{ocolors}&bib_id=$self->{dbis_bibid}&lett=l&lang=$self->{lang}&xmloutput=1";

    my $classifications_ref = [];
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'utf8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
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

sub _create_authtoken {
    my ($self,$ua) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;
    
    if (!$ua){
	$ua = LWP::UserAgent->new();
	$ua->agent('USB Koeln/1.0');
	$ua->timeout(30);
    }

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
    my ($self, $authtoken, $ua) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;
    
    if (!$ua){
	$ua = LWP::UserAgent->new();
	$ua->agent('USB Koeln/1.0');
	$ua->timeout(30);
    }
    
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

    $ua->default_header('x-authenticationToken' => $authtoken);
    
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
	    return $json_result_ref->{SessionToken};
	}
	else {
	    $logger->error('No SessionToken received'.$response->content);
	}

    } 
    else {
	$logger->error('Error in Request: '.$response->code.' - '.$response->message);
    }

    return;
}

sub connect_eds {
    my ($self,$ua) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;

    if (!$ua){
	$ua = LWP::UserAgent->new();
	$ua->agent('USB Koeln/1.0');
	$ua->timeout(30);
    }
    
    $self->{authtoken} = $self->_create_authtoken($ua);

    # second try... just in case ;-)
    if (!$self->{authtoken}){
	$self->{authtoken}  = $self->_create_authtoken($ua);
    }

    if (!$self->{authtoken}){
	$logger->error('No AuthToken available. Exiting...');
	return;	
    }
    
    $self->{sessiontoken} = $self->_create_sessiontoken($self->{authtoken},$ua);

    # second try... just in case ;-)
    if (!$self->{sessiontoken}){
	$self->{sessiontoken} = $self->_create_sessiontoken($self->{authtoken});
    }

    if (!$self->{sessiontoken}){
	$logger->error('No SessionToken available. Exiting...');
	return;	
    }

    return;
};

sub get_authtoken {
    my $self = shift;
    return $self->{authtoken};
}

sub get_sessiontoken {
    my $self = shift;
    return $self->{sessiontoken};
}

1;
__END__

=head1 NAME

OpenBib::DBIS - Objektorientiertes Interface zum DBIS XML-API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API des
Datenbankinformationssystems (DBIS) in Regensburg zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::DBIS;

 my $dbis = OpenBib::DBIS->new({});

=head1 METHODS

=over 4

=item new({ bibid => $bibid, client_ip => $client_ip, colors => $colors, ocolors => $ocolors, lang => $lang })

Erzeugung des DBIS Objektes. Dabei wird die DBIS-Kennung $bibid der
Bibliothek, die IP des aufrufenden Clients (zur Statistik), die
Sprachversion lang, sowie die Spezifikation der gewünschten
Zugriffsbedingungen color und ocolor benötigt.

=item get_subjects

Liefert eine Listenreferenz der vorhandenen Fachgruppen zurück mit
einer Hashreferenz auf die jeweilige Notation notation, der
Datenbankanzahl count, des Anfangbuchstabens lett sowie der
Beschreibung der Fachgruppe desc. Zusätzlich werden für eine
Wolkenanzeige die entsprechenden Klasseninformationen hinzugefügt.

=item search_dbs({ fs => $fs, notation => $notation })

Stellt die Suchanfrage $fs - optional eingeschränkt auf die Fachgruppe
$notation - an DBIS und liefert als Ergebnis verschiedene Informatinen
als Hashreferenz zurück.

Es sind dies die Informationen über die aktuelle Ergebnisseite
current_page (mit lett, colors, ocolors), die Fachgruppe subject, die
Kategorisierung von Datenbanken db_groups, die Zugriffsbedingungen
access_info sowie die jeweiligen Datenbanktypen db_type.

=item get_dbs({ notation => $notation, fs => $fs, lett => $lett, sc => $sc, lc => $lc, sindex => $sindex })

Liefert eine Liste mit Informationen über alle Datenbanken der
Fachgruppe $notation aus DBIS als Hashreferenz zurück.

Es sind dies die Informationen über die Fachgruppe subject, die
Kategorisierung von Datenbanken db_groups, die Zugriffsbedingungen
access_info sowie die jeweiligen Datenbanktypen db_type.

=item get_dbinfo({ id => $id })

Liefert Informationen über die Datenbank mit der Id $id als
Hashreferenz zurück. Es sind dies neben der Id $id auch Informationen
über den Titel title, hints, content, instructions, subjects,
keywords, appearance, access, access_info sowie db_type.

=item get_dbreadme({ id => $id })

Liefert zur Datenbank mit der Id $id generelle Nutzungsinformationen
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
