#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2016 Oliver Flimm <flimm@openbib.org>
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

use 5.008001;
use utf8;
use strict;
use warnings;

use Benchmark ':hireswallclock';
use Business::ISBN;
use DB_File;
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8/;
use Getopt::Long;
use JSON::XS;
use Lingua::Identify::CLD;
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use DBM_Filter;
use Storable ();

use OpenBib::Catalog::Factory;
use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Container;
use OpenBib::Conv::Config;
use OpenBib::Index::Document;
use OpenBib::Record::Classification;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Person;
use OpenBib::Record::Subject;
use OpenBib::Record::Title;
use OpenBib::Statistics;
use OpenBib::Importer::JSON::Person;
use OpenBib::Importer::JSON::CorporateBody;
use OpenBib::Importer::JSON::Classification;
use OpenBib::Importer::JSON::Subject;
use OpenBib::Importer::JSON::Holding;
use OpenBib::Importer::JSON::Title;
use OpenBib::Normalizer;

my %char_replacements = (
    
    # Zeichenersetzungen
    "\n"     => "<br\/>",
    "\r"     => "\\r",
    ""     => "",
#    "\x{00}" => "",
#    "\x{80}" => "",
#    "\x{87}" => "",
);

my $chars_to_replace = join '|',
    keys %char_replacements;

$chars_to_replace = qr/$chars_to_replace/;

my ($database,$reducemem,$scheme,$addsuperpers,$addmediatype,$addlanguage,$incremental,$keepfiles,$logfile,$loglevel,$count,$help);

&GetOptions(
    "reduce-mem"     => \$reducemem,
    "add-superpers"  => \$addsuperpers,
    "add-mediatype"  => \$addmediatype,
    "add-language"   => \$addlanguage,
    "keep-files"     => \$keepfiles,
    "incremental"    => \$incremental,
    "database=s"     => \$database,
    "scheme=s"       => \$scheme,
    "logfile=s"      => \$logfile,
    "loglevel=s"     => \$loglevel,
    "help"           => \$help,
);

if ($help) {
    print_help();
}

my $config      = OpenBib::Config->new;
my $conv_config = OpenBib::Conv::Config->instance({dbname => $database});

$logfile=($logfile)?$logfile:"/var/log/openbib/meta2sql/${database}.log";
$loglevel=($loglevel)?$loglevel:"INFO";

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

if (!-d "/var/log/openbib/meta2sql/"){
    mkdir "/var/log/openbib/meta2sql/";
}

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $dir=`pwd`;
chop $dir;

my %listitemdata_person         = ();
my %listitemdata_corporatebody  = ();
my %listitemdata_classification = ();
my %listitemdata_subject        = ();
my %listitemdata_holding        = ();
my %listitemdata_superid        = ();
my %listitemdata_popularity     = ();
my %listitemdata_tags           = ();
my %listitemdata_litlists       = ();
my %listitemdata_enriched_years = ();
my %enrichmntdata               = ();
my %indexed_person              = ();
my %indexed_corporatebody       = ();
my %indexed_subject             = ();
my %indexed_classification      = ();
my %indexed_holding             = ();
my %titleid_exists             = ();

if ($reducemem) {
    $logger->info("### $database: Reducing memory usage");
    my $db_indexed_person = tie %indexed_person,        'MLDBM', "./indexed_person.db"
        or die "Could not tie indexed_person.\n";

    $db_indexed_person->{DB}->Filter_Push('utf8');
    
    my $db_indexed_corporatebody = tie %indexed_corporatebody,        'MLDBM', "./indexed_corporatebody.db"
        or die "Could not tie indexed_corporatebody.\n";

    $db_indexed_corporatebody->{DB}->Filter_Push('utf8');
    
    my $db_indexed_subject = tie %indexed_subject,        'MLDBM', "./indexed_subject.db"
        or die "Could not tie indexed_subject.\n";

    $db_indexed_subject->{DB}->Filter_Push('utf8');
    
    my $db_indexed_classification = tie %indexed_classification,        'MLDBM', "./indexed_classification.db"
        or die "Could not tie indexed_classification.\n";

    $db_indexed_classification->{DB}->Filter_Push('utf8');
    
    my $db_indexed_holding = tie %indexed_holding,        'MLDBM', "./indexed_holding.db"
        or die "Could not tie indexed_holding.\n";

    $db_indexed_holding->{DB}->Filter_Push('utf8');
    
    my $db_listitemdata_person = tie %listitemdata_person,        'MLDBM', "./listitemdata_person.db"
        or die "Could not tie listitemdata_person.\n";

    $db_listitemdata_person->{DB}->Filter_Push('utf8');
    
    my $db_listitemdata_corporatebody = tie %listitemdata_corporatebody,        'MLDBM', "./listitemdata_corporatebody.db"
        or die "Could not tie listitemdata_corporatebody.\n";

    $db_listitemdata_corporatebody->{DB}->Filter_Push('utf8');
    
    my $db_listitemdata_classification = tie %listitemdata_classification,        'MLDBM', "./listitemdata_classification.db"
        or die "Could not tie listitemdata_classification.\n";

    $db_listitemdata_classification->{DB}->Filter_Push('utf8');
    
    my $db_listitemdata_subject = tie %listitemdata_subject,        'MLDBM', "./listitemdata_subject.db"
        or die "Could not tie listitemdata_subject.\n";

    $db_listitemdata_subject->{DB}->Filter_Push('utf8');
    
    my $db_listitemdata_holding = tie %listitemdata_holding,        'MLDBM', "./listitemdata_holding.db"
        or die "Could not tie listitemdata_holding.\n";

    $db_listitemdata_holding->{DB}->Filter_Push('utf8');
    
    #    tie %listitemdata_popularity,        'MLDBM', "./listitemdata_popularity.db"
    #        or die "Could not tie listitemdata_popularity.\n";

    #    tie %listitemdata_tags,           'MLDBM', "./listitemdata_tags.db"
    #        or die "Could not tie listitemdata_tags.\n";
    
    #    tie %listitemdata_litlists,        'MLDBM', "./listitemdata_litlists.db"
    #        or die "Could not tie listitemdata_litlists.\n";

    my $db_listitemdata_enriched_years = tie %listitemdata_enriched_years,      'MLDBM', "./listitemdata_enriched_years.db"
        or die "Could not tie listitemdata_enriched_years.\n";

    $db_listitemdata_enriched_years->{DB}->Filter_Push('utf8');
    
    my $db_listitemdata_superid = tie %listitemdata_superid,    "MLDBM", "./listitemdata_superid.db"
        or die "Could not tie listitemdata_superid.\n";

    $db_listitemdata_superid->{DB}->Filter_Push('utf8');
    
    my $db_titleid_exists = tie %titleid_exists,    "MLDBM", "./titleid_exists.db"
        or die "Could not tie titleid_exists.\n";

    $db_titleid_exists->{DB}->Filter_Push('utf8');
}

if ($scheme){
    $logger->info("### $database: Using scheme $scheme");
}

$scheme = (defined $scheme)?$scheme:'mab2';

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
    or $logger->error($DBI::errstr);

$logger->info("### $database: Popularitaet fuer Titel dieses Kataloges bestimmen");

# Popularitaet
my $request=$statisticsdbh->prepare("select titleid, count(titleid) as idcount from titleusage where origin=1 and dbname=? group by titleid");
$request->execute($database);

while (my $res    = $request->fetchrow_hashref) {
    my $id      = $res->{titleid};
    my $idcount = $res->{idcount};
    $listitemdata_popularity{$id}=$idcount;
}
$request->finish();

# Verbindung zur SQL-Datenbank herstellen
my $userdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
    or $logger->error($DBI::errstr);

$logger->info("### $database: Tags fuer Titel dieses Kataloges bestimmen");

# Tags
$request=$userdbh->prepare("select t.name, tt.titleid, t.id from tag as t, tit_tag as tt where tt.dbname=? and tt.tagid=t.id and tt.type=1");
$request->execute($database);

while (my $res    = $request->fetchrow_hashref) {
    my $titleid   = $res->{titleid};
    my $tag     = $res->{name};
    my $id      = $res->{id};
    push @{$listitemdata_tags{$titleid}}, { tag => $tag, id => $id };
}
$request->finish();

$logger->info("### $database: Literaturlisten fuer Titel dieses Kataloges bestimmen");

# Titel von Literaturlisten
$request=$userdbh->prepare("select l.title, i.titleid, l.id from litlist as l, litlistitem as i where i.dbname=? and i.litlistid=l.id and l.type=1");
$request->execute($database);

while (my $res    = $request->fetchrow_hashref) {
    my $titleid   = $res->{titleid};
    my $title   = $res->{title};
    my $id      = $res->{id};
    push @{$listitemdata_litlists{$titleid}}, { title => $title, id => $id };
}
$request->finish();

my $local_enrichmnt  = 0;
my $enrichmntdumpdir = $config->{autoconv_dir}."/data/enrichment";

if (exists $conv_config->{local_enrichmnt} && -e "$enrichmntdumpdir/enrichmntdata.db") {
    tie %enrichmntdata,           'MLDBM', "$enrichmntdumpdir/enrichmntdata.db"
        or die "Could not tie enrichment data.\n";

    $local_enrichmnt = 1;

    $logger->info("### $database: Lokale Einspielung mit zentralen Anreicherungsdaten aktiviert");
}

my $stammdateien_ref = {
    person => {
        infile             => "meta.person.gz",
        outfile            => "person.dump.gz",
        deletefile         => "person.delete",
        outfile_fields     => "person_fields.dump.gz",
        class              => "OpenBib::Importer::JSON::Person",
        type               => "Person",
    },

    corporatebody => {
        infile             => "meta.corporatebody.gz",
        outfile            => "corporatebody.dump.gz",
        deletefile         => "corporatebody.delete",
        outfile_fields     => "corporatebody_fields.dump.gz",
        class              => "OpenBib::Importer::JSON::CorporateBody",
        type               => "Corporatebody",
    },
    
    subject => {
        infile             => "meta.subject.gz",
        outfile            => "subject.dump.gz",
        deletefile         => "subjects.delete",
        outfile_fields     => "subject_fields.dump.gz",
        class              => "OpenBib::Importer::JSON::Subject",
        type               => "Subject",
    },
    
    classification => {
        infile             => "meta.classification.gz",
        outfile            => "classification.dump.gz",
        deletefile         => "classification.delete",
        outfile_fields     => "classification_fields.dump.gz",
        class              => "OpenBib::Importer::JSON::Classification",
        type               => "Classification",
    },
};

my $atime;

my $storage_ref = {
    'listitemdata_person'         => \%listitemdata_person,
    'listitemdata_corporatebody'  => \%listitemdata_corporatebody,
    'listitemdata_classification' => \%listitemdata_classification,
    'listitemdata_subject'        => \%listitemdata_subject,
    'listitemdata_holding'        => \%listitemdata_holding,
    'listitemdata_superid'        => \%listitemdata_superid,
    'listitemdata_popularity'     => \%listitemdata_popularity,
    'listitemdata_tags'           => \%listitemdata_tags,
    'listitemdata_litlists'       => \%listitemdata_litlists,
    'listitemdata_enriched_years' => \%listitemdata_enriched_years,
    'enrichmntdata'               => \%enrichmntdata,
    'indexed_person'              => \%indexed_person,
    'indexed_corporatebody'       => \%indexed_corporatebody,
    'indexed_subject'             => \%indexed_subject,
    'indexed_classification'      => \%indexed_classification,
    'indexed_holding'             => \%indexed_holding,
    'titleid_exists'              => \%titleid_exists,
};

my $normalizer = OpenBib::Normalizer->new;

my $actions_map_ref = {};

foreach my $type (keys %{$stammdateien_ref}) {
    if (-f $stammdateien_ref->{$type}{infile}){
        $atime = new Benchmark;

        $count = 1;

        my %incremental_status_map      = ();
        $actions_map_ref             = {};
        
        if ($incremental){
            # Einlesen der neuen Daten aus kompletter Einladedatei und der alten Daten aus der Datenbank.

            my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database });

            foreach my $result_ref ($catalog->get_schema->resultset($stammdateien_ref->{$type}{type})->search(
                {},{ select => ['id','import_hash'], result_class => 'DBIx::Class::ResultClass::HashRefInflator',})->all){
                $incremental_status_map{$result_ref->{id}}{old} = $result_ref->{import_hash};
            }
            
            open(IN , "zcat ".$stammdateien_ref->{$type}{infile}." | " )        || die "IN konnte nicht geoeffnet werden: $!";

	    binmode (IN, ":raw");
		;
            my $record_ref;
            
            while (my $jsonline = <IN>){
                my $import_hash = md5_hex($jsonline);
                
                eval {
                    $record_ref = decode_json $jsonline;
                };
                
                if ($@){
                    $logger->error("Skipping record: $@");
                    return;
                }

                my $id = $record_ref->{id};
                $incremental_status_map{$id}{new} = $import_hash;
            }
            
            close(IN);

            $actions_map_ref = analyze_status_map(\%incremental_status_map);

            open(OUTDELETE,           ">:utf8",$stammdateien_ref->{$type}{deletefile})        || die "OUTDELETE konnte nicht geoeffnet werden: $!";            

            foreach my $id (keys %$actions_map_ref){
                print OUTDELETE "$id\n" if ($actions_map_ref->{$id} eq "delete" || $actions_map_ref->{$id} eq "change"); 
            }
            
            close(OUTDELETE);
            
            if ($logger->is_info){
                $logger->info("$stammdateien_ref->{$type}{type}".YAML::Dump($actions_map_ref)."\n");
            }
        }

        
        $logger->info("### $database: Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}");
        
        open(IN , "zcat ".$stammdateien_ref->{$type}{infile}." | " )        || die "IN konnte nicht geoeffnet werden: $!";

	binmode(IN,":raw");
	
        open(OUT,           "| gzip > ".$stammdateien_ref->{$type}{outfile})        || die "OUT konnte nicht geoeffnet werden: $!";	
        open(OUTFIELDS,     "| gzip > ".$stammdateien_ref->{$type}{outfile_fields}) || die "OUTFIELDS konnte nicht geoeffnet werden: $!";

	binmode(OUT,":utf8");
	binmode(OUTFIELDS,":utf8");
	
        my $class = $stammdateien_ref->{$type}{class};
        
        my $importer = $class->new({
            storage         => $storage_ref,
            database        => $database,
	    scheme          => $scheme,
	    normalizer      => $normalizer,
        });
        
        while (my $jsonline=<IN>){

            # Kurz-Check bei inkrementellen Updates kann hier nicht angewendet werden, weil auch storage_ref fuer die Titel-Verarbeitung mit
            # allen Normdateninformationen gefuellt werden muss!!!
            
            eval {
                $importer->process({
                    json         => $jsonline
                });
            };
            
            if ($@){
                $logger->error($@," - $jsonline\n");
                next ;
            }
            
            my $columns_ref                = $importer->get_columns;
            my $columns_fields_ref         = $importer->get_columns_fields;

            if ($incremental && (!defined $actions_map_ref->{$importer->get_id} || $actions_map_ref->{$importer->get_id} eq "delete")){
                $columns_ref                = [];
                $columns_fields_ref         = [];
            }
            
            foreach my $this_column_ref (@$columns_ref){
                print OUT join('',@$this_column_ref),"\n";
            }
            
            foreach my $this_column_fields_ref (@$columns_fields_ref){
                print OUTFIELDS join('',@$this_column_fields_ref),"\n";
            }
            
            if ($count % 1000 == 0) {
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                $atime      = new Benchmark;
                $logger->info("### $database: 1000 ($count) Saetze in $resulttime mit $class bearbeitet");
            } 
            
            $count++;
        }
        
        close(OUT);
        close(OUTFIELDS);
        
        close(IN);
        
        unlink $stammdateien_ref->{$type}{infile} unless ($keepfiles);

        $storage_ref = $importer->get_storage;
    }
    else {
        $logger->error("### $database: $stammdateien_ref->{$type}{infile} nicht vorhanden!");
    }
}

#######################

$stammdateien_ref->{holding} = {
    infile             => "meta.holding.gz",
    outfile            => "holding.dump.gz",
    deletefile         => "holding.delete",
    outfile_fields     => "holding_fields.dump.gz",
    outfile_titleholding => "title_holding.dump.gz",
    inverted_ref       => $conv_config->{inverted_holding},
    type               => "Holding",
};

if (-f $stammdateien_ref->{holding}{infile}){
    $logger->info("### $database: Bearbeite meta.holding");

    open(IN , "zcat ".$stammdateien_ref->{'holding'}{'infile'}." | ")               || die "IN konnte nicht geoeffnet werden: $!";

    binmode (IN, ":raw");

    open(OUT,                   "| gzip > ".$stammdateien_ref->{holding}{outfile})               || die "OUT konnte nicht geoeffnet werden: $!";
    open(OUTFIELDS,             "| gzip > ".$stammdateien_ref->{holding}{outfile_fields})        || die "OUTFIELDS konnte nicht geoeffnet werden: $!";
    open(OUTTITLEHOLDING,       "| gzip > ".$stammdateien_ref->{holding}{outfile_titleholding})         || die "OUTTITLEHOLDING konnte nicht geoeffnet werden: $!";

    binmode(OUT,":utf8");
    binmode(OUTFIELDS,":utf8");
    binmode (OUTTITLEHOLDING,":utf8");
    
    my $atime = new Benchmark;
    
    $count = 1;
    
    my %incremental_status_map      = ();
    
    my $importer = OpenBib::Importer::JSON::Holding->new({
        storage         => $storage_ref,
        database        => $database,
	scheme          => $scheme,
	normalizer      => $normalizer,
    });
    
    while (my $jsonline=<IN>) {
        
        eval {
            $importer->process({
                json         => $jsonline
            });
        };
        
        if ($@){
            $logger->error($@," - $jsonline\n");
            next ;
        }
        
        my $columns_ref                = $importer->get_columns;
        my $columns_fields_ref         = $importer->get_columns_fields;
        my $columns_title_holding_ref  = $importer->get_columns_title_holding;

        foreach my $this_column_ref (@$columns_ref){
            print OUT join('',@$this_column_ref),"\n";
        }
        
        foreach my $this_column_fields_ref (@$columns_fields_ref){
            print OUTFIELDS join('',@$this_column_fields_ref),"\n";
        }
        
        foreach my $this_column_title_holding_ref (@$columns_title_holding_ref){
            print OUTTITLEHOLDING join('',@$this_column_title_holding_ref),"\n";
        }
        
        
        if ($count % 1000 == 0) {
            my $btime      = new Benchmark;
            my $timeall    = timediff($btime,$atime);
            my $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
            $atime      = new Benchmark;
            $logger->info("### $database: 1000 ($count) Exemplarsaetze in $resulttime bearbeitet");
        }
        $count++;
    }

    close(OUT);
    close(OUTFIELDS);
    close(OUTTITLEHOLDING);
    close(IN);

    unlink $stammdateien_ref->{'holding'}{infile} unless ($keepfiles);

    $storage_ref = $importer->get_storage;

} else {
    $logger->error("### $database: meta.holding nicht vorhanden!");
}

open(OUTTITLETITLE,          "| gzip > title_title.dump.gz")           || die "OUTTITLETITLE konnte nicht geoeffnet werden: $!";
open(OUTTITLEPERSON,         "| gzip > title_person.dump.gz")          || die "OUTTITLEPERSON konnte nicht geoeffnet werden: $!";
open(OUTTITLECORPORATEBODY,  "| gzip > title_corporatebody.dump.gz")   || die "OUTTITLECORPORATEBODY konnte nicht geoeffnet werden: $!";
open(OUTTITLESUBJECT,        "| gzip > title_subject.dump.gz")         || die "OUTTITLESUBJECT konnte nicht geoeffnet werden: $!";
open(OUTTITLECLASSIFICATION, "| gzip > title_classification.dump.gz")  || die "OUTTITLECLASSIFICATION konnte nicht geoeffnet werden: $!";

binmode(OUTTITLETITLE,":utf8");
binmode(OUTTITLEPERSON,":utf8");
binmode(OUTTITLECORPORATEBODY,":utf8");
binmode(OUTTITLESUBJECT,":utf8");
binmode(OUTTITLECLASSIFICATION,":utf8");

$stammdateien_ref->{title} = {
    infile             => "meta.title.gz",
    outfile            => "title.dump.gz",
    deletefile         => "title.delete",
    insertfile         => "title.insert",
    outfile_fields     => "title_fields.dump.gz",
    inverted_ref       => $conv_config->{inverted_title},
    blacklist_ref      => $conv_config->{blacklist_title},
    type               => "Title",
};

if ($addsuperpers) {
    $logger->info("### $database: Option addsuperpers ist aktiviert");
    $logger->info("### $database: 1. Durchgang: Uebergeordnete Titel-ID's finden");
    open(IN , "zcat ".$stammdateien_ref->{'title'}{'infile'}." | ") || die "IN konnte nicht geoeffnet werden: $!";

    binmode (IN, ":raw");

    $count = 1;

    while (my $jsonline=<IN>) {
        my $record_ref ;

        eval {
            $record_ref = decode_json $jsonline;
        };

        if ($@){
            $logger->error("Skipping record: $@");
            next;
        }

        my $titleid = $record_ref->{id};

	$storage_ref->{titleid_exists}{$titleid} = 1;

	if ($scheme eq "marc"){
	    if (exists $record_ref->{fields}{'0773'}){
		foreach my $item (@{$record_ref->{fields}{'0773'}}){
		    if ($item->{subfield} eq "w"){
			my $superid = $item->{content};
			$storage_ref->{listitemdata_superid}{$superid}={};
		    }
		}
	    }
	    
	    if (exists $record_ref->{fields}{'0830'}){
		foreach my $item (@{$record_ref->{fields}{'0830'}}){
		    if ($item->{subfield} eq "w"){
			my $superid = $item->{content};
			$storage_ref->{listitemdata_superid}{$superid}={};
		    }
		}
	    }
	}
	else {
	    if (exists $record_ref->{fields}{'0004'}){
		foreach my $item (@{$record_ref->{fields}{'0004'}}){
		    my $superid = $item->{content};
		    $storage_ref->{listitemdata_superid}{$superid}={};
		}
	    }
	}

       if ($count % 100000 == 0){
            $logger->info("### $database: 100000 ($count) Titel");
        }

        $count++;
    }
    close(IN);
    
    $logger->info("### $database: 2. Durchgang: Informationen in uebergeordneten Titeln finden und merken");
    open(IN , "zcat ".$stammdateien_ref->{'title'}{'infile'}." | " ) || die "IN konnte nicht geoeffnet werden: $!";

    binmode (IN, ":raw");

    $count = 1;

    while (my $jsonline=<IN>) {
        my $record_ref ;
        
        eval {
            $record_ref = decode_json $jsonline;
        };

        if ($@){
            $logger->error("Skipping record: $@");
            next;
        }

        my $id = $record_ref->{id};
	
        next unless (defined $storage_ref->{listitemdata_superid}{$id} && ref  $storage_ref->{listitemdata_superid}{$id} eq "HASH");

	unless ($scheme eq "marc"){
	    # Anreichern mit content;
	    foreach my $field ('0100','0101','0102','0103','1800','4308') {
		if (defined $record_ref->{fields}{$field}) {
		    foreach my $item_ref (@{$record_ref->{fields}{$field}}) {
			my $personid   = $item_ref->{id} || '';
			
			if ($personid && exists $storage_ref->{listitemdata_person}{$personid}) {
			    $item_ref->{content} = $storage_ref->{listitemdata_person}{$personid};
			}
			else {
			    $logger->error("PER ID $personid doesn't exist in TITLE ID $id");
			}
		    }
		}
	    }
	}
	
        $storage_ref->{listitemdata_superid}{$id} = $record_ref;

       if ($count % 100000 == 0){
            $logger->info("### $database: 100000 ($count) Titel");
        }

        $count++;	
    }

    close(IN);
}

$logger->info("### $database: Bearbeite ".$stammdateien_ref->{'title'}{'infile'});
system("ls -l");
open(IN , "zcat ".$stammdateien_ref->{'title'}{'infile'}." | " )     || die "IN ".$stammdateien_ref->{'title'}{'infile'}." konnte nicht geoeffnet werden: $!";

binmode (IN, ":raw");

open(OUT,           "| gzip > title.dump.gz"         )     || die "OUT konnte nicht geoeffnet werden: $!";
open(OUTFIELDS,     "| gzip > title_fields.dump.gz"  )     || die "OUTFIELDS konnte nicht geoeffnet werden: $!";
open(SEARCHENGINE,  "| gzip > searchengine.json.gz"  )     || die "SEARCHENGINE konnte nicht goeffnet werden: $!";

binmode (OUT, ":utf8");
binmode (OUTFIELDS, ":utf8");
binmode (SEARCHENGINE, ":raw");

my $locationid = $config->get_locationid_of_database($database);

$count = 1;

$atime = new Benchmark;

my %incremental_status_map      = ();

if ($incremental){
    # Einlesen der neuen Daten aus kompletter Einladedatei und der alten Daten aus der Datenbank.
    
    my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database });
    
    foreach my $result_ref ($catalog->get_schema->resultset('Title')->search(
        {},{ select => ['id','import_hash'], result_class => 'DBIx::Class::ResultClass::HashRefInflator',})->all){
        $incremental_status_map{$result_ref->{id}}{old} = $result_ref->{import_hash};
    }
    
    open(INHASH , "zcat ".$stammdateien_ref->{'title'}{infile}." | " )        || die "IN konnte nicht geoeffnet werden: $!";

    binmode (INHASH, ":raw");
    
    my $record_ref;
    
    while (my $jsonline = <INHASH>){
        my $import_hash = md5_hex($jsonline);
        
        eval {
            $record_ref = decode_json $jsonline;
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            return;
        }
        
        my $id = $record_ref->{id};
        $incremental_status_map{$id}{new} = $import_hash;
    }
    
    close(INHASH);
    
    $actions_map_ref = analyze_status_map(\%incremental_status_map);

    open(OUTDELETE,           ">:utf8",$stammdateien_ref->{'title'}{deletefile})        || die "OUTDELETE konnte nicht geoeffnet werden: $!";            
    open(OUTINSERT,           ">:utf8",$stammdateien_ref->{'title'}{insertfile})        || die "OUTINSERT konnte nicht geoeffnet werden: $!";            
    
    foreach my $id (keys %$actions_map_ref){
        print OUTDELETE "$id\n" if ($actions_map_ref->{$id} eq "delete" || $actions_map_ref->{$id} eq "change");
        print OUTINSERT "$id\n" if ($actions_map_ref->{$id} eq "new" || $actions_map_ref->{$id} eq "change"); 
    }
    
    close(OUTDELETE);
    close(OUTINSERT);
    
    if ($logger->is_info){
        $logger->info("$stammdateien_ref->{'title'}{type}".YAML::Dump($actions_map_ref)."\n");
    }
}

my $importer = OpenBib::Importer::JSON::Title->new({
    database        => $database,
    addsuperpers    => $addsuperpers,
    addlanguage     => $addlanguage,
    addmediatype    => $addmediatype,
    local_enrichmnt => $local_enrichmnt,
    storage         => $storage_ref,
    scheme          => $scheme,
    normalizer      => $normalizer,
});

while (my $jsonline=<IN>){

    # Kurz-Check bei inkrementellen Updates
    if ($incremental){
        my $skip_record = 0;
        
        eval {
            my $record_ref = decode_json $jsonline;
            $skip_record = 1 if (!defined $actions_map_ref->{$record_ref->{id}} || $actions_map_ref->{$record_ref->{id}} eq "delete");
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            next;
        }
        
        next if ($skip_record);
    }
    
    eval {
        $importer->process({
            json         => $jsonline
        });
    };

    if ($@){
	$logger->error($@," - $jsonline\n");
	next ;
    }

    my $columns_title_title_ref          = $importer->get_columns_title_title;
    my $columns_title_person_ref         = $importer->get_columns_title_person;
    my $columns_title_corporatebody_ref  = $importer->get_columns_title_corporatebody;
    my $columns_title_classification_ref = $importer->get_columns_title_classification;
    my $columns_title_subject_ref        = $importer->get_columns_title_subject;
    my $columns_title_ref                = $importer->get_columns_title;
    my $columns_title_fields_ref         = $importer->get_columns_title_fields;
    
    foreach my $title_title_ref (@$columns_title_title_ref){
       print OUTTITLETITLE join('',@$title_title_ref),"\n";
    }

    foreach my $title_person_ref (@$columns_title_person_ref){
       print OUTTITLEPERSON join('',@$title_person_ref),"\n";
    }

    foreach my $title_corporatebody_ref (@$columns_title_corporatebody_ref){
       print OUTTITLECORPORATEBODY join('',@$title_corporatebody_ref),"\n";
    }

    foreach my $title_classification_ref (@$columns_title_classification_ref){
       print OUTTITLECLASSIFICATION join('',@$title_classification_ref),"\n";
    }
    foreach my $title_subject_ref (@$columns_title_subject_ref){
        print OUTTITLESUBJECT join('',@$title_subject_ref),"\n";
    }
    
    foreach my $title_ref (@$columns_title_ref){
       print OUT join('',@$title_ref),"\n";
   }

    foreach my $title_fields_ref (@$columns_title_fields_ref){
       print OUTFIELDS join('',@$title_fields_ref),"\n";
    }
    
    my $searchengine = $importer->get_index_document->to_json;

    if ($incremental){
        if (defined $actions_map_ref->{$importer->get_id} && ($actions_map_ref->{$importer->get_id} eq "new" || $actions_map_ref->{$importer->get_id} eq "change")){
            print SEARCHENGINE "$searchengine\n";
        }
    }
    else {
        print SEARCHENGINE "$searchengine\n";
    }
    
    if ($count % 1000 == 0) {
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $atime      = new Benchmark;
        $logger->info("### $database: 1000 ($count) Titelsaetze in $resulttime bearbeitet");
    } 

    $count++;
}

unlink $stammdateien_ref->{title}{infile} unless ($keepfiles);

$logger->info("### $database: $count Titelsaetze bearbeitet");
$logger->info("### $database: $importer->{stats_enriched_language} Titelsaetze mit Sprachcode angereichert");

close(OUT);
close(OUTFIELDS);
close(SEARCHENGINE);

close(IN);


#######################


open(CONTROL,        ">control.sql");
open(CONTROLINDEXOFF,">control_index_off.sql");
open(CONTROLINDEXON, ">control_index_on.sql");


# Index und Contstraints werden zentral via pool_drop_index.sql geloescht

# Zunaechst Loeschentabellen anlegen

if ($incremental){
    foreach my $type ('person','corporatebody','classification','subject','title'){
        print CONTROL << "DELETETABLE";
DROP TABLE IF EXISTS ${type}_delete;
CREATE TABLE ${type}_delete ( id TEXT );
COPY ${type}_delete FROM '$dir/$stammdateien_ref->{$type}{deletefile}' WITH DELIMITER '' NULL AS '';
DELETETABLE
    }

    print CONTROL << "DELETEITEM";
ALTER TABLE title_title DISABLE TRIGGER ALL;
ALTER TABLE title_person DISABLE TRIGGER ALL;
ALTER TABLE title_corporatebody DISABLE TRIGGER ALL;
ALTER TABLE title_classification DISABLE TRIGGER ALL;
ALTER TABLE title_subject DISABLE TRIGGER ALL;
ALTER TABLE title_holding DISABLE TRIGGER ALL;
ALTER TABLE title DISABLE TRIGGER ALL;
ALTER TABLE title_fields DISABLE TRIGGER ALL;
ALTER TABLE person DISABLE TRIGGER ALL;
ALTER TABLE person_fields DISABLE TRIGGER ALL;
ALTER TABLE corporatebody DISABLE TRIGGER ALL;
ALTER TABLE corporatebody_fields DISABLE TRIGGER ALL;
ALTER TABLE classification DISABLE TRIGGER ALL;
ALTER TABLE classification_fields DISABLE TRIGGER ALL;
ALTER TABLE subject DISABLE TRIGGER ALL;
ALTER TABLE subject_fields DISABLE TRIGGER ALL;
ALTER TABLE holding DISABLE TRIGGER ALL;
ALTER TABLE holding_fields DISABLE TRIGGER ALL;

TRUNCATE TABLE title_holding;

DROP TABLE IF EXISTS person_tmp;
CREATE TABLE person_tmp (
 id            TEXT default nextval('person_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
);

DROP TABLE IF EXISTS person_fields_tmp;
CREATE TABLE person_fields_tmp (
 id            BIGSERIAL,
 personid      TEXT        NOT NULL,
 field         SMALLINT    NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT        NOT NULL
);

DROP TABLE IF EXISTS corporatebody_tmp;
CREATE TABLE corporatebody_tmp (
 id            TEXT default nextval('corporatebody_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
);

DROP TABLE IF EXISTS corporatebody_fields_tmp;
CREATE TABLE corporatebody_fields_tmp (
 id               BIGSERIAL,
 corporatebodyid  TEXT        NOT NULL,
 field            SMALLINT    NOT NULL,
 mult             SMALLINT,
 subfield         VARCHAR(2),
 content          TEXT        NOT NULL
);

DROP TABLE IF EXISTS subject_tmp;
CREATE TABLE subject_tmp (
 id            TEXT default nextval('subject_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
);

DROP TABLE IF EXISTS subject_fields_tmp;
CREATE TABLE subject_fields_tmp (
 id            BIGSERIAL,
 subjectid     TEXT       NOT NULL,
 field         SMALLINT   NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT       NOT NULL
);

DROP TABLE IF EXISTS classification_tmp;
CREATE TABLE classification_tmp (
 id            TEXT default nextval('classification_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
);

DROP TABLE IF EXISTS classification_fields_tmp;
CREATE TABLE classification_fields_tmp (
 id                BIGSERIAL,
 classificationid  TEXT        NOT NULL,
 field             SMALLINT    NOT NULL,
 mult              SMALLINT,
 subfield          VARCHAR(2),
 content           TEXT        NOT NULL
);

DROP TABLE IF EXISTS title_tmp;
CREATE TABLE title_tmp (
 id            TEXT default nextval('title_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 titlecache    TEXT,
 popularity    INT,
 import_hash   TEXT    
);

DROP TABLE IF EXISTS title_fields_tmp;
CREATE TABLE title_fields_tmp (
 id            BIGSERIAL,
 titleid       TEXT NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

DELETE FROM title_title WHERE source_titleid IN (select id from title_delete);
DELETE FROM title_person WHERE titleid IN (select id from title_delete);
DELETE FROM title_corporatebody WHERE titleid IN (select id from title_delete);
DELETE FROM title_classification WHERE titleid IN (select id from title_delete);
DELETE FROM title_subject WHERE titleid IN (select id from title_delete);
DELETEITEM
}
    
foreach my $type ('person','corporatebody','classification','subject','title','holding'){
    if (!$incremental){
        print CONTROL << "ITEMTRUNC";
TRUNCATE TABLE $type;
TRUNCATE TABLE ${type}_fields;
ITEMTRUNC
    }
    
    if ($incremental && $type ne "holding"){
        print CONTROL << "DELETEITEM";
DELETE FROM ${type}_fields WHERE ${type}id IN (select id from ${type}_delete);
DELETE FROM $type WHERE id IN (select id from ${type}_delete);
COPY ${type}_tmp FROM PROGRAM 'zcat $dir/$stammdateien_ref->{$type}{outfile}' WITH DELIMITER '' NULL AS '';
COPY ${type}_fields_tmp FROM PROGRAM 'zcat $dir/$stammdateien_ref->{$type}{outfile_fields}' WITH DELIMITER '' NULL AS '';
DELETEITEM
        if ($type eq "title"){
            print CONTROL << "INSERTITEM";
INSERT INTO $type (id,tstamp_create,tstamp_update,titlecache,popularity,import_hash) select id,tstamp_create,tstamp_update,titlecache,popularity,import_hash from ${type}_tmp; 
INSERT INTO ${type}_fields (${type}id,field,mult,subfield,content) select ${type}id,field,mult,subfield,content from ${type}_fields_tmp; 
INSERTITEM
        }
        else {
            print CONTROL << "INSERTITEM";
INSERT INTO $type (id,tstamp_create,tstamp_update,import_hash) select id,tstamp_create,tstamp_update,import_hash from ${type}_tmp; 
INSERT INTO ${type}_fields (${type}id,field,mult,subfield,content) select ${type}id,field,mult,subfield,content from ${type}_fields_tmp; 
INSERTITEM
        }
        
    }
    elsif (!$incremental) {
        print CONTROL << "ITEM";
COPY $type FROM PROGRAM 'zcat $dir/$stammdateien_ref->{$type}{outfile}' WITH DELIMITER '' NULL AS '';
COPY ${type}_fields FROM PROGRAM 'zcat $dir/$stammdateien_ref->{$type}{outfile_fields}' WITH DELIMITER '' NULL AS '';
ITEM
    }
}

    if (!$incremental){            
print CONTROL << "TITLEITEMTRUNC";
TRUNCATE TABLE title_title;
TRUNCATE TABLE title_person;
TRUNCATE TABLE title_corporatebody;
TRUNCATE TABLE title_subject;
TRUNCATE TABLE title_classification;
TITLEITEMTRUNC
}

if ($incremental){
    print CONTROL << "TITLEITEMINC";
TRUNCATE TABLE holding, holding_fields cascade;

COPY holding FROM PROGRAM 'zcat $dir/$stammdateien_ref->{'holding'}{outfile}' WITH DELIMITER '' NULL AS '';
COPY holding_fields FROM PROGRAM 'zcat $dir/$stammdateien_ref->{'holding'}{outfile_fields}' WITH DELIMITER '' NULL AS '';

DROP TABLE IF EXISTS title_title_tmp;
CREATE TABLE title_title_tmp (
id                BIGSERIAL,
field             SMALLINT,
mult              SMALLINT,
source_titleid    TEXT     NOT NULL,
target_titleid    TEXT     NOT NULL,
supplement        TEXT
);

DROP TABLE IF EXISTS title_person_tmp;
CREATE TABLE title_person_tmp (
id         BIGSERIAL,
field      SMALLINT,
mult       SMALLINT,
titleid    TEXT         NOT NULL,
personid   TEXT          NOT NULL,
supplement TEXT
);

DROP TABLE IF EXISTS title_corporatebody_tmp;
CREATE TABLE title_corporatebody_tmp (
id                BIGSERIAL,
field             SMALLINT,
mult       SMALLINT,
titleid           TEXT NOT NULL,
corporatebodyid   TEXT NOT NULL,
supplement        TEXT
);

DROP TABLE IF EXISTS title_subject_tmp;
CREATE TABLE title_subject_tmp (
id         BIGSERIAL,
field      SMALLINT,
mult       SMALLINT,
titleid    TEXT NOT NULL,
subjectid  TEXT NOT NULL,
supplement TEXT
);

DROP TABLE IF EXISTS title_classification_tmp;
CREATE TABLE title_classification_tmp (
id                BIGSERIAL,
field             SMALLINT,
mult       SMALLINT,
titleid           TEXT NOT NULL,
classificationid  TEXT NOT NULL,
supplement        TEXT
);

COPY title_title_tmp FROM PROGRAM 'zcat $dir/title_title.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_person_tmp FROM PROGRAM 'zcat $dir/title_person.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_corporatebody_tmp FROM PROGRAM 'zcat $dir/title_corporatebody.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_subject_tmp FROM PROGRAM 'zcat $dir/title_subject.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_classification_tmp FROM PROGRAM 'zcat $dir/title_classification.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_holding FROM PROGRAM 'zcat $dir/title_holding.dump.gz' WITH DELIMITER '' NULL AS '';

INSERT INTO title_title (field,mult,source_titleid,target_titleid,supplement) select field,mult,source_titleid,target_titleid,supplement from title_title_tmp; 
INSERT INTO title_person (field,mult,titleid,personid,supplement) select field,mult,titleid,personid,supplement from title_person_tmp; 
INSERT INTO title_corporatebody (field,mult,titleid,corporatebodyid,supplement) select field,mult,titleid,corporatebodyid,supplement from title_corporatebody_tmp; 
INSERT INTO title_classification (field,mult,titleid,classificationid,supplement) select field,mult,titleid,classificationid,supplement from title_classification_tmp; 
INSERT INTO title_subject (field,mult,titleid,subjectid,supplement) select field,mult,titleid,subjectid,supplement from title_subject_tmp; 

ALTER TABLE title_title ENABLE TRIGGER ALL;
ALTER TABLE title_person ENABLE TRIGGER ALL;
ALTER TABLE title_corporatebody ENABLE TRIGGER ALL;
ALTER TABLE title_classification ENABLE TRIGGER ALL;
ALTER TABLE title_subject ENABLE TRIGGER ALL;
ALTER TABLE title_holding ENABLE TRIGGER ALL;
ALTER TABLE title ENABLE TRIGGER ALL;
ALTER TABLE title_fields ENABLE TRIGGER ALL;
ALTER TABLE person ENABLE TRIGGER ALL;
ALTER TABLE person_fields ENABLE TRIGGER ALL;
ALTER TABLE corporatebody ENABLE TRIGGER ALL;
ALTER TABLE corporatebody_fields ENABLE TRIGGER ALL;
ALTER TABLE classification ENABLE TRIGGER ALL;
ALTER TABLE classification_fields ENABLE TRIGGER ALL;
ALTER TABLE subject ENABLE TRIGGER ALL;
ALTER TABLE subject_fields ENABLE TRIGGER ALL;
ALTER TABLE holding ENABLE TRIGGER ALL;
ALTER TABLE holding_fields ENABLE TRIGGER ALL;

DROP TABLE IF EXISTS title_title_tmp;
DROP TABLE IF EXISTS title_person_tmp;
DROP TABLE IF EXISTS title_corporatebody_tmp;
DROP TABLE IF EXISTS title_subject_tmp;
DROP TABLE IF EXISTS title_classification_tmp;

DROP TABLE IF EXISTS person_fields_tmp;
DROP TABLE IF EXISTS corporatebody_fields_tmp;
DROP TABLE IF EXISTS subject_fields_tmp;
DROP TABLE IF EXISTS classification_fields_tmp;
DROP TABLE IF EXISTS title_fields_tmp;

DROP TABLE IF EXISTS person_delete;
DROP TABLE IF EXISTS corporatebody_delete;
DROP TABLE IF EXISTS classification_delete;
DROP TABLE IF EXISTS subject_delete;
DROP TABLE IF EXISTS title_delete;
TITLEITEMINC
}
else {
    print CONTROL << "TITLEITEM";
COPY title_title FROM PROGRAM 'zcat $dir/title_title.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_person FROM PROGRAM 'zcat $dir/title_person.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_corporatebody FROM PROGRAM 'zcat $dir/title_corporatebody.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_subject FROM PROGRAM 'zcat $dir/title_subject.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_classification FROM PROGRAM 'zcat $dir/title_classification.dump.gz' WITH DELIMITER '' NULL AS '';
COPY title_holding FROM PROGRAM 'zcat $dir/title_holding.dump.gz' WITH DELIMITER '' NULL AS '';
TITLEITEM
}

# Index und Contstraints werden zentral via pool_create_index.sql eingerichtet

close(CONTROL);
close(CONTROLINDEXOFF);
close(CONTROLINDEXON);

# if ($reducemem){
#     untie %listitemdata_person;
#     untie %listitemdata_corporatebody;
#     untie %listitemdata_classification;
#     untie %listitemdata_subject;
#     untie %listitemdata_holding;
#     untie %listitemdata_superid;
# }


sub analyze_status_map {
   my $status_map_ref = shift;

   my $actions_map_ref = {};

   foreach my $id (keys %$status_map_ref){
       # Title deleted?
       if (!defined $status_map_ref->{$id}{new} && defined $status_map_ref->{$id}{old}){
           $actions_map_ref->{$id} = "delete";
       }
       # Title new?
       elsif (defined $status_map_ref->{$id}{new} && !defined $status_map_ref->{$id}{old}){
           $actions_map_ref->{$id} = "new";
       }
       # Title changed?
       elsif (defined $status_map_ref->{$id}{new} && defined $status_map_ref->{$id}{old}){
           if ($status_map_ref->{$id}{new} ne $status_map_ref->{$id}{old}){
               $actions_map_ref->{$id} = "change";
           }
       }
   }    

   return $actions_map_ref;
}

sub print_help {
    print << "ENDHELP";
meta2sql.pl - Migration der Metadaten in Einladedateien fuer eine SQL-Datenbank 
              und einen Suchmaschinenindex
   Optionen:
   -help                 : Diese Informationsseite
       
   -add-superpers        : Anreicherung mit Personen der Ueberordnung (Schiller-Raeuber)
   -add-mediatype        : Anreicherung mit Medientyp durch Kategorieanalyse
   -add-persondate       : Anreicherung mit Lebensjahren bei Personen fuer Facetten/Filter
   -reduce-mem           : Optimierter Speicherverbrauch durch Auslagerung in DB-Dateien
   --database=...        : Angegebenen Datenpool verwenden
   --logfile=...         : Logfile inkl Pfad.
   --loglevel=...        : Loglevel

ENDHELP
    exit;
}

1;

__END__

=head1 NAME

 meta2sql.pl - Generierung von SQL-Einladedateien aus dem Meta-Format

=head1 DESCRIPTION

 Mit dem Programm meta2sql.pl werden Daten, die im MAB2-orientierten
 Meta-Format vorliegen, in Einlade-Dateien fuer das MySQL-Datenbank-
 system umgewandelt. Bei dieser Umwandlung kann durch geeignete
 Aenderung in diesem Programm lenkend eingegriffen werden.

=head1 SYNOPSIS

 In $stammdateien_ref werden die verschiedenen Normdatentypen, ihre
 zugehoerigen Namen der Ein- und Ausgabe-Dateien, sowie die zu
 invertierenden Kategorien.

 Folgende Normdatentypen existieren:

 Titel                 (title)          -> numerische Typentsprechung: 1
 Verfasser/Person      (person)         -> numerische Typentsprechung: 2
 Koerperschaft/Urheber (corporatebody)  -> numerische Typentsprechung: 3
 Schlagwort            (subject)        -> numerische Typentsprechung: 4
 Notation/Systematik   (classification) -> numerische Typentsprechung: 5
 Exemplardaten         (holding)        -> numerische Typentsprechung: 6


 Die numerische Entsprechung wird bei der Verknuepfung einzelner Saetze
 zwischen den Normdaten in der Tabelle conn verwendet.

 Der Speicherverbrauch kann ueber die Option -reduce-mem durch
 Auslagerung der fuer den Aufbau der Kurztitel-Tabelle benoetigten
 Informationen reduziert werden.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
