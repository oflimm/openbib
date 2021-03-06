#!/usr/bin/perl

#####################################################################
#
#  ugc-migrations-korrektur-4702.pl
#
#  Korrektur des User Generated Contents (Literaturlisten, Merklisten, Tags)
#  von Titeln, die aus einem Instituts- in den USB-Katalog migriert wurden
#  Grundlage ist hier die Kategorie 4702 in inst001, in die Katalogname
#  und dortige Titelid des Ursprungskatalogs vermerkt werden
#
#  Dieses File ist (C) 2015-2016 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

use Business::ISBN;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use YAML::Syck;

my $config      = OpenBib::Config->new;

my ($sourcedatabase,$masterdatabase,$targetlocation,$migratelitlists,$migratecartitems,$migratetags,$dryrun,$help,$logfile,$loglevel);

&GetOptions("source-database=s"     => \$sourcedatabase,
	    "migrate-litlists"      => \$migratelitlists,
	    "migrate-cartitems"     => \$migratecartitems,
	    "migrate-tags"          => \$migratetags,
	    "dry-run"               => \$dryrun,
            "logfile=s"             => \$logfile,
            "loglevel=s"            => \$loglevel,
	    "help"                  => \$help
	    );

my $targetdatabase="inst001";

if ($help || !$sourcedatabase){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/ugc-migrations-korrektur-4702.log';
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

my $enrichmnt = new OpenBib::Enrichment;

$logger->info("Gezieltes Sammeln von Informationen fuer $sourcedatabase");

$logger->info("Titleids von Literaturlisten, Merklisten und Tags bestimmen");

my $litlist_titles = $config->get_schema->resultset('Litlistitem')->search(
    {
        dbname => $sourcedatabase,
    },
    {
        column       => [ qw/titleid/ ],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

my $cartitem_titles = $config->get_schema->resultset('Cartitem')->search(
    {
        dbname => $sourcedatabase,
    },
    {
        column       => [ qw/titleid/ ],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

my $tag_titles = $config->get_schema->resultset('TitTag')->search(
    {
        dbname => $sourcedatabase,
    },
    {
        column       => [ qw/titleid/ ],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

my %source_titleid_hash = ();

while (my $litlist_title = $litlist_titles->next()){
    $source_titleid_hash{$litlist_title->{titleid}} = 1;
}

while (my $cartitem_title = $cartitem_titles->next()){
    $source_titleid_hash{$cartitem_title->{titleid}} = 1;
}

while (my $tag_title = $tag_titles->next()){
    $source_titleid_hash{$tag_title->{titleid}} = 1;
}

my @source_titleids = keys %source_titleid_hash;

$logger->debug("$#source_titleids Source Titleids: ".YAML::Dump(\@source_titleids));

my $target_catalog = OpenBib::Catalog::Factory->create_catalog({ database => $targetdatabase});

my $migrated_titles = $target_catalog->get_schema->resultset('TitleField')->search(
    {
	field => 4702,
        content => {'~*' => "^$sourcedatabase"},
    },
    {
	column => [ qw/titleid content/ ],
    }
    );

my $source2target_mapping_ref = {};

while (my $migrated_title = $migrated_titles->next()){
    my $targettitleid = $migrated_title->titleid->id;
    my $content       = $migrated_title->content;
    my ($sourcetitleid) = $content =~m/:\s*?(\d+)/;

    if (!defined $sourcetitleid){
	$logger->error("Wrong format: $content");
    }
    
    if (defined $source_titleid_hash{$sourcetitleid}){
	$source2target_mapping_ref->{$sourcetitleid} = $targettitleid;
    }
}

$logger->debug(YAML::Dump($source2target_mapping_ref));

if ($migratelitlists){
    $logger->info("Literaturlisten-Eintraege korrigieren");
    
    $litlist_titles = $config->get_schema->resultset('Litlistitem')->search(
	{
	    dbname => $sourcedatabase,
	},
	);
    
    while (my $litlist_title = $litlist_titles->next()){
	
	my $source_titleid  = $litlist_title->titleid;
	my $litlist_titleid = $litlist_title->id;

	if (defined $source2target_mapping_ref->{$source_titleid} && $source2target_mapping_ref->{$source_titleid}){
	    $logger->info("Changing Litlistitem $litlist_titleid: $sourcedatabase:$source_titleid to $targetdatabase:$source2target_mapping_ref->{$source_titleid}");

	    $litlist_title->update({ dbname => $targetdatabase, titleid => $source2target_mapping_ref->{$source_titleid} }) unless ($dryrun);
	}
    }
}

if ($migratecartitems){
    $logger->info("Merklisten-Eintraege korrigieren");
    
    $cartitem_titles = $config->get_schema->resultset('Cartitem')->search(
	{
	    dbname => $sourcedatabase,
	},
	);
    
    while (my $cartitem_title = $cartitem_titles->next()){
	
	my $source_titleid   = $cartitem_title->titleid;
	my $cartitem_titleid = $cartitem_title->id;

	if (defined $source2target_mapping_ref->{$source_titleid} && $source2target_mapping_ref->{$source_titleid}){
	    $logger->info("Changing Cartitem $cartitem_titleid: $sourcedatabase:$source_titleid to $targetdatabase:$source2target_mapping_ref->{$source_titleid}");

	    $cartitem_title->update({ dbname => $targetdatabase, titleid => $source2target_mapping_ref->{$source_titleid} }) unless ($dryrun);
	}
    }
}

if ($migratetags){
    $logger->info("Tag-Eintraege korrigieren");
	
    my $tag_titles = $config->get_schema->resultset('TitTag')->search(
	{
	    dbname => $sourcedatabase,
	},
	);
    
    while (my $tag_title = $tag_titles->next()){
	
	my $source_titleid  = $tag_title->titleid;
	my $tag_titleid     = $tag_title->id;

	if (defined $source2target_mapping_ref->{$source_titleid} && $source2target_mapping_ref->{$source_titleid}){
	    $logger->info("Changing Tagsitem $tag_titleid: $sourcedatabase:$source_titleid to $targetdatabase:$source2target_mapping_ref->{$source_titleid}");
	    
	    $tag_title->update({ dbname => $targetdatabase, titleid => $source2target_mapping_ref->{$source_titleid} }) unless ($dryrun);
	}
    }
}
