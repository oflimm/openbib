#!/usr/bin/perl

#####################################################################
#
#  ugc-migrations-korrektur.pl
#
#  Korrektur des User Generated Contents (Literaturlisten, Merklisten, Tags)
#  von Titeln, die aus einem Instituts- in den USB-Katalog migriert wurden
#
#  Dieses File ist (C) 2015 Oliver Flimm <flimm@openbib.org>
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

my ($sourcedatabase,$targetdatabase,$masterdatabase,$targetlocation,$migratelitlists,$migratecartitems,$migratetags,$dryrun,$help,$logfile,$loglevel);

&GetOptions("source-database=s"     => \$sourcedatabase,
            "target-database=s"     => \$targetdatabase,
            "target-location=s"     => \$targetlocation,
            "master-database=s"     => \$masterdatabase,
	    "migrate-litlists"      => \$migratelitlists,
	    "migrate-cartitems"     => \$migratecartitems,
	    "migrate-tags"          => \$migratetags,
	    "dry-run"               => \$dryrun,
            "logfile=s"             => \$logfile,
            "loglevel=s"            => \$loglevel,
	    "help"                  => \$help
	    );

if ($help || !$sourcedatabase || !$targetdatabase || !$masterdatabase){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/ugc-migrations-korrektur.log';
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

$logger->info("Bibkeys zu den Titleids von Literaturlisten, Merklisten und Tags");

my $sourcetitle_bibkeys = $enrichmnt->get_schema->resultset('AllTitleByBibkey')->search(
    {
        dbname  => $masterdatabase,
        titleid => { -in => \@source_titleids },
    },
    {
        column       => [ qw/bibkey titleid/ ],
    }
);

my $bibkey_sourcetitle_ref = {};
my $have_bibkey_ref        = {};

while (my $sourcetitle_bibkey = $sourcetitle_bibkeys->next()){
    my $bibkey  = $sourcetitle_bibkey->bibkey;
    my $titleid = $sourcetitle_bibkey->titleid;

    $have_bibkey_ref->{$titleid}       = 1;
    $bibkey_sourcetitle_ref->{$bibkey} = $titleid;

    $logger->debug("Found Bibkey $bibkey in title $titleid");
}

my @source_bibkeys = keys %$bibkey_sourcetitle_ref;

my $source_catalog = OpenBib::Catalog::Factory->create_catalog({ database => $sourcedatabase});

my $remaining_in_source_ref = {};

my $remaining_titleids = $source_catalog->get_schema->resultset('Title')->search(
    {
	id => { -in => \@source_titleids },
    },
    {
	column => [ qw/id/ ],
    }
    );

while (my $remaining_titleid = $remaining_titleids->next()){
    $remaining_in_source_ref->{$remaining_titleid->id} = 1;
}


my @remaining_titleids = ();

foreach my $titleid (@source_titleids){
    # Massgeblich sind die uebriggebliebenen Titel, die a) schon migriert sind (NOT remaining_in_source_ref)
    if (!defined $have_bibkey_ref->{$titleid} && !defined $remaining_in_source_ref->{$titleid}){
        push @remaining_titleids, $titleid;
    }
}


if ($logger->is_debug){
    $logger->debug(($#remaining_titleids+1)." Source Titleids ohne Bibkey: ".YAML::Dump(\@remaining_titleids));
    $logger->info("Source Bibkeys: ".YAML::Dump(\@source_bibkeys));
}

$logger->info("Bibkeys und Titelids in der Zieldatenbank $targetdatabase mit Zielstandort $targetlocation suchen");

my $targettitle_bibkeys = $enrichmnt->get_schema->resultset('AllTitleByBibkey')->search(
    {
        dbname  => $targetdatabase,
        bibkey  => { -in => \@source_bibkeys },
    },
    {
        column       => [ qw/bibkey titleid/ ],
    }
);

my $bibkey_targettitle_ref = {};

while (my $targettitle_bibkey = $targettitle_bibkeys->next()){
    my $target_titleid = $targettitle_bibkey->titleid;

    $logger->debug("Target-Titleid found: $target_titleid");

    my $target_record = OpenBib::Record::Title->new({id => $target_titleid, database => $targetdatabase, config => $config})->load_full_record;

    my $target_location_is_ok = 0;

    if ($logger->is_debug){
	$logger->debug("Target-Holding: ".YAML::Dump($target_record->get_holding));
    }

    foreach my $holding_ref (@{$target_record->get_holding}){
        if ($holding_ref->{X0016}{content} =~m/^$targetlocation/){
            $bibkey_targettitle_ref->{$targettitle_bibkey->bibkey} = $targettitle_bibkey->titleid;
        }
    }
}

my @target_bibkeys = keys %$bibkey_targettitle_ref;

if ($logger->is_debug){
    $logger->info(($#target_bibkeys+1)." Target Bibkeys: ".YAML::Dump(\@target_bibkeys));
}

my $source2target_mapping_ref = {};

foreach my $target_bibkey (@target_bibkeys){
    my $sourceid;
    my $targetid = $bibkey_targettitle_ref->{$target_bibkey};

    if (defined $bibkey_sourcetitle_ref->{$target_bibkey}){
        $sourceid = $bibkey_sourcetitle_ref->{$target_bibkey};
    }

    if ($targetid && $sourceid){
        my $mastertitle = OpenBib::Record::Title->new({id => $sourceid, database => $masterdatabase, config => $config})->load_full_record;
        my $targettitle = OpenBib::Record::Title->new({id => $targetid, database => $targetdatabase, config => $config})->load_full_record;

        $logger->info("Master: ".$mastertitle->get_field({field => 'T0331', mult => 1}));
        $logger->info("Target: ".$targettitle->get_field({field => 'T0331', mult => 1}));

	$source2target_mapping_ref->{$sourceid} = $targetid;
    }
    else {
        push @remaining_titleids, $sourceid;
    }
    
}

# Wenn zu einem source_bibkey kein target_bibkey existiert, dann gehoert die zugehoerige titleid de facto zu den remaining_titleids

foreach my $source_bibkey (@source_bibkeys){
    if (!defined $bibkey_targettitle_ref->{$source_bibkey} && !$bibkey_targettitle_ref->{$source_bibkey}){
        push @remaining_titleids, $bibkey_sourcetitle_ref->{$source_bibkey};
    }
}

if (@remaining_titleids){
    $logger->info("Remaining Titleids: ".$#remaining_titleids);
}
else {
    $logger->info("All Titles found");
}


$logger->info(YAML::Dump($source2target_mapping_ref));

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
