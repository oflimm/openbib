#!/usr/bin/perl

#####################################################################
#
#  meta2marc.pl
#
#  Generierung einer MARC21 Datei aus dem (MAB2) Meta-Format
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@openbib.org>
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
use Date::Calc qw/check_date/;
use DB_File;
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8/;
use Getopt::Long;
use JSON::XS;
use Lingua::Identify::CLD;
use Log::Log4perl qw(get_logger :levels);
use MARC::Record;
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Config;

my ($outputfile,$mappingfile,$locationfile,$database,$isil,$libraryid,$logfile,$loglevel,$count,$update,$help);

&GetOptions(
    "outputfile=s"   => \$outputfile,
    "mappingfile=s"  => \$mappingfile,
    "locationfile=s" => \$locationfile,
    "database=s"     => \$database,
    "library-id=s"   => \$libraryid,
    "isil=s"         => \$isil,
    "logfile=s"      => \$logfile,
    "loglevel=s"     => \$loglevel,
    "update"         => \$update,
    "help"           => \$help,
    );

if ($help || (!$mappingfile && ! -f $mappingfile && !$database)) {
    print_help();
}
    
$logfile=($logfile)?$logfile:"./meta2marc.log";
$loglevel=($loglevel)?$loglevel:"INFO";
$outputfile=($outputfile)?$outputfile:"./output.mrc";

my $basepath = "/opt/openbib/autoconv/pools/$database";

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

my $iso_639_2_ref = {
    "aar" => 1,
	"abk" => 1,
	"ace" => 1,
	"ach" => 1,
	"ada" => 1,
	"ady" => 1,
	"afa" => 1,
	"afh" => 1,
	"afr" => 1,
	"ain" => 1,
	"aka" => 1,
	"akk" => 1,
	"alb" => 1,
	"sqi" => 1,
	"ale" => 1,
	"alg" => 1,
	"alt" => 1,
	"amh" => 1,
	"ang" => 1,
	"anp" => 1,
	"apa" => 1,
	"ara" => 1,
	"arc" => 1,
	"arg" => 1,
	"arm" => 1,
	"hye" => 1,
	"arn" => 1,
	"arp" => 1,
	"art" => 1,
	"arw" => 1,
	"asm" => 1,
	"ast" => 1,
	"ath" => 1,
	"aus" => 1,
	"ava" => 1,
	"ave" => 1,
	"awa" => 1,
	"aym" => 1,
	"aze" => 1,
	"bad" => 1,
	"bai" => 1,
	"bak" => 1,
	"bal" => 1,
	"bam" => 1,
	"ban" => 1,
	"baq" => 1,
	"eus" => 1,
	"bas" => 1,
	"bat" => 1,
	"bej" => 1,
	"bel" => 1,
	"bem" => 1,
	"ben" => 1,
	"ber" => 1,
	"bho" => 1,
	"bih" => 1,
	"bik" => 1,
	"bin" => 1,
	"bis" => 1,
	"bla" => 1,
	"bnt" => 1,
	"tib" => 1,
	"bod" => 1,
	"bos" => 1,
	"bra" => 1,
	"bre" => 1,
	"btk" => 1,
	"bua" => 1,
	"bug" => 1,
	"bul" => 1,
	"bur" => 1,
	"mya" => 1,
	"byn" => 1,
	"cad" => 1,
	"cai" => 1,
	"car" => 1,
	"cat" => 1,
	"cau" => 1,
	"ceb" => 1,
	"cel" => 1,
	"cze" => 1,
	"ces" => 1,
	"cha" => 1,
	"chb" => 1,
	"che" => 1,
	"chg" => 1,
	"chi" => 1,
	"zho" => 1,
	"chk" => 1,
	"chm" => 1,
	"chn" => 1,
	"cho" => 1,
	"chp" => 1,
	"chr" => 1,
	"chu" => 1,
	"chv" => 1,
	"chy" => 1,
	"cmc" => 1,
	"cnr" => 1,
	"cop" => 1,
	"cor" => 1,
	"cos" => 1,
	"cpe" => 1,
	"cpf" => 1,
	"cpp" => 1,
	"cre" => 1,
	"crh" => 1,
	"crp" => 1,
	"csb" => 1,
	"cus" => 1,
	"wel" => 1,
	"cym" => 1,
	"cze" => 1,
	"ces" => 1,
	"dak" => 1,
	"dan" => 1,
	"dar" => 1,
	"day" => 1,
	"del" => 1,
	"den" => 1,
	"ger" => 1,
	"deu" => 1,
	"dgr" => 1,
	"din" => 1,
	"div" => 1,
	"doi" => 1,
	"dra" => 1,
	"dsb" => 1,
	"dua" => 1,
	"dum" => 1,
	"dut" => 1,
	"nld" => 1,
	"dyu" => 1,
	"dzo" => 1,
	"efi" => 1,
	"egy" => 1,
	"eka" => 1,
	"gre" => 1,
	"ell" => 1,
	"elx" => 1,
	"eng" => 1,
	"enm" => 1,
	"epo" => 1,
	"est" => 1,
	"baq" => 1,
	"eus" => 1,
	"ewe" => 1,
	"ewo" => 1,
	"fan" => 1,
	"fao" => 1,
	"per" => 1,
	"fas" => 1,
	"fat" => 1,
	"fij" => 1,
	"fil" => 1,
	"fin" => 1,
	"fiu" => 1,
	"fon" => 1,
	"fre" => 1,
	"fra" => 1,
	"fre" => 1,
	"fra" => 1,
	"frm" => 1,
	"fro" => 1,
	"frr" => 1,
	"frs" => 1,
	"fry" => 1,
	"ful" => 1,
	"fur" => 1,
	"gaa" => 1,
	"gay" => 1,
	"gba" => 1,
	"gem" => 1,
	"geo" => 1,
	"kat" => 1,
	"ger" => 1,
	"deu" => 1,
	"gez" => 1,
	"gil" => 1,
	"gla" => 1,
	"gle" => 1,
	"glg" => 1,
	"glv" => 1,
	"gmh" => 1,
	"goh" => 1,
	"gon" => 1,
	"gor" => 1,
	"got" => 1,
	"grb" => 1,
	"grc" => 1,
	"gre" => 1,
	"ell" => 1,
	"grn" => 1,
	"gsw" => 1,
	"guj" => 1,
	"gwi" => 1,
	"hai" => 1,
	"hat" => 1,
	"hau" => 1,
	"haw" => 1,
	"heb" => 1,
	"her" => 1,
	"hil" => 1,
	"him" => 1,
	"hin" => 1,
	"hit" => 1,
	"hmn" => 1,
	"hmo" => 1,
	"hrv" => 1,
	"hsb" => 1,
	"hun" => 1,
	"hup" => 1,
	"arm" => 1,
	"hye" => 1,
	"iba" => 1,
	"ibo" => 1,
	"ice" => 1,
	"isl" => 1,
	"ido" => 1,
	"iii" => 1,
	"ijo" => 1,
	"iku" => 1,
	"ile" => 1,
	"ilo" => 1,
	"ina" => 1,
	"inc" => 1,
	"ind" => 1,
	"ine" => 1,
	"inh" => 1,
	"ipk" => 1,
	"ira" => 1,
	"iro" => 1,
	"ice" => 1,
	"isl" => 1,
	"ita" => 1,
	"jav" => 1,
	"jbo" => 1,
	"jpn" => 1,
	"jpr" => 1,
	"jrb" => 1,
	"kaa" => 1,
	"kab" => 1,
	"kac" => 1,
	"kal" => 1,
	"kam" => 1,
	"kan" => 1,
	"kar" => 1,
	"kas" => 1,
	"geo" => 1,
	"kat" => 1,
	"kau" => 1,
	"kaw" => 1,
	"kaz" => 1,
	"kbd" => 1,
	"kha" => 1,
	"khi" => 1,
	"khm" => 1,
	"kho" => 1,
	"kik" => 1,
	"kin" => 1,
	"kir" => 1,
	"kmb" => 1,
	"kok" => 1,
	"kom" => 1,
	"kon" => 1,
	"kor" => 1,
	"kos" => 1,
	"kpe" => 1,
	"krc" => 1,
	"krl" => 1,
	"kro" => 1,
	"kru" => 1,
	"kua" => 1,
	"kum" => 1,
	"kur" => 1,
	"kut" => 1,
	"lad" => 1,
	"lah" => 1,
	"lam" => 1,
	"lao" => 1,
	"lat" => 1,
	"lav" => 1,
	"lez" => 1,
	"lim" => 1,
	"lin" => 1,
	"lit" => 1,
	"lol" => 1,
	"loz" => 1,
	"ltz" => 1,
	"lua" => 1,
	"lub" => 1,
	"lug" => 1,
	"lui" => 1,
	"lun" => 1,
	"luo" => 1,
	"lus" => 1,
	"mac" => 1,
	"mkd" => 1,
	"mad" => 1,
	"mag" => 1,
	"mah" => 1,
	"mai" => 1,
	"mak" => 1,
	"mal" => 1,
	"man" => 1,
	"mao" => 1,
	"mri" => 1,
	"map" => 1,
	"mar" => 1,
	"mas" => 1,
	"may" => 1,
	"msa" => 1,
	"mdf" => 1,
	"mdr" => 1,
	"men" => 1,
	"mga" => 1,
	"mic" => 1,
	"min" => 1,
	"mis" => 1,
	"mac" => 1,
	"mkd" => 1,
	"mkh" => 1,
	"mlg" => 1,
	"mlt" => 1,
	"mnc" => 1,
	"mni" => 1,
	"mno" => 1,
	"moh" => 1,
	"mon" => 1,
	"mos" => 1,
	"mao" => 1,
	"mri" => 1,
	"may" => 1,
	"msa" => 1,
	"mul" => 1,
	"mun" => 1,
	"mus" => 1,
	"mwl" => 1,
	"mwr" => 1,
	"bur" => 1,
	"mya" => 1,
	"myn" => 1,
	"myv" => 1,
	"nah" => 1,
	"nai" => 1,
	"nap" => 1,
	"nau" => 1,
	"nav" => 1,
	"nbl" => 1,
	"nde" => 1,
	"ndo" => 1,
	"nds" => 1,
	"nep" => 1,
	"new" => 1,
	"nia" => 1,
	"nic" => 1,
	"niu" => 1,
	"dut" => 1,
	"nld" => 1,
	"nno" => 1,
	"nob" => 1,
	"nog" => 1,
	"non" => 1,
	"nor" => 1,
	"nqo" => 1,
	"nso" => 1,
	"nub" => 1,
	"nwc" => 1,
	"nya" => 1,
	"nym" => 1,
	"nyn" => 1,
	"nyo" => 1,
	"nzi" => 1,
	"oci" => 1,
	"oji" => 1,
	"ori" => 1,
	"orm" => 1,
	"osa" => 1,
	"oss" => 1,
	"ota" => 1,
	"oto" => 1,
	"paa" => 1,
	"pag" => 1,
	"pal" => 1,
	"pam" => 1,
	"pan" => 1,
	"pap" => 1,
	"pau" => 1,
	"peo" => 1,
	"per" => 1,
	"fas" => 1,
	"phi" => 1,
	"phn" => 1,
	"pli" => 1,
	"pol" => 1,
	"pon" => 1,
	"por" => 1,
	"pra" => 1,
	"pro" => 1,
	"pus" => 1,
	"qaa" => 1,
	"que" => 1,
	"raj" => 1,
	"rap" => 1,
	"rar" => 1,
	"roa" => 1,
	"roh" => 1,
	"rom" => 1,
	"rum" => 1,
	"ron" => 1,
	"rum" => 1,
	"ron" => 1,
	"run" => 1,
	"rup" => 1,
	"rus" => 1,
	"sad" => 1,
	"sag" => 1,
	"sah" => 1,
	"sai" => 1,
	"sal" => 1,
	"sam" => 1,
	"san" => 1,
	"sas" => 1,
	"sat" => 1,
	"scn" => 1,
	"sco" => 1,
	"sel" => 1,
	"sem" => 1,
	"sga" => 1,
	"sgn" => 1,
	"shn" => 1,
	"sid" => 1,
	"sin" => 1,
	"sio" => 1,
	"sit" => 1,
	"sla" => 1,
	"slo" => 1,
	"slk" => 1,
	"slo" => 1,
	"slk" => 1,
	"slv" => 1,
	"sma" => 1,
	"sme" => 1,
	"smi" => 1,
	"smj" => 1,
	"smn" => 1,
	"smo" => 1,
	"sms" => 1,
	"sna" => 1,
	"snd" => 1,
	"snk" => 1,
	"sog" => 1,
	"som" => 1,
	"son" => 1,
	"sot" => 1,
	"spa" => 1,
	"alb" => 1,
	"sqi" => 1,
	"srd" => 1,
	"srn" => 1,
	"srp" => 1,
	"srr" => 1,
	"ssa" => 1,
	"ssw" => 1,
	"suk" => 1,
	"sun" => 1,
	"sus" => 1,
	"sux" => 1,
	"swa" => 1,
	"swe" => 1,
	"syc" => 1,
	"syr" => 1,
	"tah" => 1,
	"tai" => 1,
	"tam" => 1,
	"tat" => 1,
	"tel" => 1,
	"tem" => 1,
	"ter" => 1,
	"tet" => 1,
	"tgk" => 1,
	"tgl" => 1,
	"tha" => 1,
	"tib" => 1,
	"bod" => 1,
	"tig" => 1,
	"tir" => 1,
	"tiv" => 1,
	"tkl" => 1,
	"tlh" => 1,
	"tli" => 1,
	"tmh" => 1,
	"tog" => 1,
	"ton" => 1,
	"tpi" => 1,
	"tsi" => 1,
	"tsn" => 1,
	"tso" => 1,
	"tuk" => 1,
	"tum" => 1,
	"tup" => 1,
	"tur" => 1,
	"tut" => 1,
	"tvl" => 1,
	"twi" => 1,
	"tyv" => 1,
	"udm" => 1,
	"uga" => 1,
	"uig" => 1,
	"ukr" => 1,
	"umb" => 1,
	"und" => 1,
	"urd" => 1,
	"uzb" => 1,
	"vai" => 1,
	"ven" => 1,
	"vie" => 1,
	"vol" => 1,
	"vot" => 1,
	"wak" => 1,
	"wal" => 1,
	"war" => 1,
	"was" => 1,
	"wel" => 1,
	"cym" => 1,
	"wen" => 1,
	"wln" => 1,
	"wol" => 1,
	"xal" => 1,
	"xho" => 1,
	"yao" => 1,
	"yap" => 1,
	"yid" => 1,
	"yor" => 1,
	"ypk" => 1,
	"zap" => 1,
	"zbl" => 1,
	"zen" => 1,
	"zgh" => 1,
	"zha" => 1,
	"chi" => 1,
	"zho" => 1,
	"znd" => 1,
	"zul" => 1,
	"zun" => 1,
	"zxx" => 1,
	"zza" => 1,    
};

my $dir=`pwd`;
chop $dir;

# Aufsaetze: Nach Verarbeitung von 424/425 als Jahr Quelle loeschen?
my $purge_year = 0;

$isil = ($isil)?$isil:'DE-38';

my %data_person         = ();
my %data_corporatebody  = ();
my %data_classification = ();
my %data_subject        = ();
my %data_holding        = ();
my %data_superids       = ();
my %data_super          = ();
my %titleid_exists      = ();

unlink "./data_person.db";
unlink "./data_corporatebody.db";
unlink "./data_classification.db";
unlink "./data_subject.db";
unlink "./data_holding.db";
unlink "./data_superids.db";
unlink "./data_super.db";

tie %data_person,        'MLDBM', "./data_person.db"
        or die "Could not tie data_person.\n";

tie %data_corporatebody,        'MLDBM', "./data_corporatebody.db"
        or die "Could not tie data_corporatebody.\n";

tie %data_subject,        'MLDBM', "./data_subject.db"
    or die "Could not tie data_subject.\n";

tie %data_classification,        'MLDBM', "./data_classification.db"
    or die "Could not tie data_classification.\n";

tie %data_holding,        'MLDBM', "./data_holding.db"
    or die "Could not tie data_holding.\n";

tie %data_superids,        'MLDBM', "./data_superids.db"
    or die "Could not tie data_superids.\n";

tie %data_super,        'MLDBM', "./data_super.db"
    or die "Could not tie data_super.\n";

my $stammdateien_ref = {
    person => {
        infile             => "$basepath/meta.person.gz",
    },

    corporatebody => {
        infile             => "$basepath/meta.corporatebody.gz",
    },
    
    subject => {
        infile             => "$basepath/meta.subject.gz",
    },
    
    classification => {
        infile             => "$basepath/meta.classification.gz",
    },

    holding => {
        infile             => "$basepath/meta.holding.gz",
    },
    
};

my $atime;

foreach my $type (keys %{$stammdateien_ref}) {
    if (-f $stammdateien_ref->{$type}{infile}){
        $atime = new Benchmark;

        $count = 1;
        
        $logger->info("### Bearbeite $stammdateien_ref->{$type}{infile}");
        
        open(IN , "zcat ".$stammdateien_ref->{$type}{infile}." | " )        || die "IN konnte nicht geoeffnet werden";

	binmode(IN,":raw");
	
        while (my $json=<IN>){
	    my $record_ref = decode_json $json;

	    my $id = $record_ref->{id};
	    
	    if ($type eq "person"){
		$data_person{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "corporatebody"){
		$data_corporatebody{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "subject"){
		$data_subject{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "classification"){
		$data_classification{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "holding"){
		$id = $record_ref->{fields}{'0004'}[0]{content};
		my $holding_ref = [];
		if (defined $data_holding{$id}){
		    $holding_ref = $data_holding{$id};
		}
		push @{$holding_ref}, $record_ref->{fields};		
		$data_holding{$id} = $holding_ref;
	    }
		
            if ($count % 1000 == 0) {
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                $atime      = new Benchmark;
                $logger->info("### 1000 ($count) Saetze in $resulttime fuer $type bearbeitet");
            } 
            
            $count++;
        }
	
        close(IN);
        
    }
    else {
        $logger->error("### $stammdateien_ref->{$type}{infile} nicht vorhanden!");
    }
}

#######################

$logger->info("### Bearbeite meta.title");

$stammdateien_ref = {
    title => {
        infile             => "$basepath/meta.title.gz",
    },    
};

$logger->info("### Pass 1: Ueberordnungen identifizieren");

$count = 1;

# Pass 1: Uebeordnungsinformationen bestimmen
open(IN , "zcat ".$stammdateien_ref->{'title'}{'infile'}." | " )     || die "IN konnte nicht geoeffnet werden";
binmode (IN, ":raw");

while (my $json=<IN>){
    
    my $record_ref = decode_json $json;

    my $fields_ref = $record_ref->{fields};

    if (defined $fields_ref->{'0004'}){
	foreach my $item_ref (@{$fields_ref->{'0004'}}){
	    $data_superids{$item_ref->{content}} = 1;
	}
    }

    if ($count % 1000 == 0) {
        $logger->info("### $count Titelsaetze bearbeitet");
    } 

    $count++;
}

close(IN);

$count = 1;

$logger->info("### Pass 2: Informationen zu Ueberordnungen sammeln");

open(IN , "zcat ".$stammdateien_ref->{'title'}{'infile'}." | " )     || die "IN konnte nicht geoeffnet werden";
binmode (IN, ":raw");

while (my $json=<IN>){
    
    my $record_ref = decode_json $json;

    my $titleid    = $record_ref->{id};
    my $fields_ref = $record_ref->{fields};

    if (defined $data_superids{$titleid} && $data_superids{$titleid}){
	$data_super{$titleid} = $fields_ref;
    }
    
    if ($count % 1000 == 0) {
        $logger->info("### $count Titelsaetze bearbeitet");
    } 
    
    $count++;

}

close(IN);

$logger->info("### Pass 3: Titeldaten verarbeiten");

open(IN , "zcat ".$stammdateien_ref->{'title'}{'infile'}." | " )     || die "IN konnte nicht geoeffnet werden";

open(OUT, ">:utf8",$outputfile);

binmode (IN, ":raw");

$count = 1;

$atime = new Benchmark;

my $mapping_ref = YAML::Syck::LoadFile($mappingfile);

my $location_ref = {};

if ($locationfile){
   $location_ref = YAML::Syck::LoadFile($locationfile);
}

my $title_mapping_ref = $mapping_ref->{convtab}{title};
    
while (my $json=<IN>){
    
    my $record_ref = decode_json $json;

    my $fields_ref = $record_ref->{fields};

    my $output_fields_ref = {};
                
    my $marc_record = new MARC::Record;
    
    my $titleid = $record_ref->{id};

    $marc_record->add_fields('001',$titleid);

    # Set Koha biblionumber and biblioitemnumber in 999    
    {
	my @subfields = ();
	
	push (@subfields,'c', $titleid);
	push (@subfields,'d', $titleid);
	
	my $new_field = MARC::Field->new('999', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'999'}}, $new_field if ($new_field);
    }

    # Alte ID in 035 mit "modifizierter" ISIL als Prefix sichern
    {
	my @subfields = ();
	
	push (@subfields,'a', "(".$isil."-".uc($database).")".$titleid);
	
	my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);
    }
    $marc_record->add_fields('003',$isil);

    my $last_tstamp = "1970-01-01 12:00:00";
    my $create_tstamp = "700101";
    
    if (defined $fields_ref->{'0002'}){
	my $date = $fields_ref->{'0002'}[0]{content};
	my ($day,$month,$year) = $date =~m/^(\d\d)\.(\d\d)\.(\d\d\d\d)$/;

	if ($day && $month && $year && check_date($year,$month,$day)){
	    $last_tstamp = "$year$month$day"."120000.0";
	    $create_tstamp = substr($year,2,2)."$month$day";
	}

    }

    if (defined $fields_ref->{'0003'}){
	my $date = $fields_ref->{'0003'}[0]{content};
	my ($day,$month,$year) = $date =~m/^(\d\d)\.(\d\d)\.(\d\d\d\d)$/;
	
	if ($day && $month && $year && check_date($year,$month,$day)){
	    $last_tstamp = "$year$month$day"."120000.0";
	}
    }

    $marc_record->add_fields('005',$last_tstamp);

    $marc_record->add_fields('007','tu');

    my $fixed_length_008 = "700101|1970####xxu###########|||#|#eng#c"; # example

    if (defined $fields_ref->{'0424'}){
	my $tmp_ref = $fields_ref->{'0424'}[0];
	$fields_ref->{'0424'} = [];
	$fields_ref->{'0425'} = [];
	push @{$fields_ref->{'0425'}}, $tmp_ref;
	
	delete $fields_ref->{'0424'};
    }

    my $year = "";    
    if (defined $fields_ref->{'0425'}){
	($year) = $fields_ref->{'0425'}[0]{content} =~m/(\d\d\d\d)/;
    }

    my $lang = '###';

    if (defined $fields_ref->{'0015'}){
	my $thislang = $fields_ref->{'0015'}[0]{content};

	if (defined $iso_639_2_ref->{$thislang} && $iso_639_2_ref->{$thislang}){
	    $lang = $thislang;
	}
	else { # sonst verwerfen
	    $fields_ref->{'0015'} = [];
	    delete $fields_ref->{'0015'};
	}
    }
    
    substr($fixed_length_008,0,6)  = $create_tstamp;
    substr($fixed_length_008,6,1)  = "s";
    substr($fixed_length_008,7,4)  = $year if ($year);    
    substr($fixed_length_008,15,3) = '|||';
    substr($fixed_length_008,24,1) = '|';
    substr($fixed_length_008,25,3) = '|||';
    substr($fixed_length_008,35,3) = $lang;

    $marc_record->add_fields('008',$fixed_length_008);

    # HBZID?
    if (defined $fields_ref->{'0010'}){
	foreach my $item_ref (@{$fields_ref->{'0010'}}){
	    my $fremdid = $item_ref->{content};

	    if ($fremdid =~m/^[CTH][A-Z]\d+$/){
		my @subfields = ();
		
		push (@subfields,'a', "(DE-605)".$fremdid); # HBZ
		
		my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
		
		push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);
	    }
	    elsif ($fremdid =~m/^BV\d+$/){
		my @subfields = ();
		
		push (@subfields,'a', "(DE-604)".$fremdid); # BVB
		
		my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
		
		push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);
	    }
 	}
    }
    
    if ($logger->is_debug){
	$logger->debug(YAML::Dump($fields_ref));
    }

    my $is_band       = 0;
    my $is_serialpart = 0;
    
    if (defined $fields_ref->{'0089'}){
	$is_band = 1;
    }    

    if (defined $fields_ref->{'0451'}){
	$is_serialpart = 1;
    }    
    
    # Normdaten processen

    my $have_1xx = 0; # Geistiger Schoepfer / Haupteintragung

    my $firstpersonid = 0;
    my $firstpersonsupplement = "";
    
    my @personids = ();

    foreach my $field ('0100','0101','0102','0103'){	    
	foreach my $thisfield_ref (@{$fields_ref->{$field}}){
	    if ($field eq '0100' && !$firstpersonid){
		$firstpersonid         = $thisfield_ref->{id};
		$firstpersonsupplement = $thisfield_ref->{supplement};
	    }
	    else {
		push @personids, {
		    id         => $thisfield_ref->{id},
		    supplement => $thisfield_ref->{supplement},
		};
	    }
	}
    }

    if ($firstpersonid){
	# Erste in 100 1#
	my $personid = $firstpersonid;

	my $person_fields_ref = $data_person{$personid};

	if ($logger->is_debug){
	    $logger->debug("Persondata for id $personid: ".YAML::Syck::Dump($person_fields_ref));
	}
	
	my @subfields = ();

	# Ansetzungsform
	if ($person_fields_ref->{'0800'}){
	    push (@subfields,'a', cleanup($person_fields_ref->{'0800'}[0]{content}));
	}
	
	# GND
	if ($person_fields_ref->{'0010'} && $person_fields_ref->{'0010'}[0]{content} =~m/^\d+/){
	    push (@subfields,'0', "(DE-588)".$person_fields_ref->{'0010'}[0]{content});
	}

	# Relationship

	my $relation = ($firstpersonsupplement)?supplement2relation($firstpersonsupplement):'aut';
	
	push (@subfields,'4', $relation) if ($relation);
	
	my $new_field = MARC::Field->new('100', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'100'}}, $new_field if ($new_field);
	
	$have_1xx = 1;
    }
    
    if (@personids){
	foreach my $person_ref (@personids){
	    my $personid   = $person_ref->{id};
	    my $supplement = $person_ref->{supplement};

	    my $person_fields_ref = $data_person{$personid};
	    
	    if ($logger->is_debug){
		$logger->debug("Persondata for id $personid: ".YAML::Syck::Dump($person_fields_ref));
	    }
	    
	    my @subfields = ();
	    
	    # Ansetzungsform
	    if ($person_fields_ref->{'0800'}){
		push (@subfields,'a', cleanup($person_fields_ref->{'0800'}[0]{content}));
	    }
	    
	    # GND
	    if ($person_fields_ref->{'0010'} && $person_fields_ref->{'0010'}[0]{content} =~m/^\d+/){
		push (@subfields,'0', "(DE-588)".$person_fields_ref->{'0010'}[0]{content});
	    }
	    
	    # Relationship
	    my $relation = ($supplement)?supplement2relation($supplement):'aut';
	    
	    push (@subfields,'4', $relation) if ($relation);
	    	    
	    my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);

	    push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);	
	}	
    }
	
    # Koerperschaften
    my $firstcorporatebodyid = 0;
    my $firstcorporatebodysupplement = "";
    
    my @corporatebodyids = ();

    foreach my $field ('0200','0201'){	
	foreach my $thisfield_ref (@{$fields_ref->{$field}}){
	    if ($field eq '0200' && !$firstcorporatebodyid && !$have_1xx){
		$firstcorporatebodyid = $thisfield_ref->{id};
		$firstcorporatebodysupplement = $thisfield_ref->{supplement};
	    }
	    else {
		push @corporatebodyids, {
		    id => $thisfield_ref->{id},
		    supplement => $thisfield_ref->{supplement},
		};
	    }
	}
    }
    
    if ($firstcorporatebodyid){
	# Erste in 110 2#
	my $corporatebodyid = $firstcorporatebodyid;

	my $corporatebody_fields_ref = $data_corporatebody{$corporatebodyid};
	
	if ($logger->is_debug){
	    $logger->debug("Corporatebodydata for id $corporatebodyid: ".YAML::Syck::Dump($corporatebody_fields_ref));
	}
	
	my @subfields = ();
	
	# Ansetzungsform
	if ($corporatebody_fields_ref->{'0800'}){
	    push (@subfields,'a', cleanup($corporatebody_fields_ref->{'0800'}[0]{content}));
	}
	
	# GND
	if ($corporatebody_fields_ref->{'0010'} && $corporatebody_fields_ref->{'0010'}[0]{content} =~m/^\d+/){
	    push (@subfields,'0', "(DE-588)".$corporatebody_fields_ref->{'0010'}[0]{content});
	}

	# Relationship	
	my $relation = ($firstcorporatebodysupplement)?supplement2relation($firstcorporatebodysupplement):'';
	
	push (@subfields,'4', $relation) if ($relation);
	
	my $new_field = MARC::Field->new('110', '2',  ' ', @subfields);
	
	push @{$output_fields_ref->{'110'}}, $new_field if ($new_field);
	
	$have_1xx = 1;
    }

    if (@corporatebodyids){

	foreach my $corporatebody_ref (@corporatebodyids){
	    my $corporatebodyid = $corporatebody_ref->{id};
	    my $supplement      = $corporatebody_ref->{supplement};
	    
	    my $corporatebody_fields_ref = $data_corporatebody{$corporatebodyid};

	    if ($logger->is_debug){
		$logger->debug("Corporatebodydata for id $corporatebodyid: ".YAML::Syck::Dump($corporatebody_fields_ref));
	    }
	    
	    my @subfields = ();
	    
	    # Ansetzungsform
	    if ($corporatebody_fields_ref->{'0800'}){
		push (@subfields,'a', cleanup($corporatebody_fields_ref->{'0800'}[0]{content}));
	    }
	    
	    # GND
	    if ($corporatebody_fields_ref->{'0010'} && $corporatebody_fields_ref->{'0010'}[0]{content} =~m/^\d+/){
		push (@subfields,'0', "(DE-588)".$corporatebody_fields_ref->{'0010'}[0]{content});
	    }
	    
	    # Relationship
	    my $relation = ($supplement)?supplement2relation($supplement):'';

	    push (@subfields,'4', $relation) if ($relation);
	    	    
	    my $new_field = MARC::Field->new('710', '2',  ' ', @subfields);

	    push @{$output_fields_ref->{'710'}}, $new_field if ($new_field);
	}	
    }

    # Schlagworte
    my @subjectids = ();
    foreach my $field ('0710','0902','0907','0912','0917','0922','0927','0932','0937','0942','0947'){
	foreach my $thisfield_ref (@{$fields_ref->{$field}}){
	    push @subjectids, $thisfield_ref->{id};
	}
    }
        
    if (@subjectids){
	
	foreach my $subjectid (@subjectids){	
	    my $subject_fields_ref = $data_subject{$subjectid};

	    if ($logger->is_debug){	    
		$logger->debug("Subjectdata for id $subjectid: ".YAML::Syck::Dump($subject_fields_ref));
	    }
	    
	    my @subfields = ();
	    
	    # Ansetzungsform
	    if ($subject_fields_ref->{'0800'}){
		# Sortierung der Ansetzungsformen fuer Schlagwortketten nach Mult-Wert
		my %terms_mult = ();
		foreach my $item_ref (@{$subject_fields_ref->{'0800'}}){
		    $terms_mult{$item_ref->{mult}}= $item_ref->{content};
		}

		my @terms = ();
		foreach my $mult (sort keys %terms_mult){
		    push @terms, $terms_mult{$mult};
		}
		
		my $this_subject = join(' / ',@terms);
		
		push (@subfields,'a', cleanup($this_subject));
	    }
	    
	    # GND
	    if ($subject_fields_ref->{'0010'} && $subject_fields_ref->{'0010'}[0]{content} =~m/^\d+/){
		push (@subfields,'0', "(DE-588)".$subject_fields_ref->{'0010'}[0]{content});
		push (@subfields,'2', "gnd-content");
	    }
	    
	    my $new_field = MARC::Field->new('650', ' ',  '4', @subfields);

	    push @{$output_fields_ref->{'650'}}, $new_field if ($new_field);	    
#	    $marc_record->append_fields($new_field) if ($new_field);	    	
	}	
    }

    # Notationen
    my @classificationids = ();
    foreach my $field ('0700'){
	foreach my $thisfield_ref (@{$fields_ref->{$field}}){
	    push @classificationids, $thisfield_ref->{id};
	}
    }
        
    if (@classificationids){
	
	foreach my $classificationid (@classificationids){	
	    my $classification_fields_ref = $data_classification{$classificationid};
	    
	    if ($logger->is_debug){
		$logger->debug("Classificationdata for id $classificationid: ".YAML::Syck::Dump($classification_fields_ref));
	    }
	    
	    my @subfields = ();
	    
	    # Ansetzungsform
	    if ($classification_fields_ref->{'0800'}){
		push (@subfields,'a', cleanup($classification_fields_ref->{'0800'}[0]{content}));
		push (@subfields,'2', 'z'); # z = Other see: https://www.loc.gov/standards/sourcelist/classification.html
	    }
	    	    
	    my $new_field = MARC::Field->new('084', ' ',  ' ', @subfields);

	    push @{$output_fields_ref->{'084'}}, $new_field if ($new_field);	    
#	    $marc_record->append_fields($new_field) if ($new_field);	    	
	}	
    }
    
    # URLs processen
    foreach my $thisfield_ref (@{$fields_ref->{'0662'}}){
	my $thismult = $thisfield_ref->{mult};
	my $url      = $thisfield_ref->{content};
	my $desc     = "";

	foreach my $thisfield_0663_ref (@{$fields_ref->{'0663'}}){
	    next unless $thisfield_0663_ref->{mult} == $thismult;
	    $desc = $thisfield_0663_ref->{content};
	}

	my @subfields = ();

	push (@subfields,'u', $url);
	push (@subfields,'y', $desc) if ($desc);	

	my $new_field = MARC::Field->new('856', '4',  ' ', @subfields);

	push @{$output_fields_ref->{'856'}}, $new_field if ($new_field);	
#	$marc_record->append_fields($new_field) if ($new_field);	    	
    }

    
    # Fussnote in 505 bearbeiten
    {	
	if (defined $fields_ref->{'0505'}){
	    foreach my $item_ref (@{$fields_ref->{'0505'}}){
		my $content    = $item_ref->{content};

		my ($info,$thiscontent) = $content =~m/^(.+?):(.+)$/;

		next unless ($info && $thiscontent);
		
		my @subfields = ();
		
		push (@subfields,'i', $info);
		push (@subfields,'a', $thiscontent);
		
		my $new_field = MARC::Field->new('246', '1',  ' ', @subfields);
		
		push @{$output_fields_ref->{'246'}}, $new_field if ($new_field);
	    }
	}
    }

    # Fussnote in 527 bearbeiten
    {	
	if (defined $fields_ref->{'0527'}){
	    foreach my $item_ref (@{$fields_ref->{'0527'}}){
		my $content    = $item_ref->{content};

		my ($info,$thiscontent) = $content =~m/^(.+?):(.+)$/;

		next unless ($info && $thiscontent);
		
		my @subfields = ();
		
		push (@subfields,'i', $info);
		push (@subfields,'t', $thiscontent);
		
		my $new_field = MARC::Field->new('775', '0',  '8', @subfields);
		
		push @{$output_fields_ref->{'775'}}, $new_field if ($new_field);
	    }
	}
    }


    # Fussnote in 529 bearbeiten
    {	
	if (defined $fields_ref->{'0529'}){
	    foreach my $item_ref (@{$fields_ref->{'0529'}}){
		my $content    = $item_ref->{content};

		my ($info,$thiscontent) = $content =~m/^(.+?):(.+)$/;

		next unless ($info && $thiscontent);
		
		my @subfields = ();
		
		push (@subfields,'i', $info);
		push (@subfields,'t', $thiscontent);
		
		my $new_field = MARC::Field->new('770', '0',  '8', @subfields);
		
		push @{$output_fields_ref->{'770'}}, $new_field if ($new_field);
	    }
	}
    }
    
    # Fussnote in 530 bearbeiten
    {	
	if (defined $fields_ref->{'0530'}){
	    foreach my $item_ref (@{$fields_ref->{'0530'}}){
		my $content    = $item_ref->{content};

		my ($info,$thiscontent) = $content =~m/^(.+?):(.+)$/;

		next unless ($info && $thiscontent);
		
		my @subfields = ();
		
		push (@subfields,'i', $info);
		push (@subfields,'t', $thiscontent);
		
		my $new_field = MARC::Field->new('772', '0',  '8', @subfields);
		
		push @{$output_fields_ref->{'772'}}, $new_field if ($new_field);
	    }
	}
    }

    # Fussnote in 531 bearbeiten
    {	
	if (defined $fields_ref->{'0531'}){
	    foreach my $item_ref (@{$fields_ref->{'0531'}}){
		my $content    = $item_ref->{content};

		my ($info,$thiscontent) = $content =~m/^(.+?):(.+)$/;

		next unless ($info && $thiscontent);
		
		my @subfields = ();
		
		push (@subfields,'i', $info);
		push (@subfields,'t', $thiscontent);
		
		my $new_field = MARC::Field->new('780', '0',  '8', @subfields);
		
		push @{$output_fields_ref->{'780'}}, $new_field if ($new_field);
	    }
	}
    }

    # Fussnote in 532 bearbeiten
    {	
	if (defined $fields_ref->{'0532'}){
	    foreach my $item_ref (@{$fields_ref->{'0532'}}){
		my $content    = $item_ref->{content};

		my ($info,$thiscontent) = $content =~m/^(.+?):(.+)$/;

		next unless ($info && $thiscontent);
		
		my @subfields = ();
		
		push (@subfields,'i', $info);
		push (@subfields,'t', $thiscontent);
		
		my $new_field = MARC::Field->new('785', '0',  '8', @subfields);
		
		push @{$output_fields_ref->{'785'}}, $new_field if ($new_field);
	    }
	}
    }

    # Fussnote in 533 bearbeiten
    {	
	if (defined $fields_ref->{'0533'}){
	    foreach my $item_ref (@{$fields_ref->{'0533'}}){
		my $content    = $item_ref->{content};

		my ($info,$thiscontent) = $content =~m/^(.+?):(.+)$/;

		next unless ($info && $thiscontent);
		
		my @subfields = ();
		
		push (@subfields,'i', $info);
		push (@subfields,'t', $thiscontent);
		
		my $new_field = MARC::Field->new('785', '0',  '0', @subfields);
		
		push @{$output_fields_ref->{'785'}}, $new_field if ($new_field);
	    }
	}
    }

    # 619 fixen
    {	
	if (defined $fields_ref->{'0619'}){
	    foreach my $item_ref (@{$fields_ref->{'0619'}}){
		my $content    = $item_ref->{content};

		$content =~s/\D//g; # Nicht-Ziffern entfernen

		$item_ref->{content} = "d".$content;
	    }
	}
    }
    
    # 333 zu HST getrennt mit ' / ' hinzufuegen:
    {
	if (defined $fields_ref->{'0333'} && defined $fields_ref->{'0331'}){
	    $fields_ref->{'0331'}[0]{content} .= " / ".$fields_ref->{'0333'}[0]{content};
	}
    }
       
    # {	
    # 	if (defined $fields_ref->{'0361'}){
    # 	    foreach my $item_ref (@{$fields_ref->{'0361'}}){
    # 		my $content    = $item_ref->{content};

    # 		my @subfields = ();
		
    # 		push (@subfields,'i', "Erweitert durch");
    # 		push (@subfields,'t', $content);
		
    # 		my $new_field = MARC::Field->new('787', '0',  '8', @subfields);
		
    # 		push @{$output_fields_ref->{'787'}}, $new_field if ($new_field);
    # 	    }
    # 	}
    # }
    
    # Ueberordnungen entsprechen 0004 nach 773 0# schreiben
    {
	# Titel hat Ueberordnung
	if (defined $fields_ref->{'0004'}){
	    foreach my $item_ref (@{$fields_ref->{'0004'}}){
		my $super_titleid    = $item_ref->{content};
		
		next unless (defined $data_super{$super_titleid} && $data_super{$super_titleid});
		
		my $super_fields_ref = $data_super{$super_titleid};

		my $super_title = "";
		if (defined $super_fields_ref->{'0331'} && $super_fields_ref->{'0331'}){
		    $super_title = $super_fields_ref->{'0331'}[0]{content};
		}
		
		my @subfields = ();
		
		push (@subfields,'t', $super_title) if ($super_title);
		push (@subfields,'w', $super_titleid) if ($super_titleid);	
		
		my $new_field = MARC::Field->new('773', '0',  ' ', @subfields);
		
		push @{$output_fields_ref->{'773'}}, $new_field if ($new_field);
	    }
	}

    }
    #print YAML::Dump($fields_ref->{'0590'}),"\n";
    # Medientyp setzen

    # Koha Medientyp
    my $mediatype = "BK"; # default: Book

    # HSTQuelle usw. -> Artikel/Aufsatz
    if (defined $fields_ref->{'0590'} || defined $fields_ref->{'0591'} || defined $fields_ref->{'0597'}) {
	$mediatype = "AR"; # Artikel
    }   
    elsif (defined $fields_ref->{'0519'}) {
	$mediatype = "HS"; # Hochschulschrift
    }   
    elsif (defined $fields_ref->{'0572'} || defined $fields_ref->{'0543'}) {
	$mediatype = "CR"; # Zeitschrift/Serie
    }

    {
	my @subfields = ();
    
	push (@subfields,'c', $mediatype);
	
	my $new_field = MARC::Field->new('942', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'942'}}, $new_field if ($new_field);
    }

    # Verschiedene Defaults setzten
    {
	# 336$b = txt
	# see: https://www.loc.gov/standards/valuelist/rdacontent.html
	{
	    my @subfields = ();
	    
	    push (@subfields,'b', "txt");
	    push (@subfields,'2', "rdacontent");
	    
	    my $new_field = MARC::Field->new('336', ' ',  ' ', @subfields);
	    
	    push @{$output_fields_ref->{'336'}}, $new_field if ($new_field);
	}

	# 337$b = n
	# see: https://www.loc.gov/standards/valuelist/rdamedia.html
	{
	    my @subfields = ();
	    
	    push (@subfields,'b', "n");
	    push (@subfields,'2', "rdamedia");
	    
	    my $new_field = MARC::Field->new('337', ' ',  ' ', @subfields);
	    
	    push @{$output_fields_ref->{'337'}}, $new_field if ($new_field);
	}
	
	# 338$b = nc = Volume
	# see: https://www.loc.gov/standards/valuelist/rdacarrier.html
	{
	    my @subfields = ();
	    
	    push (@subfields,'b', "nc");
	    push (@subfields,'2', "rdacarrier");
	    
	    my $new_field = MARC::Field->new('338', ' ',  ' ', @subfields);
	    
	    push @{$output_fields_ref->{'338'}}, $new_field if ($new_field);
	}
	
    }
    
    # Korrektur der Ursprungsdaten
    {
	
	# Zusammenfassen 590/591 bei Aufsaetzen. Voraussetzung: Neu eine Quellangabe
	my @quellangaben = ();
	if (defined $fields_ref->{'0590'}){
	    push @quellangaben, $fields_ref->{'0590'}[0]{content};
	}
	
	if (defined $fields_ref->{'0591'}){ # Verfasser der Quelle
	    push @quellangaben, $fields_ref->{'0591'}[0]{content};
	    $fields_ref->{'0591'} = []; # entfernen
	    delete $fields_ref->{'0591'};
	}

	if (@quellangaben){
	    my $quellangabe = join(' / ',@quellangaben);
	    
	    $fields_ref->{'0590'} = []; # entfernen
	    
	    push @{$fields_ref->{'0590'}}, { # und neu setzen
		content  => $quellangabe,
		mult     => "001",
		subfield => "",
	    };
	}

	if ($database eq "aufsaetze"){
	    # Bei Aufsaetzen Erscheinungsjahr der Quelle aus 425 nach 594 anghaengen
	    if (defined $fields_ref->{'0590'} && $year){
		if  (defined $fields_ref->{'0594'}){
		    $fields_ref->{'0594'}[0]{content} = $fields_ref->{'0594'}[0]{content}.", ".$year;
		}
		elsif (!defined $fields_ref->{'0594'}){
		    push @{$fields_ref->{'0594'}}, { # und neu setzen
			content  => $year,
			mult     => "001",
			subfield => "",
		    };
		}

		if ($purge_year){
		    $fields_ref->{'0424'} = [];
		    $fields_ref->{'0425'} = [];		
		    delete $fields_ref->{'0424'};
		    delete $fields_ref->{'0425'};
		}
	    }
	    
	    if (defined $fields_ref->{'0595'} && !$year){
		if  (defined $fields_ref->{'0594'}){
		    $fields_ref->{'0594'}[0]{content} = $fields_ref->{'0594'}[0]{content}.", ".$fields_ref->{'0595'}[0]{content};
		}
		elsif (!defined $fields_ref->{'0594'}){
		    push @{$fields_ref->{'0594'}}, { # und neu setzen
			content  => $fields_ref->{'0595'}[0]{content},
			mult     => "001",
			subfield => "",
		    };
		}
	    }
	    
	    # Prefixen der HBZ-ID als Fremdnummer in 4599 (Aufsatzkatalog)
	    if (defined $fields_ref->{'4599'}){
		my $hbzid_quelle = $fields_ref->{'4599'}[0]{content};
		unless ($hbzid_quelle =~m/DE-605/){
		    $hbzid_quelle = "(DE-605)".$hbzid_quelle;
		}
		
		$fields_ref->{'4599'} = [];
		push @{$fields_ref->{'4599'}}, {
		    content  => $hbzid_quelle,
		    mult     => "001",
		    subfield => "",
		};
	    }
	}
	
	# Aufsplitten von Illustrationsangaben aus 0433 nach 0434
	if (defined $fields_ref->{'0433'}){
	    foreach my $thisfield_ref (@{$fields_ref->{'0433'}}){
		my $content = $thisfield_ref->{content};

		if ($content =~m/^(.+?) : (.+)$/){
		    my $kollation = $1;
		    my $illustr   = $2;
		    $thisfield_ref->{content} = $kollation;
		    $fields_ref->{'0434'} = [];
		    push @{$fields_ref->{'0434'}}, {
			content  => $illustr,
			mult     => $thisfield_ref->{mult},
			subfield => $thisfield_ref->{subfield},
		    };
		}
		last;
	    }
	}
	
	if ($mediatype eq "AR"){ # Aufsatz
	    # ZDB-ID 'interpretieren' als Fremdid in 773 via 4599. ZDBID geht vor HBZ-ID (wg. Verfuegbarkeitsrecherche mit OpenURL)
	    if (defined $fields_ref->{'0572'}){
		foreach my $thisfield_ref (@{$fields_ref->{'0572'}}){
		    my $zdbid_quelle  = $thisfield_ref->{content};
		    unless ($zdbid_quelle =~m/DE-600/){
			$zdbid_quelle = "(DE-600)".$zdbid_quelle;
		    }

		    $fields_ref->{'4599'} = [];
		    push @{$fields_ref->{'4599'}}, {
			content  => $zdbid_quelle,
			mult     => "001",
			subfield => "",
		    };

		    last; # nur eine 572
		}
	    }
	}
	else {
	    # ZDB-ID als ID nach 035
	    foreach my $thisfield_ref (@{$fields_ref->{'0572'}}){
		my $zdbid  = $thisfield_ref->{content};

		unless ($zdbid =~m/DE-600/){
		    $zdbid = "(DE-600)".$zdbid;
		}
		
		my @subfields = ();
		
		push (@subfields,'a', $zdbid);
		
		my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
		
		push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);

		last; # Nur eine 0572
	    }    	    
	}

	# Korrektur 451 mit Zaehlung, wenn diese bereits in 455 enthalten ist
	if (defined $fields_ref->{'0451'} && defined $fields_ref->{'0455'}){

	    foreach my $item451_ref (@{$fields_ref->{'0451'}}){
		my $mult451    = $item451_ref->{mult};
		my $content451 = $item451_ref->{content};
		
		my $content455 = "";
		foreach my $item455_ref (@{$fields_ref->{'0455'}}){
		    if ($item455_ref->{mult} eq $mult451){
			$content455 = $item455_ref->{content};
			last;
		    }
		}

		if ($content451 =~m/^(.+) ; (.+?)$/){
		    my $titel    = $1;
		    my $zaehlung = $2;

		    if ($zaehlung =~m/$content455/i){
			$item451_ref->{content} = $titel;
		    }
		}
		
	    }

	    my $thisfields_ref = {};
	    foreach my $field ('0451','0455'){
		foreach my $thisfield_ref (@{$fields_ref->{$field}}){
		    $thisfields_ref->{$thisfield_ref->{mult}}{$field} = $thisfield_ref->{content};
		}
	    }	    
	}
    }
    
    # Exemplardaten processen (Koha holding scheme)
    # https://wiki.koha-community.org/wiki/Holdings_data_fields_(9xx)
    if (defined $data_holding{$titleid}){
	my $holdings_ref = $data_holding{$titleid};

	if ($logger->is_debug){
	    $logger->debug("Holdings for $titleid: ".YAML::Dump($holdings_ref));
	}
	
	# Iteration ueber Exemplare

	foreach my $thisholding_ref (@{$holdings_ref}){
	    my @subfields = ();

	    my $this_libraryid = "";

	    $this_libraryid = $libraryid if ($libraryid);
	    
	    push (@subfields,'o', $thisholding_ref->{'0014'}[0]{content}) if (defined $thisholding_ref->{'0014'}[0]{content});
	    #push (@subfields,'e', $thisholding_ref->{'0016'}[0]{content}) if (defined $thisholding_ref->{'0016'}[0]{content}) ;
	    push (@subfields,'p', $thisholding_ref->{'0010'}[0]{content}) if (defined $thisholding_ref->{'0010'}[0]{content}) ; # barcode
	    push (@subfields,'i', $thisholding_ref->{'0005'}[0]{content}) if (defined $thisholding_ref->{'0005'}[0]{content}) ;
	    #	    push (@subfields,'a', $thisholding_ref->{'3330'}[0]{content}) if (defined $thisholding_ref->{'3330'}[0]{content}) ;
	    
	    if (!$this_libraryid && defined $thisholding_ref->{'3330'}){
		$this_libraryid = $thisholding_ref->{'3330'}[0]{content};
	    }

	    if ($this_libraryid && $locationfile){
		# Falsche Location (in 3330), dann Aenderungsversuch
		$logger->debug("Libraryid ist '$this_libraryid'");
		if ($location_ref->{change}{$this_libraryid}){
		    $logger->info("Korrektur Libraryid $this_libraryid -> ".$location_ref->{change}{$this_libraryid});
		    $this_libraryid = $location_ref->{change}{$this_libraryid};
		}

		unless ($location_ref->{valid}{$this_libraryid}){
#		    $logger->error(YAML::Dump($location_ref));
		    $logger->error("Libraryid $this_libraryid ist nicht gueltig");
		    next;
		}
	    }
	    
	    # Libraryid als Parameter (Prioritaet 1) oder aus 3330 (Prioritaet 2)
	    if ($this_libraryid){
		push (@subfields,'a', $this_libraryid) ;
		push (@subfields,'b', $this_libraryid) ;
	    }

	    push (@subfields,'y', $mediatype);

	    my $new_field = MARC::Field->new('952', ' ',  ' ', @subfields);

	    push @{$output_fields_ref->{'952'}}, $new_field if ($new_field);

	    if ($this_libraryid && !defined $output_fields_ref->{'040'}){
		@subfields = ();

		push (@subfields,'a', $this_libraryid) ;
		push (@subfields,'b', 'ger') ;
		push (@subfields,'c', 'DE-38') ;
		
		$new_field = MARC::Field->new('040', ' ',  ' ', @subfields);
		
		push @{$output_fields_ref->{'040'}}, $new_field if ($new_field);
		
	    }

	    
#	    $marc_record->append_fields($new_field) if ($new_field);	    	
	    
	}
    }    

    # 3330 nur in Titeldaten, d.h. ohne sinnvolle Exemplarinformationen wie Signaturen? Dann daraus 040 erzeugen
    if (defined $fields_ref->{'3330'} && !defined $output_fields_ref->{'040'}){
	foreach my $item_ref (@{$fields_ref->{'3330'}}){
	    my $this_libraryid = $item_ref->{content};

	    if ($this_libraryid && $locationfile){
		# Falsche Location (in 3330), dann Aenderungsversuch
		$logger->debug("Libraryid ist '$this_libraryid'");
		if ($location_ref->{change}{$this_libraryid}){
		    $logger->info("Korrektur Libraryid $this_libraryid -> ".$location_ref->{change}{$this_libraryid});
		    $this_libraryid = $location_ref->{change}{$this_libraryid};
		}

		unless ($location_ref->{valid}{$this_libraryid}){
#		    $logger->error(YAML::Dump($location_ref));
		    $logger->error("Libraryid $this_libraryid ist nicht gueltig");
		    $this_libraryid = "";
		}
	    }

	    if ($this_libraryid){
		my @subfields = ();
		
		push (@subfields,'a', $this_libraryid) ;
		push (@subfields,'b', 'ger') ;
		push (@subfields,'c', 'DE-38') ;
		
		my $new_field = MARC::Field->new('040', ' ',  ' ', @subfields);
		
		push @{$output_fields_ref->{'040'}}, $new_field if ($new_field);
	    }
	}
    }

    # Felder aus Mapping-Datei verarbeiten
    foreach my $marcfield (keys %{$title_mapping_ref}){
	my ($ind1)    = $marcfield =~m/^..._(.)_.$/;
	my ($ind2)    = $marcfield =~m/^..._._(.)$/;
	my ($fieldno) = $marcfield =~m/^(\d\d\d)/;

	# Korrektur einzelner Felder und Indikatoren
	if ($fieldno eq "240" && !$have_1xx){ # Aendern von aunf 130 0#
	    $fieldno = "130";
	    $ind1 = '0';
	    $ind2 = ' ';
	}

	if ($fieldno eq "245" && !$have_1xx){ # Aendern von default 1# auf 0#
	    $ind1 = '0'; # no added entry
	}

	if ($fieldno eq "490" && defined $fields_ref->{'0004'}){
	    $ind1 = '1'; # series is (probably...) traced, default is 0 = untraced
	}

	$logger->debug("$marcfield -> Ind1: x${ind1}x - Ind2: x${ind2}x");
	
#	$ind1 = "\'$ind1\'";
#	$ind2 = "\'$ind2\'";
		
	# Daten mit mapping-Datein in interne MARC21-Struktur ueberfuehren
	my $marcfields_ref = {};

	# Titeldaten
	foreach my $marcdef_ref (@{$title_mapping_ref->{$marcfield}}){
	    if ($logger->is_debug){
		$logger->debug(YAML::Dump($marcdef_ref));
	    }
	    
	    my $mab2_field = $marcdef_ref->{from_field};
	    if (defined $fields_ref->{$mab2_field}){
		
		foreach my $thisfield_ref (@{$fields_ref->{$mab2_field}}){
		    if (!defined $marcfields_ref->{$thisfield_ref->{mult}}){
			$marcfields_ref->{$thisfield_ref->{mult}} = [];
		    }
		    push @{$marcfields_ref->{$thisfield_ref->{mult}}}, {
			ind1 => $ind1,
			ind2 => $ind2,
			subfield => $marcdef_ref->{subfield},
			content => cleanup($thisfield_ref->{content}),
		    }
		}
	    }
	}

	if ($logger->is_debug){
	    $logger->debug(YAML::Dump($marcfields_ref));
	}

	# Nachtraegliche Korrekturen
	
	# 773 $i = Enthalten In zusaetzlich setzen fuer Aufsaetze in 773 80
	{
	    foreach my $mult (sort keys %{$marcfields_ref}){
		foreach my $thisitem_ref (@{$marcfields_ref->{$mult}}){
		    if ($fieldno eq "773" && $thisitem_ref->{ind1} eq "0" && $thisitem_ref->{ind2} eq "8" && $thisitem_ref->{subfield} eq "t"){
			push @{$marcfields_ref->{$mult}}, {
			    ind1     => $thisitem_ref->{ind1},
			    ind2     => $thisitem_ref->{ind2},
			    subfield => "i",
			    content  => "Enthalten in",
			}
		    }
		}
	    }
	}

	# 773 $t = In: zusaetzlich setzen fuer Aufsaetze in 773 80 entfernen, da redundant zu $i
	{
	    foreach my $mult (sort keys %{$marcfields_ref}){
		foreach my $thisitem_ref (@{$marcfields_ref->{$mult}}){
		    if ($fieldno eq "773" && $thisitem_ref->{ind1} eq "0" && $thisitem_ref->{ind2} eq "8" && $thisitem_ref->{subfield} eq "t"){
			$thisitem_ref->{content} =~s/^In:\s+//;
		    }
		}
	    }
	}
	
	# Sortierung Subfelder 773 08: i - t - b - d - g - k - w - x - z
	{
	    foreach my $mult (sort keys %{$marcfields_ref}){
		my $new_marcmult_ref = [];
		foreach my $subfield ('i','t','b','d','g','k','w','x','z'){
		    foreach my $thisitem_ref (@{$marcfields_ref->{$mult}}){
			if ($fieldno eq "773" && $thisitem_ref->{ind1} eq "0" && $thisitem_ref->{ind2} eq "8" && $thisitem_ref->{subfield} eq $subfield){
			    push @{$new_marcmult_ref}, {
				ind1     => $thisitem_ref->{ind1},
				ind2     => $thisitem_ref->{ind2},
				subfield => $thisitem_ref->{subfield},
				content  => $thisitem_ref->{content},
			    };
			}
		    }
		}
		if (@{$new_marcmult_ref}){
		    $marcfields_ref->{$mult} = $new_marcmult_ref;
		}		
	    }
	}
	
	# Aus interner MARC21-Struktur valide MARC21-Ausgabedaten erzeugen
	foreach my $mult (sort keys %{$marcfields_ref}){
	    my $first = 1;
	    my $new_field;
	    foreach my $thisitem_ref (@{$marcfields_ref->{$mult}}){
		
		if ($first){
		    $new_field = MARC::Field->new($fieldno, $thisitem_ref->{ind1}, $thisitem_ref->{ind2}, $thisitem_ref->{subfield} => $thisitem_ref->{content});

		}
		else {
		    $new_field->add_subfields($thisitem_ref->{subfield} => $thisitem_ref->{content});
		}
		$first = 0;
	    }
	    push @{$output_fields_ref->{$fieldno}}, $new_field if ($new_field);	    
#	    $marc_record->append_fields($new_field) if ($new_field);	    
	}
    }

    
    # Felder aus output_fields_ref in MARC-Record setzen
    foreach my $fieldno (sort keys %{$output_fields_ref}){
	foreach my $field (@{$output_fields_ref->{$fieldno}}){
	    $marc_record->append_fields($field);
	}
    }
    
    if ($count % 1000 == 0) {
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $atime      = new Benchmark;
        $logger->info("### 1000 ($count) Titelsaetze in $resulttime bearbeitet");
    } 

    # Process Leader
    my $leader = $marc_record->leader();
    
    if ($update){
	substr($leader,5,1) = "c"; # changed
    }
    else {
	substr($leader,5,1) = "n"; # new	
    }

    # Bibliographic level
    my $biblevel="m"; # default: Monograph/Item
    if ($mediatype eq "AR" || $is_band){ # Artikel oder Band
	$biblevel="a"; # Monographic component part
    }
    elsif ($mediatype eq "CR"){ # Zeitschrift/Serie
	$biblevel="s"; # Serial
    }

    if ($is_serialpart){
	$biblevel="b"; # Serial component part
    }

    
    substr($leader,7,1) = $biblevel;

    substr($leader,9,1) = "a"; # Unicode
    
    # Encoding level: 1 Full level, material not examined ; blank Vallstaendiges Niveau
    substr($leader,17,1) = " ";

    # Descriptive cataloging form: ISBD punctuation omitted    
    substr($leader,18,1) = "c"; 

    
    $marc_record->leader($leader);
    
    print OUT $marc_record->as_usmarc;

    $count++;
}

if ($logger->is_debug){
    $logger->debug("Holding: ".YAML::Dump(\%data_holding));
}

$logger->info("### $count Titelsaetze bearbeitet");

close(IN);
close(OUT);

sub print_help {
    print << "ENDHELP";
meta2marc.pl - Erzeugung einer MARC21 Datei aus den Import-Dateien im MAB2 Metaformat

   Optionen:
   -help                 : Diese Informationsseite

   --database=...        : Name des Katalogs (wg. Basis-Pfad zu den meta.* Dateien)       
   --outputfile=...      : Name der MARC21 Ausgabedatei (default: output.mrc)
   --mappingfile=...     : Name der Datei mit Kategorie-Mappings
   --locationfile=...    : Definition valider Library-IDs (aus Feld 3330) sowie Umwandlung falscher IDs
   --isil=...            : ISIL fuer control number 001 (default: DE-38)
   --library-id=..       : Library-ID/ISIL fuer Exemplare
   -update               : Setzen der Update-Markierung c im Leader anstelle n
   --logfile=...         : Logfile inkl Pfad.
   --loglevel=...        : Loglevel

Beispiel:

./meta2marc.pl --database=aufsaetze --mappingfile=mab2marc_mapping.yml

ENDHELP
    exit;
}

sub supplement2relation {
    my $content = shift;

    my $relation = "";

    if ($content =~m/\[(Hrsg|Herausgeber|editor|Ed\.|edt|éditeur|Ermittelter Hrsg)/i){
	$relation = "edt";
    }
    elsif ($content =~m/Drucker/i){
	$relation = "prt";
    }
    elsif ($content =~m/\[Fotogr/i){
	$relation = "pht";
    }
    elsif ($content =~m/\[Schauspieler/i){
	$relation = "act";
    }
    elsif ($content =~m/\[Künstler/i){
	$relation = "art";
    }
    elsif ($content =~m/\[Architekt/i){
	$relation = "arc";
    }
    elsif ($content =~m/\[(Illustrator|Ill\.)/i){
	$relation = "ill";
    }
    elsif ($content =~m/\[Komponist/i){
	$relation = "cmp";
    }
    elsif ($content =~m/\[Stecher/i){
	$relation = "egr";
    }
    elsif ($content =~m/\[Art Director/i){
	$relation = "adi";
    }
    elsif ($content =~m/\[Verfasser eines Nachworts/i){
	$relation = "aft";
    }
    elsif ($content =~m/\[Trickfilmzeichner/i){
	$relation = "anm";
    }
    elsif ($content =~m/\[Arrangeur/i){
	$relation = "arr";
    }
    elsif ($content =~m/\[Kürzender/i){
	$relation = "abr";
    }
    elsif ($content =~m/\[Unterzeichner/i){
	$relation = "ato";
    }
    elsif ($content =~m/\[Tontechniker/i){
	$relation = "aue";
    }
    elsif ($content =~m/\[Verfasser eines Geleitworts/i){
	$relation = "aui";
    }
    elsif ($content =~m/\[Verfasser einer Einleitung/i){
	$relation = "win";
    }
    elsif ($content =~m/\[(Verfasser eines Vorworts|Vorwort)/i){
	$relation = "wpr";
    }
    elsif ($content =~m/\[Produzent einer Tonaufnahme/i){
	$relation = "aup";
    }
    elsif ($content =~m/\[Produzent/i){
	$relation = "pro";
    }
    elsif ($content =~m/\[Sonstige/i){
	$relation = "oth";
    }
    elsif ($content =~m/\[(Übers\.|Übersetzer)/i){
	$relation = "trl";
    }
    elsif ($content =~m/\[Adressat/i){
	$relation = "rcp";
    }
    elsif ($content =~m/\[Akademischer Betreuer/i){
	$relation = "dgs";
    }
    elsif ($content =~m/\[Gefeierter/i){
	$relation = "hnr";
    }
    elsif ($content =~m/\[Mitwirkender/i){
	$relation = "ctb";
    }
    elsif ($content =~m/\[Sammler/i){
	$relation = "col";
    }
    elsif ($content =~m/\[Sänger/i){
	$relation = "sng";
    }
    elsif ($content =~m/\[Textdichter/i){
	$relation = "lyr";
    }
    elsif ($content =~m/\[(Verf\.|Verfasser)/i){
	$relation = "aut";
    }
    elsif ($content =~m/\[Verfasser von ergänzendem Text/i){
	$relation = "wst";
    }
    elsif ($content =~m/\[Verfasser von Zusatztexten/i){
	$relation = "wat";
    }
    elsif ($content =~m/\[Zusammenstellender/i){
	$relation = "com";
    }
    elsif ($content =~m/\[Herausgebendes Organ/i){
	$relation = "isb";
    }
    elsif ($content =~m/\[Grad-verleihende Institution/i){
	$relation = "dgg";
    }
    elsif ($content =~m/\[Veranstalter/i){
	$relation = "orm";
    }
    
    return $relation;
}

sub cleanup {
    my $content = shift;

    $content=~s/&lt;/</g;
    $content=~s/&gt;/>/g;
    $content=~s/&amp;/&/g;
    $content=~s/¬//;
    
    return $content;
}
