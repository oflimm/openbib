#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2013 Oliver Flimm <flimm@openbib.org>
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
use Encode qw/decode_utf8/;
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Index::Document;
use OpenBib::Record::Classification;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Person;
use OpenBib::Record::Subject;
use OpenBib::Record::Title;
use OpenBib::Statistics;

my %char_replacements = (
    
    # Zeichenersetzungen
    "\n"     => "<br\/>",
    "\\"     => "\\\\",
    "\r"     => "\\r",
    ""     => "",
    "\x{00}" => "",
);

my $chars_to_replace = join '|',
    keys %char_replacements;

$chars_to_replace = qr/$chars_to_replace/;

my ($database,$reducemem,$addsuperpers,$addmediatype,$incremental,$logfile,$loglevel,$count,$help);

&GetOptions(
    "reduce-mem"     => \$reducemem,
    "add-superpers"  => \$addsuperpers,
    "add-mediatype"  => \$addmediatype,
    "incremental"    => \$incremental,
    "database=s"     => \$database,
    "logfile=s"      => \$logfile,
    "loglevel=s"     => \$loglevel,
    "help"           => \$help,
);

if ($help) {
    print_help();
}

my $config      = OpenBib::Config->instance;
my $conv_config = new OpenBib::Conv::Config({dbname => $database});

$logfile=($logfile)?$logfile:"/var/log/openbib/meta2sql-$database.log";
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

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $dir=`pwd`;
chop $dir;

my %listitemdata_person         = ();
my %listitemdata_person_date    = ();
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

if ($reducemem) {
    tie %indexed_person,        'MLDBM', "./indexed_person.db"
        or die "Could not tie indexed_person.\n";

    tie %indexed_corporatebody,        'MLDBM', "./indexed_corporatebody.db"
        or die "Could not tie indexed_corporatebody.\n";

    tie %indexed_subject,        'MLDBM', "./indexed_subject.db"
        or die "Could not tie indexed_subject.\n";

    tie %indexed_classification,        'MLDBM', "./indexed_classification.db"
        or die "Could not tie indexed_classification.\n";

    tie %indexed_holding,        'MLDBM', "./indexed_holding.db"
        or die "Could not tie indexed_holding.\n";

    tie %listitemdata_person,        'MLDBM', "./listitemdata_person.db"
        or die "Could not tie listitemdata_person.\n";

    tie %listitemdata_corporatebody,        'MLDBM', "./listitemdata_corporatebody.db"
        or die "Could not tie listitemdata_corporatebody.\n";

    tie %listitemdata_classification,        'MLDBM', "./listitemdata_classification.db"
        or die "Could not tie listitemdata_classification.\n";
 
    tie %listitemdata_subject,        'MLDBM', "./listitemdata_subject.db"
        or die "Could not tie listitemdata_subject.\n";

    tie %listitemdata_holding,        'MLDBM', "./listitemdata_holding.db"
        or die "Could not tie listitemdata_holding.\n";

    #    tie %listitemdata_popularity,        'MLDBM', "./listitemdata_popularity.db"
    #        or die "Could not tie listitemdata_popularity.\n";

    #    tie %listitemdata_tags,           'MLDBM', "./listitemdata_tags.db"
    #        or die "Could not tie listitemdata_tags.\n";
    
    #    tie %listitemdata_litlists,        'MLDBM', "./listitemdata_litlists.db"
    #        or die "Could not tie listitemdata_litlists.\n";

    tie %listitemdata_enriched_years,      'MLDBM', "./listitemdata_enriched_years.db"
        or die "Could not tie listitemdata_enriched_years.\n";

    tie %listitemdata_superid,    "MLDBM", "./listitemdata_superid.db"
        or die "Could not tie listitemdata_superid.\n";
}

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
    or $logger->error($DBI::errstr);

$logger->info("### $database: Popularitaet fuer Titel dieses Kataloges bestimmen");

# Popularitaet
my $request=$statisticsdbh->prepare("select id, count(id) as idcount from titleusage where origin=1 and dbname=? group by id");
$request->execute($database);

while (my $res    = $request->fetchrow_hashref) {
    my $id      = $res->{id};
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
        type               => "person",
        infile             => "meta.person",
        outfile            => "person.dump",
        outfile_fields     => "person_fields.dump",
        inverted_ref       => $conv_config->{inverted_person},
        blacklist_ref      => $conv_config->{blacklist_person},
    },
    
    corporatebody => {
        infile             => "meta.corporatebody",
        outfile            => "corporatebody.dump",
        outfile_fields     => "corporatebody_fields.dump",
        inverted_ref       => $conv_config->{inverted_corporatebody},
        blacklist_ref      => $conv_config->{blacklist_corporatebody},
    },
    
    subject => {
        infile             => "meta.subject",
        outfile            => "subject.dump",
        outfile_fields     => "subject_fields.dump",
        inverted_ref       => $conv_config->{inverted_subject},
        blacklist_ref      => $conv_config->{blacklist_subject},
    },
    
    classification => {
        infile             => "meta.classification",
        outfile            => "classification.dump",
        outfile_fields     => "classification_fields.dump",
        inverted_ref       => $conv_config->{inverted_classification},
        blacklist_ref      => $conv_config->{blacklist_classification},
    },
};

foreach my $type (keys %{$stammdateien_ref}) {
    $logger->info("### $database: Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}");
    
    open(IN ,           "<:raw",$stammdateien_ref->{$type}{infile} )        || die "IN konnte nicht geoeffnet werden";
    open(OUT,           ">:utf8",$stammdateien_ref->{$type}{outfile})        || die "OUT konnte nicht geoeffnet werden";
    open(OUTFIELDS,     ">:utf8",$stammdateien_ref->{$type}{outfile_fields})     || die "OUTFIELDS konnte nicht geoeffnet werden";

    my ($category,$mult,$content);

    my $serialid = 1;
    
    while (my $jsonline=<IN>){

        my $record_ref = decode_json $jsonline;

        my $id         = $record_ref->{id};
        my $fields_ref = $record_ref->{fields};
        
        # Primaeren Normdatensatz erstellen und schreiben
        
        my $create_tstamp = "1970-01-01 12:00:00";
        
        if (defined $fields_ref->{'0002'} && defined $fields_ref->{'0002'}[0]) {
            $create_tstamp = $fields_ref->{'0002'}[0]{content};
            if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
                $create_tstamp=$3."-".$2."-".$1." 12:00:00";
            }
        }
        
        my $update_tstamp = "1970-01-01 12:00:00";
        
        if (exists $fields_ref->{'0003'} && exists $fields_ref->{'0003'}[0]) {
            $update_tstamp = $fields_ref->{'0003'}[0]{content};
            if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
                $update_tstamp=$3."-".$2."-".$1." 12:00:00";
            }            
        }
        
        print OUT "$id$create_tstamp$update_tstamp\n";

        # Ansetzungsformen fuer Kurztitelliste merken
        
        my $mainentry;
        
        if (exists $fields_ref->{'0800'} && exists $fields_ref->{'0800'}[0] ) {
            $mainentry = $fields_ref->{'0800'}[0]{content};
        }
        
        if ($mainentry) {
            if ($type eq "person") {
                $listitemdata_person{$id}=$mainentry;
            }
            elsif ($type eq "corporatebody") {
                $listitemdata_corporatebody{$id}=$mainentry;
            }
            elsif ($type eq "classification") {
                $listitemdata_classification{$id}=$mainentry;
            }
            elsif ($type eq "subject") {
                if (defined $fields_ref->{'0800'}[1]){
                    # Schlagwortketten zusammensetzen
                    my @mainentries = ();
                    foreach my $item (map { $_->[0] }
                                          sort { $a->[1] <=> $b->[1] }
                                              map { [$_, $_->{mult}] } @{$fields_ref->{'0800'}}){
                        push @mainentries, $item->{content};
                        $mainentry = join (' / ',@mainentries);
                    }

                    $fields_ref->{'0800'} = [
                        {
                            content  => $mainentry,
                            mult     => 1,
                            subfield => '',
                        }
                    ];
                }
                $listitemdata_subject{$id}=$mainentry;
            }
        }

        foreach my $field (keys %{$fields_ref}) {
            next if ($field eq "id" || defined $stammdateien_ref->{$type}{blacklist_ref}->{$field} );
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                if (exists $stammdateien_ref->{$type}{inverted_ref}{$field}->{index}) {
                    foreach my $searchfield (keys %{$stammdateien_ref->{$type}{inverted_ref}{$field}->{index}}) {
                        my $weight = $stammdateien_ref->{$type}{inverted_ref}{$field}->{index}{$searchfield};
                        
                        if ($type eq "person"){
                            my $hash_ref = {};
                            if (exists $indexed_person{$id}){
                                $hash_ref = $indexed_person{$id};
                            }
                            push @{$hash_ref->{$searchfield}{$weight}}, ["P$field",$item_ref->{content}];
                            
                            $indexed_person{$id} = $hash_ref;
                        }
                        elsif ($type eq "corporatebody"){
                            my $hash_ref = {};
                            if (exists $indexed_corporatebody{$id}){
                                $hash_ref = $indexed_corporatebody{$id};
                            }
                            push @{$hash_ref->{$searchfield}{$weight}}, ["C$field",$item_ref->{content}];
                            
                            $indexed_corporatebody{$id} = $hash_ref;
                        }
                        elsif ($type eq "subject"){
                            my $hash_ref = {};
                            if (exists $indexed_subject{$id}){
                                $hash_ref = $indexed_subject{$id};
                            }
                            push @{$hash_ref->{$searchfield}{$weight}}, ["S$field",$item_ref->{content}];
                            
                            $indexed_subject{$id} = $hash_ref;
                        }
                        elsif ($type eq "classification"){
                            my $hash_ref = {};
                            if (exists $indexed_classification{$id}){
                                $hash_ref = $indexed_classification{$id};
                            }                        
                            push @{$hash_ref->{$searchfield}{$weight}}, ["N$field",$item_ref->{content}];
                            
                            $indexed_classification{$id} = $hash_ref;
                        }
                    }
                }
                
                if ($id && $field && $item_ref->{content}){
                    $item_ref->{content} = cleanup_content($item_ref->{content});
                    # Abhaengige Feldspezifische Saetze erstellen und schreiben
                    print OUTFIELDS "$serialid$id$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
                    $serialid++;
                }
            }
        }
        
    }

    close(OUT);
    close(OUTFIELDS);

    close(IN);

    unlink $stammdateien_ref->{$type}{infile};
}

#######################

$stammdateien_ref->{holding} = {
    infile             => "meta.holding",
    outfile            => "holding.dump",
    outfile_fields     => "holding_fields.dump",
    inverted_ref       => $conv_config->{inverted_holding},
};

$logger->info("### $database: Bearbeite meta.holding");

open(IN ,                   "<:raw","meta.holding")               || die "IN konnte nicht geoeffnet werden";
open(OUT,                   ">:utf8","holding.dump")               || die "OUT konnte nicht geoeffnet werden";
open(OUTFIELDS,             ">:utf8","holding_fields.dump")        || die "OUTFIELDS konnte nicht geoeffnet werden";
open(OUTTITLETITLE,         ">:utf8","title_title.dump")           || die "OUTTITLETITLE konnte nicht geoeffnet werden";
open(OUTTITLEHOLDING,       ">:utf8","title_holding.dump")         || die "OUTTITLEHOLDING konnte nicht geoeffnet werden";
open(OUTTITLEPERSON,        ">:utf8","title_person.dump")          || die "OUTTITLEPERSON konnte nicht geoeffnet werden";
open(OUTTITLECORPORATEBODY, ">:utf8","title_corporatebody.dump")   || die "OUTTITLECORPORATEBODY konnte nicht geoeffnet werden";
open(OUTTITLESUBJECT,       ">:utf8","title_subject.dump")         || die "OUTTITLESUBJECT konnte nicht geoeffnet werden";
open(OUTTITLECLASSIFICATION,">:utf8","title_classification.dump")  || die "OUTTITLECLASSIFICATION konnte nicht geoeffnet werden";

my $id;
my ($category,$mult,$content);

$count = 1;

my $atime = new Benchmark;

my $titleid;
my $thisyear = `date +"%Y"`;

my $serialid = 1;

my $title_person_serialid = 1;
my $title_corporatebody_serialid = 1;
my $title_subject_serialid = 1;
my $title_classification_serialid = 1;
my $title_holding_serialid = 1;
my $title_title_serialid = 1;

while (my $jsonline=<IN>){

    my $record_ref = decode_json $jsonline;

    my $id         = $record_ref->{id};
    my $fields_ref = $record_ref->{fields};
    
    # Primaeren Normdatensatz erstellen und schreiben
    
    print OUT "$id\n";
    
    # Titelid bestimmen
    
    my $titleid;

    if (exists $fields_ref->{'0004'} && exists $fields_ref->{'0004'}[0] ) {
        $titleid = $fields_ref->{'0004'}[0]{content};
    }
    
    # Verknupefungen
    if ($titleid && $id) {
        print OUTTITLEHOLDING "$title_holding_serialid$titleid$id\n";
        $title_holding_serialid++;
    }
    
    foreach my $field (keys %{$fields_ref}) {
        next if ($field eq "id" || defined $stammdateien_ref->{holding}{blacklist_ref}{$field} );
        
        foreach my $item_ref (@{$fields_ref->{$field}}) {
            next unless ($item_ref->{content});
            
            if (exists $stammdateien_ref->{holding}{inverted_ref}{$field}->{index}) {
                foreach my $searchfield (keys %{$stammdateien_ref->{holding}{inverted_ref}{$field}->{index}}) {
                    my $weight = $stammdateien_ref->{holding}{inverted_ref}{$field}->{index}{$searchfield};
                    
                    my $hash_ref = {};
                    if (defined $indexed_holding{$titleid}){
                        $hash_ref = $indexed_holding{$titleid};
                    }
                    
                    push @{$hash_ref->{$searchfield}{$weight}}, ["X$field",$item_ref->{content}];
                    
                    $indexed_holding{$titleid} = $hash_ref;
                }
            }
            
            if ($id && $field && $item_ref->{content}){
                $item_ref->{content} = cleanup_content($item_ref->{content});
                # Abhaengige Feldspezifische Saetze erstellen und schreiben        
                print OUTFIELDS "$serialid$id$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
                $serialid++;
            }
        }
    }
        
    # Signatur fuer Kurztitelliste merken
    
    if (exists $fields_ref->{'0014'} && $titleid) {
        my $array_ref= [];
        if (exists $listitemdata_holding{$titleid}){
            $array_ref = $listitemdata_holding{$titleid};
        }
        push @$array_ref, $fields_ref->{'0014'}[0]{content};
        $listitemdata_holding{$titleid}=$array_ref;
    }
    
    # Bestandsverlauf in Jahreszahlen umwandeln
    if ((defined $fields_ref->{'1204'}) && $titleid) {        
        my $array_ref=[];
        if (exists $listitemdata_enriched_years{$titleid}){
            $array_ref = $listitemdata_enriched_years{$titleid};
        }
        
        foreach my $date (split(";",cleanup_content($fields_ref->{'1204'}[0]{content}))) {
            if ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-\s+.*?(\d\d\d\d)/) {
                my $startyear = $1;
                my $endyear   = $2;
                
                $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                for (my $year=$startyear;$year<=$endyear; $year++) {
                    $logger->debug("Adding year $year");
                    push @$array_ref, $year;
                }
            }
            elsif ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-/) {
                my $startyear = $1;
                my $endyear   = $thisyear;
                $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                for (my $year=$startyear;$year<=$endyear;$year++) {
                    $logger->debug("Adding year $year");
                    push @$array_ref, $year;
                }                
            }
            elsif ($date =~/(\d\d\d\d)/) {
                $logger->debug("Not expanding $date, just adding year $1");
                push @$array_ref, $1;
            }
        }

        $listitemdata_enriched_years{$titleid}=$array_ref;
    }
    
    if ($count % 1000 == 0) {
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $atime      = new Benchmark;
        $logger->info("### $database: $count Exemplarsaetze in $resulttime bearbeitet");
    }
    $count++;
}

close(OUT);
close(OUTFIELDS);
close(IN);

unlink "meta.holding";

$stammdateien_ref->{title} = {
    infile             => "meta.title",
    outfile            => "title.dump",
    outfile_fields     => "title_fields.dump",
    inverted_ref       => $conv_config->{inverted_title},
    blacklist_ref      => $conv_config->{blacklist_title},
};

if ($addsuperpers) {
    $logger->info("### $database: Option addsuperpers ist aktiviert");
    $logger->info("### $database: 1. Durchgang: Uebergeordnete Titel-ID's finden");
    open(IN ,           "<:raw","meta.title"          ) || die "IN konnte nicht geoeffnet werden";

    $count = 1;

    while (my $jsonline=<IN>) {
        my $record_ref = decode_json $jsonline;
        
        if (exists $record_ref->{fields}{'0004'}){
            foreach my $item (@{$record_ref->{fields}{'0004'}}){
                my $superid = $item->{content};
                $listitemdata_superid{$superid}={};
            }
        }

       if ($count % 100000 == 0){
            $logger->info("### $database: $count Titel");
        }

        $count++;
    }
    close(IN);
    
    $logger->info("### $database: 2. Durchgang: Informationen in uebergeordneten Titeln finden und merken");
    open(IN ,           "<:raw","meta.title"          ) || die "IN konnte nicht geoeffnet werden";

    $count = 1;

    while (my $jsonline=<IN>) {
        my $record_ref = decode_json $jsonline;

        my $id = $record_ref->{id};

        next unless (exists $listitemdata_superid{$id} && ref  $listitemdata_superid{$id} eq "HASH");

        # Anreichern mit content;
        foreach my $field ('0100','0101','0102','0103','1800') {
            if (defined $record_ref->{fields}{$field}) {
                foreach my $item_ref (@{$record_ref->{fields}{$field}}) {
                    my $personid   = $item_ref->{id};
                    
                    if (exists $listitemdata_person{$personid}) {
                        $item_ref->{content} = $listitemdata_person{$personid};
                    }
                    else {
                        $logger->error("PER ID $personid doesn't exist in TITLE ID $id");
                    }
                }
            }
        }

        $listitemdata_superid{$id} = $record_ref;

       if ($count % 100000 == 0){
            $logger->info("### $database: $count Titel");
        }

        $count++;	
    }

    close(IN);
}

$logger->info("### $database: Bearbeite meta.title");

open(IN ,           "<:raw" ,"meta.title"         )     || die "IN konnte nicht geoeffnet werden";
open(OUT,           ">:utf8","title.dump"        )      || die "OUT konnte nicht geoeffnet werden";
open(OUTFIELDS,     ">:utf8","title_fields.dump"     )  || die "OUTFIELDS konnte nicht geoeffnet werden";
open(SEARCHENGINE,  ">:raw" ,"searchengine.json" )       || die "SEARCHENGINE konnte nicht goeffnet werden";

my $locationid = $config->get_locationid_of_database($database);

$count = 1;

$atime = new Benchmark;

$serialid = 1;
    
while (my $jsonline=<IN>){
    
    my $record_ref = decode_json $jsonline;

    my $id         = $record_ref->{id};
    my $fields_ref = $record_ref->{fields};
    
    my $titlecache_ref   = {}; # Inhalte fuer den Titel-Cache
    my $searchengine_ref = {}; # Inhalte fuer die Suchmaschinen

    my $enrichmnt_isbns_ref = [];
    my $enrichmnt_issns_ref = [];

    # Initialisieren und Basisinformationen setzen
    my $index_doc = OpenBib::Index::Document->new({ database => $database, id => $id, locationid => $locationid });

    # Popularitaet, Tags und Literaturlisten verarbeiten fuer Index-Data
    {
        if (exists $listitemdata_popularity{$id}) {
            if (exists $conv_config->{'listitemcat'}{popularity}) {
                $index_doc->set_data('popularity',$listitemdata_popularity{$id});
            }

            
            $index_doc->add_index('popularity',1, $listitemdata_popularity{$id});
        }
        
        if (exists $listitemdata_tags{$id}) {
            if (exists $conv_config->{'listitemcat'}{tags}) {
                $index_doc->set_data('tag',$listitemdata_tags{$id});
            }
        }
        
        if (exists $listitemdata_litlists{$id}) {
            if (exists $conv_config->{'listitemcat'}{litlists}) {
                $index_doc->set_data('litlist',$listitemdata_litlists{$id});
            }
        }        
    }
    
    my @superids               = (); # IDs der Ueberordnungen fuer Schiller-Raeuber-Anreicherung
    
    my @person                 = ();
    my @corporatebody          = ();
    my @subject                = ();
    my @classification         = ();
    my @isbn                   = ();
    my @issn                   = ();
    my @personcorporatebody    = ();

    # Anreicherungs-IDs bestimmen

    # ISBN
    foreach my $field ('0540','0553') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {

                # Alternative ISBN zur Rechercheanreicherung erzeugen
                my $isbn = Business::ISBN->new($item_ref->{content});
                
                if (defined $isbn && $isbn->is_valid) {
                    
                    # ISBN13 fuer Anreicherung merken
                    
                    push @{$enrichmnt_isbns_ref}, OpenBib::Common::Util::normalize({
                        field    => "T0540",
                        content  => $isbn->as_isbn13->as_string,
                    });
                }
            }
        }
    }

    # ISSN
    foreach my $field ('0543') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                push @{$enrichmnt_issns_ref}, OpenBib::Common::Util::normalize({
                    field    => "T0543",
                    content  => $item_ref->{content},
                });
            }
        }
    }

    # Zentrale Anreicherungsdaten lokal einspielen
    if ($local_enrichmnt && (@{$enrichmnt_isbns_ref} || @{$enrichmnt_issns_ref})) {
        @{$enrichmnt_isbns_ref} =  keys %{{ map { $_ => 1 } @${enrichmnt_isbns_ref} }}; # Only unique
        @{$enrichmnt_issns_ref} =  keys %{{ map { $_ => 1 } @${enrichmnt_issns_ref} }}; # Only unique
        
        foreach my $field (keys %{$conv_config->{local_enrichmnt}}) {
            my $enrichmnt_data_ref = [];
            
            if (@{$enrichmnt_isbns_ref}) {
                foreach my $isbn13 (@{$enrichmnt_isbns_ref}) {
                    my $lookup_ref = $enrichmntdata{$isbn13};
                    $logger->debug("Testing ISBN $isbn13 for field $field");
                    foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                        $logger->debug("Enrich field $field for ISBN $isbn13 with $enrich_content");
                        push @$enrichmnt_data_ref, $enrich_content;
                    }
                }
            }
            elsif (@{$enrichmnt_issns_ref}) {
                foreach my $issn (@{$enrichmnt_issns_ref}) {
                    my $lookup_ref = $enrichmntdata{$issn};
                    
                    foreach my $enrich_content  (@{$lookup_ref->{"$field"}}) {
                        $logger->debug("Enrich field $field for ISSN $issn with $enrich_content");
                        push @$enrichmnt_data_ref, $enrich_content;
                    }
                }
            }
            
            if (@{$enrichmnt_data_ref}) {
                my $mult = 1;
                
                foreach my $content (keys %{{ map { $_ => 1 } @${enrichmnt_data_ref} }}) { # unique
                    $content = decode_utf8($content);
                    
                    $logger->debug("Id: $id - Adding $field -> $content");

                    push @{$fields_ref->{$field}}, {
                        mult      => $mult,
                        content   => $content,
                        subfield  => '',
                    };
                    
                    $mult++;
                }
            }
        }
    }

    # Medientypen erkennen und anreichern
    if ($addmediatype) {
        my $type_mult = 1;
        foreach my $item_ref (@{$fields_ref->{'4410'}}) {
            $type_mult++;
        }

        # Zeitschriften/Serien:
        # ISSN und/oder ZDB-ID besetzt
        if (defined $fields_ref->{'0572'} || defined $fields_ref->{'0543'}) {
            my $have_journal = 0;

            foreach my $item_ref (@{$fields_ref->{'4410'}}) {
                if ($item_ref->{'0800'} eq "Zeitschrift/Serie"){
                    $have_journal = 1;
                }
            }

            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult++,
                content   => 'Zeitschrift/Serie',
                subfield  => '',
            } unless ($have_journal);
        }   
                
        # Aufsatz
        # HSTQuelle besetzt
        if ($fields_ref->{'0590'}) {
            my $have_article = 0;
            
            foreach my $item_ref (@{$fields_ref->{'4410'}}) {
                if ($item_ref->{'0800'} eq "Aufsatz"){
                    $have_article = 1;
                }
            }
            
            push @{$fields_ref->{'4410'}}, {
                mult      => $type_mult,
                content   => 'Aufsatz',
                subfield  => '',
            } if ($have_article);
        }   
        
        # Elektronisches Medium mit Online-Zugriff
        # werden vorher katalogspezifisch per pre_unpack.pl angereichert
    } 

    # Jahreszahlen umwandeln
    if (defined $fields_ref->{'0425'}) {        
        my $array_ref=[];

        if (exists $listitemdata_enriched_years{$id}){
            $array_ref = $listitemdata_enriched_years{$id};
        }

        foreach my $item_ref (@{$fields_ref->{'0425'}}){
            my $date = $item_ref->{content};
            
            if ($date =~/^(-?\d+)\s*-\s*(-?\d+)/) {
                my $startyear = $1;
                my $endyear   = $2;
                
                $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                for (my $year=$startyear;$year<=$endyear; $year++) {
                    $logger->debug("Adding year $year");
                    push @$array_ref, $year;
                }
            }
            else {
                $logger->debug("Not expanding $date, just adding year");
                push @$array_ref, $date;
            }
        }
        
        $listitemdata_enriched_years{$id}=$array_ref;
    }

    # Verknuepfungskategorien bearbeiten    
    if (defined $fields_ref->{'0004'}) {
        foreach my $item_ref (@{$fields_ref->{'0004'}}) {
            my $target_titleid   = $item_ref->{content};
            my $mult             = $item_ref->{mult};
            my $source_titleid   = $id;
            my $supplement       = "";
            my $field            = "0004";
            
            if (defined $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}) {
                    my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};

                    $index_doc->add_index($searchfield, $weight, ["T$field",$target_titleid]);
                }
            }
            
            push @superids, $target_titleid;
            
            if (defined $listitemdata_superid{$target_titleid} && $source_titleid && $target_titleid){
                $supplement = cleanup_content($supplement);
                print OUTTITLETITLE "$title_title_serialid$field$source_titleid$target_titleid$supplement\n";
                $title_title_serialid++;
            }


            if (defined $listitemdata_superid{$target_titleid} && %{$listitemdata_superid{$target_titleid}}){
                # my $title_super = encode_json($listitemdata_superid{$target_titleid});

                # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
                # $title_super = cleanup_content($title_super);

                # Anreicherungen mit 5005 (Titelinformationen der Ueberordnung)
                push @{$fields_ref->{'5005'}}, {
                    mult      => $mult,
                    subfield  => '',
                    content   => $listitemdata_superid{$target_titleid},
                  #  content   => $title_super,
                };
            }
        }
    }
    

    # Verfasser/Personen
    foreach my $field ('0100','0101','0102','0103','1800') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
	        $item_ref->{ignore} = 1;
                
                my $personid   = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = $item_ref->{supplement};
                
                #                 # Feld 1800 wird als 0100 behandelt
                #                 if ($field eq "1800") {
                #                     $field = "0100";   
                #                 }
                
                next unless $personid;
                
                if (defined $listitemdata_person{$personid}){
                    $supplement = cleanup_content($supplement);
                    print OUTTITLEPERSON "$title_person_serialid$field$id$personid$supplement\n";
                    $title_person_serialid++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $listitemdata_person{$personid}) {
                    my $mainentry = $listitemdata_person{$personid};
                    
                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;

                    $index_doc->add_data("P$field",{
                        id      => $personid,
                        type    => 'person',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if (exists $conv_config->{listitemcat}{$field});
                    
                    push @personcorporatebody, $mainentry;
                    
#                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {
                    push @person, $personid;
#                    }
                }
                else {
                    $logger->error("PER ID $personid doesn't exist in TITLE ID $id");
                }
            }
        }
    }
    
    # Bei 1800 ohne Normdatenverknuepfung muss der Inhalt analog verarbeitet werden
    if (defined $fields_ref->{'1800'}) {
        foreach my $item_ref (@{$fields_ref->{'1800'}}) {
            unless (defined $item_ref->{id}) {
                push @personcorporatebody, $item_ref->{content};
            }
        }
    }
    
    #Koerperschaften/Urheber
    foreach my $field ('0200','0201','1802') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                my $corporatebodyid = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = "";
                
                #                 # Feld 1802 wird als 0200 behandelt
                #                 if ($field eq "1802") {
                #                     $field = "0200";   
                #                 }
                
                next unless $corporatebodyid;
                
                if (defined $listitemdata_corporatebody{$corporatebodyid}){
                    $supplement = cleanup_content($supplement);
                    print OUTTITLECORPORATEBODY "$title_corporatebody_serialid$field$id$corporatebodyid$supplement\n";
                    $title_corporatebody_serialid++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $listitemdata_corporatebody{$corporatebodyid}) {                        
                    my $mainentry = $listitemdata_corporatebody{$corporatebodyid};
                    

                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;

                    $index_doc->add_data("C$field", {
                        id      => $corporatebodyid,
                        type    => 'corporatebody',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if (exists $conv_config->{listitemcat}{$field});
                    
                    push @personcorporatebody, $mainentry;
                    
#                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {                    
                        push @corporatebody, $corporatebodyid;
#                    }
                }
                else {
                    $logger->error("CORPORATEBODY ID $corporatebodyid doesn't exist in TITLE ID $id");
                }
            }
        }
    }
    
    # Bei 1802 ohne Normdatenverknuepfung muss der Inhalt analog verarbeitet werden
    if (defined $fields_ref->{'1802'}) {
        foreach my $item_ref (@{$fields_ref->{'1802'}}) {
            # Verknuepfungsfelder werden ignoriert
            $item_ref->{ignore} = 1;
            
            unless ($item_ref->{id}) {
                my $field = '1802';
                
                push @personcorporatebody, $item_ref->{content};
            }
        }
    }
    
    # Klassifikation
    foreach my $field ('0700') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                my $classificationid = $item_ref->{id};
                my $titleid          = $id;
                my $supplement       = "";
                
                next unless $classificationid;
                
                if (defined $listitemdata_classification{$classificationid}){
                    print OUTTITLECLASSIFICATION "$title_classification_serialid$field$id$classificationid$supplement\n";
                    $title_classification_serialid++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $listitemdata_classification{$classificationid}) {
                    my $mainentry = $listitemdata_classification{$classificationid};
                    
                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;
                    
                    $index_doc->add_data("N$field", {
                        id      => $classificationid,
                        type    => 'classification',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if (exists $conv_config->{listitemcat}{$field});
                    
#                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {                    
                        push @classification, $classificationid;
#                    }        
                }
                else {
                    $logger->error("SYS ID $classificationid doesn't exist in TITLE ID $id");
                }
            }
        }
    }
    
    # Schlagworte
    foreach my $field ('0710','0902','0907','0912','0917','0922','0927','0932','0937','0942','0947') {
        if (defined $fields_ref->{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                my $subjectid = $item_ref->{id};
                my $titleid    = $id;
                my $supplement = "";
                
                next unless $subjectid;
                
                if (defined $listitemdata_subject{$subjectid}){
                    $supplement = cleanup_content($supplement);
                    print OUTTITLESUBJECT "$title_subject_serialid$field$id$subjectid$supplement\n";
                    $title_subject_serialid++;
                }
                
                # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                # auch wirklich existiert -> schlechte Katalogisate
                if (exists $listitemdata_subject{$subjectid}) {
                    my $mainentry = $listitemdata_subject{$subjectid};
                    
                    # Um Ansetzungsform erweitern
                    $item_ref->{content} = $mainentry;
                    
                    $index_doc->add_data("S$field", {
                        id      => $subjectid,
                        type    => 'subject',
                        content => $mainentry,
                        supplement => $supplement,
                    }) if (exists $conv_config->{listitemcat}{$field});
                    
#                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {                    
                        push @subject, $subjectid;
#                    }
                } 
                else {
                    $logger->error("SUBJECT ID $subjectid doesn't exist in TITLE ID $id");
                }
            }
        }
    }

    # Personen der Ueberordnung anreichern (Schiller-Raeuber). Wichtig: Vor der Erzeugung der Suchmaschineneintraege, da sonst nicht ueber
    # die Personen der Ueberordnung facettiert wird. Das ist wegen der Vereinheitlichung auf Endnutzerebene sinnvoll.

    if ($addsuperpers) {
        foreach my $superid (@superids) {
            if ($superid && exists $listitemdata_superid{$superid}) {
                my $super_ref = $listitemdata_superid{$superid};
                foreach my $field ('0100','0101','0102','0103','1800') {
                    if (defined $super_ref->{fields}{$field}) {
                        # Anreichern fuer Facetten
                        if (defined $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}){
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}) {
                                foreach my $item_ref (@{$super_ref->{fields}{$field}}) {
                                    $index_doc->add_facet("facet_".$searchfield, $item_ref->{content});
                                }
                            }
                        }

                        # Anreichern fuer Recherche
                        foreach my $item_ref (@{$super_ref->{fields}{$field}}) {
                            push @person, $item_ref->{id};
                        }
                    }
                }
            }
        }
    }


    # Bibkey-Kategorie 5050 wird *immer* angereichert, wenn alle relevanten Kategorien enthalten sind. Die Invertierung ist konfigurabel
    if ((defined $fields_ref->{'0100'} || defined $fields_ref->{'0101'}) && defined $fields_ref->{'0331'} && (defined $fields_ref->{'0424'} || defined $fields_ref->{'0425'})){

        my $bibkey_record_ref = {
            'T0100' => $fields_ref->{'0100'},
            'T0101' => $fields_ref->{'0101'},
            'T0331' => $fields_ref->{'0331'},
            'T0425' => $fields_ref->{'0425'},
        };

        if ($fields_ref->{'0424'} && !$fields_ref->{'0425'}){
            $bibkey_record_ref->{'T0425'} = $fields_ref->{'0424'};
        }

        my $bibkey_base = OpenBib::Common::Util::gen_bibkey_base({ fields => $bibkey_record_ref});

        my $bibkey      = ($bibkey_base)?OpenBib::Common::Util::gen_bibkey({ bibkey_base => $bibkey_base }):"";
        
        if ($bibkey) {
            push @{$fields_ref->{'5050'}}, {
                mult      => 1,
                content   => $bibkey,
                subfield  => '',
            };
                
            push @{$fields_ref->{'5051'}}, {
                mult      => 1,
                content   => $bibkey_base,
                subfield   => '',
            };

            # Bibkey merken fuer Recherche ueber Suchmaschine
#            $index_doc->add_index('bkey',1, ['T5050',$bibkey]);
#            $index_doc->add_index('bkey',1, ['T5051',$bibkey_base]);
        }
    }

    # Suchmaschineneintraege mit den Tags, Literaturlisten und Standard-Titelkategorien fuellen
    {
        foreach my $field (keys %{$stammdateien_ref->{title}{inverted_ref}}){
            # a) Indexierung in der Suchmaschine
            if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}){

                my $flag_isbn = 0;
                # Wird dieses Feld als ISBN genutzt, dann zusaetzlicher Inhalt
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}) {
                    if ($searchfield eq "isbn"){
                        $flag_isbn=1;
                    }
                }
                
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}) {
                    my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                    if    ($field eq "tag"){
                        if (exists $listitemdata_tags{$id}) {
                            
                            foreach my $tag_ref (@{$listitemdata_tags{$id}}) {
                                $index_doc->add_index($searchfield,$weight, ['tag',$tag_ref->{tag}]);
                            }
                            
                            
                            $logger->info("### $database: Adding Tags to ID $id");
                        }
                        
                    }
                    elsif ($field eq "litlist"){
                        if (exists $listitemdata_litlists{$id}) {
                            foreach my $litlist_ref (@{$listitemdata_litlists{$id}}) {
                                $index_doc->add_index($searchfield,$weight, ['litlist',$litlist_ref->{title}]);
                            }
                            
                            $logger->info("### $database: Adding Litlists to ID $id");
                        }
                    }
                    else {
                        next unless (defined $fields_ref->{$field});
                        
                        foreach my $item_ref (@{$fields_ref->{$field}}){
                            next unless $item_ref->{content};

                            $index_doc->add_index($searchfield,$weight, ["T$field",$item_ref->{content}]);

                            # Wird diese Kategorie als isbn verwendet?
                            if ($flag_isbn) {
                                # Alternative ISBN zur Rechercheanreicherung erzeugen
                                my $isbn = Business::ISBN->new($item_ref->{content});

                                if (defined $isbn && $isbn->is_valid) {
                                    my $isbnXX;
                                    if (!$isbn->prefix) { # ISBN10 haben kein Prefix
                                        $isbnXX = $isbn->as_isbn13;
                                    } else {
                                        $isbnXX = $isbn->as_isbn10;
                                    }
                                    
                                    if (defined $isbnXX) {
                                        my $enriched_isbn = $isbnXX->as_string;

                                        $enriched_isbn = lc($enriched_isbn);
                                        $enriched_isbn=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
                                        $enriched_isbn=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
                                        
                                        $index_doc->add_index($searchfield,$weight, ["T$field",$enriched_isbn]);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            # b) Facetten in der Suchmaschine
            if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}){
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}) {
                    if ($field eq "tag"){
                        if (exists $listitemdata_tags{$id}) {
                            foreach my $tag_ref (@{$listitemdata_tags{$id}}) {
                                $index_doc->add_facet("facet_$searchfield", $tag_ref->{tag});
                            }
                        }
                    }
                    elsif ($field eq "litlist"){
                        if (exists $listitemdata_litlists{$id}) {
                            foreach my $litlist_ref (@{$listitemdata_tags{$id}}) {
                                $index_doc->add_facet("facet_$searchfield", $litlist_ref->{title});
                            }
                        }
                    }            
                    else {
                        next unless (defined $fields_ref->{$field});
                        
                        foreach my $item_ref (@{$fields_ref->{$field}}) {
                            $index_doc->add_facet("facet_$searchfield", $item_ref->{content});        
                        }
                    }
                }
            }
        }
    }
            
    # Indexierte Informationen aus anderen Normdateien fuer Suchmaschine
    {
        # Im Falle einer Personenanreicherung durch Ueberordnungen mit
        # -add-superpers sollen Dubletten entfernt werden.
        my %seen_person=();
        foreach my $item (@person) {
            next if (exists $seen_person{$item});
            
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('personid',1, ['id',$item]);
            
            if (exists $indexed_person{$item}) {
                my $thisperson = $indexed_person{$item};
                foreach my $searchfield (keys %{$thisperson}) {		    
                    foreach my $weight (keys %{$thisperson->{$searchfield}}) {                        
                        $index_doc->add_index_array($searchfield,$weight, $thisperson->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
            
            $seen_person{$item}=1;
        }
        
        foreach my $item (@corporatebody) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('corporatebodyid',1, ['id',$item]);
            
            if (exists $indexed_corporatebody{$item}) {
                my $thiscorporatebody = $indexed_corporatebody{$item};
                
                foreach my $searchfield (keys %{$thiscorporatebody}) {
                    foreach my $weight (keys %{$thiscorporatebody->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thiscorporatebody->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
        foreach my $item (@subject) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('subjectid',1, ['id',$item]);
            
            if (exists $indexed_subject{$item}) {
                my $thissubject = $indexed_subject{$item};
                
                foreach my $searchfield (keys %{$thissubject}) {
                    foreach my $weight (keys %{$thissubject->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thissubject->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
        foreach my $item (@classification) {
            # ID-Merken fuer Recherche ueber Suchmaschine
            $index_doc->add_index('classificationid',1, ['id',$item]);
            
            if (exists $indexed_classification{$item}) {
                my $thisclassification = $indexed_classification{$item};
                
                foreach my $searchfield (keys %{$thisclassification}) {
                    foreach my $weight (keys %{$thisclassification->{$searchfield}}) {
                        $index_doc->add_index_array($searchfield,$weight, $thisclassification->{$searchfield}{$weight}); # value is arrayref
                    }
                }
            }
        }
        
    }
    
    if (exists $indexed_holding{$id}) {
        my $thisholding = $indexed_holding{$id};
        
        foreach my $searchfield (keys %{$thisholding}) {
            foreach my $weight (keys %{$thisholding->{$searchfield}}) {
                $index_doc->add_index_array($searchfield,$weight, $thisholding->{$searchfield}{$weight}); # value is arrayref
            }
        }
    }
    
    # Automatische Anreicherung mit Bestands- oder Jahresverlaeufen
    {
        if (exists $listitemdata_enriched_years{$id}) {
            foreach my $year (@{$listitemdata_enriched_years{$id}}) {
                $logger->debug("Enriching year $year to Title-ID $id");
                $index_doc->add_index('year',1, ['T0425',$year]);
                $index_doc->add_index('freesearch',1, ['T0425',$year]);
            }
        }
    }
    
    # Index-Data mit Titelfeldern fuellen
    foreach my $field (keys %{$fields_ref}) {            
        # Kategorien in listitemcat werden fuer die Kurztitelliste verwendet
        if (defined $conv_config->{listitemcat}{$field}) {
            foreach my $item_ref (@{$fields_ref->{$field}}) {
                unless (defined $item_ref->{ignore}){
                    $index_doc->add_data("T".$field, $item_ref);
                }
            }
        }
    }
        
    # Potentiell fehlender Titel fuer Index-Data zusammensetzen
    {
        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Ist nichts zu tun
        #
        # 2. Fall: Es existiert kein HST(331)
        #
        # Dann:
        #
        # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
        #                Gesamttitel(451)
        #
        # Dann: Verwende diesen GT
        #
        # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
        #                aber eine Zeitschriftensignatur(1203/USB-spezifisch)
        #
        # Dann: Verwende diese Zeitschriftensignatur
        #
        if (!defined $fields_ref->{'0331'}) {
            # UnterFall 2.1:
            if (defined $fields_ref->{'0089'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'0089'}[0]{content}
                });
            }
            # Unterfall 2.2:
            elsif (defined $fields_ref->{'0455'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'0455'}[0]{content}
                });
            }
            # Unterfall 2.3:
            elsif (defined $fields_ref->{'0451'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'0451'}[0]{content}
                });
            }
            # Unterfall 2.4:
            elsif (defined $fields_ref->{'1203'}) {
                $index_doc->add_data('T0331',{
                    content => $fields_ref->{'1203'}[0]{content}
                });
            }
            else {
                $index_doc->add_data('T0331',{
                    content => "Kein HST/AST vorhanden",
                });
            }
        }
        
        # Bestimmung der Zaehlung
        
        # Fall 1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Setze diese Bandzahl
        #
        # Fall 2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Setze diese Bandzahl
        
        # Fall 1:
        if (defined $fields_ref->{'0089'}) {
            $index_doc->set_data('T5100', [
                {
                    content => $fields_ref->{'0089'}[0]{content}
                }
            ]);
        }
        # Fall 2:
        elsif (defined $fields_ref->{'0455'}) {
            $index_doc->set_data('T5100', [
                {
                    content => $fields_ref->{'0455'}[0]{content}
                }
            ]);
        }
        
        # Exemplardaten-Hash zu listitem-Hash hinzufuegen
        
        # Exemplardaten-Hash zu listitem-Hash hinzufuegen
        if (exists $listitemdata_holding{$id}){
            my $thisholdings = $listitemdata_holding{$id};
            foreach my $content (@{$thisholdings}) {
                $index_doc->add_data('X0014', {
                    content => $content,
                });
            }
        }
        
        # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
        $index_doc->add_data('PC0001', {
            content   => join(" ; ",@personcorporatebody),
        });
    }
    
    
    my $titlecache = encode_json $index_doc->get_data;
    
   # $titlecache =~s/\\/\\\\/g; # Escape Literal Backslash for PostgreSQL
    $titlecache = cleanup_content($titlecache);
    
    my $create_tstamp = "1970-01-01 12:00:00";
    
    if (defined $fields_ref->{'0002'} && defined $fields_ref->{'0002'}[0]) {
        $create_tstamp = $fields_ref->{'0002'}[0]{content};
        if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
            $create_tstamp=$3."-".$2."-".$1." 12:00:00";
        }
    }
    
    my $update_tstamp = "1970-01-01 12:00:00";
    
    if (defined $fields_ref->{'0003'} && defined $fields_ref->{'0003'}[0]) {
        $update_tstamp = $fields_ref->{'0003'}[0]{content};
        if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
            $update_tstamp=$3."-".$2."-".$1." 12:00:00";
        }
        
    }
    
    # Primaeren Normdatensatz erstellen und schreiben
    my $popularity = (exists $listitemdata_popularity{$id})?$listitemdata_popularity{$id}:0;
    
    print OUT "$id$create_tstamp$update_tstamp$titlecache$popularity\n";
    
    # Abhaengige Feldspezifische Saetze erstellen und schreiben
    
    foreach my $field (keys %{$fields_ref}) {
        next if ($field eq "id" || defined $stammdateien_ref->{title}{blacklist_ref}->{$field});
        
        foreach my $item_ref (@{$fields_ref->{$field}}) {
            next if ($item_ref->{ignore});

            if (ref $item_ref->{content} eq "HASH"){
                my $content = decode_utf8(encode_json ($item_ref->{content})); # decode_utf8, um doppeltes Encoding durch encode_json und binmode(:utf8) zu vermeiden
                $item_ref->{content} = cleanup_content($content);
            }

            if ($id && $field && $item_ref->{content}){
                $item_ref->{content} = cleanup_content($item_ref->{content});

#                $logger->error("mult fehlt") if (!defined $item_ref->{mult});
#                $logger->error("subfield fehlt") if (!defined $item_ref->{subfield});
                
                print OUTFIELDS "$serialid$id$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
                $serialid++;
            }
        }
    }                
        
    # Suchmaschinen-Daten schreiben
    my $searchengine = $index_doc->to_json;

    print SEARCHENGINE "$searchengine\n";
    
    if ($count % 1000 == 0) {
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $atime      = new Benchmark;
        $logger->info("### $database: $count Titelsaetze in $resulttime bearbeitet");
    } 

    $count++;
}

$logger->info("### $database: $count Titelsaetze bearbeitet");

close(OUT);
close(OUTFIELDS);
close(SEARCHENGINE);

close(IN);


#######################


open(CONTROL,        ">control.sql");
open(CONTROLINDEXOFF,">control_index_off.sql");
open(CONTROLINDEXON, ">control_index_on.sql");


# Index und Contstraints werden zentral via pool_drop_index.sql geloescht

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROL << "ITEMTRUNC";
truncate table $type;
truncate table ${type}_fields;
ITEMTRUNC
    print CONTROL << "ITEM";
COPY $type FROM '$dir/$stammdateien_ref->{$type}{outfile}' WITH DELIMITER '' NULL AS '';
COPY ${type}_fields FROM '$dir/$stammdateien_ref->{$type}{outfile_fields}' WITH DELIMITER '' NULL AS '';
ITEM
}

print CONTROL << "TITLEITEMTRUNC";
truncate table title_title;
truncate table title_person;
truncate table title_corporatebody;
truncate table title_subject;
truncate table title_classification;
truncate table title_holding;
TITLEITEMTRUNC
    
print CONTROL << "TITLEITEM";
COPY title_title FROM '$dir/title_title.dump' WITH DELIMITER '' NULL AS '';
COPY title_person FROM '$dir/title_person.dump' WITH DELIMITER '' NULL AS '';
COPY title_corporatebody FROM '$dir/title_corporatebody.dump' WITH DELIMITER '' NULL AS '';
COPY title_subject FROM '$dir/title_subject.dump' WITH DELIMITER '' NULL AS '';
COPY title_classification FROM '$dir/title_classification.dump' WITH DELIMITER '' NULL AS '';
COPY title_holding FROM '$dir/title_holding.dump' WITH DELIMITER '' NULL AS '';
TITLEITEM

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

sub cleanup_content {
    my $content = shift;

    # Make PostgreSQL Happy    
    $content =~ s/($chars_to_replace)/$char_replacements{$1}/g;
            
    return $content;
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
