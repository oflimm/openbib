#!/usr/bin/perl

#####################################################################
#
#  enrich_meta.pl
#
#  Anreicherung des Meta-Formats mit Daten aus der Anreicherungs-Datenbank
#
#  Herausgeloest aus OpenBib::Importer::JSON::Title
#
#  Dieses File ist (C) 1997-2024 Oliver Flimm <flimm@openbib.org>
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

my ($database,$scheme,$filename,$keepfiles,$logfile,$loglevel,$count,$help);

&GetOptions(
    "database=s"     => \$database,
    "filename=s"     => \$filename,
    "scheme=s"       => \$scheme,
    "keep-files"     => \$keepfiles,
    "logfile=s"      => \$logfile,
    "loglevel=s"     => \$loglevel,
    "help"           => \$help,
);

if ($help) {
    print_help();
}

my $config      = OpenBib::Config->new;
my $conv_config = OpenBib::Conv::Config->instance({dbname => $database});

$logfile=($logfile)?$logfile:"/var/log/openbib/enrich_meta/${database}.log";
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

if (!-d "/var/log/openbib/enrich_meta/"){
    mkdir "/var/log/openbib/enrich_meta/";
}

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $dir=`pwd`;
chop $dir;

my %enrichmntdata               = ();

if ($scheme){
    $logger->info("### $database: Using scheme $scheme");
}

$scheme = (defined $scheme)?$scheme:'mab2';

my $local_enrichmnt  = 0;
my $enrichmntdumpdir = $config->{autoconv_dir}."/data/enrichment";

if (exists $conv_config->{local_enrichmnt} && -e "$enrichmntdumpdir/enrichmntdata.db") {
    tie %enrichmntdata,           'MLDBM', "$enrichmntdumpdir/enrichmntdata.db"
        or die "Could not tie enrichment data.\n";

    $local_enrichmnt = 1;

    $logger->info("### $database: Lokale Einspielung mit zentralen Anreicherungsdaten aktiviert");
}

my $atime;

my $storage_ref = {
    'enrichmntdata'               => \%enrichmntdata,
};

my $normalizer = OpenBib::Normalizer->new;

my $actions_map_ref = {};

$logger->info("### $database: Bearbeite meta.title");

open(IN , $filename)     || die "IN konnte nicht geoeffnet werden";

binmode (IN, ":raw");

open(OUT, ">", "${filename}.enriched"         )     || die "OUT konnte nicht geoeffnet werden";

$count = 1;

$atime = new Benchmark;

my $importer = OpenBib::Importer::JSON::Title->new({
    database        => $database,
    local_enrichmnt => $local_enrichmnt,
    storage         => $storage_ref,
    scheme          => $scheme,
    normalizer      => $normalizer,
});

while (my $jsonline=<IN>){

    eval {
        $jsonline = $importer->enrich({
            json         => $jsonline
        });
    };

    if ($@){
	$logger->error($@," - $jsonline\n");
	next ;
    }

    print OUT $jsonline,"\n";
    
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

unlink $filename;

if ($keepfiles){
    system("cp -f $filename ${filename}.original");
}

system("mv -f ${filename}.enriched $filename");

$logger->info("### $database: $count Titelsaetze bearbeitet");

close(OUT);
close(IN);

sub print_help {
    print << "ENDHELP";
enrich_meta.pl - Anreichern der Meta-Daten mit Informationen aus der Anreicherungs-Datenbank

   Optionen:
   -help                 : Diese Informationsseite
       
   --filename=...        : Dateiname der Titeldaten, die angereichert werden sollen
   --database=...        : Angegebenen Datenpool verwenden
   -keep-files           : Urspruengliche Datei meta.title sichern
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
