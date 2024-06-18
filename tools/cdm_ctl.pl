#!/usr/bin/perl
#####################################################################
#
#  cdm_ctl.pl
#
#  Helper for CDM
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
use utf8;

use Encode qw(decode_utf8 encode_utf8 encode decode);
use File::Path qw(make_path);
use Getopt::Long;
use JSON::XS qw/encode_json decode_json/;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use OpenBib::Template::Provider;
use Template;
use XML::LibXML;
use XML::LibXML::XPathContext;
use YAML;

our ($do,$host,$collection,$id,$offline,$outputdir,$outputfile,$viewerurl,$stdout,$help,$loglevel,$logfile);

&GetOptions("do=s"            => \$do,

            "host=s"          => \$host,

	    "collection=s"    => \$collection,
	    "id=s"            => \$id,	    
	    "outputfile=s"    => \$outputfile,
	    "outputdir=s"     => \$outputdir,
	    "viewer-url=s"    => \$viewerurl,	    
	    "stdout"          => \$stdout,
	    "offline"         => \$offline,
	    
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
	    "help"            => \$help
	    );

if ($help || !$do){
    print_help();
}

$host=($host)?$host:'services.ub.uni-koeln.de';

$logfile=($logfile)?$logfile:'./cdm_ctl.log';
$loglevel=($loglevel)?$loglevel:'INFO';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

our $ua = LWP::UserAgent->new();
$ua->agent('USB Koeln/1.0');
$ua->timeout(30);
$ua->default_header(
    'Accept-Charset' => 'utf-8',
    );

if ($offline && ( !$outputdir || !$viewerurl)){
    $logger->error("Offline mode needs outputdir from previous run and viewer-url");
    exit;
}

if ($do !~m/^_/ && defined &{$do}){
    no strict 'refs';
    &{$do};
}
else {
    $logger->error("Action $do not supported");
    exit;
}
    
sub list_collections {
    if (!$outputfile && !$stdout ){
	$logger->error("Missing args collection");
	exit;
    }

    my $url = "https://${host}/dmwebservices/index.php?q=dmGetCollectionList/json";
    
    my $response_ref = _get_json($url);

    output($response_ref,"Listing collections");
}

sub list_items {
    if ((!$outputfile && !$stdout ) || !$collection){
	$logger->error("Missing args collection");
	exit;
    }
    
    my $records_ref = _cdm_get_records_in_collection($collection);
    
    # Informatinen fuer Items holen
    my $items_ref = [];
    
    foreach my $record_ref (@$records_ref){
	my $cdmid = $record_ref->{pointer};
	my $item_ref = _cdm_get_iteminfo($collection,$cdmid);
	
	push @$items_ref, $item_ref;
    }
    
    output($items_ref,"Listing items in collection $collection");    
}

sub get_manifest4dfgviewer {
    if ((!$outputfile && !$stdout ) || !$collection || !$id){
	$logger->error("Missing args collection");
	exit;
    }

    my $info_ref      = _cdm_get_iteminfo($collection,$id);
    my $structure_ref = _cdm_get_structure($collection,$id);

    my $record_ref = {
	info => $info_ref,
	structure => $structure_ref,
    };

    my $procname = "_cdm_create_dfgviewer_manifest";

    if (defined &{$procname."_".$collection}){
	no strict 'refs';
	my $manifest = &{$procname."_".$collection}($record_ref);

	output($manifest,"Getting dfgviewer manifest for item $id in collection $collection");    
    }
    elsif (defined &{$procname}){
	no strict 'refs';
	my $manifest = &{$procname}($record_ref);
	output($manifest,"Getting default dfgviewer manifest for item $id in collection $collection");    	
    }
    else {
	$logger->error("Action $do not supported");
	exit;
    }
}

sub get_manifest4dfgviewer_obsolete {
    if ((!$outputfile && !$stdout ) || !$collection || !$id){
	$logger->error("Missing args collection");
	exit;
    }

    my $url = "https://${host}/cdm4/mets_gateway.php?CISOROOT=/$collection&CISOPTR=$id";
	
    my $manifest_ref = _get_url($url);
    
    output($manifest_ref,"Getting DFGviewer manifest for item $id in collection $collection");    
}

sub get_manifest4iiif {
    if ((!$outputfile && !$stdout ) || !$collection || !$id){
	$logger->error("Missing args collection");
	exit;
    }

    my $info_ref      = _cdm_get_iteminfo($collection,$id);
    my $structure_ref = _cdm_get_structure($collection,$id);

    my $procname = "_cdm_create_iiif_manifest_$collection";

    if (defined &{$procname}){
	no strict 'refs';
	my $manifest_ref = &{$procname};

	output($manifest_ref,"Getting IIIF manifest for item $id in collection $collection");    
    }
    else {
	$logger->error("Action $do not supported");
	exit;
    }
}

sub get_structure {
    if ((!$outputfile && !$stdout ) || !$collection || !$id){
	$logger->error("Missing args");
	exit;
    }

    my $structure_ref = _cdm_get_structure($collection,$id);
    
    output($structure_ref,"Getting structure for item $id in collection $collection");    
}

sub dump_item4iiif {
    if (!$outputdir || !$collection || !$id){
	$logger->error("Missing args");
	exit;
    }

    my $info_ref      = _cdm_get_iteminfo($collection,$id);
    my $structure_ref = _cdm_get_structure($collection,$id);
    
    my $url = "https://${host}/cdm4/mets_gateway.php?CISOROOT=/$collection&CISOPTR=$id";
    
    my $manifest = _get_url($url);
    
    _cdm_process_item({ id => $id, manifest => $manifest, type => 'iiif'});
}

sub dump_item4dfgviewer {
    if (!$outputdir || !$collection || !$id){
	$logger->error("Missing args");
	exit;
    }

    my $url = "https://${host}/cdm4/mets_gateway.php?CISOROOT=/$collection&CISOPTR=$id";
    
    my $manifest = _get_url($url);
    
    _cdm_process_item({ id => $id, type => 'dfgviewer'});
}

sub dump_collection4dfgviewer {
    if (!$outputdir || !$viewerurl || !$collection){
	$logger->error("Missing args");
	exit;
    }

    my $records_ref = _cdm_get_records_in_collection($collection);

    foreach my $record_ref (@$records_ref){
	if (ref $record_ref eq "HASH"){
	    my $cdmid = $record_ref->{pointer};

	    _cdm_process_item({id => $cdmid, type => 'dfgviewer'});
	}
    }
}

sub list_fieldinfo {
    if ((!$outputfile && !$stdout ) || !$collection){
	$logger->error("Missing args collection");
	exit;
    }

    my $url = "https://${host}/dmwebservices/index.php?q=dmGetCollectionFieldInfo/$collection/json";
    
    my $response_ref = _get_json($url);

    if (ref $response_ref eq "HASH" && $response_ref->{code}){
	$logger->error("Error ".$response_ref->{code}.": ".$response_ref->{message}) unless ($stdout);
	exit;
    }
    
    output($response_ref,"Listing fieldinfo for collection $collection");        }

##########################################################################
# Helper functions
##########################################################################
sub output {
    my ($response_ref,$description) = @_;
    
    if ($stdout){
	if (!ref $response_ref){ # Scalar == String?
	    print $response_ref,"\n";		
	}
	elsif (ref $response_ref eq "ARRAY"){ # Arrayref?
	    foreach my $item_ref (@$response_ref){
		print encode_json($item_ref),"\n";		
	    }
	}
	else {
	    print encode_json($response_ref),"\n";
	}
    }
    else {
	open(OUTPUT,">:utf8",$outputfile);
	
	$logger->info($description);

	if (!ref $response_ref){ # Scalar == String?
	    print OUTPUT $response_ref,"\n";		
	}
	elsif (ref $response_ref eq "ARRAY"){ # Arrayref?
	    foreach my $item_ref (@$response_ref){
		print OUTPUT encode_json($item_ref),"\n";		
	    }
	}
	else {
	    print OUTPUT encode_json($response_ref),"\n";
	}
	
	close(OUTPUT);
    }
}

sub _get_json {
    my ($url) = @_;

    $logger->debug("Request: $url");

    my $request = HTTP::Request->new('GET' => $url);
    
    my $response = $ua->request($request);

    if ($logger->is_debug){
	$logger->debug("Response: ".decode_utf8($response->content));
	$logger->debug("Status: ".$response->status_line);
    }
    
    if (!$response->is_success) {
	$logger->error($response->code . ' - ' . $response->message);
	exit;
    }

    my $result = $response->content;

    my $json_ref = undef;
    
    eval {
	$json_ref = decode_json $result;
    };

    if ($@){
	$logger->error($response->content);
	exit;
    }
    
    $logger->debug("Returning ".YAML::Dump($json_ref));
            
    return $json_ref;
}

sub _cdm_get_iteminfo {
    my $collection = shift;
    my $cdmid = shift;

    my $fieldinfo_ref = {};

    {
	my $url = "https://${host}/dmwebservices/index.php?q=dmGetCollectionFieldInfo/$collection/json";
	
	my $response_ref = _get_json($url);

	if (ref $response_ref eq "HASH" && $response_ref->{code}){
	    $logger->error("Error ".$response_ref->{code}.": ".$response_ref->{message}) unless ($stdout);
	    next;
	}
	
	foreach my $field_ref (@$response_ref){
	    $fieldinfo_ref->{$field_ref->{nick}} = $field_ref->{name};
	}
    }
    
    my $url = "https://${host}/dmwebservices/index.php?q=dmGetItemInfo/$collection/$cdmid/json";
    
    $logger->info("Getting info for id $cdmid") unless ($stdout);	    
    my $response_ref = _get_json($url);

    if (ref $response_ref eq "HASH" && $response_ref->{code}){
	$logger->error("Error ".$response_ref->{code}.": ".$response_ref->{message}) unless ($stdout);
	next;
    }
    
    my $item_ref = {
	id => $cdmid,
	dbname => $collection,
    };
    
    foreach my $field (keys %{$response_ref}){
	# Leeres Hashrefs auf "" vereinheitlichen
	$response_ref->{$field} = "" if (ref $response_ref->{$field} eq "HASH" && !keys %{$response_ref->{$field}});
	
	next if (!$response_ref->{$field});
	
	push @{$item_ref->{fields}{$field}}, {
	    content => $response_ref->{$field},
	    description => $fieldinfo_ref->{$field},
	    mult => 1,
	};
	
    }

    return $item_ref;
}

sub _cdm_get_structure {
    my $collection = shift;
    my $cdmid = shift;

    my $url = "https://${host}/dmwebservices/index.php?q=dmGetCompoundObjectInfo/$collection/$cdmid/json";


    my $structure_ref = _get_json($url);

    return $structure_ref;
}
sub _cdm_get_records_in_collection {
    my $collection = shift;

    $logger->info("Getting first 1024 items in collection");    
    
    my $url = "https://${host}/dmwebservices/index.php?q=dmQuery/$collection/0/dmrecord/dmrecord/1024/0/0/0/0/0/json";
    
    my $response_ref = _get_json($url);

    my $records_ref = $response_ref->{records};
    my $total       = $response_ref->{pager}{total};
    my $maxrecs     = $response_ref->{pager}{maxrecs};    

    # Mehr als 1024, dann iterativ den Rest holen
    unless ($total <= $maxrecs){
	my $max_idx = int ($total / $maxrecs);
	my $offset = $maxrecs;

	$logger->debug("Max idx is $max_idx");
	
	for (my $idx=1;$idx <= $max_idx;$idx++){

	    $logger->info("Getting next 1024 items in collection with offset $offset");    

	    my $url = "https://${host}/dmwebservices/index.php?q=dmQuery/$collection/0/dmrecord/dmrecord/1024/$offset/0/0/0/0/json";

	    $logger->debug("Getting items for offset $offset");	    
	    my $response_ref = _get_json($url);

	    push @{$records_ref}, @{$response_ref->{records}};
	    
	    $offset = $offset + $maxrecs;
	}
    }

    my $total_count = scalar @{$records_ref};

    $logger->info("Got $total_count items");
    
    return $records_ref;
}

sub _get_url {
    my ($url) = @_;

    $logger->debug("Request: $url");

    my $request = HTTP::Request->new('GET' => $url);
    
    my $response = $ua->request($request);

    if ($logger->is_debug){
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success) {
	$logger->error($response->code . ' - ' . $response->message);
	exit;
    }

    my $result = $response->decoded_content;
    
    $logger->debug("Returning $result");
            
    return $result;
}

sub _cdm_process_item {
    my $arg_ref = shift;
    my $id       = (defined $arg_ref->{id})?$arg_ref->{id}:undef;    
    my $manifest = (defined $arg_ref->{manifest})?$arg_ref->{manifest}:'';
    my $type     = (defined $arg_ref->{type})?$arg_ref->{type}:'dfgviewer';

    my $info_ref      = _cdm_get_iteminfo($collection,$id);
    my $structure_ref = _cdm_get_structure($collection,$id);

    # Not Compound Object?
    if (defined $info_ref->{fields}{'find'}){
	my $find = $info_ref->{fields}{'find'}[0]{content};
	if ($find !~m/\.cpd$/){
	    $structure_ref = {
		page => [
		    {
			pagefile => $find,
			pageptr => $id,
			pagetitle => "1",
		    },
		    ],
	    };
	}
    }
    
    my $record_ref = {
	info => $info_ref,
	structure => $structure_ref,
    };

    my $new_dir = "$outputdir/$collection/$id";    
    
    make_path($new_dir);

    $outputfile = "$new_dir/record.json";
    $logger->info("Dumping JSON-Record to $outputfile");
    output($record_ref,"Dumping item $id in collection $collection as record.json done");

    my $is_cover = 1;
    foreach my $page_ref (@{$record_ref->{structure}{node}{node}}){
	if (defined $page_ref->{page} && ref $page_ref->{page} eq "ARRAY"){
	    foreach my $thispage_ref (@{$page_ref->{page}}){
		my $format = "jpg";
		if ($thispage_ref->{pagefile} =~m/\.tif/){
		    $format = "tif";
		}
		elsif ($thispage_ref->{pagefile} =~m/\.pdf/){
		    $format = "pdf";
		}
		my $filename = $thispage_ref->{pageptr}.".$format";
		my $png      = $thispage_ref->{pageptr}.".png";
		my $jpeg     = $thispage_ref->{pageptr}.".jpg";
		my $webview  = $thispage_ref->{pageptr}."_web.jpg";
		my $thumb    = $thispage_ref->{pageptr}."_thumb.jpg";
		my $cover    = "cover.jpg";
		
		if (-e "$new_dir/$filename"){
		    $logger->info("File $filename already exists. Ignoring");
		}
		else {
		    my $cdm_url = "https://${host}/cgi-bin/showfile.exe?CISOROOT=/${collection}&CISOPTR=".$thispage_ref->{pageptr};
		    
		    $logger->info("Getting $filename from $cdm_url");		
		    
		    system("wget --quiet --no-check-certificate -O $new_dir/$filename '$cdm_url'");
		}

		my $convertargs = ($format eq "tif")?'-flatten':'';
		
		# Generate Thumbs und Webview
		if ($format eq "tif" && !-e "$new_dir/$png"){
		    system("convert $convertargs $new_dir/$filename $new_dir/$png");
		}

		if ($is_cover && !-e "$new_dir/$cover"){
		    system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$cover");
		    $is_cover = 0;
		}
		
		if (!-e "$new_dir/$webview"){
		    system("convert $convertargs -resize '900x900>' $new_dir/$filename $new_dir/$webview");
		}
		
		if (!-e "$new_dir/$thumb"){
		    system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$thumb");
		}
	    }
	}
	elsif (defined $page_ref->{page} && ref $page_ref->{page} eq "HASH"){
	    my $format = "jpg";
	    if ($page_ref->{page}{pagefile} =~m/\.tif/){
		$format = "tif";
	    }
	    elsif ($page_ref->{page}{pagefile} =~m/\.pdf/){
		$format = "pdf";
	    }
	    my $filename = $page_ref->{page}{pageptr}.".$format";
	    my $jpeg     = $page_ref->{page}{pageptr}.".jpg";
	    my $png      = $page_ref->{page}{pageptr}.".png";
	    my $webview  = $page_ref->{page}{pageptr}."_web.jpg";
	    my $thumb    = $page_ref->{page}{pageptr}."_thumb.jpg";
	    my $cover    = "cover.jpg";
	    
	    if (-e "$new_dir/$filename"){
		$logger->info("File $filename already exists. Ignoring");
	    }
	    else {
		my $cdm_url = "https://${host}/cgi-bin/showfile.exe?CISOROOT=/${collection}&amp;CISOPTR=".$page_ref->{page}{pageptr};
		
		$logger->info("Getting $filename from $cdm_url");		
		
		system("wget --quiet --no-check-certificate -O $new_dir/$filename '$cdm_url'");
	    }

	    my $convertargs = ($format eq "tif")?'-flatten':'';
	    
	    # Generate Thumbs und Webview
	    if ($format eq "tif" && !-e "$new_dir/$png"){
		system("convert $convertargs $new_dir/$filename $new_dir/$png");
	    }

	    if ($is_cover && !-e "$new_dir/$cover"){
		system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$cover");
		$is_cover = 0;
	    }

	    if (!-e "$new_dir/$webview"){
		system("convert $convertargs -resize '900x900>' $new_dir/$filename $new_dir/$webview");
	    }
	    
	    if (!-e "$new_dir/$thumb"){
		system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$thumb");
	    }
	}
    }

    if (defined $record_ref->{structure}{node}{page} && ref $record_ref->{structure}{node}{page} eq "ARRAY"){    
	foreach my $thispage_ref (@{$record_ref->{structure}{node}{page}}){
	    my $format = "jpg";
	    if ($thispage_ref->{pagefile} =~m/\.tif/){
		$format = "tif";
	    }
	    elsif ($thispage_ref->{pagefile} =~m/\.pdf/){
		$format = "pdf";
	    }
	    my $filename = $thispage_ref->{pageptr}.".$format";
	    my $jpeg     = $thispage_ref->{pageptr}.".jpg";
	    my $png      = $thispage_ref->{pageptr}.".png";	    
	    my $webview  = $thispage_ref->{pageptr}."_web.jpg";
	    my $thumb    = $thispage_ref->{pageptr}."_thumb.jpg";
	    my $cover    = "cover.jpg";
	    
	    if (-e "$new_dir/$filename"){
		$logger->info("File $filename already exists. Ignoring");
	    }
	    else {
		my $cdm_url = "https://${host}/cgi-bin/showfile.exe?CISOROOT=/${collection}&CISOPTR=".$thispage_ref->{pageptr};
		
		$logger->info("Getting $filename from $cdm_url");		
		
		system("wget --quiet --no-check-certificate -O $new_dir/$filename '$cdm_url'");
	    }
	    
	    my $convertargs = ($format eq "tif")?'-flatten':'';

	    # Generate Thumbs und Webview
	    if ($format eq "tif" && !-e "$new_dir/$png"){
		system("convert $convertargs $new_dir/$filename $new_dir/$png");
	    }
	    
	    if ($is_cover && !-e "$new_dir/$cover"){
		system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$cover");
		$is_cover = 0;
	    }
	    
	    if (!-e "$new_dir/$webview"){
		system("convert $convertargs -resize '900x900>' $new_dir/$filename $new_dir/$webview");
	    }
	    
	    if (!-e "$new_dir/$thumb"){
		system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$thumb");
	    }
	}
    }

    if (defined $record_ref->{structure}{page} && ref $record_ref->{structure}{page} eq "ARRAY"){    
	foreach my $thispage_ref (@{$record_ref->{structure}{page}}){
	    my $format = "jpg";
	    if ($thispage_ref->{pagefile} =~m/\.tif/){
		$format = "tif";
	    }
	    elsif ($thispage_ref->{pagefile} =~m/\.pdf/){
		$format = "pdf";
	    }
	    my $filename = $thispage_ref->{pageptr}.".$format";
	    my $pdf      = $thispage_ref->{pageptr}.".pdf";
	    my $jpeg     = $thispage_ref->{pageptr}.".jpg";
	    my $png      = $thispage_ref->{pageptr}.".png";	    
	    my $webview  = $thispage_ref->{pageptr}."_web.jpg";
	    my $thumb    = $thispage_ref->{pageptr}."_thumb.jpg";
	    my $cover    = "cover.jpg";

	    $logger->debug("Pageptr: ".$thispage_ref->{pageptr}." Filename: $filename ; JPEG: $jpeg ; PNG: $png ; Webview: $webview ; Thumb: $thumb ; Cover: $cover");
	    
	    if (-e "$new_dir/$filename"){
		$logger->info("File $filename already exists. Ignoring");
	    }
	    else {
		my $cdm_url = "https://${host}/cgi-bin/showfile.exe?CISOROOT=/${collection}&CISOPTR=".$thispage_ref->{pageptr};
		
		$logger->info("Getting $filename from $cdm_url");		
		
		system("wget --quiet --no-check-certificate -O $new_dir/$filename '$cdm_url'");
	    }

	    if ($format eq "pdf"){
		system("cd $new_dir ; pdftoppm -f 1 -l 1 $pdf ".$thispage_ref->{pageptr}." -jpeg");
		system("cd $new_dir ; mv ".$thispage_ref->{pageptr}."-01.jpg $jpeg");
		$filename = $jpeg;
	    }
	    
	    my $convertargs = ($format eq "tif")?'-flatten':'';
	    
	    # Generate Thumbs und Webview
	    if ($format eq "tif" && !-e "$new_dir/$png"){
		system("convert $convertargs $new_dir/$filename $new_dir/$png");
	    }
	    
	    if ($is_cover && !-e "$new_dir/$cover"){
		system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$cover");
		$is_cover = 0;
	    }
	    
	    if (!-e "$new_dir/$webview"){
		system("convert $convertargs -resize '900x900>' $new_dir/$filename $new_dir/$webview");
	    }
	    
	    if (!-e "$new_dir/$thumb"){
		system("convert $convertargs -resize '150x150>' $new_dir/$filename $new_dir/$thumb");
	    }
	}
    }

    if ($type eq "dfgviewer"){
	$outputfile = "$new_dir/manifest.xml";
	my $procname = "_cdm_create_dfgviewer_manifest";
	
	if (defined &{$procname."_".$collection}){
	    no strict 'refs';
	    my $manifest = &{$procname."_".$collection}($record_ref);
	    
	    output($manifest,"Getting dfgviewer manifest for item $id in collection $collection");    
	}
	elsif (defined &{$procname}){
	    no strict 'refs';
	    my $manifest = &{$procname}($record_ref);
	    output($manifest,"Getting default dfgviewer manifest for item $id in collection $collection");    	
	}
	else {
	    $logger->error("Action $do not supported");
	    exit;
	}
    }
    
    if ( 0 == 1 && $manifest && $type eq "dfgviewer"){
	my $parser = XML::LibXML->new();
	my $tree   = $parser->parse_string($manifest);
	my $xpc    = XML::LibXML::XPathContext->new($tree);
	
	$xpc->registerNs('mets',  'http://www.loc.gov/METS/');
	$xpc->registerNs('xlink',  'http://www.w3.org/1999/xlink');    
	
	my $new_dir = "$outputdir/$collection/$id";
	
	make_path($new_dir);
	
	foreach my $link_node ($xpc->findnodes('//mets:file/mets:FLocat')){
	    my $cdm_imgurl = $link_node->getAttribute('xlink:href');
	    $cdm_imgurl =~s/&amp;/&/g;
	    
	    my ($imgid) = $cdm_imgurl =~m{CISOPTR=(\d+)};
	    my ($width) = $cdm_imgurl =~m{WIDTH=(\d+)};
	    
	    my $img_name = ($width)?"${imgid}_w${width}.jpg":"$imgid.jpg";
	    
	    my $new_url = $viewerurl."/$collection/$id/$img_name";
	    
	    system("wget --quiet --no-check-certificate -O $new_dir/$img_name '$cdm_imgurl'");
	    $logger->info("Dumping $cdm_imgurl -> $img_name");
	    
	    $link_node->setAttribute('xlink:href' => $new_url);
	}
	
	$outputfile = "$new_dir/manifest.xml";
	$logger->info("Dumping manifest $outputfile");
	output($tree->toString,"Dumping item $id in collection $collection done");
    }
    
    return;
}

# USB specific processing
sub _cdm_create_dfgviewer_manifest {
    my $record_ref = shift;
    # Generate METS/MODS Manifest
    my $manifest = "";

    my $ttdata = {
	record     => $record_ref,
	collection => $collection,
	viewerurl  => $viewerurl,
    };
    
    my $template = Template->new({ 
	# LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
	#     INCLUDE_PATH   => '/opt/openbib/templates',
	#     ABSOLUTE       => 1,
	#     STAT_TTL => 120,  # two minutes
	#     COMPILE_DIR => '/tmp/ttc',
	# 						     }) ],
	INCLUDE_PATH   => '/opt/openbib/templates',
	ENCODING     => 'utf8',
	ABSOLUTE       => 1,
	STAT_TTL => 120,  # two minutes
	COMPILE_DIR => '/tmp/ttc',
	OUTPUT         => \$manifest,    # Output geht in Scalar-Ref
				 });
    
    $template->process('dfgviewer', $ttdata) || do {
            $logger->fatal($template->error());
    };
    
    
    return $manifest;
}

sub _cdm_create_iiif_manifest_zas {

}

sub print_help {
    print << "ENDHELP";
cdm_ctl.pl - Helper for CDM

Generel Options:
   -help                 : This info
   --logfile=...         : logfile (default: ./es_ctl.log)
   --loglevel=...        : loglevel (default: INFO)
   --host=...            : host (default: services.ub.uni-koeln.de)

List collections
   --do=list_collections
   --outputfile=...      : Outputfile
   -stdout               : Ausgabe nach STDOUT anstelle Outputfile

List fieldinfo of collection
   --do=list_fieldinfo
   --collection=...      : Collection Name
   --outputfile=...      : Outputfile
   -stdout               : Ausgabe nach STDOUT anstelle Outputfile

List collection items
   --do=list_items
   --collection=...      : Collection Name
   --outputfile=...      : Outputfile
   -stdout               : Ausgabe nach STDOUT anstelle Outputfile

List compound structure of item
   --do=get_structure
   --collection=...      : Collection Name
   --id=...              : Item ID
   --outputfile=...      : Outputfile
   -stdout               : Ausgabe nach STDOUT anstelle Outputfile

Dump single item to display with DFG-Viewer
   --do=dump_item4dfgviewer
   --collection=...      : Collection Name
   --id=...              : Item ID
   --outputdir=...       : Base directory to output Images/Manifest
   --viewer-url=...      : Base URL Prefix to reference files in base directory

Dump all items in collection to display with DFG-Viewer
   --do=dump_collection4dfgviewer
   --collection=...      : Collection Name
   --outputdir=...       : Base directory to output Images/Manifest
   --viewer-url=...      : Base URL Prefix to reference files in base directory

e.g:

./cdm_ctl.pl --do=list_collections --outputfile=collections.json
./cdm_ctl.pl --do=list_fieldinfo -stdout --collection=abc | jq -S . | more
./cdm_ctl.pl --do=list_items --outputfile=abc_items.json --collection=abc
./cdm_ctl.pl --do=get_structure --stdout --collection=inkunabeln --id=209521|jq -S .|less
./cdm_ctl.pl --do=dump_item4dfgviewer --outputdir=/store/scans --collection=inkunabeln --id=209521  --viewer-url="https://search.ub.uni-koeln.de/scans"
./cdm_ctl.pl --do=dump_collection4dfgviewer --outputdir=/store/scans --collection=inkunab_tmp  --viewer-url="https://search.ub.uni-koeln.de/scans"
./cdm_ctl.pl -offline --do=dump_collection4dfgviewer --outputdir=/store/scans --collection=inkunab_tmp  --viewer-url="https://search.ub.uni-koeln.de/scans"

ENDHELP
    exit;
}

