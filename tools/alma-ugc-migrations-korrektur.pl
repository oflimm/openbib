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
use OpenBib::User;

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
my $user        = new OpenBib::User;

my ($usemappingcache,$sourcedatabase,$targetdatabase,$titlefile,$username,$migratelitlists,$migratecartitems,$migratetags,$maxtitles,$dryrun,$help,$logfile,$loglevel);

&GetOptions(
    "migrate-litlists"      => \$migratelitlists,
    "migrate-cartitems"     => \$migratecartitems,
    "migrate-tags"          => \$migratetags,
    "mapping-titlefile=s"   => \$titlefile,
    "username=s"            => \$username,
    "source-database=s"     => \$sourcedatabase,
    "target-database=s"     => \$targetdatabase,
    "max-titles=s"          => \$maxtitles,
    "use-mapping-cache"     => \$usemappingcache,    
    "dry-run"               => \$dryrun,
    "logfile=s"             => \$logfile,
    "loglevel=s"            => \$loglevel,
    "help"                  => \$help
    );

$sourcedatabase=($sourcedatabase)?$sourcedatabase:"inst001"; # oder lehrbuchsmlg, lesesaal
$targetdatabase=($targetdatabase)?$targetdatabase:"uni";

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

my $userid = 0;
my $viewname = "";

if ($username){
    if (!$user->user_exists($username)){
	$logger->error("NO_USER: $username");
	exit;
    }
    
    $userid = $user->get_userid_for_username($username,$viewname);

    $logger->info("userid is $userid for username $username");
}

$logger->info("Bestimmung der Mappings von MMSIDs zu den Katkeys aus Exportdatei");

my %katkey2mmsid = ();

unlink "./alma-ugc-katkey2mmsid.db" unless ($usemappingcache);
        
eval {
    tie %katkey2mmsid,        'MLDBM', "./alma-ugc-katkey2mmsid.db";
};

if ($@){
    $logger->error_die("$@: Could not tie alma-ugc-katkey2mmsid.db");
}


my $target_catalog = OpenBib::Catalog::Factory->create_catalog({ database => $targetdatabase});

unless ($usemappingcache) {
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

}

if ($migratelitlists){
    $logger->info("Literaturlisten-Eintraege korrigieren");

    open(LITLISTPROT,  ">./alma-ugc-prot-litlist.json");
    
    my $where_ref = {
	dbname => $sourcedatabase,
    };

    my $options_ref = {
    };

    if ($userid){
	$where_ref->{'litlistid.userid'} = $userid;
	$options_ref->{'join'} = ['litlistid'];
    }

    if ($maxtitles){
	$options_ref->{'rows'} = $maxtitles;
    }
    
    my $litlist_titles = $config->get_schema->resultset('Litlistitem')->search(
	$where_ref,
	$options_ref
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
		
		$litlist_title->update({ dbname => $targetdatabase, titleid => $target_titleid, titlecache => $record_json, comment => "Migrated from $sourcedatabase:$source_titleid" }) unless ($dryrun);

		my $prot_ref = {
		    id     => $litlist_titleid,
		    userid => $userid,
		    source => {
			titleid => $source_titleid,
			dbname  => $sourcedatabase,
		    },
		    target => {
			titleid => $target_titleid,
			dbname  => $targetdatabase,
		    },
		};

		print LITLISTPROT encode_json $prot_ref,"\n";

	    }
	}
	else {
	    $logger->error("No title found in $targetdatabase for $sourcedatabase:$source_titleid");
	    my $prot_ref = {
		id     => $litlist_titleid,
		userid => $userid,
		source => {
		    titleid => $source_titleid,
		    dbname  => $sourcedatabase,
		},

		no_target_found => 1,
	    };
	    
	    print LITLISTPROT encode_json $prot_ref,"\n";

	}
    }

    close(LITLISTPROT);
}

if ($migratecartitems){
    $logger->info("Merklisten-Eintraege korrigieren");

    open(CARTITEMPROT, ">./alma-ugc-prot-cartitems.json");
    
    my $where_ref = {
	dbname => $sourcedatabase,
    };

    my $options_ref = {
    };
    
    if ($userid){
	$where_ref->{'user_cartitems.userid'} = $userid;
	$options_ref->{'join'} = ['user_cartitems'];
    }

    if ($maxtitles){
	$options_ref->{'rows'} = $maxtitles;
    }
    
    my $cartitem_titles = $config->get_schema->resultset('Cartitem')->search(
	$where_ref,
	$options_ref
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
		
		$cartitem_title->update({ dbname => $targetdatabase, titleid =>  $target_titleid, titlecache => $record_json, comment => "Migrated from $sourcedatabase:$source_titleid" }) unless ($dryrun);

		my $prot_ref = {
		    id     => $cartitem_titleid,
		    userid => $userid,
		    source => {
			titleid => $source_titleid,
			dbname  => $sourcedatabase,
		    },
		    target => {
			titleid => $target_titleid,
			dbname  => $targetdatabase,
		    },
		};

		print CARTITEMPROT encode_json $prot_ref,"\n";

	    }
	}
	else {
	    $logger->error("No title found in $targetdatabase for $sourcedatabase:$source_titleid");
	    
	    my $prot_ref = {
		id     => $cartitem_titleid,
		userid => $userid,
		source => {
		    titleid => $source_titleid,
		    dbname  => $sourcedatabase,
		},
		
		no_target_found => 1,
	    };
	    
	    print CARTITEMPROT encode_json $prot_ref,"\n";
	}
    }

    close(CARTITEMPROT);
}

if ($migratetags){
    $logger->info("Tag-Eintraege korrigieren");

    open(TAGPROT,      ">./alma-ugc-prot-tags.json");
    
    my $where_ref = {
	dbname => $sourcedatabase,
    };
    
    my $options_ref = {
    };

    if ($userid){
	$where_ref->{'userid'} = $userid;
    }

    if ($maxtitles){
	$options_ref->{'rows'} = $maxtitles;
    }
    
    my $tag_titles = $config->get_schema->resultset('TitTag')->search(
	$where_ref,
	$options_ref
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

		my $prot_ref = {
		    id     => $tag_titleid,
		    userid => $userid,
		    source => {
			titleid => $source_titleid,
			dbname  => $sourcedatabase,
		    },
		    target => {
			titleid => $target_titleid,
			dbname  => $targetdatabase,
		    },
		};

		print TAGPROT encode_json $prot_ref,"\n";
		
	    }
	}
	else {
	    $logger->error("No title found in $targetdatabase for $sourcedatabase:$source_titleid");

	    my $prot_ref = {
		id     => $tag_titleid,
		userid => $userid,
		source => {
		    titleid => $source_titleid,
		    dbname  => $sourcedatabase,
		},
		
		no_target_found => 1,
	    };
	    
	    print TAGPROT encode_json $prot_ref,"\n";
	}
    }

    close(TAGPROT);
}


sub print_help {
    print << "ENDHELP";
alma-ugc-migrations-korrektur.pl - Korrektur des User Generated Contents (Literaturlisten, Merklisten, Tags) von Titeln, die aus USB- in den Alma-Katalog migriert wurden

   Optionen:
   -help                   : Diese Informationsseite
   -dry-run                : Testlauf ohne Aenderungen
   --source-database=...   : Ursprungs-Katalog der UGC-Eintraege (default: inst001)
   --target-database=...   : Ziel-Katalog der UGC-Eintraege (default: uni)
   --mapping-titlefile=... : meta.title.gz Datei des Alma-Systems mit Alt-IDs
   --max-titles=...        : Maximal zu konvertierende Titelzahl
   -migrate-litlists       : Literaturlisten migrieren
   -migrate-cartitems      : Merklisten migrieren
   -migrate-tags           : Tags migrieren
   --logfile=...           : Alternatives Logfile

Bsp:

./alma-ugc-migrations-korrektur.pl -dry-run -migrate-litlists --mapping-titlefile=/opt/openbib/autoconv/pools/uni/meta.title.gz

./alma-ugc-migrations-korrektur.pl --username=admin --mapping-titlefile=/store/uni/meta.title.gz -migrate-cartitems -use-mapping-cache

ENDHELP
    exit;
}

