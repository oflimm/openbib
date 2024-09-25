#!/usr/bin/perl

use OpenBib::SearchQuery;
use OpenBib::API::HTTP::JOP;

use Log::Log4perl qw(get_logger :levels);
use YAML;

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=ERROR, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=./joptest.log
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

my $query = new OpenBib::SearchQuery;

#$query->set_searchfield('issn','2160-3308'); # Electronic only
$query->set_searchfield('issn','1536-6065'); # Print and Electronic
$query->set_searchfield('genre','journal');

my $api = OpenBib::API::HTTP::JOP->new({ bibid => USBK, searchquery => $query });

my $search = $api->search();

my $hits   = $search->get_resultcount;
my $result = $search->get_search_resultlist;

print "$hits items found\n";

foreach my $record (@{$result->to_list}){
    print YAML::Dump($record->to_hash);
}

