#!/usr/bin/perl

#####################################################################
#
#  bcp2meta.pl
#
#  Aufloesung der mit bcp exportierten Blob-Daten in den Normdateien 
#  und Konvertierung in ein Metaformat.
#  Zusaetzlich werden die Daten in einem leicht modifizierten
#  Original-Format ausgegeben.
#
#  Routinen zum Aufloesen der Blobs (das intellektuelle Herz
#  des Programs):
#
#  Copyright 2003 Friedhelm Komossa
#                 <friedhelm.komossa@uni-muenster.de>
#
#  Programm, Konvertierungsroutinen in das Metaformat
#  und generelle Optimierung auf Bulk-Konvertierungen
#
#  Copyright 2003-2013 Oliver Flimm
#                      <flimm@openbib.org>
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

use 5.008000;
#use warnings;
use strict;
use utf8;

use Encode;
use Getopt::Long;
use JSON::XS;
#use MLDBM qw(DB_File Storable);
use Storable ();

our ($bcppath,$usestatus,$useusbschema,$used01buch,$used01buchstandort,$usemcopynum,$blobencoding,$reducemem);

&GetOptions(
    "reduce-mem"           => \$reducemem,
    "bcp-path=s"           => \$bcppath,
    "blob-encoding=s"      => \$blobencoding, # V<4.0: iso-8859-1, V>=4.0: utf8
    "use-d01buch"          => \$used01buch,
    "use-status"           => \$usestatus,
    "use-usbschema"        => \$useusbschema,
    "use-d01buch-standort" => \$used01buchstandort,
    "use-mcopynum"         => \$usemcopynum,
);

# Konfiguration:

our $valid_lang_code_ref = {
   'aar' => 1,
   'abk' => 1,
   'ace' => 1,
   'ach' => 1,
   'ada' => 1,
   'ady' => 1,
   'afa' => 1,
   'afh' => 1,
   'afr' => 1,
   'ain' => 1,
   'aka' => 1,
   'akk' => 1,
   'alb' => 1,
   'ale' => 1,
   'alg' => 1,
   'alt' => 1,
   'amh' => 1,
   'ang' => 1,
   'anp' => 1,
   'apa' => 1,
   'ara' => 1,
   'arc' => 1,
   'arg' => 1,
   'arm' => 1,
   'arn' => 1,
   'arp' => 1,
   'art' => 1,
   'arw' => 1,
   'asm' => 1,
   'ast' => 1,
   'ath' => 1,
   'aus' => 1,
   'ava' => 1,
   'ave' => 1,
   'awa' => 1,
   'aym' => 1,
   'aze' => 1,
   'bad' => 1,
   'bai' => 1,
   'bak' => 1,
   'bal' => 1,
   'bam' => 1,
   'ban' => 1,
   'baq' => 1,
   'bas' => 1,
   'bat' => 1,
   'bej' => 1,
   'bel' => 1,
   'bem' => 1,
   'ben' => 1,
   'ber' => 1,
   'bho' => 1,
   'bih' => 1,
   'bik' => 1,
   'bin' => 1,
   'bis' => 1,
   'bla' => 1,
   'bnt' => 1,
   'tib' => 1,
   'bos' => 1,
   'bra' => 1,
   'bre' => 1,
   'btk' => 1,
   'bua' => 1,
   'bug' => 1,
   'bul' => 1,
   'bur' => 1,
   'byn' => 1,
   'cad' => 1,
   'cai' => 1,
   'car' => 1,
   'cat' => 1,
   'cau' => 1,
   'ceb' => 1,
   'cel' => 1,
   'cze' => 1,
   'cha' => 1,
   'chb' => 1,
   'che' => 1,
   'chg' => 1,
   'chi' => 1,
   'chk' => 1,
   'chm' => 1,
   'chn' => 1,
   'cho' => 1,
   'chp' => 1,
   'chr' => 1,
   'chu' => 1,
   'chv' => 1,
   'chy' => 1,
   'cmc' => 1,
   'cop' => 1,
   'cor' => 1,
   'cos' => 1,
   'cpe' => 1,
   'cpf' => 1,
   'cpp' => 1,
   'cre' => 1,
   'crh' => 1,
   'crp' => 1,
   'csb' => 1,
   'cus' => 1,
   'wel' => 1,
   'cze' => 1,
   'dak' => 1,
   'dan' => 1,
   'dar' => 1,
   'day' => 1,
   'del' => 1,
   'den' => 1,
   'ger' => 1,
   'dgr' => 1,
   'din' => 1,
   'div' => 1,
   'doi' => 1,
   'dra' => 1,
   'dsb' => 1,
   'dua' => 1,
   'dum' => 1,
   'dut' => 1,
   'dyu' => 1,
   'dzo' => 1,
   'efi' => 1,
   'egy' => 1,
   'eka' => 1,
   'gre' => 1,
   'ell' => 1,
   'elx' => 1,
   'eng' => 1,
   'enm' => 1,
   'epo' => 1,
   'est' => 1,
   'baq' => 1,
   'ewe' => 1,
   'ewo' => 1,
   'fan' => 1,
   'fao' => 1,
   'per' => 1,
   'fat' => 1,
   'fij' => 1,
   'fil' => 1,
   'fin' => 1,
   'fiu' => 1,
   'fon' => 1,
   'fre' => 1,
   'frm' => 1,
   'fro' => 1,
   'frr' => 1,
   'frs' => 1,
   'fry' => 1,
   'ful' => 1,
   'fur' => 1,
   'gaa' => 1,
   'gay' => 1,
   'gba' => 1,
   'gem' => 1,
   'geo' => 1,
   'ger' => 1,
   'gez' => 1,
   'gil' => 1,
   'gla' => 1,
   'gle' => 1,
   'glg' => 1,
   'glv' => 1,
   'gmh' => 1,
   'goh' => 1,
   'gon' => 1,
   'gor' => 1,
   'got' => 1,
   'grb' => 1,
   'grc' => 1,
   'gre' => 1,
   'grn' => 1,
   'gsw' => 1,
   'guj' => 1,
   'gwi' => 1,
   'hai' => 1,
   'hat' => 1,
   'hau' => 1,
   'haw' => 1,
   'heb' => 1,
   'her' => 1,
   'hil' => 1,
   'him' => 1,
   'hin' => 1,
   'hit' => 1,
   'hmn' => 1,
   'hmo' => 1,
   'hrv' => 1,
   'hsb' => 1,
   'hun' => 1,
   'hup' => 1,
   'arm' => 1,
   'iba' => 1,
   'ibo' => 1,
   'ice' => 1,
   'ido' => 1,
   'iii' => 1,
   'ijo' => 1,
   'iku' => 1,
   'ile' => 1,
   'ilo' => 1,
   'ina' => 1,
   'inc' => 1,
   'ind' => 1,
   'ine' => 1,
   'inh' => 1,
   'ipk' => 1,
   'ira' => 1,
   'iro' => 1,
   'ice' => 1,
   'ita' => 1,
   'jav' => 1,
   'jbo' => 1,
   'jpn' => 1,
   'jpr' => 1,
   'jrb' => 1,
   'kaa' => 1,
   'kab' => 1,
   'kac' => 1,
   'kal' => 1,
   'kam' => 1,
   'kan' => 1,
   'kar' => 1,
   'kas' => 1,
   'geo' => 1,
   'kau' => 1,
   'kaw' => 1,
   'kaz' => 1,
   'kbd' => 1,
   'kha' => 1,
   'khi' => 1,
   'khm' => 1,
   'kho' => 1,
   'kik' => 1,
   'kin' => 1,
   'kir' => 1,
   'kmb' => 1,
   'kok' => 1,
   'kom' => 1,
   'kon' => 1,
   'kor' => 1,
   'kos' => 1,
   'kpe' => 1,
   'krc' => 1,
   'krl' => 1,
   'kro' => 1,
   'kru' => 1,
   'kua' => 1,
   'kum' => 1,
   'kur' => 1,
   'kut' => 1,
   'lad' => 1,
   'lah' => 1,
   'lam' => 1,
   'lao' => 1,
   'lat' => 1,
   'lav' => 1,
   'lez' => 1,
   'lim' => 1,
   'lin' => 1,
   'lit' => 1,
   'lol' => 1,
   'loz' => 1,
   'ltz' => 1,
   'lua' => 1,
   'lub' => 1,
   'lug' => 1,
   'lui' => 1,
   'lun' => 1,
   'luo' => 1,
   'lus' => 1,
   'mac' => 1,
   'mad' => 1,
   'mag' => 1,
   'mah' => 1,
   'mai' => 1,
   'mak' => 1,
   'mal' => 1,
   'man' => 1,
   'mao' => 1,
   'map' => 1,
   'mar' => 1,
   'mas' => 1,
   'may' => 1,
   'mdf' => 1,
   'mdr' => 1,
   'men' => 1,
   'mga' => 1,
   'mic' => 1,
   'min' => 1,
   'mis' => 1,
   'mac' => 1,
   'mkh' => 1,
   'mlg' => 1,
   'mlt' => 1,
   'mnc' => 1,
   'mni' => 1,
   'mno' => 1,
   'moh' => 1,
   'mon' => 1,
   'mos' => 1,
   'mao' => 1,
   'may' => 1,
   'mul' => 1,
   'mun' => 1,
   'mus' => 1,
   'mwl' => 1,
   'mwr' => 1,
   'myn' => 1,
   'myv' => 1,
   'nah' => 1,
   'nai' => 1,
   'nap' => 1,
   'nau' => 1,
   'nav' => 1,
   'nbl' => 1,
   'nde' => 1,
   'ndo' => 1,
   'nds' => 1,
   'nep' => 1,
   'new' => 1,
   'nia' => 1,
   'nic' => 1,
   'niu' => 1,
   'nno' => 1,
   'nob' => 1,
   'nog' => 1,
   'non' => 1,
   'nor' => 1,
   'nqo' => 1,
   'nso' => 1,
   'nub' => 1,
   'nwc' => 1,
   'nya' => 1,
   'nym' => 1,
   'nyn' => 1,
   'nyo' => 1,
   'nzi' => 1,
   'oci' => 1,
   'oji' => 1,
   'ori' => 1,
   'orm' => 1,
   'osa' => 1,
   'oss' => 1,
   'ota' => 1,
   'oto' => 1,
   'paa' => 1,
   'pag' => 1,
   'pal' => 1,
   'pam' => 1,
   'pan' => 1,
   'pap' => 1,
   'pau' => 1,
   'peo' => 1,
   'per' => 1,
   'phi' => 1,
   'phn' => 1,
   'pli' => 1,
   'pol' => 1,
   'pon' => 1,
   'por' => 1,
   'pra' => 1,
   'pro' => 1,
   'pus' => 1,
   'que' => 1,
   'raj' => 1,
   'rap' => 1,
   'rar' => 1,
   'roa' => 1,
   'roh' => 1,
   'rom' => 1,
   'rum' => 1,
   'run' => 1,
   'rup' => 1,
   'rus' => 1,
   'sad' => 1,
   'sag' => 1,
   'sah' => 1,
   'sai' => 1,
   'sal' => 1,
   'sam' => 1,
   'san' => 1,
   'sas' => 1,
   'sat' => 1,
   'scn' => 1,
   'sco' => 1,
   'sel' => 1,
   'sem' => 1,
   'sga' => 1,
   'sgn' => 1,
   'shn' => 1,
   'sid' => 1,
   'sin' => 1,
   'sio' => 1,
   'sit' => 1,
   'sla' => 1,
   'slo' => 1,
   'slv' => 1,
   'sma' => 1,
   'sme' => 1,
   'smi' => 1,
   'smj' => 1,
   'smn' => 1,
   'smo' => 1,
   'sms' => 1,
   'sna' => 1,
   'snd' => 1,
   'snk' => 1,
   'sog' => 1,
   'som' => 1,
   'son' => 1,
   'sot' => 1,
   'spa' => 1,
   'alb' => 1,
   'srd' => 1,
   'srn' => 1,
   'srp' => 1,
   'srr' => 1,
   'ssa' => 1,
   'ssw' => 1,
   'suk' => 1,
   'sun' => 1,
   'sus' => 1,
   'sux' => 1,
   'swa' => 1,
   'swe' => 1,
   'syc' => 1,
   'syr' => 1,
   'tah' => 1,
   'tai' => 1,
   'tam' => 1,
   'tat' => 1,
   'tel' => 1,
   'tem' => 1,
   'ter' => 1,
   'tet' => 1,
   'tgk' => 1,
   'tgl' => 1,
   'tha' => 1,
   'tib' => 1,
   'tig' => 1,
   'tir' => 1,
   'tiv' => 1,
   'tkl' => 1,
   'tlh' => 1,
   'tli' => 1,
   'tmh' => 1,
   'tog' => 1,
   'ton' => 1,
   'tpi' => 1,
   'tsi' => 1,
   'tsn' => 1,
   'tso' => 1,
   'tuk' => 1,
   'tum' => 1,
   'tup' => 1,
   'tur' => 1,
   'tut' => 1,
   'tvl' => 1,
   'twi' => 1,
   'tyv' => 1,
   'udm' => 1,
   'uga' => 1,
   'uig' => 1,
   'ukr' => 1,
   'umb' => 1,
   'und' => 1,
   'urd' => 1,
   'uzb' => 1,
   'vai' => 1,
   'ven' => 1,
   'vie' => 1,
   'vol' => 1,
   'vot' => 1,
   'wak' => 1,
   'wal' => 1,
   'war' => 1,
   'was' => 1,
   'wel' => 1,
   'wen' => 1,
   'wln' => 1,
   'wol' => 1,
   'xal' => 1,
   'xho' => 1,
   'yao' => 1,
   'yap' => 1,
   'yid' => 1,
   'yor' => 1,
   'ypk' => 1,
   'zap' => 1,
   'zbl' => 1,
   'zen' => 1,
   'zgh' => 1,
   'zha' => 1,
   'znd' => 1,
   'zul' => 1,
   'zun' => 1,
   'zxx' => 1,
   'zza' => 1,
};

our %lang_replacements = (
    'aa' => 'aar',
    'ab' => 'abk',
    'af' => 'afr',
    'ak' => 'aka',
    'am' => 'amh',
    'ar' => 'ara',
    'an' => 'arg',
    'as' => 'asm',
    'av' => 'ava',
    'ae' => 'ave',
    'ay' => 'aym',
    'az' => 'aze',
    'ba' => 'bak',
    'bm' => 'bam',
    'be' => 'bel',
    'bn' => 'ben',
    'bh' => 'bih',
    'bi' => 'bis',
    'bs' => 'bos',
    'br' => 'bre',
    'bo' => 'tib',
    'bod' => 'tib',
    'bg' => 'bul',
    'ca' => 'cat',
    'ch' => 'cha',
    'ce' => 'che',
    'cs' => 'cze',
    'ces' => 'cze',
    'cu' => 'chu',
    'cv' => 'chv',
    'kw' => 'cor',
    'co' => 'cos',
    'cr' => 'cre',
    'cy' => 'wel',
    'cym' => 'wel',
    'da' => 'dan',
    'de' => 'ger',
    'deu' => 'ger',
    'nld' => 'dut',
    'dut/nla' => 'dut',
    'dv' => 'div',
    'dz' => 'dzo',
    'en' => 'eng',
    'eo' => 'epo',
    'esl/spa' => 'spa',
    'et' => 'est',
    'ee' => 'ewe',
    'el' => 'gre',
    'ell' => 'gre',
    'eu' => 'baq',
    'eus' => 'baq',
    'fa' => 'per',
    'fas' => 'per',
    'fr' => 'fre',
    'fra' => 'fre',
    'fo' => 'fao',
    'fj' => 'fij',
    'fi' => 'fin',
    'fy' => 'fry',
    'ff' => 'ful',
    'gd' => 'gla',
    'ga' => 'gle',
    'gl' => 'glg',
    'gv' => 'glv',
    'gn' => 'grn',
    'gu' => 'guj',
    'ht' => 'hat',
    'ha' => 'hau',
    'he' => 'heb',
    'hz' => 'her',
    'hi' => 'hin',
    'ho' => 'hmo',
    'hr' => 'hrv',
    'hu' => 'hun',
    'hy' => 'arm',
    'hye' => 'arm',
    'ig' => 'ibo',
    'io' => 'ido',
    'ii' => 'iii',
    'iu' => 'iku',
    'ie' => 'ile',
    'ia' => 'ina',
    'id' => 'ind',
    'ik' => 'ipk',
    'is' => 'ice',
    'isl' => 'ice',
    'it' => 'ita',
    'jv' => 'jav',
    'ja' => 'jpn',
    'ka' => 'geo',
    'kat' => 'geo',
    'kl' => 'kal',
    'kn' => 'kan',
    'ks' => 'kas',
    'kr' => 'kau',
    'kk' => 'kaz',
    'km' => 'khm',
    'ki' => 'kik',
    'rw' => 'kin',
    'ky' => 'kir',
    'kv' => 'kom',
    'kg' => 'kon',
    'ko' => 'kor',
    'kj' => 'kua',
    'ku' => 'kur',
    'lo' => 'lao',
    'la' => 'lat',
    'lv' => 'lav',
    'li' => 'lim',
    'ln' => 'lin',
    'lt' => 'lit',
    'lb' => 'ltz',
    'lu' => 'lub',
    'lg' => 'lug',
    'mi' => 'mao',
    'mri' => 'mao',
    'mk' => 'mac',
    'mka' => 'mac',
    'mh' => 'mah',
    'ml' => 'mal',
    'mr' => 'mar',
    'mg' => 'mlg',
    'ms' => 'may',
    'msa' => 'may',
    'mt' => 'mlt',
    'mn' => 'mon',
    'my' => 'bur',
    'mya' => 'bur',
    'na' => 'nau',
    'nv' => 'nav',
    'nr' => 'nbl',
    'nd' => 'nde',
    'ng' => 'ndo',
    'ne' => 'nep',
    'nl' => 'dut',
    'nn' => 'nno',
    'nb' => 'nob',
    'no' => 'nor',
    'ny' => 'nya',
    'oc' => 'oci',
    'oj' => 'oji',
    'or' => 'ori',
    'om' => 'orm',
    'os' => 'oss',
    'pa' => 'pan',
    'pi' => 'pli',
    'pl' => 'pol',
    'pt' => 'por',
    'ps' => 'pus',
    'qu' => 'que',
    'rm' => 'roh',
    'rn' => 'run',
    'ro' => 'rum',
    'ron' => 'rum',
    'ru' => 'rus',
    'sg' => 'sag',
    'sa' => 'san',
    'si' => 'sin',
    'sl' => 'slv',
    'se' => 'sme',
    'sm' => 'smo',
    'sn' => 'sna',
    'sd' => 'snd',
    'so' => 'som',
    'st' => 'sot',
    'es' => 'spa',
    'sc' => 'srd',
    'sk' => 'slo',
    'slk' => 'slo',
    'sq' => 'alb',
    'sqi' => 'alb',
    'sr' => 'srp',
    'ss' => 'ssw',
    'su' => 'sun',
    'sw' => 'swa',
    'sv' => 'swe',
    'ty' => 'tah',
    'ta' => 'tam',
    'tt' => 'tat',
    'te' => 'tel',
    'tg' => 'tgk',
    'tl' => 'tgl',
    'th' => 'tha',
    'ti' => 'tir',
    'to' => 'ton',
    'tn' => 'tsn',
    'ts' => 'tso',
    'tk' => 'tuk',
    'tr' => 'tur',
    'tw' => 'twi',
    'ug' => 'uig',
    'uk' => 'ukr',
    'ur' => 'urd',
    'uz' => 'uzb',
    've' => 'ven',
    'vi' => 'vie',
    'vo' => 'vol',
    'wa' => 'wln',
    'wo' => 'wol',
    'xh' => 'xho',
    'yi' => 'yid',
    'yo' => 'yor',
    'za' => 'zha',
    'zh' => 'chi',
    'zho' => 'chi',
    'zu' => 'zul',
);

my $langs_to_replace = join '|',
    keys %lang_replacements;

$langs_to_replace = qr/$langs_to_replace/;

# Wo liegen die bcp-Dateien

$bcppath=($bcppath)?$bcppath:"/tmp";
$blobencoding=($blobencoding)?$blobencoding:"utf8";

# Problematische Kategorien in den Titeln:
#
# - 0220.001 Entspricht der Verweisform, die eigentlich zu den
#            Koerperschaften gehoert.
#

my $subfield_transform_ref = {
    person => {
        '0806a' => '0200',      # Lebensjahre
        '0806i' => '0201',      # Beruf
        '0806c' => '0305',      # Geburtsort
    },
};

our $entl_map_ref = {
      'X' => 0, # nein
      ' ' => 1, # ja
      'L' => 2, # Lesesaal
      'B' => 3, # Bes. Lesesaal
      'W' => 4, # Wochenende
  };

###
## Feldstrukturtabelle auswerten
#

our ($fstab_ref,$subfield_ref) = read_fstab();

my %zweigstelle  = ();
my %abteilung    = ();
my %standort     = ();
my %buchdaten    = ();
my %titelbuchkey = ();

if ($reducemem) {
    #tie %buchdaten,        'MLDBM', "./buchdaten.db"
        #or die "Could not tie buchdaten.\n";

    #tie %titelbuchkey,     'MLDBM', "./titelbuchkey.db"
        #or die "Could not tie titelbuchkey.\n";
}

#goto WEITER;
###
## Normdateien einlesen
#

print STDERR  "Processing persons\n";

open(PER,"cat $bcppath/per_daten.bcp |");
#open(PERSIK,"|gzip > ./unload.PER.gz");
open(PERSIKJSON,"|gzip > ./meta.person.gz");
#binmode(PERSIK,     ":utf8");
binmode(PERSIKJSON);

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<PER>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    my %record  = decode_blob('person',$daten);

#    printf PERSIK "0000:%0d\n", $katkey;

    my $person_ref = {
        id     => $katkey,
        fields => {},
    };

    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;

        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content  = $record{$key};

        my $subfield = "";
        
        ($content,$subfield) = check_subfield('person',$field,$content) if (defined $subfield_ref->{'person'}{$field});
        
        my $thiskey = $key;
        my $newkey  = transform_subfield('person',$key,$subfield,$content) if (defined $subfield_ref->{'person'}{$field});

        if ($newkey) {
            $thiskey = $newkey;
            $content=~s/^[a-z]\|*//;
            $content=~s/\$\$.+$//;
            $content=~s/^\d\d\d\d\d\d\d-\d           //;

            # Aufteilung in Geburts/Sterbedatum, wenn genaue Datumsangaben in 0200
            if ($newkey eq "0200" && $content=~/\d\d\.\d\d\.\d\d\d\d/) {
                my ($dateofbirth) = $content=~/^(\d\d\.\d\d\.\d\d\d\d)-/;
                my ($dateofdeath) = $content=~/-(\d\d\.\d\d\.\d\d\d\d)$/;

                if ($dateofbirth) {
#                    print PERSIK "0304:".konv($dateofbirth)."\n";
                }

                if ($dateofdeath) {
#                    print PERSIK "0306:".konv($dateofdeath)."\n";
                }

                next;
            }
        }

        $content = konv($content);
            
#        print PERSIK $thiskey.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$person_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };

    }
    
    eval {
	print PERSIKJSON encode_json $person_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }
#    print PERSIK "9999:\n\n";    
}
close(PERSIKJSON);
close(PERSIK);
close(PER);

print STDERR  "Processing corporate bodies\n";

open(KOE,"cat $bcppath/koe_daten.bcp |");
#open(KOESIK,"| gzip >./unload.KOE.gz");
open(KOESIKJSON,"|gzip > ./meta.corporatebody.gz");
#binmode(KOESIK,     ":utf8");
binmode(KOESIKJSON);

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<KOE>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    my %record  = decode_blob('corporatebody',$daten);

#    printf KOESIK "0000:%0d\n", $katkey;

    my $corporatebody_ref = {
        id     => $katkey,
        fields => {},
    };

    foreach my $key (sort {$b cmp $a} keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content = konv($record{$key});

        my $subfield = "";
        
        ($content,$subfield) = check_subfield('corporatebody',$field,$content) if (defined $subfield_ref->{'corporatebody'}{$field});
        
#        print KOESIK $key.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$corporatebody_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };

    }

    eval {
	print KOESIKJSON encode_json $corporatebody_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }

#    print KOESIK "9999:\n\n";
}
close(KOESIKJSON);
#close(KOESIK);
close(KOE);

print STDERR  "Processing classifications\n";

open(SYS,"cat $bcppath/sys_daten.bcp |");
#open(SYSSIK,"| gzip >./unload.SYS.gz");
open(SYSSIKJSON,"| gzip >./meta.classification.gz");
#binmode(SYSSIK,     ":utf8");
binmode(SYSSIKJSON);

while (my ($katkey,$aktion,$reserv,$ansetzung,$daten) = split ("",<SYS>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    my %record  = decode_blob('classification',$daten);
        
#    printf SYSSIK "0000:%0d\n", $katkey;

    my $classification_ref = {
        id     => $katkey,
        fields => {},
    };

    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content = konv($record{$key});

        my $subfield = "";
        
        ($content,$subfield) = check_subfield('classification',$field,$content) if (defined $subfield_ref->{'classification'}{$field});
        
#        print SYSSIK $key.":".$content."\n" if ($record{$key} !~ /idn:/);

        push @{$classification_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };

    }

    eval {
	print SYSSIKJSON encode_json $classification_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }

#    print SYSSIK "9999:\n\n";
}
close(SYSSIKJSON);
#close(SYSSIK);
close(SYS);

print STDERR  "Processing subjects\n";

open(SWD,       "cat $bcppath/swd_daten.bcp |");
#open(SWDSIK,    "| gzip >./unload.SWD.gz");
open(SWDSIKJSON,"| gzip >./meta.subject.gz");
#binmode(SWDSIK,     ":utf8");
binmode(SWDSIKJSON);

while (my ($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<SWD>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);

    my %record  = decode_blob('subject',$daten);
    
#    printf SWDSIK "0000:%0d\n", $katkey;

    my $subject_ref = {
        id     => $katkey,
        fields => {},
    };

    # Schlagwortkettensonderbehandlung SIKIS
    # Nicht im JSON-Format!!!
    
    my @swtkette=();
    foreach my $key (sort {$b cmp $a} keys %record) {
        if ($key =~/^0800/) {
            $record{$key}=~s/^\(?[a-z]\)?([\p{Lu}0-9¬])/$1/; # Indikator herausfiltern
            push @swtkette, konv($record{$key});
        }
    }

    my $schlagw;
    
    if ($#swtkette > 0) {
        $schlagw=join (" / ",reverse @swtkette);

    } else {
        $schlagw=$swtkette[0];
    }

#    printf SWDSIK "0800.001:$schlagw\n" if ($schlagw !~ /idn:/);

    # Jetzt den Rest ausgeben.

    foreach my $key (sort {$b cmp $a} keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }
        
        my $content  = konv($record{$key});

        my $subfield = "";
        
        ($content,$subfield) = check_subfield('subject',$field,$content) if (defined $subfield_ref->{'subject'}{$field});

#        print SWDSIK $key.":".$content."\n" if ($record{$key} !~ /idn:/ && $key !~/^0800/);
    
        push @{$subject_ref->{fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };
    }

    eval {
	print SWDSIKJSON encode_json $subject_ref, "\n";
    };

    if ($@){
	print STDERR $@, "\n";
    }
    
#    print SWDSIK "9999:\n\n";
}

close(SWDSIKJSON);
#close(SWDSIK);
close(SWD);

#WEITER:
# cat eingefuegt, da bei 'zu grossen' bcp-Dateien bei Systemtools wie less oder perl
# ein Fehler bei open() auftritt:
# Fehler: Wert zu gro�ss fuer definierten Datentyp
# Daher Umweg ueber cat, bei dem dieses Problem nicht auftritt

print STDERR  "Processing titles and holdings\n";

if ($used01buch) {
    ###
    ## Zweigstellen auswerten
    #
    
    open(ZWEIG,"cat $bcppath/d50zweig.bcp |");
    while (<ZWEIG>) {
        my ($zwnr,$zwname)=split("",$_);
        $zweigstelle{$zwnr}=$zwname;
    }
    close(ZWEIG);
    
    if ($used01buchstandort){
	###
	## Originaeres Standortfeld auswerten
	#
	
	open(ORT,"cat $bcppath/d615standort.bcp |");
	while (<ORT>) {
	    my ($lfd,$standortkuerzel,$text)=split("",$_);
	    $standort{$standortkuerzel}=$text;
	}
	close(ORT);
    } 
    else {
	###
	## Abteilungen als "Standorte" auswerten
	#
	
	open(ABT,"cat $bcppath/d60abteil.bcp |");
	while (<ABT>) {
	    my ($zwnr,$abtnr,$abtname)=split("",$_);
	    $abteilung{$zwnr}{$abtnr}=$abtname;
	}
	close(ABT);
    }

    ###
    ## Titel-Buch-Key auswerten
    #

    if ($usemcopynum) {
        print STDERR  "Using mcopynum\n";
        open(TITELBUCHKEY,"cat $bcppath/titel_buch_key.bcp |");
        while (<TITELBUCHKEY>) {
            my ($katkey,$mcopynum,$seqnr)=split("",$_);
            push @{$titelbuchkey{$mcopynum}},$katkey;
        }
        close(TITELBUCHKEY);
    }
    
    ###
    ## Buchdaten auswerten
    #

    print STDERR  "Reading d01buch\n";
    open(D01BUCH,"cat $bcppath/d01buch.bcp |");
    while (<D01BUCH>) {
        my @line = split("",$_);

        if ($usemcopynum) {            
            my ($d01gsi,$d01ex,$d01zweig,$d01entl,$d01mcopynum,$d01status,$d01skond,$d01ort,$d01abtlg,$d01standort)=@line[0,1,2,3,7,11,12,24,31,55];
            #print "$d01gsi,$d01ex,$d01zweig,$d01mcopynum,$d01ort,$d01abtlg\n";
            foreach my $katkey (@{$titelbuchkey{$d01mcopynum}}) {
                push @{$buchdaten{$katkey}}, [$d01zweig,$d01ort,$d01abtlg,$d01standort,$d01entl,$d01status,$d01skond,$d01gsi];
            }
        } else {
            my ($d01gsi,$d01ex,$d01zweig,$d01entl,$d01katkey,$d01status,$d01skond,$d01ort,$d01abtlg,$d01standort)=@line[0,1,2,3,7,11,12,24,31,55];
            #print "$d01gsi,$d01ex,$d01zweig,$d01katkey,$d01ort,$d01abtlg\n";
            push @{$buchdaten{$d01katkey}}, [$d01zweig,$d01ort,$d01abtlg,$d01standort,$d01entl,$d01status,$d01skond,$d01gsi];
        }
    }
    close(D01BUCH);

}

###
## titel_exclude Daten auswerten
#

print STDERR  "Reading titel_exclude\n";

my %titelexclude = ();
open(TEXCL,"cat $bcppath/titel_exclude.bcp |");
while (<TEXCL>) {
    my ($junk,$titidn)=split("",$_);
    chomp($titidn);
    $titelexclude{"$titidn"}="excluded";
}
close(TEXCL);

open(TITEL,"cat $bcppath/titel_daten.bcp |");
open(TITSIKJSON,"| gzip >./meta.title.gz");
open(MEXSIKJSON,"| gzip >./meta.holding.gz");
binmode(TITSIKJSON);
binmode(MEXSIKJSON);

my $mexid           = 1;

while (my ($katkey,$aktion,$fcopy,$reserv,$vsias,$vsiera,$vopac,$daten) = split ("",<TITEL>)) {
    next if ($katkey < 0);
    next if ($aktion != 0 && $aktion != 2);
    next if ($titelexclude{"$katkey"} eq "excluded");

    my %record  = decode_blob('title',$daten);
        
    my $treffer="";
    my $active=0;
    my $idx=0;
    my @fussnbuf=();

    my $maxmex          = 0;
    my %besbibbuf       = ();
    my %erschverlbuf    = ();
    my %erschverlbufpos = ();
    my %erschverlbufneg = ();
    my %bemerkbuf1      = ();
    my %bemerkbuf2      = ();
    my %signaturbuf     = ();
    my %standortbuf     = ();
    my %inventarbuf     = ();

#    printf TITSIK "0000:%0d\n", $katkey;

    my $title_ref = {
        id     => $katkey,
        fields => {},
    };

    my $langmult = 1;
    
    foreach my $key (sort keys %record) {
        my $field = $key;
        my $mult  = 1;
        
        if ($key=~/^(\d\d\d\d)\.(\d\d\d)/) {
            $field = $1;
            $mult  = $2;
        }

        if ($key !~/^0000/) {

            my $content  = konv($record{$key});
            
            my $subfield = "";
            
            ($content,$subfield) = check_subfield('title',$field,$content) if (defined $subfield_ref->{'title'}{$field});
            
            my $line = $key.":".$content."\n";
#            print TITSIK $line if ($record{$key} !~ /idn:/);

            # Verknuepfungskategorien?
            if ($content =~m/^IDN: (\S+)/) {
                my $id = $1;
                my $supplement = "";
                if ($content =~m/^IDN: \S+ ; (.+)/) {
                    $supplement = $1;
                }

                push @{$title_ref->{fields}{$field}}, {
                    mult       => $mult,
                    subfield   => '',
                    id         => $id,
                    supplement => $supplement,
                };
            }
            else {

                # Filter fuer Sprachbezeichnungen
                if ($field =~/^0015/){
                    if ($content =~/[;,]/){
                        foreach my $lang (split /\s*[;,]\s*/, $content){
                            my $normalized_lang = normalize_lang($lang);

                            if (defined $normalized_lang){
                                push @{$title_ref->{fields}{$field}}, {
                                    mult       => $langmult++,
                                    subfield   => '',
                                    content    => $normalized_lang,
                                };
                            }
                        }
                    }
                    else {
                        my $normalized_lang = normalize_lang($content);
                        
                        if (defined $normalized_lang){
                            push @{$title_ref->{fields}{$field}}, {
                                mult       => $langmult++,
                                subfield   => '',
                                content    => $normalized_lang,
                            };
                        }
                    }
                }

                else {
                    push @{$title_ref->{fields}{$field}}, {
                        mult       => $mult,
                        subfield   => '',
                        content    => $content,
                    };
                }
                
                if ($useusbschema) {
                    # Grundsignatur ZDB-Aufnahme
                    if ($line=~/^1204\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $signaturbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1200\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $bemerkbuf1{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1201\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $erschverlbufpos{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1202\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $erschverlbufneg{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^1203\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $bemerkbuf2{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }

                    if ($line=~/^0012\.(\d\d\d):(.*$)/) {
                        my $zaehlung=$1;
                        my $inhalt=$2;
                        $besbibbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung
                        }
                    }
                }
                else {
                    if ($line=~/^0016.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $standortbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^0014\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $signaturbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                                        
                    if ($line=~/^1204\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $erschverlbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                    if ($line=~/^3330\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $besbibbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung
                        }
                    }
                    
                    if ($line=~/^0005\.(\d\d\d):(.*$)/) {
                        my $zaehlung = $1;
                        my $inhalt   = $2;
                        $inventarbuf{$zaehlung}=$inhalt;
                        if ($maxmex <= $zaehlung) {
                            $maxmex=$zaehlung;
                        }
                    }
                    
                }
            }
        }
    }                           # Ende foreach

    # Exemplardaten abarbeiten Anfang
  
    # Wenn ZDB-Aufnahmen gefunden wurden, dann diese Ausgeben
    if ($maxmex && !exists $buchdaten{$katkey}) {
        my $k=1;
        while ($k <= $maxmex) {	  
            my $multkey=sprintf "%03d",$k;
            
            my $signatur = $signaturbuf{$multkey};
            my $standort = $standortbuf{$multkey};
            my $inventar = $inventarbuf{$multkey};
            my $bemerk1  = $bemerkbuf1{$multkey};
            my $bemerk2  = $bemerkbuf2{$multkey};
            my $sigel    = $besbibbuf{$multkey};
            $sigel=~s!^38/!!;
            
            if ($useusbschema) {
                my $erschverl=$erschverlbufpos{$multkey};
                $erschverl.=" ".$erschverlbufneg{$multkey} if (exists $erschverlbufneg{$multkey});
                
                my $holding_ref = {
                    'id'     => $mexid,
                    'fields' => {
                        '0004'   => [
                            {
                                mult     => 1,
                                subfield => '',
                                content  => $katkey,
                            },
                         ],
                    },                    
                };

                if ($inventar) {
                    push @{$holding_ref->{fields}{'0005'}}, {
                        content  => $inventar,
                        mult     => 1,
                        subfield => '',
                    };
                }
                            
                if ($signatur) {
                    push @{$holding_ref->{fields}{'0014'}}, {
                        content  => $signatur,
                        mult     => 1,
                        subfield => '',
                    };
                }

                if ($standort) {
                    push @{$holding_ref->{fields}{'0016'}}, {
                        content  => $standort,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($bemerk1) {
                    push @{$holding_ref->{fields}{'1200'}}, {
                        content  => $bemerk1,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($bemerk2) {
                    push @{$holding_ref->{fields}{'1203'}}, {
                        content  => $bemerk2,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($erschverl) {
                    push @{$holding_ref->{fields}{'1204'}}, {
                        content  => $erschverl,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($sigel) {
                    push @{$holding_ref->{fields}{'3330'}}, {
                        content  => $sigel,
                        mult     => 1,
                        subfield => '',
                    };
                }

		eval {
		    print MEXSIKJSON encode_json $holding_ref, "\n";
		};

		if ($@){
		    print STDERR $@, "\n";
		}
            }
            else {
                my $erschverl=$erschverlbuf{$multkey};

                my $holding_ref = {
                    id      => $mexid,
                    'fields' => {
                       '0004' =>
                        [
                            {
                                mult     => 1,
                                subfield => '',
                                content  => $katkey,
                            },
                        ],
                     },
                };

                if ($inventar) {
                    push @{$holding_ref->{fields}{'0005'}}, {
                        content  => $inventar,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($signatur) {
                    push @{$holding_ref->{fields}{'0014'}}, {
                        content  => $signatur,
                        mult     => 1,
                        subfield => '',
                    };
                }

                if ($standort) {
                    push @{$holding_ref->{fields}{'0016'}}, {
                        content  => $standort,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($erschverl) {
                    push @{$holding_ref->{fields}{'1204'}}, {
                        content  => $erschverl,
                        mult     => 1,
                        subfield => '',
                    };
                }
              
                if ($sigel) {
                    push @{$holding_ref->{fields}{'3330'}}, {
                        content  => $sigel,
                        mult     => 1,
                        subfield => '',
                    };
                }

		eval {
		    print MEXSIKJSON encode_json $holding_ref, "\n";
		};

		if ($@){
		    print STDERR $@, "\n";
		}
            }
          
            $mexid++;
            $k++;
        }

        if ($usestatus){
            push @{$title_ref->{fields}{'4400'}}, {
                mult       => 1,
                subfield   => '',
                content    => 'presence',
            };
        }
    }
    elsif (exists $buchdaten{$katkey}) {
        my $overall_mediastatus_ref = {}; # lendable_[immediate|order|weekend] oder presence_[immediate|order]
        
        foreach my $buchsatz_ref (@{$buchdaten{$katkey}}) {
            my $mediennr    = $buchsatz_ref->[7];
            my $signatur    = $buchsatz_ref->[1];
            my $standort    = $zweigstelle{$buchsatz_ref->[0]};
            my $mediastatus;
            
            if ($usestatus){
                $mediastatus = get_mediastatus($buchsatz_ref) ;

                if ($mediastatus eq "bestellbar"){
                    $overall_mediastatus_ref->{lendable} = 1;
#                    $overall_mediastatus_ref->{lendable_order} = 1;
                }
                elsif ($mediastatus eq "nur in Lesesaal bestellbar" || $mediastatus eq "nur in bes. Lesesaal bestellbar"){
                    $overall_mediastatus_ref->{presence} = 1;
#                    $overall_mediastatus_ref->{presence_order} = 1;                    
                }
                elsif ($mediastatus eq "nur Wochenende"){
                    $overall_mediastatus_ref->{lendable} = 1;
#                    $overall_mediastatus_ref->{lendable_weekend} = 1;                    
                }
                elsif ($mediastatus eq "nicht entleihbar"){
                    $overall_mediastatus_ref->{presence} = 1;
#                    $overall_mediastatus_ref->{presence_immediate} = 1;                    
                }
            }
            
	    if ($used01buchstandort){
		if ($standort{$buchsatz_ref->[3]}){
		    $standort .= " / ".$standort{$buchsatz_ref->[3]};
		}
	    }
	    else {
		if ($abteilung{$buchsatz_ref->[0]}{$buchsatz_ref->[2]}){
		    $standort .= " / ".$abteilung{$buchsatz_ref->[0]}{$buchsatz_ref->[2]};
		}
	    }
            chomp($standort);
	  
            my $holding_ref = {
                'id'     => $mexid,
                'fields' => {
                  '0004' =>
                    [
                        {
                            mult     => 1,
                            subfield => '',
                            content  => $katkey,
                        },
                    ],
                },
            };
          
            if ($mediennr) {
                push @{$holding_ref->{fields}{'0010'}}, {
                    content  => $mediennr,
                    mult     => 1,
                    subfield => '',
                };
            }

            if ($signatur) {
                push @{$holding_ref->{fields}{'0014'}}, {
                    content  => $signatur,
                    mult     => 1,
                    subfield => '',
                };
            }
          
            if ($standort) {
                push @{$holding_ref->{fields}{'0016'}}, {
                    content  => $standort,
                    mult     => 1,
                    subfield => '',
                };
            }
            
	    eval {
		print MEXSIKJSON encode_json $holding_ref, "\n";
	    };

	    if ($@){
		print STDERR $@, "\n";
	    }

            $mexid++;
        }

        if ($usestatus){
            my $mult = 1;
            foreach my $thisstatus (keys %{$overall_mediastatus_ref}){
                push @{$title_ref->{fields}{'4400'}}, {
                    mult       => $mult++,
                    subfield   => '',
                    content    => $thisstatus,
                };                
            }
        }
    }

    # Exemplardaten abarbeiten Ende

    eval {
        print TITSIKJSON encode_json $title_ref, "\n";
    };
    
    if ($@){
        print STDERR $@,"\n";
    }
    
    %inventarbuf     = ();
    %signaturbuf     = ();
    %standortbuf     = ();
    %besbibbuf       = ();
    %erschverlbufpos = ();
    %erschverlbufneg = ();
    %bemerkbuf1      = ();
    %bemerkbuf2      = ();
    undef $maxmex;

}                               # Ende einzelner Satz in while

close(TITSIKJSON);
close(TITEL);
#close(MEXSIK);
close(MEXSIKJSON);

sub get_mediastatus {
    my ($buchsatz_ref) = @_;

    my $statusstring   = "";
    my $entl   = $buchsatz_ref->[4];
    my $status = $buchsatz_ref->[5];
    my $skond  = $buchsatz_ref->[6];

    if    ($entl_map_ref->{$entl} == 0){
        $statusstring="nicht entleihbar";
    }
    elsif ($entl_map_ref->{$entl} == 1){
    	if ($status eq "0"){
            $statusstring="bestellbar";
        }
        elsif ($status eq "2"){
            $statusstring="entliehen"; # Sonderwunsch. Eigentlich: bestellt
        }
        elsif ($status eq "4"){
            $statusstring="entliehen";
        }
        else {
            $statusstring="unbekannt";
        }
    }
    elsif ($entl_map_ref->{$entl} == 2){
      $statusstring="nur in Lesesaal bestellbar";
    }
    elsif ($entl_map_ref->{$entl} == 3){
      $statusstring="nur in bes. Lesesaal bestellbar";
    }
    elsif ($entl_map_ref->{$entl} == 4){
      $statusstring="nur Wochenende";
    }
    else {
      $statusstring="unbekannt";
    }

    # Sonderkonditionen

    if ($skond eq "16"){
      $statusstring="verloren";
    }
    elsif ($skond eq "32"){
      $statusstring="vermi&szlig;t";
    }

    return $statusstring;
}

sub konv {
    my ($content)=@_;

    if ($blobencoding eq "utf8"){
        $content=decode_utf8($content);
    }
    else {
        $content=decode($blobencoding, $content);
    }
    
    $content=~s/\&amp;/&/g;     # zuerst etwaige &amp; auf & normieren 
    $content=~s/\&/&amp;/g;     # dann erst kann umgewandet werden (sonst &amp;amp;) 
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    $content=~s/¯e/\x{113}/g;   # Kl. e mit Ueberstrich/Macron
    $content=~s/µe/\x{115}/g;   # Kl. e mit Hacek/Breve
    $content=~s/·e/\x{11b}/g;   # Kl. e mit Caron
    $content=~s/±e/\x{117}/g;   # Kl. e mit Punkt
    $content=~s/ªd/ð/g;         # Kl. Islaend. e Eth (durchgestrichenes D)

    $content=~s/¯E/\x{112}/g;   # Gr. E mit Ueberstrich/Macron
    $content=~s/µE/\x{114}/g;   # Gr. E mit Hacek/Breve
    $content=~s/·E/\x{11a}/g;   # Gr. E mit Caron
    $content=~s/±E/\x{116}/g;   # Gr. E mit Punkt
    $content=~s/ªD/Ð/g;         # Gr. Islaend. E Eth (durchgestrichenes D)

    $content=~s/¯a/\x{101}/g;   # Kl. a mit Ueberstrich/Macron
    $content=~s/µa/\x{103}/g;   # Kl. a mit Hacek/Breve

    $content=~s/¯A/\x{100}/g;   # Gr. A mit Ueberstrich/Macron
    $content=~s/µA/\x{102}/g;   # Gr. A mit Hacek/Breve

    $content=~s/¯o/\x{14d}/g;   # Kl. o mit Ueberstrich/Macron
    $content=~s/µo/\x{14f}/g;   # Kl. o mit Hacek/Breve
    $content=~s/¶o/\x{151}/g;   # Kl. o mit Doppel-Acute

    $content=~s/¯O/\x{14c}/g;   # Gr. O mit Ueberstrich/Macron
    $content=~s/µO/\x{14e}/g;   # Gr. O mit Hacek/Breve
    $content=~s/¶O/\x{150}/g;   # Gr. O mit Doppel-Acute

    #     $content=~s//\x{131}/g; # Kl. punktloses i
    $content=~s/¯i/\x{12b}/g;   # Kl. i mit Ueberstrich/Macron
    $content=~s/µi/\x{12d}/g;   # Kl. i mit Hacek/Breve

    $content=~s/±I/\x{130}/g;   # Gr. I mit Punkt
    $content=~s/¯I/\x{12a}/g;   # Gr. i mit Ueberstrich/Macron
    $content=~s/µI/\x{12c}/g;   # Gr. i mit Hacek/Breve


    #     $content=~s//\x{168}/g; # Gr. U mit Tilde
    $content=~s/¯U/\x{16a}/g;   # Gr. U mit Ueberstrich/Macron
    $content=~s/µU/\x{16c}/g;   # Gr. U mit Hacek/Breve
    $content=~s/¶U/\x{170}/g;   # Gr. U mit Doppel-Acute
    $content=~s/¹U/\x{16e}/g;   # Gr. U mit Ring oben

    #     $content=~s//\x{169}/g; # Kl. u mit Tilde
    $content=~s/¯u/\x{16b}/g;   # Kl. u mit Ueberstrich/Macron
    $content=~s/µu/\x{16d}/g;   # Kl. u mit Hacek/Breve
    $content=~s/¶u/\x{171}/g;   # Kl. u mit Doppel-Acute
    $content=~s/¹u/\x{16f}/g;   # Kl. u mit Ring oben
    
    $content=~s/´n/\x{144}/g;   # Kl. n mit Acute
    $content=~s/½n/\x{146}/g;   # Kl. n mit Cedille
    $content=~s/·n/\x{148}/g;   # Kl. n mit Caron

    $content=~s/´N/\x{143}/g;   # Gr. N mit Acute
    $content=~s/½N/\x{145}/g;   # Gr. N mit Cedille
    $content=~s/·N/\x{147}/g;   # Gr. N mit Caron

    $content=~s/´r/\x{155}/g;   # Kl. r mit Acute
    $content=~s/½r/\x{157}/g;   # Kl. r mit Cedille
    $content=~s/·r/\x{159}/g;   # Kl. r mit Caron

    $content=~s/´R/\x{154}/g;   # Gr. R mit Acute
    $content=~s/½R/\x{156}/g;   # Gr. R mit Cedille
    $content=~s/·R/\x{158}/g;   # Gr. R mit Caron

    $content=~s/´s/\x{15b}/g;   # Kl. s mit Acute
    #     $content=~s//\x{15d}/g; # Kl. s mit Circumflexe
    $content=~s/½s/\x{15f}/g;   # Kl. s mit Cedille
    $content=~s/·s/š/g;         # Kl. s mit Caron

    $content=~s/´S/\x{15a}/g;   # Gr. S mit Acute
    #     $content=~s//\x{15c}/g; # Gr. S mit Circumflexe
    $content=~s/½S/\x{15e}/g;   # Gr. S mit Cedille
    $content=~s/·S/Š/g;         # Gr. S mit Caron

    $content=~s/ªt/\x{167}/g;   # Kl. t mit Mittelstrich
    $content=~s/½t/\x{163}/g;   # Kl. t mit Cedille
    $content=~s/·t/\x{165}/g;   # Kl. t mit Caron

    $content=~s/ªT/\x{166}/g;   # Gr. T mit Mittelstrich
    $content=~s/½T/\x{162}/g;   # Gr. T mit Cedille
    $content=~s/·T/\x{164}/g;   # Gr. T mit Caron

    $content=~s/´z/\x{17a}/g;   # Kl. z mit Acute
    $content=~s/±z/\x{17c}/g;   # Kl. z mit Punkt oben
    $content=~s/·z/ž/g;         # Kl. z mit Caron

    $content=~s/´Z/\x{179}/g;   # Gr. Z mit Acute
    $content=~s/±Z/\x{17b}/g;   # Gr. Z mit Punkt oben
    $content=~s/·Z/Ž/g;         # Gr. Z mit Caron

    $content=~s/´c/\x{107}/g;   # Kl. c mit Acute
    #     $content=~s//\x{108}/g; # Kl. c mit Circumflexe
    $content=~s/±c/\x{10b}/g;   # Kl. c mit Punkt oben
    $content=~s/·c/\x{10d}/g;   # Kl. c mit Caron
    
    $content=~s/´C/\x{106}/g;   # Gr. C mit Acute
    #     $content=~s//\x{108}/g; # Gr. C mit Circumflexe
    $content=~s/±C/\x{10a}/g;   # Gr. C mit Punkt oben
    $content=~s/·C/\x{10c}/g;   # Gr. C mit Caron

    $content=~s/·d/\x{10f}/g;   # Kl. d mit Caron
    $content=~s/·D/\x{10e}/g;   # Gr. D mit Caron

    $content=~s/½g/\x{123}/g;   # Kl. g mit Cedille
    $content=~s/·g/\x{11f}/g;   # Kl. g mit Breve
    $content=~s/µg/\x{11d}/g;   # Kl. g mit Circumflexe
    $content=~s/±g/\x{121}/g;   # Kl. g mit Punkt oben

    $content=~s/½G/\u0122/g;    # Gr. G mit Cedille
    $content=~s/·G/\x{11e}/g;   # Gr. G mit Breve
    $content=~s/µG/\x{11c}/g;   # Gr. G mit Circumflexe
    $content=~s/±G/\x{120}/g;   # Gr. G mit Punkt oben
        
    $content=~s/ªh/\x{127}/g;   # Kl. h mit Ueberstrich
    $content=~s/¾h/\x{e1}\x{b8}\x{a5}/g; # Kl. h mit Punkt unten
    $content=~s/ªH/\x{126}/g;   # Gr. H mit Ueberstrich
    $content=~s/¾H/\x{e1}\x{b8}\x{a4}/g; # Gr. H mit Punkt unten

    $content=~s/½k/\x{137}/g;   # Kl. k mit Cedille
    $content=~s/½K/\x{136}/g;   # Gr. K mit Cedille

    $content=~s/½l/\x{13c}/g;   # Kl. l mit Cedille
    $content=~s/´l/\x{13a}/g;   # Kl. l mit Acute
    #     $content=~s//\x{13e}/g; # Kl. l mit Caron
    $content=~s/·l/\x{140}/g;   # Kl. l mit Punkt mittig
    $content=~s/ºl/\x{142}/g;   # Kl. l mit Querstrich

    $content=~s/½L/\x{13b}/g;   # Gr. L mit Cedille
    $content=~s/´L/\x{139}/g;   # Gr. L mit Acute
    #     $content=~s//\x{13d}/g; # Gr. L mit Caron
    $content=~s/·L/\x{13f}/g;   # Gr. L mit Punkt mittig
    $content=~s/ºL/\x{141}/g;   # Gr. L mit Querstrick

    $content=~s/¾z/\x{e1}\x{ba}\x{93}/g; # Kl. z mit Punkt unten
    $content=~s/¾Z/\x{e1}\x{ba}\x{92}/g; # Gr. z mit Punkt unten

    #     $content=~s//\x{160}/g;   # S hacek
    #     $content=~s//\x{161}/g;   # s hacek
    #     $content=~s//\x{17d}/g;   # Z hacek
    #     $content=~s//\x{17e}/g;   # z hacek
    #     $content=~s//\x{178}/g;   # Y Umlaut

    return $content;
}

sub decode_blob {
    my ($type,$BLOB) = @_;

    my %record = ();
    my $j = length($BLOB);
    my $outBLOB = pack "H$j", $BLOB;
    $j /= 2;
    my $i = 0;
    while ( $i < $j ) {
        my $idup = $i*2;
        my $fnr = sprintf "%04d", hex(substr($BLOB,$idup,4));
        my $kateg = $fstab_ref->{$type}[$fnr]{field};
        my $len = hex(substr($BLOB,$idup+4,4));
        if ( $len < 1000 ) {
            # nicht multiples Feld
            my $inh = substr($outBLOB,$i+4,$len);
            if ( $fstab_ref->{$type}[$fnr]{type} eq "V" ) {
                $inh = hex(substr($BLOB,$idup+8,8));
                $inh="IDN: $inh";
            }
# Leerzeichen-Indikator entfernen
#            if ( substr($inh,0,1) eq " " ) {
#                $inh =~ s/^ //;
#            }

            # Schmutzzeichen weg
            $inh=~s/ //g;

            my $KAT = sprintf "%04d", $kateg;

            if ($inh ne "") {
                $record{$KAT} = $inh;
            }

            $i = $i + 4 + $len;
        } else {
            # multiples Feld
            my $mlen = 65536 - $len;
            my $k = $i + 4;
            my $ukat = 1;
            while ( $k < $i + 4 + $mlen ) {
                my $kdup = $k*2;
                my $ulen = hex(substr($BLOB,$kdup,4));
                if ( $ulen > 0 ) {
                    my $inh = substr($outBLOB,$k+2,$ulen);
                    if ( $fstab_ref->{$type}[$fnr]{type} eq "V" ) {
                        my $verwnr = hex(substr($BLOB,$kdup+4,8));
                        my $zusatz="";
                        if ($ulen > 4) {
                            $zusatz=substr($inh,4,$ulen);
                            $inh="IDN: $verwnr ;$zusatz";
                        } else {
                            $inh="IDN: $verwnr";
                        }
                    }
                    my $uKAT = sprintf "%04d.%03d", $kateg, $ukat;

# Leerzeichen-Indikator entfernen
#                    if ( substr($inh,0,1) eq " " ) {
#                        $inh =~ s/^ //;
#                    }

                    # Schmutzzeichen weg
                    $inh=~s/ //g;

                    if ($inh ne "") {
                        $record{$uKAT} = $inh;
                    }
                }
                $ukat++;
                $k = $k + 2 + $ulen;
            }
            $i = $i + 4 + $mlen;
        }
    }

    return %record;
}

sub read_fstab {

    my $fstab_map_ref = {
        1 => 'title',
        2 => 'person',
        3 => 'corporatebody',
        4 => 'subject',
        5 => 'classification',
    };

    my $fstab_ref = {};

    my $subfield_ref = {};
    
    open(FSTAB,"cat $bcppath/sik_fstab.bcp |");
    while (<FSTAB>) {
        my ($setnr,$fnr,$name,$kateg,$muss,$fldtyp,$mult,$invert,$stop,$zusatz,$multgr,$refnr,$vorbnr,$pruef,$knuepf,$trenn,$normueber,$bewahrenjn,$pool_cop,$indikator,$ind_bezeicher,$ind_indikator,$sysnr,$vocnr)=split("",$_);
        
        if ($setnr >= 1 && $setnr <= 5){
            if ($indikator){

                my $field = sprintf "%04d", $kateg;
                $subfield_ref->{$fstab_map_ref->{$setnr}}{$field}{$ind_indikator} = 1;
            }

            $fstab_ref->{$fstab_map_ref->{$setnr}}[$fnr] = {
                field => $kateg,
                type  => $fldtyp,
                refnr => $refnr,
            };
        }
    }
    close(FSTAB);

    return ($fstab_ref,$subfield_ref);
}

sub transform_subfield {
    my ($type,$field,$subfield,$content) = @_;

    if ($field=~/^(\d\d\d\d)/) {
        if ($subfield_transform_ref->{$type}{"$1$subfield"}) {
            return $subfield_transform_ref->{$type}{"$1$subfield"};
        }
    }

    return;
}

sub check_subfield {
    my ($type,$field,$content) = @_;

    my $subfield = "";

    if (defined $subfield_ref->{$type}{$field}){
        my $subfield_regexp = join "|", map {$_ = $_."\\|?"} keys %{$subfield_ref->{$type}{$field}};

        if ($content=~m/^($subfield_regexp)(.+)$/){
            $subfield=$1;
            $content=$2;
            $subfield =~s/\|//;
        }
    }

    
    return ($content,$subfield);    
}

sub normalize_lang {
    my $inputlang = shift;

    return $inputlang if (defined $valid_lang_code_ref->{$inputlang});

    $inputlang =~ s/($langs_to_replace)/$lang_replacements{$1}/g;

    return (defined $valid_lang_code_ref->{$inputlang})?$inputlang:undef;
}
