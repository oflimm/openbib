#!/usr/bin/perl

#####################################################################
#
#  alma-ugc-migrations-korrektur.pl
#
#  Korrektur des User Generated Contents (Literaturlisten, Merklisten, Tags)
#  von Titeln, die aus USB- in den Alma-Katalog migriert wurden
#
#  basiert auf ugc-migrations-korrektur.pl aus 2015
#
#  Dieses File ist (C) 2023 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Catalog::Factory;
use OpenBib::Record::Title;

use Business::ISBN;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode 'decode_utf8';
use IO::File;
use IO::Uncompress::Gunzip;
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DB_File;
use JSON::XS;
use MLDBM qw(DB_File Storable);
use Storable ();
use Getopt::Long;
use YAML::Syck;

my $config      = OpenBib::Config->new;

my ($sourcedatabase,$targetdatabase,$titlefile,$migratelitlists,$migratecartitems,$migratetags,$dryrun,$help,$logfile,$loglevel);

&GetOptions(
    "migrate-litlists"      => \$migratelitlists,
    "migrate-cartitems"     => \$migratecartitems,
    "migrate-tags"          => \$migratetags,
    "target-titlefile=s"    => \$titlefile,
    
    "dry-run"               => \$dryrun,
    "logfile=s"             => \$logfile,
    "loglevel=s"            => \$loglevel,
    "help"                  => \$help
    );

$sourcedatabase="inst001";
$targetdatabase="uni";

if ($help){
    print_help();
}

unless ($migratelitlists || $migratecartitems || $migratetags){
    print_help();
}
    
$logfile=($logfile)?$logfile:'/var/log/openbib/alma-ugc-migrations-korrektur.log';
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

$logger->info("Bestimmung der Mappings von MMSIDs zu den Katkeys");

my %katkey2mmsid = ();

my $target_catalog = OpenBib::Catalog::Factory->create_catalog({ database => $targetdatabase});


my $input_io;

if ($titlefile){
    if ($titlefile =~/\.gz$/){
        $input_io = IO::Uncompress::Gunzip->new($titlefile);
    }
    else {
        $input_io = IO::File->new($titlefile);
    }
}

my $idx     = 1;
my $idx_all = 0;
while (my $jsonline = <$input_io>){
    my $record_ref = decode_json($jsonline);

    my $mmsid = $record_ref->{id};
    
    my $fields_ref = $record_ref->{fields};

    if (defined $fields_ref->{'0981'}){
	foreach my $item_ref (@{$fields_ref->{'0981'}}){
	    if ($item_ref->{subfield} eq "a"){
		my $katkey = $item_ref->{content};
		
		$logger->debug("$katkey -> $mmsid");

		next unless ($katkey =~m/\(DE-38\)/);
		$katkey=~s/\(DE-38\)//;
		
		$logger->debug("Post $katkey -> $mmsid");
		
		$katkey2mmsid{$katkey} = $mmsid;
    
		if ($idx % 10000 == 0){
		    $logger->info("$idx mappings processed");
		}
		
		$idx++;
	    }
	}
    }

    $idx_all++;
}

close $input_io;

$logger->info("$idx_all records processed");
$logger->info(($idx - 1)." mappings found");

# unlink "./katkey2mmsid.db";
        
# eval {
#     tie %katkey2mmsid,        'MLDBM', "./katkey2mmsid.db";
# };

# if ($@){
#     $logger->error_die("$@: Could not tie ./katkey2mmsid.db.db");
# }

# my $titlemmsids = $target_catalog->get_schema->resultset('TitleField')->search(
#     {
# 	field => 981,
# 	subfield => 'a',
#     },
#     {
# 	select => [ 'titleid', 'content' ],
# 	as     => [ 'mmsid', 'katkey' ],
# 	result_class => 'DBIx::Class::ResultClass::HashRefInflator',
#     }
#     );

# my $idx = 1;
# while (my $thistitle = $titlemmsids->next()){
#     my $katkey = $thistitle->{katkey};
#     my $mmsid  = $thistitle->{mmsid};

#     $logger->info("$katkey -> $mmsid");
    
#     if ($idx % 10000 == 0){
# 	$logger->info("$idx processed");
#     }
    
#     next unless ($katkey =~m/\(DE-38\)/);
#     $katkey=~s/\(DE-38\)//;

#     $logger->info("Post $katkey -> $mmsid");
    
#     $katkey2mmsid{$katkey} = $mmsid;
#     $idx++;
# }


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

	my $target_titleid = (defined $katkey2mmsid{$source_titleid} && $katkey2mmsid{$source_titleid})?$katkey2mmsid{$source_titleid}:0;

	if ($target_titleid){
	    $logger->info("Changing Litlistitem $litlist_titleid: $sourcedatabase:$source_titleid to $targetdatabase:$target_titleid");
	    
	    my $record = new OpenBib::Record::Title({ database => $targetdatabase , id => $target_titleid, config => $config })->load_full_record;
	    
	    if ($record->record_exists){
		
		my $record_json = $record->to_json;
		
		$litlist_title->update({ dbname => $targetdatabase, titleid => $target_titleid }) unless ($dryrun);
	    }
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

	my $target_titleid = (defined $katkey2mmsid{$source_titleid} && $katkey2mmsid{$source_titleid})?$katkey2mmsid{$source_titleid}:0;
	
	if ($target_titleid){
	    $logger->info("Changing Cartitem $cartitem_titleid: $sourcedatabase:$source_titleid to $targetdatabase:$target_titleid");
	    
	    my $record = new OpenBib::Record::Title({ database => $targetdatabase , id => $target_titleid, config => $config })->load_full_record;
	    
	    if ($record->record_exists){
		
		my $record_json = $record->to_json;
		
		$cartitem_title->update({ dbname => $targetdatabase, titleid =>  $target_titleid, titlecache => $record_json }) unless ($dryrun);
	    }
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

	my $target_titleid = (defined $katkey2mmsid{$source_titleid} && $katkey2mmsid{$source_titleid})?$katkey2mmsid{$source_titleid}:0;
	
	if ($target_titleid){
	    $logger->info("Changing Tagsitem $tag_titleid: $sourcedatabase:$source_titleid to $targetdatabase:$target_titleid");
	    
	    my $record = new OpenBib::Record::Title({ database => $targetdatabase , id => $target_titleid, config => $config })->load_full_record;
	    
	    if ($record->record_exists){
		
		my $record_json = $record->to_json;
		
		$tag_title->update({ dbname => $targetdatabase, titleid => $target_titleid, titlecache => $record_json }) unless ($dryrun);
	    }
	}
    }
}

sub print_help {
    print << "ENDHELP";
alma-ugc-migrations-korrektur.pl - Korrektur des User Generated Contents (Literaturlisten, Merklisten, Tags) von Titeln, die aus USB- in den Alma-Katalog migriert wurden

   Optionen:
   -help                 : Diese Informationsseite
   -dry-run              : Testlauf ohne Aenderungen
   -target-titlefile     : meta.title.gz Datei des Alma-Systems
   -migrate-litlists     : Literaturlisten migrieren
   -migrate-cartitems    : Merklisten migrieren
   -migrate-tags         : Tags migrieren
   --logfile=...         : Alternatives Logfile
   --type=...            : Metrik-Typ

Bsp:

./alma-ugc-migrations-korrektur.pl -dry-run -migrate-litlists --target-titlefile=/opt/openbib/autoconv/pools/uni/meta.title.gz

ENDHELP
    exit;
}

