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

use Encode qw(decode_utf8 encode_utf8);
use File::Path qw(make_path);
use Getopt::Long;
use JSON::XS qw/encode_json decode_json/;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use XML::LibXML;
use XML::LibXML::XPathContext;
use YAML;

our ($do,$host,$collection,$id,$outputdir,$outputfile,$viewerurl,$stdout,$help,$loglevel,$logfile);

&GetOptions("do=s"            => \$do,

            "host=s"          => \$host,

	    "collection=s"    => \$collection,
	    "id=s"            => \$id,	    
	    "outputfile=s"    => \$outputfile,
	    "outputdir=s"     => \$outputdir,
	    "viewer-url=s"    => \$viewerurl,	    
	    "stdout"          => \$stdout,
	    
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
	my $item_ref = cdm_get_item_info($cdmid);
	
	push @$items_ref, $item_ref;
    }
    
    output($items_ref,"Listing items in collection $collection");    
}

sub get_manifest4dfgviewer {
    if ((!$outputfile && !$stdout ) || !$collection || !$id){
	$logger->error("Missing args collection");
	exit;
    }

    my $url = "https://${host}/cdm4/mets_gateway.php?CISOROOT=/$collection&CISOPTR=$id";
	
    my $manifest = _get_url($url);
    
    output($manifest,"Getting DFGviewer manifest for item $id in collection $collection");    
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
    
    _cdm_process_item($id,$manifest);
}

sub dump_item4dfgviewer {
    if (!$outputdir || !$collection || !$id){
	$logger->error("Missing args");
	exit;
    }

    my $url = "https://${host}/cdm4/mets_gateway.php?CISOROOT=/$collection&CISOPTR=$id";
    
    my $manifest = _get_url($url);
    
    _cdm_process_item($id,$manifest);
}

sub dump_collection4dfgviewer {
    if (!$outputdir || !$viewerurl || !$collection){
	$logger->error("Missing args");
	exit;
    }

    my $records_ref = cdm_get_records_in_collection($collection);

    foreach my $record_ref (@$records_ref){
	my $cdmid = $record_ref->{pointer};
    
	my $url = "https://${host}/cdm4/mets_gateway.php?CISOROOT=/$collection&CISOPTR=$cdmid";
    
	my $manifest = _get_url($url);
    
	_cdm_process_item($cdmid,$manifest);
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
	open(OUTPUT,">$outputfile");
	
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
	$logger->debug("Response: ".$response->content);
    }
    
    if (!$response->is_success) {
	$logger->error($response->code . ' - ' . $response->message);
	exit;
    }

    my $result = decode_utf8($response->content);

    my $json_ref = undef;
    
    eval {
	$json_ref = decode_json ($result);
    };

    if ($@){
	$logger->error($response->content);
	exit;
    }
    
    $logger->debug("Returning ".YAML::Dump($json_ref));
            
    return $json_ref;
}

sub _cdm_get_iteminfo {
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

    my $url = "https://${host}/dmwebservices/index.php?q=dmGetCompoundObjectInfo/$collection/$id/json";


    my $structure_ref = _get_url($url);

    return $structure_ref;
}
sub _cdm_get_records_in_collection {
    my $collection = shift;
    
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
	    my $url = "https://${host}/dmwebservices/index.php?q=dmQuery/$collection/0/dmrecord/dmrecord/1024/$offset/0/0/0/0/json";

	    $logger->debug("Getting items for offset $offset");	    
	    my $response_ref = _get_json($url);

	    push @{$records_ref}, $response_ref->{records};
	    
	    $offset = $offset + $maxrecs;
	}
    }

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

    my $result = decode_utf8($response->content);
    
    $logger->debug("Returning $result");
            
    return $result;
}

sub _cdm_process_item {
    my $id = shift;    
    my $item = shift;

    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($item);
    my $xpc    = XML::LibXML::XPathContext->new($tree);

    $xpc->registerNs('mets',  'http://www.loc.gov/METS/');
    $xpc->registerNs('xlink',  'http://www.w3.org/1999/xlink');    

    my $new_dir = "$outputdir/$collection/$id";
    print $new_dir,"\n";
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
    return;
}

# USB specific processing
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

List collection items
   --do=list_items
   --index=collection    : Collection Name
   --outputfile=...      : Outputfile

e.g:

./cdm_ctl.pl --do=list_collections --outputfile=collections.json
./cdm_ctl.pl --do=list_fieldinfo -stdout --collection=abc | jq -S . | more
./cdm_ctl.pl --do=list_items --outputfile=abc_items.json --collection=abc
./cdm_ctl.pl --do=get_structure --stdout --collection=inkunabeln --id=209521|jq -S .|less
./cdm_ctl.pl --do=dump_item4dfgviewer --outputdir=/store/scans --collection=inkunabeln --id=209521  --viewer-url="https://search.ub.uni-koeln.de/scans"
./cdm_ctl.pl --do=dump_collection4dfgviewer --outputdir=/store/scans --collection=inkunab_tmp  --viewer-url="https://search.ub.uni-koeln.de/scans"

ENDHELP
    exit;
}

