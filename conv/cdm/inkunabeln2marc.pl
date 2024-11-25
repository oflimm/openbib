#!/usr/bin/perl

#####################################################################
#
#  inkunabeln2marc.pl
#
#  Generierung einer MARC21 Datei aus CDM-JSON-Daten von cdm_ctl.pl
#
#  basiert auf meta2marc.pl
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

my ($filename,$outputfile,$mappingfile,$locationfile,$isil,$libraryid,$logfile,$loglevel,$count,$update,$help);

&GetOptions(
    "filename=s"     => \$filename,    
    "outputfile=s"   => \$outputfile,
    "mappingfile=s"  => \$mappingfile,
    "locationfile=s" => \$locationfile,
    "library-id=s"   => \$libraryid,
    "isil=s"         => \$isil,
    "logfile=s"      => \$logfile,
    "loglevel=s"     => \$loglevel,
    "update"         => \$update,
    "help"           => \$help,
    );

if ($help || (!$mappingfile && ! -f $mappingfile )) {
    print_help();
}
    
$logfile=($logfile)?$logfile:"./inkunabeln2marc.log";
$loglevel=($loglevel)?$loglevel:"INFO";
$outputfile=($outputfile)?$outputfile:"./output.mrc";

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

# JSON-Daten kommen per API via cdm_ctl.pl aus CDM
#
# /opt/openbib/bin/cdm_ctl.pl --do=list_items --collection=inkunabeln --outputfile=inkunabeln.json
# /opt/openbib/bin/cdm_ctl.pl --do=list_items --collection=inkunabeln_tmp --outputfile=inkunabeln_tmp.json

$logger->info("### JSON-Titeldaten aus $filename verarbeiten");

open(IN , $filename )     || die "IN konnte nicht geoeffnet werden";

open(OUT, ">:utf8",$outputfile);

binmode (IN, ":raw");

$count = 1;

my $atime = new Benchmark;

my $mapping_ref = YAML::Syck::LoadFile($mappingfile);
my $title_mapping_ref = $mapping_ref->{convtab}{title};

while (my $json=<IN>){
    
    my $record_ref = decode_json $json;

    my $fields_ref = $record_ref->{fields};

    my $output_fields_ref = {};
                
    my $marc_record = new MARC::Record;
    
    my $titleid = $record_ref->{id};
    my $dbname = $record_ref->{dbname};

    $marc_record->add_fields('001',"cdm_".$dbname."_".$titleid);

    # Alle IDs in 035
    if (defined $fields_ref->{istc}){
	my @subfields = ();
	
	push (@subfields,'a', "(ISTC)".$fields_ref->{istc}[0]{content});
	
	my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{gw}){
	my @subfields = ();
	
	push (@subfields,'a', "(GW)".$fields_ref->{gw}[0]{content});
	
	my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{katkey}){
	my @subfields = ();
	
	push (@subfields,'a', "(DE-38)".$fields_ref->{katkey}[0]{content});
	
	my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{hbzid}){
	my @subfields = ();
	
	push (@subfields,'a', "(DE-605)".$fields_ref->{hbzid}[0]{content});
	
	my $new_field = MARC::Field->new('035', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'035'}}, $new_field if ($new_field);
    }
    

    $marc_record->add_fields('003',$isil);

    my $last_tstamp = "1970-01-01 12:00:00";
    my $create_tstamp = "700101";
    
    if (defined $fields_ref->{'dmcreated'}){
	my $date = $fields_ref->{'dmcreated'}[0]{content};
	my ($year,$month,$day) = $date =~m/^(\d\d\d\d)-(\d\d)-(\d\d)$/;

	if ($day && $month && $year && check_date($year,$month,$day)){
	    $last_tstamp = "$year$month$day"."120000.0";
	    $create_tstamp = substr($year,2,2)."$month$day";
	}

    }

    if (defined $fields_ref->{'dmmodified'}){
	my $date = $fields_ref->{'dmmodified'}[0]{content};
	my ($year,$month,$day) = $date =~m/^(\d\d\d\d)-(\d\d)-(\d\d)$/;
	
	if ($day && $month && $year && check_date($year,$month,$day)){
	    $last_tstamp = "$year$month$day"."120000.0";
	}
    }

    $marc_record->add_fields('005',$last_tstamp);

    $marc_record->add_fields('007','tu');

    my $fixed_length_008 = "700101|1970####xxu###########|||#|#eng#c"; # example

    my $year = "";    
    if (defined $fields_ref->{'jahr'}){
	($year) = $fields_ref->{'jahr'}[0]{content} =~m/(\d\d\d\d)/;
    }

    my $lang = '###';

    if (defined $fields_ref->{'sprach'}){
	my $thislang = $fields_ref->{'sprach'}[0]{content};

	if ($thislang=~m/lat/i){
	    $thislang = "lat";
	}
	
	if (defined $iso_639_2_ref->{$thislang} && $iso_639_2_ref->{$thislang}){
	    $lang = $thislang;

	    my @subfields = ();
	    
	    push (@subfields,'a', $lang);

	    my $new_field = MARC::Field->new('041', ' ',  ' ', @subfields);
	    
	    push @{$output_fields_ref->{'041'}}, $new_field if ($new_field);
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
    
    if ($logger->is_debug){
	$logger->debug(YAML::Dump($fields_ref));
    }

    # Normdaten processen

    my $have_1xx = 0; # Geistiger Schoepfer / Haupteintragung

    my $firstpersonid = 0;

    if (defined $fields_ref->{'creato'}){
	$have_1xx = 1
    }
    
    if ($have_1xx){
	# Erste in 100 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'creato'}[0]{content}));

	# GND
	if (defined $fields_ref->{'pnd'}){
	    push (@subfields,'0', "(DE-588)".$fields_ref->{'pnd'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "aut");
	
	my $new_field = MARC::Field->new('100', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'100'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{weiter}){ # 2. Verfasser (inkunab_tmp)
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'weiter'}[0]{content}));

	# GND
	if (defined $fields_ref->{'pnda'}){
	    push (@subfields,'0', "(DE-588)".$fields_ref->{'pnda'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "aut");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{weitea}){ # 3. Verfasser (inkunab_tmp)
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'weitea'}[0]{content}));

	# GND
	if (defined $fields_ref->{'pndnum'}){
	    push (@subfields,'0', "(DE-588)".$fields_ref->{'pndnum'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "aut");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{editor}){ # 1. Herausgeber
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'editor'}[0]{content}));

	# GND
	if (defined $fields_ref->{'hsrg'}){
	    push (@subfields,'0', "(DE-588)".$fields_ref->{'hsrg'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "edt");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{heraus}){ # 2. Herausgeber
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'heraus'}[0]{content}));

	# GND
	if (defined $fields_ref->{'heraub'}){
	    push (@subfields,'0', "(DE-588)".$fields_ref->{'heraub'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "edt");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{berset}){ # 1. Ubersetzer
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'berset'}[0]{content}));

	# GND
	if (defined $fields_ref->{'berseb'}){
	    push (@subfields,'0', "(DE-588)".$fields_ref->{'berseb'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "trl");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{bersec}){ # 2. Ubersetzer
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'bersec'}[0]{content}));

	# GND
	if (defined $fields_ref->{'bersee'}){
	    push (@subfields,'0', "(DE-588)".$fields_ref->{'bersee'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "trl");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{daran} || defined $fields_ref->{daranb} || defined $fields_ref->{darana}){ # Daran 
	# Erste in 700 12

	my @subfields = ();

	my $daran = $fields_ref->{'daran'}[0]{content} || '';
	my $darana = $fields_ref->{'darana'}[0]{content} || '';	
	my $daranb = $fields_ref->{'daranb'}[0]{content} || '';

	# Ansetzungsform
	if ($daranb){ # Daran 1. Verfasser
	    push (@subfields,'a', cleanup($daranb));
	    push (@subfields,'t', cleanup($daran)) if ($daran);

	    # GND
	    if (defined $fields_ref->{'darinc'}){
		push (@subfields,'0', "(DE-588)".$fields_ref->{'darinc'}[0]{content});
	    }

	    my $new_field = MARC::Field->new('700', '1',  '2', @subfields);
	
	    push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
	}

	if ($darana){ # Daran 2. Verfasser
	    push (@subfields,'a', cleanup($daranb));
	    push (@subfields,'t', cleanup($daran)) if ($daran);

	    # GND
	    if (defined $fields_ref->{'darinf'}){
		push (@subfields,'0', "(DE-588)".$fields_ref->{'darinf'}[0]{content});
	    }
	    
	    my $new_field = MARC::Field->new('700', '1',  '2', @subfields);
	
	    push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
	}
	
    }

    if (defined $fields_ref->{darin} || defined $fields_ref->{darina}){ # Darin 
	# Erste in 700 12

	my @subfields = ();

	my $darin = $fields_ref->{'darin'}[0]{content} || '';
	my $darina = $fields_ref->{'darina'}[0]{content} || '';	

	# Ansetzungsform
	if ($darina){ # Darin 1. Verfasser
	    push (@subfields,'a', cleanup($darina));
	    push (@subfields,'t', cleanup($darin)) if ($darin);

	    # GND
	    if (defined $fields_ref->{'darinc'}){
		push (@subfields,'0', "(DE-588)".$fields_ref->{'darinc'}[0]{content});
	    }

	    my $new_field = MARC::Field->new('700', '1',  '2', @subfields);
	
	    push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
	}
	
    }
    
    if (defined $fields_ref->{drucko}){ # Druckort
	# Druckort in 264 #1
	# Druckort in 751 ##
	
	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'drucko'}[0]{content}));
	
	push (@subfields,'0', cleanup($fields_ref->{'drucko'}[0]{content}));
	
	# Relationship
	push (@subfields,'4', "mfp");
	
	my $new_field = MARC::Field->new('751', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'751'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{ersche}){ # Erscheinungsort
	# Druckort in 264 #1
	# Druckort in 751 ##
	
	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'ersche'}[0]{content}));
	
	push (@subfields,'0', cleanup($fields_ref->{'ersche'}[0]{content}));
	
	# Relationship
	push (@subfields,'4', "pub");
	
	my $new_field = MARC::Field->new('751', ' ',  ' ', @subfields);
	
	push @{$output_fields_ref->{'751'}}, $new_field if ($new_field);
    }
    
    if (defined $fields_ref->{drucke}){ # 1. Drucker
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'drucke'}[0]{content}));


	# Relationship
	push (@subfields,'4', "prt");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{a}){ # 2. Drucker
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'a'}[0]{content}));


	# Relationship
	push (@subfields,'4', "prt");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{aa}){ # 3. Drucker
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'aa'}[0]{content}));


	# Relationship
	push (@subfields,'4', "prt");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    if (defined $fields_ref->{ab}){ # 4. Drucker
	# Erste in 700 1#

	my @subfields = ();

	# Ansetzungsform
	push (@subfields,'a', cleanup($fields_ref->{'ab'}[0]{content}));


	# Relationship
	push (@subfields,'4', "prt");
	
	my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	
	push @{$output_fields_ref->{'700'}}, $new_field if ($new_field);
    }

    # Typ
    {
	my @subfields = ();
	
	push (@subfields,'a', "Inkunabel");
	push (@subfields,'0', "(DE-588)4027041-5");	
	push (@subfields,'2', "rdacontent");
	
	my $new_field = MARC::Field->new('655', ' ',  '7', @subfields);
	
	push @{$output_fields_ref->{'655'}}, $new_field if ($new_field);
    }
    
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
	# Aufsplitten von Illustrationsangaben aus 0433 nach 0434
	if (defined $fields_ref->{'umfang'}){
	    foreach my $thisfield_ref (@{$fields_ref->{'umfang'}}){
		my $content = $thisfield_ref->{content};

		if ($content =~m/^(.+?) : (.+)$/){
		    my $kollation = $1;
		    my $illustr   = $2;
		    $thisfield_ref->{content} = $kollation;
		    $fields_ref->{'illu'} = [];
		    push @{$fields_ref->{'illu'}}, {
			content  => $illustr,
			mult     => $thisfield_ref->{mult},
			subfield => $thisfield_ref->{subfield},
		    };
		}
		last;
	    }
	}
	
    }
    
    # Exemplardaten processen (Koha holding scheme)
    # https://wiki.koha-community.org/wiki/Holdings_data_fields_(9xx)

    my $holdings_ref = [];

    my $holding_mult = 1;
    if (defined $fields_ref->{signat}){
	push @{$holdings_ref}, {
	    '0014' => [
		{
		    content => $fields_ref->{signat}[0]{content},
		    mult => $holding_mult,
		},
		],
		'3330' => [
		    {
			content => 'DE-38',
			mult => $holding_mult,
		    },
		],
	};
	$holding_mult++;
    }

    if (defined $fields_ref->{weitec}){
	push @{$holdings_ref}, {
	    '0014' => [
		{
		    content => $fields_ref->{weitec}[0]{content},
		    mult => $holding_mult,
		},
		],
		'3330' => [
		    {
			content => 'DE-38',
			mult => $holding_mult,
		    },
		],
	};
	$holding_mult++;
    }
    
    # Exemplardaten processen (Koha holding scheme)
    # https://wiki.koha-community.org/wiki/Holdings_data_fields_(9xx)
    if (@$holdings_ref){

	if ($logger->is_debug){
	    $logger->debug("Holdings for $titleid: ".YAML::Dump($holdings_ref));
	}
	
	# Iteration ueber Exemplare

	foreach my $thisholding_ref (@{$holdings_ref}){
	    my @subfields = ();

	    my $this_libraryid = "";

	    $this_libraryid = $libraryid if ($libraryid);
	    
	    push (@subfields,'o', $thisholding_ref->{'0014'}[0]{content}) if (defined $thisholding_ref->{'0014'}[0]{content});
	    
	    if (!$this_libraryid && defined $thisholding_ref->{'3330'}){
		$this_libraryid = $thisholding_ref->{'3330'}[0]{content};
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

$logger->info("### $count Titelsaetze bearbeitet");

close(IN);
close(OUT);

sub print_help {
    print << "ENDHELP";
inkunabeln2marc.pl - Erzeugung einer MARC21 Datei aus der JSON-API Export-Datei

   Optionen:
   -help                 : Diese Informationsseite

   --outputfile=...      : Name der MARC21 Ausgabedatei (default: output.mrc)
   --mappingfile=...     : Name der Datei mit Kategorie-Mappings
   --locationfile=...    : Definition valider Library-IDs (aus Feld 3330) sowie Umwandlung falscher IDs
   --isil=...            : ISIL fuer control number 001 (default: DE-38)
   --library-id=..       : Library-ID/ISIL fuer Exemplare
   -update               : Setzen der Update-Markierung c im Leader anstelle n
   --logfile=...         : Logfile inkl Pfad.
   --loglevel=...        : Loglevel

Beispiel:

./inkunabeln2marc.pl --mappingfile=inkunabeln2marc_mapping.yml

ENDHELP
    exit;
}

sub cleanup {
    my $content = shift;

    $content=~s/&lt;/</g;
    $content=~s/&gt;/>/g;
    $content=~s/&amp;/&/g;
    $content=~s/¬//;
    
    return $content;
}
