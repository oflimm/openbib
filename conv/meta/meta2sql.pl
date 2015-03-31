#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2014 Oliver Flimm <flimm@openbib.org>
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
use Lingua::Identify::CLD;
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();

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
use OpenBib::Importer::JSON::Title;

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

my ($database,$reducemem,$addsuperpers,$addmediatype,$addlanguage,$incremental,$logfile,$loglevel,$count,$help);

&GetOptions(
    "reduce-mem"     => \$reducemem,
    "add-superpers"  => \$addsuperpers,
    "add-mediatype"  => \$addmediatype,
    "add-language"   => \$addlanguage,
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
my $conv_config = OpenBib::Conv::Config->instance({dbname => $database});

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
    if (-f $stammdateien_ref->{$type}{infile}){
        $logger->info("### $database: Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}");

        open(IN ,           "<:raw",$stammdateien_ref->{$type}{infile} )        || die "IN konnte nicht geoeffnet werden";
        open(OUT,           ">:utf8",$stammdateien_ref->{$type}{outfile})        || die "OUT konnte nicht geoeffnet werden";
        open(OUTFIELDS,     ">:utf8",$stammdateien_ref->{$type}{outfile_fields})     || die "OUTFIELDS konnte nicht geoeffnet werden";
        
        my ($category,$mult,$content);
        
        my $serialid = 1;
        
        while (my $jsonline=<IN>) {
            
            my $record_ref ;
            
            eval {
                $record_ref = decode_json $jsonline;
            };
            
            if ($@){
                $logger->error("Skipping record: $@");
                next;
            }
            
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
                } elsif ($type eq "corporatebody") {
                    $listitemdata_corporatebody{$id}=$mainentry;
                } elsif ($type eq "classification") {
                    $listitemdata_classification{$id}=$mainentry;
                } elsif ($type eq "subject") {
                    if (defined $fields_ref->{'0800'}[1]) {
                        # Schlagwortketten zusammensetzen
                        my @mainentries = ();
                        foreach my $item (map { $_->[0] }
                                              sort { $a->[1] <=> $b->[1] }
                                                  map { [$_, $_->{mult}] } @{$fields_ref->{'0800'}}) {
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
                        
                            if ($type eq "person") {
                                my $hash_ref = {};
                                if (exists $indexed_person{$id}) {
                                    $hash_ref = $indexed_person{$id};
                                }
                                push @{$hash_ref->{$searchfield}{$weight}}, ["P$field",$item_ref->{content}];
                            
                                $indexed_person{$id} = $hash_ref;
                            } elsif ($type eq "corporatebody") {
                                my $hash_ref = {};
                                if (exists $indexed_corporatebody{$id}) {
                                    $hash_ref = $indexed_corporatebody{$id};
                                }
                                push @{$hash_ref->{$searchfield}{$weight}}, ["C$field",$item_ref->{content}];
                            
                                $indexed_corporatebody{$id} = $hash_ref;
                            } elsif ($type eq "subject") {
                                my $hash_ref = {};
                                if (exists $indexed_subject{$id}) {
                                    $hash_ref = $indexed_subject{$id};
                                }
                                push @{$hash_ref->{$searchfield}{$weight}}, ["S$field",$item_ref->{content}];
                            
                                $indexed_subject{$id} = $hash_ref;
                            } elsif ($type eq "classification") {
                                my $hash_ref = {};
                                if (exists $indexed_classification{$id}) {
                                    $hash_ref = $indexed_classification{$id};
                                }                        
                                push @{$hash_ref->{$searchfield}{$weight}}, ["N$field",$item_ref->{content}];
                            
                                $indexed_classification{$id} = $hash_ref;
                            }
                        }
                    }
                
                    if ($id && $field && $item_ref->{content}) {
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
    } else {
        $logger->error("### $database: $stammdateien_ref->{$type}{infile} nicht vorhanden!");
    }
}

#######################

$stammdateien_ref->{holding} = {
    infile             => "meta.holding",
    outfile            => "holding.dump",
    outfile_fields     => "holding_fields.dump",
    inverted_ref       => $conv_config->{inverted_holding},
};

if (-f "meta.holding"){
    $logger->info("### $database: Bearbeite meta.holding");

    open(IN ,                   "<:raw","meta.holding")               || die "IN konnte nicht geoeffnet werden";
    open(OUT,                   ">:utf8","holding.dump")               || die "OUT konnte nicht geoeffnet werden";
    open(OUTFIELDS,             ">:utf8","holding_fields.dump")        || die "OUTFIELDS konnte nicht geoeffnet werden";
    open(OUTTITLEHOLDING,       ">:utf8","title_holding.dump")         || die "OUTTITLEHOLDING konnte nicht geoeffnet werden";

    my $id;
    my ($category,$mult,$content);

    $count = 1;

    my $atime = new Benchmark;

    my $titleid;
    my $thisyear = `date +"%Y"`;

    my $serialid = 1;

    my $title_holding_serialid = 1;

    while (my $jsonline=<IN>) {

        my $record_ref ;
        
        eval {
            $record_ref = decode_json $jsonline;
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            next;
        }

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
                        if (defined $indexed_holding{$titleid}) {
                            $hash_ref = $indexed_holding{$titleid};
                        }
                    
                        push @{$hash_ref->{$searchfield}{$weight}}, ["X$field",$item_ref->{content}];
                    
                        $indexed_holding{$titleid} = $hash_ref;
                    }
                }
            
                if ($id && $field && $item_ref->{content}) {
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
            if (exists $listitemdata_holding{$titleid}) {
                $array_ref = $listitemdata_holding{$titleid};
            }
            push @$array_ref, $fields_ref->{'0014'}[0]{content};
            $listitemdata_holding{$titleid}=$array_ref;
        }
    
        # Bestandsverlauf in Jahreszahlen umwandeln
        if ((defined $fields_ref->{'1204'}) && $titleid) {        
            my $array_ref=[];
            if (exists $listitemdata_enriched_years{$titleid}) {
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
                } elsif ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-/) {
                    my $startyear = $1;
                    my $endyear   = $thisyear;
                    $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                    for (my $year=$startyear;$year<=$endyear;$year++) {
                        $logger->debug("Adding year $year");
                        push @$array_ref, $year;
                    }                
                } elsif ($date =~/(\d\d\d\d)/) {
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
    close(OUTTITLEHOLDING);
    close(IN);

    unlink "meta.holding";
} else {
    $logger->error("### $database: meta.holding nicht vorhanden!");
}

open(OUTTITLETITLE,         ">:utf8","title_title.dump")           || die "OUTTITLETITLE konnte nicht geoeffnet werden";
open(OUTTITLEPERSON,        ">:utf8","title_person.dump")          || die "OUTTITLEPERSON konnte nicht geoeffnet werden";
open(OUTTITLECORPORATEBODY, ">:utf8","title_corporatebody.dump")   || die "OUTTITLECORPORATEBODY konnte nicht geoeffnet werden";
open(OUTTITLESUBJECT,       ">:utf8","title_subject.dump")         || die "OUTTITLESUBJECT konnte nicht geoeffnet werden";
open(OUTTITLECLASSIFICATION,">:utf8","title_classification.dump")  || die "OUTTITLECLASSIFICATION konnte nicht geoeffnet werden";

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
        my $record_ref ;
        
        eval {
            $record_ref = decode_json $jsonline;
        };

        if ($@){
            $logger->error("Skipping record: $@");
            next;
        }
            
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
        my $record_ref ;
        
        eval {
            $record_ref = decode_json $jsonline;
        };

        if ($@){
            $logger->error("Skipping record: $@");
            next;
        }

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
open(OUT,           ">:utf8","title.dump"         )     || die "OUT konnte nicht geoeffnet werden";
open(OUTFIELDS,     ">:utf8","title_fields.dump"  )     || die "OUTFIELDS konnte nicht geoeffnet werden";
open(SEARCHENGINE,  ">:raw" ,"searchengine.json"  )     || die "SEARCHENGINE konnte nicht goeffnet werden";

my $locationid = $config->get_locationid_of_database($database);

$count = 1;

my $atime = new Benchmark;

my $serialid = 1;

# my $storage = OpenBib::Container->instance;

# $storage->register('listitemdata_person',\%listitemdata_person);
# $storage->register('listitemdata_person_date',\%listitemdata_person_date);
# $storage->register('listitemdata_corporatebody',\%listitemdata_corporatebody);
# $storage->register('listitemdata_classification',\%listitemdata_classification);
# $storage->register('listitemdata_subject',\%listitemdata_subject);
# $storage->register('listitemdata_holding',\%listitemdata_holding);
# $storage->register('listitemdata_superid',\%listitemdata_superid);
# $storage->register('listitemdata_popularity',\%listitemdata_popularity);
# $storage->register('listitemdata_tags',\%listitemdata_tags);
# $storage->register('listitemdata_litlists',\%listitemdata_litlists);
# $storage->register('listitemdata_enriched_years',\%listitemdata_enriched_years);
# $storage->register('enrichmntdata',\%enrichmntdata);
# $storage->register('indexed_person',\%indexed_person);
# $storage->register('indexed_corporatebody',\%indexed_corporatebody);
# $storage->register('indexed_subject',\%indexed_subject);
# $storage->register('indexed_classification',\%indexed_classification);
# $storage->register('indexed_holding',\%indexed_holding);
# $storage->register('stats_enriched_language',$stats_enriched_language);
# $storage->register('title_title_serialid',$title_title_serialid);
# $storage->register('title_person_serialid',$title_person_serialid);
# $storage->register('title_corporatebody_serialid',$title_corporatebody_serialid);
# $storage->register('title_classification_serialid',$title_classification_serialid);
# $storage->register('title_subject_serialid',$title_subject_serialid);
# $storage->register('serialid',$serialid);

my $storage_ref = {
    'listitemdata_person' => \%listitemdata_person,
    'listitemdata_person_date' => \%listitemdata_person_date,
    'listitemdata_corporatebody' => \%listitemdata_corporatebody,
    'listitemdata_classification' => \%listitemdata_classification,
    'listitemdata_subject' => \%listitemdata_subject,
    'listitemdata_holding' => \%listitemdata_holding,
    'listitemdata_superid' => \%listitemdata_superid,
    'listitemdata_popularity' => \%listitemdata_popularity,
    'listitemdata_tags' => \%listitemdata_tags,
    'listitemdata_litlists' => \%listitemdata_litlists,
    'listitemdata_enriched_years' => \%listitemdata_enriched_years,
    'enrichmntdata' => \%enrichmntdata,
    'indexed_person' => \%indexed_person,
    'indexed_corporatebody' => \%indexed_corporatebody,
    'indexed_subject' => \%indexed_subject,
    'indexed_classification' => \%indexed_classification,
    'indexed_holding' => \%indexed_holding,
};

my $importer = OpenBib::Importer::JSON::Title->new({
    database        => $database,
    addsuperpers    => $addsuperpers,
    addlanguage     => $addlanguage,
    addmediatype    => $addmediatype,
    local_enrichmnt => $local_enrichmnt,
    storage         => $storage_ref,
});

while (my $jsonline=<IN>){

    $importer->process({
        json         => $jsonline
    });

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

unlink $stammdateien_ref->{title}{infile};

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
    $content =~ s/\\/\\\\/g;
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
