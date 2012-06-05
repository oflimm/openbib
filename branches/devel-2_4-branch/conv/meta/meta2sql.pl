#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2012 Oliver Flimm <flimm@openbib.org>
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

use Business::ISBN;
use DB_File;
use Encode qw/decode_utf8/;
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Record::Classification;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Person;
use OpenBib::Record::Subject;
use OpenBib::Record::Title;
use OpenBib::Statistics;

my ($database,$reducemem,$addsuperpers,$addmediatype,$addpersondate,$incremental,$logfile,$loglevel,$count,$help);

&GetOptions("reduce-mem"     => \$reducemem,
            "add-superpers"  => \$addsuperpers,
            "add-mediatype"  => \$addmediatype,
            "add-persondate" => \$addpersondate,
            "incremental"    => \$incremental,
	    "database=s"     => \$database,
            "logfile=s"      => \$logfile,
            "loglevel=s"     => \$loglevel,
            "help"           => \$help,
	    );

if ($help){
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

if ($reducemem){
    tie %listitemdata_person,        'MLDBM', "./listitemdata_person.db"
        or die "Could not tie listitemdata_person.\n";

    tie %listitemdata_person_date,   'MLDBM', "./listitemdata_person_date.db"
        or die "Could not tie listitemdata_person_date.\n";

    tie %listitemdata_corporatebody,        'MLDBM', "./listitemdata_corporatebody.db"
        or die "Could not tie listitemdata_corporatebody.\n";

    tie %listitemdata_classification,        'MLDBM', "./listitemdata_classification.db"
        or die "Could not tie listitemdata_classification.\n";
 
    tie %listitemdata_subject,        'MLDBM', "./listitemdata_subject.db"
        or die "Could not tie listitemdata_subject.\n";

    tie %listitemdata_holding,        'MLDBM', "./listitemdata_holding.db"
        or die "Could not tie listitemdata_holding.\n";

    tie %listitemdata_popularity,        'MLDBM', "./listitemdata_popularity.db"
        or die "Could not tie listitemdata_popularity.\n";

    tie %listitemdata_tags,           'MLDBM', "./listitemdata_tags.db"
        or die "Could not tie listitemdata_tags.\n";
    
    tie %listitemdata_litlists,        'MLDBM', "./listitemdata_litlists.db"
        or die "Could not tie listitemdata_litlists.\n";

    tie %listitemdata_enriched_years,      'MLDBM', "./listitemdata_enriched_years.db"
        or die "Could not tie listitemdata_enriched_years.\n";

    tie %listitemdata_superid,    "DB_File", "./listitemdata_superid.db"
        or die "Could not tie listitemdata_superid.\n";
}

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
    or $logger->error($DBI::errstr);

# Popularitaet
my $request=$statisticsdbh->prepare("select id, count(id) as idcount from titleusage where origin=2 and dbname=? group by id");
$request->execute($database);

while (my $res    = $request->fetchrow_hashref){
    my $id      = $res->{id};
    my $idcount = $res->{idcount};
    $listitemdata_popularity{$id}=$idcount;
}
$request->finish();

# Verbindung zur SQL-Datenbank herstellen
my $userdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd})
    or $logger->error($DBI::errstr);

# Tags
$request=$userdbh->prepare("select t.name, tt.titleid, t.id from tag as t, tit_tag as tt where tt.dbname=? and tt.tagid=t.id and tt.type=1");
$request->execute($database);

while (my $res    = $request->fetchrow_hashref){
    my $titid   = $res->{titleid};
    my $tag     = $res->{name};
    my $id      = $res->{id};
    push @{$listitemdata_tags{$titid}}, { tag => $tag, id => $id };
}
$request->finish();

# Titel von Literaturlisten
$request=$userdbh->prepare("select l.title, i.titleid, l.id from litlist as l, litlistitem as i where i.dbname=? and i.litlistid=l.id and l.type=1");
$request->execute($database);

while (my $res    = $request->fetchrow_hashref){
    my $titid   = $res->{titleid};
    my $title   = $res->{title};
    my $id      = $res->{id};
    push @{$listitemdata_litlists{$titid}}, { title => $title, id => $id };
}
$request->finish();

my $local_enrichmnt  = 0;
my $enrichmntdumpdir = $config->{autoconv_dir}."/data/enrichment";

if (exists $conv_config->{local_enrichmnt} && -e "$enrichmntdumpdir/enrichmntdata.db"){
    tie %enrichmntdata,           'MLDBM', "$enrichmntdumpdir/enrichmntdata.db"
        or die "Could not tie enrichment data.\n";

    $local_enrichmnt = 1;

    $logger->info("Lokale Einspielung mit zentralen Anreicherungsdaten aktiviert");
}

my $stammdateien_ref = {
    person => {
        type               => "person",
        infile             => "meta.person",
        outfile            => "person.mysql",
        outfile_fields     => "person_fields.mysql",
        outfile_normfields => "person_normfields.mysql",
        inverted_ref       => $conv_config->{inverted_person},
        blacklist_ref      => $conv_config->{blacklist_person},
    },
    
    corporatebody => {
        infile             => "meta.corporatebody",
        outfile            => "corporatebody.mysql",
        outfile_fields     => "corporatebody_fields.mysql",
        outfile_normfields => "corporatebody_normfields.mysql",
        inverted_ref       => $conv_config->{inverted_corporatebody},
        blacklist_ref      => $conv_config->{blacklist_corporatebody},
    },
    
    subject => {
        infile             => "meta.subject",
        outfile            => "subject.mysql",
        outfile_fields     => "subject_fields.mysql",
        outfile_normfields => "subject_normfields.mysql",
        inverted_ref       => $conv_config->{inverted_subject},
        blacklist_ref      => $conv_config->{blacklist_subject},
    },
    
    classification => {
        infile             => "meta.classification",
        outfile            => "classification.mysql",
        outfile_fields     => "classification_fields.mysql",
        outfile_normfields => "classification_normfields.mysql",
        inverted_ref       => $conv_config->{inverted_classification},
        blacklist_ref      => $conv_config->{blacklist_classification},
    },
};


foreach my $type (keys %{$stammdateien_ref}){
  $logger->info("Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}");

  open(IN ,           "<:utf8",$stammdateien_ref->{$type}{infile} )        || die "IN konnte nicht geoeffnet werden";
  open(OUT,           ">:utf8",$stammdateien_ref->{$type}{outfile})        || die "OUT konnte nicht geoeffnet werden";
  open(OUTFIELDS,     ">:utf8",$stammdateien_ref->{$type}{outfile_fields})     || die "OUTFIELDS konnte nicht geoeffnet werden";
  open(OUTNORMFIELDS, ">:utf8",$stammdateien_ref->{$type}{outfile_normfields}) || die "OUTNORMFIELDS konnte nicht geoeffnet werden";

  my $id;
  my ($category,$mult,$content);
  my $record_ref = {};
 CATLINE:
  while (my $line=<IN>){


    if ($line=~m/^0000:(.+)$/){
        $record_ref = {};
        $id         = $1;
    }
    elsif ($line=~m/^9999:/){
        # Primaeren Normdatensatz erstellen und schreiben

        my $create_tstamp = 0;

        if (exists $record_ref->{'0100'} && exists $record_ref->{'0100'}[0]){
            $create_tstamp = $record_ref->{'0100'}[0]{content};
            if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/){
                $create_tstamp=$3.$2.$1;
            }
        }

        my $update_tstamp = 0;
        
        if (exists $record_ref->{'0101'} && exists $record_ref->{'0101'}[0]){
            $update_tstamp = $record_ref->{'0101'}[0]{content};
            if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/){
                $update_tstamp=$3.$2.$1;
            }

        }
        
        print OUT "$id$create_tstamp$update_tstamp\n";
        
        # Abhaengige Feldspezifische Saetze erstellen und schreiben
        
        foreach my $field (keys %{$record_ref}){
            foreach my $item_ref (@{$record_ref->{$field}}){
                print OUTFIELDS "$id$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
            }
        }
        
        # Abhaengige normalisierte Feldspezifische Saetze erstellen und schreiben

        foreach my $field (keys %{$record_ref}){
            foreach my $item_ref (@{$record_ref->{$field}}){

                my $contentnorm   = "";
                if (defined $field && exists $stammdateien_ref->{$type}{inverted_ref}->{$field}){
                    $contentnorm = OpenBib::Common::Util::grundform({
                        category => $field,
                        content  => $item_ref->{content},
                    });
                }
                
                
                if (exists $stammdateien_ref->{$type}{inverted_ref}{$field}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{$type}{inverted_ref}{$field}->{index}}){
                        my $weight = $stammdateien_ref->{$type}{inverted_ref}{$field}->{index}{$searchfield};
                        
                        push @{$stammdateien_ref->{$type}{data}{$id}{$searchfield}{$weight}}, $contentnorm;
                    }
                }
                
                
                print OUTNORMFIELDS "$id$field$item_ref->{mult}$item_ref->{subfield}$contentnorm\n";
            }
        }


        # Ansetzungsformen fuer Kurztitelliste merken

        my $mainentry;
        
        if (exists $record_ref->{'0001'} && exists $record_ref->{'0001'}[0] ){
            $mainentry = $record_ref->{'0001'}[0]{content};
        }
        
        if ($mainentry){
            if ($type eq "person"){
                $listitemdata_person{$id}=$mainentry;
            }
            elsif ($type eq "corporatebody"){
                $listitemdata_corporatebody{$id}=$mainentry;
            }
            elsif ($type eq "classification"){
                $listitemdata_classification{$id}=$mainentry;
            }
            elsif ($type eq "subject"){
                $listitemdata_subject{$id}=$mainentry;
            }
        }

        if ($type eq "Person" && exists $record_ref->{'0200'} && exists $record_ref->{'0200'}[0]){
            my $lifedates = $record_ref->{'0200'}[0]{content};
            
            if ($lifedates){
                $listitemdata_person_date{$id}=$lifedates;
            }
        }

        next CATLINE;
    }
    elsif ($line=~m/^\d\d\d\d/){

        if ($line=~m/^(\d+)\.(\d+):(.*?)$/){
            ($category,$mult,$content)=($1,$2,$3);
        }
        elsif ($line=~m/^(\d+):(.*?)$/){
            ($category,$mult,$content)=($1,1,$2);
        }
        else {
            $logger->error("Can't parse line: $line");
            next CATLINE;
        }

        next CATLINE unless (defined $content && defined $category);

        chomp($content);

        next CATLINE if (exists $stammdateien_ref->{$type}{blacklist_ref}->{$category});

        # Todo: Indikatoren auswerten

#         if ($record->have_indicators($content){
#             foreach my $subcontent ($record->content_per_indicator($content)){
#                 $record->set_category({ category => $category, mult => $mult, indicator => $subcontent->{indicator}, content => $subcontent->{content} });
#             }
#         }
        # Kategorie in Record setzen

        push @{$record_ref->{$category}}, {
            mult => $mult, subfield => '', content => $content,
        };
        
        
    }
  }

  close(OUT);
  close(OUTFIELDS);
  close(OUTNORMFIELDS);

  close(IN);
}

#######################

$stammdateien_ref->{holding} = {
    infile             => "meta.holding",
    outfile            => "holding.mysql",
    outfile_fields     => "holding_fields.mysql",
    outfile_normfields => "holding_normfields.mysql",
    inverted_ref       => $conv_config->{inverted_holding},
};

$logger->info("Bearbeite meta.holding");

open(IN ,          "<:utf8","meta.holding"        ) || die "IN konnte nicht geoeffnet werden";
open(OUT,          ">:utf8","holding.mysql"       ) || die "OUT konnte nicht geoeffnet werden";
open(OUTFIELDS,    ">:utf8","holding_fields.mysql"    ) || die "OUTFIELDS konnte nicht geoeffnet werden";
open(OUTNORMFIELDS,">:utf8","holding_normfields.mysql") || die "OUTNORMFIELDS konnte nicht geoeffnet werden";
open(OUTTITLETITLE,         ">:utf8","title_title.mysql")           || die "OUTTITLETITLE konnte nicht geoeffnet werden";
open(OUTTITLEHOLDING,       ">:utf8","title_holding.mysql")         || die "OUTTITLEHOLDING konnte nicht geoeffnet werden";
open(OUTTITLEPERSON,        ">:utf8","title_person.mysql")          || die "OUTTITLEPERSON konnte nicht geoeffnet werden";
open(OUTTITLECORPORATEBODY, ">:utf8","title_corporatebody.mysql")    || die "OUTTITLECORPORATEBODY konnte nicht geoeffnet werden";
open(OUTTITLESUBJECT,       ">:utf8","title_subject.mysql")         || die "OUTTITLESUBJECT konnte nicht geoeffnet werden";
open(OUTTITLECLASSIFICATION,">:utf8","title_classification.mysql")  || die "OUTTITLECLASSIFICATION konnte nicht geoeffnet werden";

my $id;
my $titleid;
my $thisyear = `date +"%Y"`;

my ($category,$mult,$content);
my $record_ref = {};
CATLINE:
while (my $line=<IN>){
    
    if ($line=~m/^0000:(.+)$/){
        $record_ref = {};
        $id         = $1;
    }
    elsif ($line=~m/^9999:/){
        # Primaeren Normdatensatz erstellen und schreiben
        
        print OUT "$id\n";
        
        # Abhaengige Feldspezifische Saetze erstellen und schreiben
        
        foreach my $field (keys %{$record_ref}){
            foreach my $item_ref (@{$record_ref->{$field}}){
                print OUTFIELDS "$id$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
            }
        }
        
        # Abhaengige normalisierte Feldspezifische Saetze erstellen und schreiben
        
        foreach my $field (keys %{$record_ref}){
            foreach my $item_ref (@{$record_ref->{$field}}){

                my $contentnorm   = "";
                if (defined $field && exists $stammdateien_ref->{holding}{inverted_ref}->{$field}){
                    $contentnorm = OpenBib::Common::Util::grundform({
                        category => $field,
                        content  => $item_ref->{content},
                    });
                }
                
                
                if (exists $stammdateien_ref->{holding}{inverted_ref}{$field}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{holding}{inverted_ref}{$field}->{index}}){
                        my $weight = $stammdateien_ref->{holding}{inverted_ref}{$field}->{index}{$searchfield};
                        
                        push @{$stammdateien_ref->{holding}{data}{$id}{$searchfield}{$weight}}, $contentnorm;
                    }
                }
                
                
                print OUTNORMFIELDS "$id$field$item_ref->{mult}$item_ref->{subfield}$contentnorm\n";
            }
        }

        # Titelid bestimmen

        my $titleid;
        
        if (exists $record_ref->{'0004'} && exists $record_ref->{'0004'}[0] ){
            $titleid = $record_ref->{'0004'}[0]{content};
        }

        # Verknupefungen
        if ($titleid){
            print OUTTITLEHOLDING "$titleid$id\n";
        }
        
        # Signatur fuer Kurztitelliste merken
        
        if (exists $record_ref->{'0014'} && $titleid){
            my $array_ref=exists $listitemdata_holding{$titleid}?$listitemdata_holding{$titleid}:[];
            push @$array_ref, $record_ref->{'0014'}[0]{content};
            $listitemdata_holding{$titleid}=$array_ref;
        }
        
        # Bestandsverlauf in Jahreszahlen umwandeln
        if (exists $record_ref->{'1204'} && $titleid){        
            my $array_ref=exists $listitemdata_enriched_years{$titleid}?$listitemdata_enriched_years{$titleid}:[];
            
            foreach my $date (split(";",$record_ref->{'1204'}[0]{content})){
                if ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-\s+.*?(\d\d\d\d)/){
                    my $startyear = $1;
                    my $endyear   = $2;
                    
                    $logger->info("Expanding yearstring $date from $startyear to $endyear");
                    for (my $year=$startyear;$year<=$endyear; $year++){
                        $logger->debug("Adding year $year");
                        push @$array_ref, $year;
                    }
                }
                elsif ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-/){
                    my $startyear = $1;
                    my $endyear   = $thisyear;
                    $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                    for (my $year=$startyear;$year<=$endyear;$year++){
                        $logger->info("Adding year $year");
                        push @$array_ref, $year;
                    }                
                }
                elsif ($date =~/(\d\d\d\d)/){
                    $logger->debug("Not expanding $date, just adding year $1");
                    push @$array_ref, $1;
                }
            }
            
            $listitemdata_enriched_years{$titleid}=$array_ref;
        }
        
        

        next CATLINE;
    }
    elsif ($line=~m/^\d\d\d\d/){

        if ($line=~m/^(\d+)\.(\d+):(.*?)$/){
            ($category,$mult,$content)=($1,$2,$3);
        }
        elsif ($line=~m/^(\d+):(.*?)$/){
            ($category,$mult,$content)=($1,1,$2);
        }
        else {
            $logger->error("Can't parse line: $line");
            next CATLINE;
        }

        next CATLINE unless (defined $content && defined $category);

        chomp($content);

        next CATLINE if (exists $stammdateien_ref->{holding}{blacklist_ref}->{$category});

        # Todo: Indikatoren auswerten

#         if ($record->have_indicators($content){
#             foreach my $subcontent ($record->content_per_indicator($content)){
#                 $record->set_category({ category => $category, mult => $mult, indicator => $subcontent->{indicator}, content => $subcontent->{content} });
#             }
#         }
        # Kategorie in Record setzen

        push @{$record_ref->{$category}}, {
            mult => $mult, subfield => '', content => $content,
        };
        
        
    }
}

close(OUT);
close(OUTFIELDS);
close(OUTNORMFIELDS);
close(IN);

$stammdateien_ref->{title} = {
    infile             => "meta.title",
    outfile            => "title.mysql",
    outfile_fields     => "title_fields.mysql",
    outfile_normfields => "title_normfields.mysql",
    inverted_ref       => $conv_config->{inverted_title},
    blacklist_ref      => $conv_config->{blacklist_title},
};

if ($addsuperpers){
    $logger->info("Option addsuperpers ist aktiviert");
    $logger->info("1. Durchgang: Uebergeordnete Titel-ID's finden");
    open(IN ,           "<:utf8","meta.title"          ) || die "IN konnte nicht geoeffnet werden";

    while (my $line=<IN>){
        if ($line=~m/^0004.*?:(.+)/){
            my $superid=$1;
            $listitemdata_superid{$superid}=1;
        }
    }
    close(IN);

    $logger->info("2. Durchgang: Verfasser-ID's in uebergeordneten Titeln finden");
    open(IN ,           "<:utf8","meta.title"          ) || die "IN konnte nicht geoeffnet werden";

    my ($id,@persids);

    while (my $line=<IN>){
        if ($line=~m/^0000:(.+)$/){            
            $id=$1;
            @persids=();
        }
        elsif ($line=~m/^9999:/){
            if ($#persids >= 0){
                $listitemdata_superid{$id}=join(":",@persids);
            }
        }
        elsif ($line=~m/^010[0123].*?:IDN: (\S+)/){
            my $persid=$1;
            if (exists $listitemdata_superid{$id}){
                push @persids, $persid;
            }
        }
    }

    close(IN);
}

$logger->info("Bearbeite meta.title");

open(IN ,           "<:utf8","meta.title"         )     || die "IN konnte nicht geoeffnet werden";
open(OUT,           ">:utf8","title.mysql"        )     || die "OUT konnte nicht geoeffnet werden";
open(OUTFIELDS,     ">:utf8","title_fields.mysql"     ) || die "OUTFIELDS konnte nicht geoeffnet werden";
open(OUTNORMFIELDS, ">:utf8","title_normfields.mysql" ) || die "OUTNORMFIELDS konnte nicht geoeffnet werden";
open(SEARCHENGINE,  ">:utf8","searchengine.csv" )       || die "SEARCHENGINE konnte nicht goeffnet werden";


my $id;
my $count = 0;

my ($category,$mult,$content);
$record_ref = {};
CATLINE:
while (my $line=<IN>){
    
    if ($line=~m/^0000:(.+)$/){
        $count++;

        $record_ref = {};
        $id         = $1;
    }
    elsif ($line=~m/^9999:/){
        my $titlecache_ref   = {}; # Inhalte fuer den Titel-Cache
        my $searchengine_ref = {}; # Inhalte fuer die Suchmaschinen

        # Basisinformationen setzen
        {
            push @{$searchengine_ref->{id}{1}}, $id;
            push @{$searchengine_ref->{dbstring}{1}}, $database;
            push @{$searchengine_ref->{facet_database}}, $database;
            
            $titlecache_ref->{id}       = $id;
            $titlecache_ref->{database} = $database;
        }
        
        # Popularitaet verarbeiten fuer titlecache / searchengine
        {
            if (exists $listitemdata_popularity{$id}){
                if (exists $conv_config->{'listitemcat'}{popularity}){
                    $titlecache_ref->{popularity} = $listitemdata_popularity{$id};
                }
                
                push @{$searchengine_ref->{popularity}{1}}, $listitemdata_popularity{$id};
            }
        }

        # Tags verarbeiten fuer titlecache / searchengine
        {
            if (exists $listitemdata_tags{$id}){
                if (exists $conv_config->{'listitemcat'}{tags}){
                    $titlecache_ref->{tag} = $listitemdata_tags{$id};
                }
                
                foreach my $tag_ref (@{$listitemdata_tags{$id}}){
                    
                    if (exists $stammdateien_ref->{title}{inverted_ref}{tag}->{index}){
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{tag}->{index}}){
                            my $weight = $stammdateien_ref->{title}{inverted_ref}{tag}->{index}{$searchfield};
                            
                            push @{$searchengine_ref->{$searchfield}{$weight}}, OpenBib::Common::Util::grundform({
                                content  => $tag_ref->{tag},
                            });
                        }
                    }
                    
                    if (exists $stammdateien_ref->{title}{inverted_ref}{tag}->{facet}){
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{tag}->{facet}}){
                            push @{$searchengine_ref->{"facet_$searchfield"}}, $tag_ref->{tag};
                        }
                    }
                }
                
                $logger->info("Adding Tags to ID $id");
            }
        }

        # Literaturlisten verarbeiten fuer titlecache / searchengine
        {
            if (exists $listitemdata_litlists{$id}){
                if (exists $conv_config->{'listitemcat'}{litlists}){
                    $titlecache_ref->{litlist} = $listitemdata_litlists{$id};
                }
                
                foreach my $litlist_ref (@{$listitemdata_litlists{$id}}){
                    if (exists $stammdateien_ref->{title}{inverted_ref}{litlist}->{index}){
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{litlist}->{index}}){
                            my $weight = $stammdateien_ref->{title}{inverted_ref}{litlist}->{index}{$searchfield};
                            push @{$searchengine_ref->{$searchfield}{$weight}}, OpenBib::Common::Util::grundform({
                                content  => $litlist_ref->{title},
                            });
                        }
                    }
                    
                    if (exists $stammdateien_ref->{title}{inverted_ref}{litlist}->{facet}){
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{litlist}->{facet}}){
                            push @{$searchengine_ref->{"facet_$searchfield"}}, $litlist_ref->{title};
                        }
                    }
                }            
                
                $logger->info("Adding Listlists to ID $id");
            }
        }
        
        my @superids         = (); # IDs der Ueberordnungen fuer Schiller-Raeuber-Anreicherung

        my @isbn13           = ();
        
        my @person                 = ();
        my @corporatebody          = ();
        my @subject                = ();
        my @classification         = ();
        my @isbn                   = ();
        my @issn                   = ();
        my @personcorporatebody    = ();
                
        # Verknuepfungskategorien bearbeiten

        if (exists $record_ref->{'0004'}){
            foreach my $item_ref (@{$record_ref->{'0004'}}){
                my ($target_titleid) = $item_ref->{content}=~m/^(.+)/;
                my $source_titleid   = $id;
                my $supplement       = "";
                my $field            = "0004";
                
                if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}){
                        my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                        
                        push @{$searchengine_ref->{$searchfield}{$weight}}, $target_titleid;
                    }
                }
                
                if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}){
                        push @{$searchengine_ref->{"facet_".$searchfield}}, $item_ref->{content};
                    }
                }
                
                push @superids, $target_titleid;
                
                #            print OUT           "$id$category$indicator$content\n";
                print OUTTITLETITLE "$field$source_titleid$target_titleid$supplement\n";
            }
        }

        # Verfasser/Personen
#        $logger->info(YAML::Dump($record_ref));

        foreach my $field ('0100','0101','0102','0103','1800'){
            if (exists $record_ref->{$field}){
                foreach my $item_ref (@{$record_ref->{$field}}){
                    # Verknuepfungsfelder werden ignoriert
                    $item_ref->{ignore} = 1;
                    
                    my ($personid) = $item_ref->{content}=~m/^IDN: (\S+)/;
                    my $titleid    = $id;
                    my $supplement = "";

                    # Feld 1800 wird als 0100 behandelt
                    if ($field eq "1800"){
                        $field = "0100";   
                    }

                    next unless $personid;

                    if ($item_ref->{content}=~m/^IDN: \S+ ; (.+)/){
                        $supplement = $1;
                    }
                    
                    print OUTTITLEPERSON "$field$id$personid$supplement\n";
                    
                    # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                    # auch wirklich existiert -> schlechte Katalogisate
                    if (exists $listitemdata_person{$personid}){
                        push @person, $personid;
                        
                        my $mainentry = $listitemdata_person{$personid};
                        
                        # Verweisung durch Ansetzungsform ersetzen
                        $item_ref->{content} = $mainentry;
                        
                        push @{$titlecache_ref->{"P$field"}}, {
                            id      => $personid,
                            type    => 'person',
                            content => $mainentry,
                            supplement => $supplement,
                        } if (exists $conv_config->{listitemcat}{$field});
                        
                        push @personcorporatebody, $mainentry;
                        
                        # Searchengine
                        if ($addpersondate){
                            my $date = $listitemdata_person_date{$personid};
                            if ($date){
                                $mainentry = "$mainentry ($date)";
                            }
                        }
                        
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}){                    
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}){
                                my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                                
                                my $mainentrynorm = OpenBib::Common::Util::grundform({
                                    category => $field,
                                    content  => $mainentry,
                                });
                                push @{$searchengine_ref->{$searchfield}{$weight}}, $mainentrynorm;
                            }
                        }
                        
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}){
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}){
                                push @{$searchengine_ref->{"facet_".$searchfield}}, $mainentry;
                            }
                        }
                    }
                    else {
                        $logger->error("PER ID $personid doesn't exist in TITLE ID $id");
                    }
                }
            }
        }

        # Bei 1800 ohne Normdatenverknuepfung muss der Inhalt analog verarbeitet werden
        if (exists $record_ref->{'1800'}){
            foreach my $item_ref (@{$record_ref->{'1800'}}){
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;

                unless ($item_ref->{content}=~m/^IDN: \S+/){
                    my $field = '1800';
                    
                    push @personcorporatebody, $item_ref->{content};
                    
                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}){                    
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}){
                            my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                            my $contentnormtmp = $item_ref->{norm} || OpenBib::Common::Util::grundform({
                                category => $category,
                                content  => $item_ref->{content},
                            });
                            push @{$searchengine_ref->{$searchfield}{$weight}}, $contentnormtmp;
                        }
                    }
                    
                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}){
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}){
                            push @{$searchengine_ref->{"facet_".$searchfield}}, $item_ref->{content};
                        }
                    }                
                }
            }
        }
            
        #Koerperschaften/Urheber
        foreach my $field ('0200','0201','1802'){
            if (exists $record_ref->{$field}){
                foreach my $item_ref (@{$record_ref->{$field}}){
                    # Verknuepfungsfelder werden ignoriert
                    $item_ref->{ignore} = 1;
                    
                    my ($corporatebodyid) = $item_ref->{content}=~m/^IDN: (\S+)/;
                    my $titleid    = $id;
                    my $supplement = "";
                    
                    # Feld 1802 wird als 0200 behandelt
                    if ($field eq "1802"){
                        $field = "0200";   
                    }
                    
                    next unless $corporatebodyid;
                    
                    print OUTTITLECORPORATEBODY "$field$id$corporatebodyid$supplement\n";
                    
                    # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                    # auch wirklich existiert -> schlechte Katalogisate
                    if (exists $listitemdata_corporatebody{$corporatebodyid}){
                        push @corporatebody, $corporatebodyid;
                        
                        my $mainentry = $listitemdata_corporatebody{$corporatebodyid};
                        
                        # Verweisung durch Ansetzungsform ersetzen
                        $item_ref->{content} = $mainentry;
                        
                        push @{$titlecache_ref->{"C$field"}}, {
                            id      => $corporatebodyid,
                            type    => 'corporatebody',
                            content => $mainentry,
                            supplement => $supplement,
                        } if (exists $conv_config->{listitemcat}{$field});
                        
                        push @personcorporatebody, $mainentry;
                        
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}){                    
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}){
                                my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                                
                                my $mainentrynorm = OpenBib::Common::Util::grundform({
                                    category => $field,
                                    content  => $mainentry,
                                });
                                push @{$searchengine_ref->{$searchfield}{$weight}}, $mainentrynorm;
                            }
                        }
                        
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}){
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}){
                                push @{$searchengine_ref->{"facet_".$searchfield}}, $mainentry;
                            }
                        }
                    }
                    else {
                        $logger->error("CORPORATEBODY ID $corporatebodyid doesn't exist in TITLE ID $id");
                    }
                }
            }
        }
        
        # Bei 1802 ohne Normdatenverknuepfung muss der Inhalt analog verarbeitet werden
        if (exists $record_ref->{'1802'}){
            foreach my $item_ref (@{$record_ref->{'1802'}}){
                # Verknuepfungsfelder werden ignoriert
                $item_ref->{ignore} = 1;
                
                unless ($item_ref->{content}=~m/^IDN: \S+/){
                    my $field = '1802';
                    
                    push @personcorporatebody, $item_ref->{content};
                    
                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}){                    
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}){
                            my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                            my $contentnormtmp = $item_ref->{norm} || OpenBib::Common::Util::grundform({
                                category => $category,
                                content  => $item_ref->{content},
                            });
                            push @{$searchengine_ref->{$searchfield}{$weight}}, $contentnormtmp;
                        }
                    }
                    
                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}){
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}){
                            push @{$searchengine_ref->{"facet_".$searchfield}}, $item_ref->{content};
                        }
                    }                
                }
            }
        }
        
                
        # Klassifikation
        foreach my $field ('0700') {
            if (exists $record_ref->{$field}) {
                foreach my $item_ref (@{$record_ref->{$field}}) {
                    # Verknuepfungsfelder werden ignoriert
                    $item_ref->{ignore} = 1;
                            
                    my ($classificationid) = $item_ref->{content}=~m/^IDN: (\S+)/;
                    my $titleid    = $id;
                    my $supplement = "";
                              
                    next unless $classificationid;
                            
                    print OUTTITLECLASSIFICATION "$field$id$classificationid$supplement\n";
                            
                    # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                    # auch wirklich existiert -> schlechte Katalogisate
                    if (exists $listitemdata_classification{$classificationid}) {
                        push @classification, $classificationid;
                                
                        my $mainentry = $listitemdata_classification{$classificationid};
                                
                                # Verweisung durch Ansetzungsform ersetzen
                        $item_ref->{content} = $mainentry;
                                
                        push @{$titlecache_ref->{"N$field"}}, {
                            id      => $classificationid,
                            type    => 'classification',
                            content => $mainentry,
                            supplement => $supplement,
                        } if (exists $conv_config->{listitemcat}{$field});
                                
                        push @personcorporatebody, $mainentry;
                                                                
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {                    
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}) {
                                my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                                        
                                my $mainentrynorm = $item_ref->{norm} || OpenBib::Common::Util::grundform({
                                    category => $field,
                                    content  => $mainentry,
                                });
                                push @{$searchengine_ref->{$searchfield}{$weight}}, $mainentrynorm;
                            }
                        }
                                
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}) {
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}) {
                                push @{$searchengine_ref->{"facet_".$searchfield}}, $mainentry;
                            }
                        }
                    }
                    else {
                        $logger->error("SYS ID $classificationid doesn't exist in TITLE ID $id");
                    }
                }
            }
        }
                
        # Schlagworte
        foreach my $field ('0710','0902','0907','0912','0917','0922','0927','0932','0937','0942','0947') {
            if (exists $record_ref->{$field}) {
                foreach my $item_ref (@{$record_ref->{$field}}) {
                    # Verknuepfungsfelder werden ignoriert
                    $item_ref->{ignore} = 1;
                            
                    my ($subjectid) = $item_ref->{content}=~m/^IDN: (\S+)/;
                    my $titleid    = $id;
                    my $supplement = "";
                              
                    next unless $subjectid;
                            
                    print OUTTITLESUBJECT "$field$id$subjectid$supplement\n";
                            
                    # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
                    # auch wirklich existiert -> schlechte Katalogisate
                    if (exists $listitemdata_subject{$subjectid}) {
                        push @subject, $subjectid;
                                
                        my $mainentry = $listitemdata_subject{$subjectid};
                                
                                # Verweisung durch Ansetzungsform ersetzen
                        $item_ref->{content} = $mainentry;
                                
                        push @{$titlecache_ref->{"S$field"}}, {
                            id      => $subjectid,
                            type    => 'subject',
                            content => $mainentry,
                            supplement => $supplement,
                        } if (exists $conv_config->{listitemcat}{$field});
                                
                        push @personcorporatebody, $mainentry;
                                                                
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {                    
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}) {
                                my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                                        
                                my $mainentrynorm = OpenBib::Common::Util::grundform({
                                    category => $field,
                                    content  => $mainentry,
                                });
                                push @{$searchengine_ref->{$searchfield}{$weight}}, $mainentrynorm;
                            }
                        }
                                
                        if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}) {
                            foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{facet}}) {
                                push @{$searchengine_ref->{"facet_".$searchfield}}, $mainentry;
                            }
                        }
                    }
                    else {
                        $logger->error("SYS ID $subjectid doesn't exist in TITLE ID $id");
                    }
                }
            }
        }


        # Suchmaschinen eintraege mit den Standard-Titelkategorien fuellen
        {
            foreach my $field (keys %{$record_ref}) {
                foreach my $item_ref (@{$record_ref->{$field}}) {
                    next if ($item_ref->{ignore});
                
                    my $contentnorm   = "";
                    if (defined $field && exists $stammdateien_ref->{title}{inverted_ref}->{$field}) {
                        $contentnorm = OpenBib::Common::Util::grundform({
                            category => $field,
                            content  => $item_ref->{content},
                        });
                    }

                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}) {
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}) {
                            my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                            if ($searchfield eq "isbn") {
                                # Alternative ISBN zur Rechercheanreicherung erzeugen
                                my $isbn = Business::ISBN->new($contentnorm);
                            
                                if (defined $isbn && $isbn->is_valid) {
                                    my $isbnXX;
                                    if (length($contentnorm) == 10) {
                                        $isbnXX = $isbn->as_isbn13;
                                    } else {
                                        $isbnXX = $isbn->as_isbn10;
                                    }
                                
                                    if (defined $isbnXX) {
                                        if (!exists $searchengine_ref->{isbn13}{1}) {
                                            my $isbn13 = OpenBib::Common::Util::grundform({
                                                category => $category,
                                                content  => $isbnXX->as_isbn13->as_string,
                                            });
                                            push @isbn13, $isbn13;
                                            push @{$searchengine_ref->{isbn13}{1}}, $isbn13;
                                            push @{$searchengine_ref->{freesearch}{1}}, $isbn13;
                                            # push @{$searchengine_ref->{freesearch}{1}}, $contentnorm;
                                        }
                                    }
                                }
                            }
                            push @{$searchengine_ref->{$searchfield}{$weight}}, $contentnorm;
                        }
                    }

                    if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{facet}) {
                        foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}) {
                            push @{$searchengine_ref->{"facet_".$searchfield}}, $item_ref->{content};
                        }
                    }
                }
            }
        }
        
        # Personen der Ueberordnung anreichern (Schiller-Raeuber)
        if ($addsuperpers){
            foreach my $superid (@superids){
                if (exists $listitemdata_superid{$superid}){
                    my @superpersids = split (":",$listitemdata_superid{$superid}); 
                    push @person, @superpersids;
                }
            }
        }
        
        # Zentrale Anreicherungsdaten lokal einspielen
        if ($local_enrichmnt && (exists $searchengine_ref->{isbn13} || exists $searchengine_ref->{issn})){
            foreach my $field (keys %{$conv_config->{local_enrichmnt}}){
                my $enrichmnt_data_ref = [];
                if    (exists $searchengine_ref->{isbn13}){
                    foreach my $weight (keys %{$searchengine_ref->{isbn13}}){
                        foreach my $isbn13 (@{$searchengine_ref->{isbn13}{$weight}}){
                            if (exists $enrichmntdata{$isbn13}{$field}){
                                push @$enrichmnt_data_ref, @{$enrichmntdata{$isbn13}{$field}};
                            }
                        }
                    }
                }
                elsif (exists $searchengine_ref->{issn}){
                    foreach my $weight (keys %{$searchengine_ref->{issn}}){
                        foreach my $issn (@{$searchengine_ref->{issn}{$weight}}){
                            if (exists $enrichmntdata{$issn}{$field}){
                                push @$enrichmnt_data_ref, @{$enrichmntdata{$issn}{$field}};
                            }
                        }
                    }
                }
                
                if ($enrichmnt_data_ref){
                    my $mult = 1;
                    foreach my $content (@{$enrichmnt_data_ref}){
                        $content = decode_utf8($content);
                        
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });

                        # ToDo: Parametrisierbarkeit in convert.yml im Bereich search fuer
                        #       die Recherchierbarkeit via Suchmaschine
                        
                        $logger->debug("Id: $id - Adding $field -> $content");
                        push @{$record_ref->{$field}}, {
                            mult      => $mult,
                            content   => $content,
                            subfield  => '',
                        };
                        
                        $mult++;
                    }

                    # ToDo: Wird Suchmaschine hiermit befuellt?
                    
                    if (exists $conv_config->{'listitemcat'}{$field}){
                        push @{$titlecache_ref->{"T".$field}}, {
                            content => $content,
                        };
                    }
                
                }
            }
        }
    
    
        # Medientypen erkennen und anreichern
        if ($addmediatype){

            # Zeitschriften/Serien:
            # ISSN und/oder ZDB-ID besetzt
            if (exists $record_ref->{'0572'} || exists $record_ref->{'0543'}) {
                # Steht Medientyp schon auf Zeitschrift?
                my $have_journal   = 0;
                my $type_mult = 1;
                foreach my $item_ref (@{$record_ref->{'0800'}}){
                    $have_journal = 1 if ($item_ref->{content} eq "Zeitschrift/Serie");
                    $type_mult++;
                }

                if (!$have_journal){
                    if (! exists $searchengine_ref->{mediatype} ){
                        $searchengine_ref->{mediatype}{1} = [];
                    }
                    
                    push @{$searchengine_ref->{mediatype}{1}}, "Zeitschrift/Serie";

                    push @{$record_ref->{'0800'}}, {
                        mult      => $type_mult,
                        content   => 'Zeitschrift/Serie',
                        subfield  => '',
                    };
                }
            }   


            # Aufsatz
            # HSTQuelle besetzt
            if (exists $record_ref->{'0590'}) {
                # Steht Medientyp schon auf Aufsatz?
                my $have_article=0;
                my $type_mult = 1;
                foreach my $item_ref (@{$record_ref->{'0800'}}){
                    if ($item_ref->{content} eq "Aufsatz"){
                        $have_article = 1 ;
                    }
                    $type_mult++;
                }

                if (!$have_article){
                    if (! exists $searchengine_ref->{mediatype} ){
                        $searchengine_ref->{mediatype}{1} = [];
                    }

                    push @{$searchengine_ref->{mediatype}{1}}, "Aufsatz";
                    
                    push @{$record_ref->{'0800'}}, {
                        mult      => $type_mult,
                        content   => 'Aufsatz',
                        subfield  => '',
                    };
                }
            }   

            # Elektronisches Medium mit Online-Zugriff
            # Besetzung der folgenden Kategorien
            # [02]807:g
            # 0334:Elektronische Ressource
            # 0652:Online-Ressource
            #
            # Lizensiert:
            # [02]663.001:Info: Zugriff nur im Hochschulnetz der Universitaet Koeln bzw.
            #          fuer autorisierte Benutzer moeglich
            
            if (((exists $record_ref->{'0807'} && $record_ref->{'0807'}[0]{content} eq "g") || (exists $record_ref->{'2807'} && $record_ref->{'2807'}[0]{content} eq "g"))
                && exists $record_ref->{'0334'} && $record_ref->{'0334'}[0]{content} eq "Elektronische Ressource"
                    && exists $record_ref->{'0652'} && $record_ref->{'0652'}[0]{content} eq "Online-Ressource"){
                # Steht Medientyp schon auf Online-Zugriff?
                my $have_digital=0;
                my $type_mult = 1;
                foreach my $item_ref (@{$record_ref->{'0800'}}){
                    if ($item_ref->{content} eq "Digital"){
                        $have_digital = 1 ;
                    }
                    $type_mult++;
                }

                if (!$have_digital){
                    if (! exists $searchengine_ref->{mediatype} ){
                        $searchengine_ref->{mediatype}{1} = [];
                    }

                    push @{$searchengine_ref->{mediatype}{1}}, "Digital";

                    push @{$record_ref->{'0800'}}, {
                        mult      => $type_mult,
                        content   => 'Digital',
                        subfield  => '',
                    };
                }
            }   
            
            # mit Inhaltsverzeichnis
            # Anreicherungskategorie 4110
            if (exists $record_ref->{'4110'}) {
                my $have_toc=0;
                my $type_mult = 1;
                foreach my $item_ref (@{$record_ref->{'0800'}}){
                    $have_toc = 1 if ($item_ref->{content} eq "mit Inhaltsverzeichnis");
                    $type_mult++;
                }

                if (!$have_toc){
                    push @{$searchengine_ref->{mediatype}{1}}, "mit Inhaltsverzeichnis";

                    push @{$record_ref->{'0800'}}, {
                        mult      => $type_mult,
                        content   => 'mit Inhaltsverzeichnis',
                        subfield  => '',
                    };
                }
            }   
            
        } 


        # Indexierte Informationen aus anderen Normdateien fuer Suchmaschine
        {
            # Im Falle einer Personenanreicherung durch Ueberordnungen mit
            # -add-superpers sollen Dubletten entfernt werden.
            my %seen_person=();
            foreach my $item (@person){
                next if (exists $seen_person{$item});
                
                # ID-Merken fuer Recherche ueber Suchmaschine
                push @{$searchengine_ref->{'personid'}{1}}, $item;

                if (exists $stammdateien_ref->{person}{data}{$item}) {
                    foreach my $searchfield (keys %{$stammdateien_ref->{person}{data}{$item}}) {
                        foreach my $weight (keys %{$stammdateien_ref->{person}{data}{$item}{$searchfield}}) {                        
                            push @{$searchengine_ref->{$searchfield}{$weight}}, @{$stammdateien_ref->{person}{data}{$item}{$searchfield}{$weight}};
                        }
                    }
                }

                $seen_person{$item}=1;
            }

            foreach my $item (@corporatebody) {
                # ID-Merken fuer Recherche ueber Suchmaschine
                push @{$searchengine_ref->{'corporatebodyid'}{1}}, $item;

                if (exists $stammdateien_ref->{corporatebody}{data}{$item}) {
                    foreach my $searchfield (keys %{$stammdateien_ref->{corporatebody}{data}{$item}}) {
                        foreach my $weight (keys %{$stammdateien_ref->{corporatebody}{data}{$item}{$searchfield}}) {
                            push @{$searchengine_ref->{$searchfield}{$weight}}, @{$stammdateien_ref->{corporatebody}{data}{$item}{$searchfield}{$weight}};
                        }
                    }
                }
            }

            foreach my $item (@subject) {
                # ID-Merken fuer Recherche ueber Suchmaschine
                push @{$searchengine_ref->{'subjectid'}{1}}, $item;

                if (exists $stammdateien_ref->{subject}{data}{$item}) {
                    foreach my $searchfield (keys %{$stammdateien_ref->{subject}{data}{$item}}) {
                        foreach my $weight (keys %{$stammdateien_ref->{subject}{data}{$item}{$searchfield}}) {
                            push @{$searchengine_ref->{$searchfield}{$weight}}, @{$stammdateien_ref->{subject}{data}{$item}{$searchfield}{$weight}};
                        }
                    }
                }
            }

            foreach my $item (@classification) {
                # ID-Merken fuer Recherche ueber Suchmaschine
                push @{$searchengine_ref->{'classificationid'}{1}}, $item;

                if (exists $stammdateien_ref->{classification}{data}{$item}) {
                    foreach my $searchfield (keys %{$stammdateien_ref->{classification}{data}{$item}}) {
                        foreach my $weight (keys %{$stammdateien_ref->{classification}{data}{$item}{$searchfield}}) {
                            push @{$searchengine_ref->{$searchfield}{$weight}}, @{$stammdateien_ref->{classification}{data}{$item}{$searchfield}{$weight}};
                        }
                    }
                }
            }

#             if (exists $stammdateien_ref->{holding}{data}{$id}) {
#                 foreach my $searchfield (keys %{$stammdateien_ref->{holding}{data}{$id}}) {
#                     foreach my $weight (keys %{$stammdateien_ref->{holding}{data}{$id}{$searchfield}}) {
#                         push @{$searchengine_ref->{$searchfield}}, @{$stammdateien_ref->{holding}{data}{$id}{$searchfield}{$weight}};
#                     }
#                 }
#             }
        }
        
        # Listitem zusammensetzen
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
            if (!exists $titlecache_ref->{'T0331'}) {
                # UnterFall 2.1:
                if (exists $record_ref->{'0089'}) {
                    $titlecache_ref->{T0331}[0]{content}=$record_ref->{'0089'}[0]{content};
                }
                # Unterfall 2.2:
                elsif (exists $record_ref->{'0455'}) {
                    $titlecache_ref->{T0331}[0]{content}=$record_ref->{'0455'}[0]{content};
                }
                # Unterfall 2.3:
                elsif (exists $record_ref->{'0451'}) {
                    $titlecache_ref->{T0331}[0]{content}=$record_ref->{'0451'}[0]{content};
                }
                # Unterfall 2.4:
                elsif (exists $record_ref->{'1203'}) {
                    $titlecache_ref->{T0331}[0]{content}=$record_ref->{'1203'}[0]{content};
                }
                else {
                    $titlecache_ref->{T0331}[0]{content}="Kein HST/AST vorhanden";
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
            if (exists $record_ref->{'0089'}) {
                $titlecache_ref->{'T5100'}= [
                    {
                        content => $record_ref->{'0089'}[0]{content}
                    }
                ];
            }
            # Fall 2:
            elsif (exists $record_ref->{'0455'}) {
                $titlecache_ref->{'T5100'}= [
                    {
                        content => $record_ref->{'0455'}[0]{content}
                    }
                ];
            }
        
            # Exemplardaten-Hash zu listitem-Hash hinzufuegen

            foreach my $content (@{$listitemdata_holding{$id}}) {
                push @{$titlecache_ref->{'X0014'}}, {
                    content => $content,
                };
            }
        
            # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
            push @{$titlecache_ref->{'PC0001'}}, {
                content   => join(" ; ",@personcorporatebody),
            };
        }

        
        # Bibkey-Kategorie 5050 wird *immer* angereichert. Die Invertierung ist konfigurabel
        {
            my $bibkey_base = OpenBib::Common::Util::gen_bibkey_base({ normdata => $record_ref});
            my $bibkey      = OpenBib::Common::Util::gen_bibkey({ bibkey_base => $bibkey_base });
        
            if ($bibkey) {
                push @{$record_ref->{'5050'}}, {
                    mult      => 1,
                    content   => $bibkey,
                    subfield  => '',
                };

                push @{$record_ref->{'5051'}}, {
                    mult      => 1,
                    content   => $bibkey_base,
                    subfield   => '',
                };

                # Bibkey merken fuer Recherche ueber Suchmaschine
                push @{$searchengine_ref->{'bkey'}{1}}, $bibkey;
            }
        }
        
        # Automatische Anreicherung mit Bestandsjahren wenn kein
        # Erscheinungsjahr vorhanden, aber Bestandsverlauf besetzt.
        {
            if (!exists $searchengine_ref->{'year'} && !exists $searchengine_ref->{'T0424'} && !exists $searchengine_ref->{'T0425'}) {
                if (exists $listitemdata_enriched_years{$id}) {
                    foreach my $year (@{$listitemdata_enriched_years{$id}}) {
                        $logger->debug("Enriching year $year to Title-ID $id");
                        push @{$searchengine_ref->{year}{1}}, $year;
                        push @{$searchengine_ref->{freesearch}{1}}, $year;
                    }
                }
            } 
        }

        # Titlecache erstellen                
        foreach my $field (keys %{$record_ref}) {            
            # Kategorien in listitemcat werden fuer die Kurztitelliste verwendet
            if (exists $conv_config->{listitemcat}{$field}) {
                foreach my $item_ref (@{$record_ref->{$field}}) {
                    push @{$titlecache_ref->{"T".$field}}, $item_ref unless ($item_ref->{ignore});
                }
            }
        }        
        my $titlecache = encode_json $titlecache_ref;

        my $create_tstamp = 0;

        if (exists $record_ref->{'0002'} && exists $record_ref->{'0002'}[0]){
            $create_tstamp = $record_ref->{'0002'}[0]{content};
            if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/){
                $create_tstamp=$3.$2.$1;
            }
        }

        my $update_tstamp = 0;
        
        if (exists $record_ref->{'0003'} && exists $record_ref->{'0003'}[0]){
            $update_tstamp = $record_ref->{'0003'}[0]{content};
            if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/){
                $update_tstamp=$3.$2.$1;
            }

        }

        # Primaeren Normdatensatz erstellen und schreiben
        my $popularity = (exists $listitemdata_popularity{$id})?$listitemdata_popularity{$id}:0;
        
        print OUT "$id$create_tstamp$update_tstamp$titlecache$popularity\n";
        
        # Abhaengige Feldspezifische Saetze erstellen und schreiben
        
        foreach my $field (keys %{$record_ref}){
            foreach my $item_ref (@{$record_ref->{$field}}){
                next if ($item_ref->{ignore});

                print OUTFIELDS "$id$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
            }
        }
        
        # Abhaengige normalisierte Feldspezifische Saetze erstellen und schreiben
        
        foreach my $field (keys %{$record_ref}){
            foreach my $item_ref (@{$record_ref->{$field}}){
                next if ($item_ref->{ignore});
                
                if (defined $field && exists $stammdateien_ref->{title}{inverted_ref}->{$field}){
                    $item_ref->{norm} = OpenBib::Common::Util::grundform({
                        category => $field,
                        content  => $item_ref->{content},
                    });
                }
                
                if (exists $stammdateien_ref->{title}{inverted_ref}{$field}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$field}->{index}}){
                        my $weight = $stammdateien_ref->{title}{inverted_ref}{$field}->{index}{$searchfield};
                        
                        push @{$stammdateien_ref->{title}{data}{$id}{$searchfield}{$weight}}, $item_ref->{norm};
                    }
                }
                
#                $logger->info(defined($id).":".defined($field).":".defined($item_ref->{mult}).":".defined($item_ref->{subfield}).":".defined($item_ref->{norm}));

                print OUTNORMFIELDS "$id$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{norm}\n";
            }
        }                

        # Suchmaschinen-Daten schreiben
        my $searchengine = encode_json $searchengine_ref;
        print SEARCHENGINE "$id$searchengine\n";

        if ($count % 1000 == 0) {
            $logger->debug("$count Titelsaetze bearbeitet");
        } 

        next CATLINE;
    }
    elsif ($line=~m/^\d\d\d\d/){

        if ($line=~m/^(\d+)\.(\d+):(.*?)$/){
            ($category,$mult,$content)=($1,$2,$3);
        }
        elsif ($line=~m/^(\d+):(.*?)$/){
            ($category,$mult,$content)=($1,1,$2);
        }
        else {
            $logger->error("Can't parse line: $line");
            next CATLINE;
        }

        next CATLINE unless (defined $content && defined $category);

        chomp($content);

        next CATLINE if (exists $stammdateien_ref->{title}{blacklist_ref}->{$category});

        # Todo: Indikatoren auswerten

#         if ($record->have_indicators($content){
#             foreach my $subcontent ($record->content_per_indicator($content)){
#                 $record->set_category({ category => $category, mult => $mult, indicator => $subcontent->{indicator}, content => $subcontent->{content} });
#             }
#         }

        # Gegebenenfalls Inhalt indexieren (=wenn keine Verknuepfungen)
        my $norm = "";
        unless ($content =~/^IDN: \S+/){
            if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){                    
                $norm = OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
        }
        
        # Kategorie in Record setzen
        push @{$record_ref->{$category}}, {
            mult     => $mult,
            subfield => '',
            content  => $content,
            norm     => $norm
        };
        
    }
}


close(OUT);
close(OUTFIELDS);
close(OUTNORMFIELDS);
close(OUT);
close(SEARCHENGINE);

close(IN);


#######################


open(CONTROL,        ">control.mysql");
open(CONTROLINDEXOFF,">control_index_off.mysql");
open(CONTROLINDEXON, ">control_index_on.mysql");

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROLINDEXOFF << "DISABLEKEYS";
alter table $type        disable keys;
alter table ${type}_fields     disable keys;
alter table ${type}_normfields disable keys;
DISABLEKEYS
}

print CONTROLINDEXOFF "alter table title_title        disable keys;\n";
print CONTROLINDEXOFF "alter table title_person        disable keys;\n";
print CONTROLINDEXOFF "alter table title_corporatebody        disable keys;\n";
print CONTROLINDEXOFF "alter table title_subject        disable keys;\n";
print CONTROLINDEXOFF "alter table title_classification        disable keys;\n";
print CONTROLINDEXOFF "alter table title_holding        disable keys;\n";

foreach my $type (keys %{$stammdateien_ref}){
    if (!$incremental){
        print CONTROL << "ITEMTRUNC";
truncate table $type;
truncate table ${type}_fields;
truncate table ${type}_normfields;
ITEMTRUNC
    }

    print CONTROL << "ITEM";
load data local infile '$dir/$stammdateien_ref->{$type}{outfile}'        into table $type        fields terminated by '' ;
load data local infile '$dir/$stammdateien_ref->{$type}{outfile_fields}'     into table ${type}_fields     fields terminated by '' ;
load data local infile '$dir/$stammdateien_ref->{$type}{outfile_normfields}' into table ${type}_normfields fields terminated by '' ;
ITEM
}

if (!$incremental){
    print CONTROL << "TITLEITEMTRUNC";
truncate table title_title;
truncate table title_person;
truncate table title_corporatebody;
truncate table title_subject;
truncate table title_classification;
truncate table title_holding;
TITLEITEMTRUNC
}
    
print CONTROL << "TITLEITEM";
load data local infile '$dir/title_title.mysql'        into table title_title   fields terminated by '' ;
load data local infile '$dir/title_person.mysql'        into table title_person   fields terminated by '' ;
load data local infile '$dir/title_corporatebody.mysql'        into table title_corporatebody   fields terminated by '' ;
load data local infile '$dir/title_subject.mysql'        into table title_subject   fields terminated by '' ;
load data local infile '$dir/title_classification.mysql'        into table title_classification   fields terminated by '' ;
load data local infile '$dir/title_holding.mysql'        into table title_holding   fields terminated by '' ;
TITLEITEM

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROLINDEXON << "ENABLEKEYS";
alter table $type          enable keys;
alter table ${type}_fields     enable keys;
alter table ${type}_normfields enable keys;
ENABLEKEYS
}

print CONTROLINDEXON "alter table title_title           enable keys;\n";
print CONTROLINDEXON "alter table title_person           enable keys;\n";
print CONTROLINDEXON "alter table title_corporatebody           enable keys;\n";
print CONTROLINDEXON "alter table title_subject           enable keys;\n";
print CONTROLINDEXON "alter table title_classification           enable keys;\n";
print CONTROLINDEXON "alter table title_holding           enable keys;\n";

close(CONTROL);
close(CONTROLINDEXOFF);
close(CONTROLINDEXON);

if ($reducemem){
    untie %listitemdata_person;
    untie %listitemdata_corporatebody;
    untie %listitemdata_classification;
    untie %listitemdata_subject;
    untie %listitemdata_holding;
    untie %listitemdata_superid;
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
   -incremental          : Incrementelle Aktualisierung (experimentell)
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
