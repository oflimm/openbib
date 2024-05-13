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
use Getopt::Long;
use JSON::XS qw/encode_json decode_json/;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Search::Elasticsearch;
use YAML;

our ($do,$host,$collection,$outputfile,$stdout,$help,$loglevel,$logfile);

&GetOptions("do=s"            => \$do,

            "host=s"          => \$host,

	    "collection=s"    => \$collection,
	    "outputfile=s"    => \$outputfile,
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

if (defined &{$do}){
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
    
    my $response_ref = get_json($url);

    output($response_ref,"Listing collections");
}

sub list_items {
    if ((!$outputfile && !$stdout ) || !$collection){
	$logger->error("Missing args collection");
	exit;
    }

    my $fieldinfo_ref = {};

    {
	my $url = "https://${host}/dmwebservices/index.php?q=dmGetCollectionFieldInfo/$collection/json";
	
	my $response_ref = get_json($url);

	foreach my $field_ref (@$response_ref){
	    $fieldinfo_ref->{$field_ref->{nick}} = $field_ref->{name};
	}
    }
    
    my $url = "https://${host}/dmwebservices/index.php?q=dmQuery/$collection/0/dmrecord/dmrecord/1024/0/0/0/0/0/json";
    
    my $response_ref = get_json($url);

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
	    my $response_ref = get_json($url);

	    push @{$records_ref}, $response_ref->{records};
	    
	    $offset = $offset + $maxrecs;
	}
    }

    # Informatinen fuer Items holen
    my $items_ref = [];
    
    foreach my $record_ref (@$records_ref){
	my $cdmid = $record_ref->{pointer};
	my $url = "https://${host}/dmwebservices/index.php?q=dmGetItemInfo/$collection/$cdmid/json";
	
	$logger->info("Getting info for id $cdmid") unless ($stdout);	    
	my $response_ref = get_json($url);

	my $item_ref = {
	    id => $cdmid,
	    dbname => $collection,
	};
	
	foreach my $field (keys %{$response_ref}){
	    $response_ref->{$field} = "" if (ref $response_ref->{$field} eq "HASH" && !keys %{$response_ref->{$field}});
	    
	    push @{$item_ref->{fields}{$field}}, {
		content => $response_ref->{$field},
		description => $fieldinfo_ref->{$field},
		mult => 1,
	    };
	
	}
	push @$items_ref, $item_ref;
    }
    
    output($items_ref,"Listing items in collection $collection");    
}

sub list_fieldinfo {
    if ((!$outputfile && !$stdout ) || !$collection){
	$logger->error("Missing args collection");
	exit;
    }

    my $url = "https://${host}/dmwebservices/index.php?q=dmGetCollectionFieldInfo/$collection/json";
    
    my $response_ref = get_json($url);
    
    output($response_ref,"Listing fieldinfo for collection $collection");        }

sub output {
    my ($response_ref,$description) = @_;
    
    if ($stdout){
	if (ref $response_ref eq "ARRAY"){
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

	if (ref $response_ref eq "ARRAY"){
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

sub get_json {
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
	$logger->error("Error: ".$@);
	exit;
    }

    $logger->debug("Returning ".YAML::Dump($json_ref));
        
    return $json_ref;
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

ENDHELP
    exit;
}

