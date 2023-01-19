#!/usr/bin/perl
#####################################################################
#
#  es_ctl.pl
#
#  Helper for Elasticsearch
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use JSON::XS qw/encode_json decode_json/;
use Log::Log4perl qw(get_logger :levels);
use Search::Elasticsearch;
use YAML;

our ($alias,$credential,$do,$host,$index,$inputfile,$outputfile,$help,$loglevel,$logfile);

&GetOptions("do=s"            => \$do,

            "host=s"          => \$host,
            "credential=s"    => \$credential,
	    "index=s"         => \$index,
	    "alias=s"         => \$alias,
	    
	    "inputfile=s"     => \$inputfile,
	    "outputfile=s"    => \$outputfile,
	    
            "logfile=s"       => \$logfile,
            "loglevel=s"      => \$loglevel,
	    "help"            => \$help
	    );

if ($help || !$do){
    print_help();
}

$host=($host)?$host:'localhost:9200';

$logfile=($logfile)?$logfile:'./es_ctl.log';
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

our $es;

if ($credential){
    $es = Search::Elasticsearch->new(
	userinfo   => $credential,
	cxn_pool   => "Sniff",
	nodes      => $host,
	);
}
else {
    $es = Search::Elasticsearch->new(
	cxn_pool   => "Sniff",
	nodes      => $host,
	);
}


if (defined &{$do}){
    no strict 'refs';
    &{$do};
}
else {
    $logger->error("Action $do not supported");
    exit;
}
    
sub export {
    if (!$outputfile || !$index){
	$logger->error("Missing args outputfile or index");
	exit;
    }

    open(OUTPUT,">$outputfile");
    
    $logger->info("Exporting");

    # 1) Mapping des Index bestimmen und ausgeben

    my $meta = $es->indices->get(
	index   => $index,
	);

    print OUTPUT encode_json($meta->{$index}),"\n";
	
    # 2) Per Scroll durch das alle Datensaetze gehen und ausgeben
    
    my $scroller = $es->scroll_helper(
	index       => $index,
	scroll      => '2m',
	size        => 1000,
	body        => {
	    query  => {
		"match_all" => {},
	    },
	}
	);

    my $count = 1;
    while (my $record_ref = $scroller->next) {
	print OUTPUT encode_json($record_ref),"\n";
	
	if ($count % 10000 == 0){
	    $logger->info("$count records");
	}
	
	$count++;
    }

    $logger->info("$count records done");

    close(OUTPUT);
    
}

sub import {
    if (!$inputfile || !$index){
	$logger->error("Missing args inputfile or index");
	exit;
    }

    open(INPUT,"$inputfile");
    
    $logger->info("Importing");

    # 1) Neuen Index erzeugen

    my $result;
    
    if ($es->indices->exists( index => $index )){
	$result = $es->indices->delete( index => $index );
    }
    
    $result = $es->indices->create(
	index    => $index,
	);
    
    # 2) Mapping des Index einladen und schreiben
    
    my $mapping = <INPUT>;
    
    my $mapping_ref = decode_json($mapping);
    
    $result = $es->indices->put_mapping(
	index => $index,
	body => {
	    properties => $mapping_ref->{mappings}{properties},
	}	
	);
    
    # 3) Datensaetze einladen und schreiben

    my $bulk = $es->bulk_helper(
	index => $index,
	max_count => 2000,
	);

    my $count = 1;
    while (my $record = <INPUT>){
	my $record_ref = decode_json($record);
	
	$bulk->index({
	    _id    => $record_ref->{_id},
	    source => $record_ref->{_source},
		     });

	if ($count % 10000 == 0){
	    $logger->info("$count records");
	}
	
	$count++;
    }

    $logger->info("$count records done");

    # 4) Alias fuer Index setzen

    if ($alias){
	$logger->info("Setting alias $alias for index $index");

	$result = $es->indices->get_alias( name => $alias );

	foreach my $oldindex (keys %$result){
	    $result = $es->indices->delete_alias(
		name  => $alias,
		index => $oldindex,
		);
	}
	
	$result = $es->indices->put_alias(
	    name  => $alias,
	    index => $index,
	    ) ;
    }
}

sub print_help {
    print << "ENDHELP";
es_ctl.pl - Helper for Elasticsearch

Generel Options:
   -help                 : This info
   --logfile=...         : logfile (default: ./es_ctl.log)
   --loglevel=...        : loglevel (default: INFO)
   --host=...            : host (default: localhost:9200)
   --credential=...      : USER:PASSWORD (default: '')

Export index
   --do=export
   --index=...           : Indexname
   --outputfile=...      : Outputfile

Import index
   --do=import
   --index=...           : Index
   --inputfile=...       : Inputfile
   --alias=...           : set alias for index

e.g:

./es_ctl.pl --credential="foo:bar" --do=export --outputfile=index.json --index=index_a

./es_ctl.pl --credential="foo:bar" --do=import --inputfile=index.json --index=index_b --alias=index

ENDHELP
    exit;
}

