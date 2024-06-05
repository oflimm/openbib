####################################################################
#
#  OpenBib::Normalizer
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
#
#  Objektifizierung von Common::Util.pm
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

package OpenBib::Normalizer;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Business::ISBN;
use DBI;
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use MARC::Charset 'marc8_to_utf8';
use POSIX();
use String::Tokenizer;
use Text::Unidecode qw(unidecode);
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Stopwords;

my %char_replacements = (
    
    # Zeichenersetzungen
    "'" => " ",
    "\/" => " ",
    #":" => " ",
    "  " => " ",

    # $logger->debug("Checkpoint 3: $content");

    # Alte/Neue Schriftformen
#    "ph"  => "f",
#    "Ph"  => "F",

    # Buchstabenersetzungen
    "u\x{0308}" => "ue",
    "a\x{0308}" => "ae",
    "o\x{0308}" => "oe",
    "U\x{0308}" => "Ue",
    "O\x{0308}" => "Oe",
    "A\x{0308}" => "Ae",
    
    "ü" => "ue",
    "ä" => "ae",
    "ö" => "oe",
    "Ü" => "Ue",
    "Ö" => "Oe",
    "Ä" => "Ae",
    "ß" => "ss",

    "é" => "e",
    "è" => "e",
    "ê" => "e",
    "ë" => "e",
    "\x{113}" => "e", # Kl. e mit Ueberstrich" => "Macron
    "\x{115}" => "e", # Kl. e mit Hacek" => "Breve
    "\x{11b}" => "e", # Kl. e mit Caron
    "\x{117}" => "e", # Kl. e mit Punkt
    
    "É" => "E",
    "È" => "E",
    "Ê" => "E",
    "Ë" => "E",
    "\x{112}" => "E", # Gr. E mit Ueberstrich" => "Macron
    "\x{114}" => "E", # Gr. E mit Hacek" => "Breve
    "\x{11a}" => "E", # Gr. E mit Caron
    "\x{116}" => "E", # Gr. E mit Punkt
    
    "á" => "a",
    "à" => "a",
    "â" => "a",
    "ã" => "a",
    "å" => "a",
    "\x{101}" => "a", # Kl. a mit Ueberstrich" => "Macron
    "\x{103}" => "a", # Kl. a mit Hacek" => "Breve
    
    "Á" => "A",
    "À" => "A",
    "Â" => "A",
    "Ã" => "A",
    "Å" => "A",
    "\x{100}" => "A", # Gr. A mit Ueberstrich" => "Macron
    "\x{102}" => "A", # Gr. A mit Hacek" => "Breve
    
    "ó" => "o",
    "ò" => "o",
    "ô" => "o",
    "õ" => "o",
    "\x{14d}" => "o", # Kl. o mit Ueberstrich" => "Macron
    "\x{14f}" => "o", # Kl. o mit Hacek" => "Breve
    "\x{151}" => "o", # Kl. o mit Doppel-Acute
    
    "Ó" => "O",
    "Ò" => "O",
    "Ô" => "O",
    "Õ" => "O",
    "\x{14c}" => "O", # Gr. O mit Ueberstrich" => "Macron
    "\x{14e}" => "O", # Gr. O mit Hacek" => "Breve
    "\x{150}" => "O", # Gr. O mit Doppel-Acute
    
    "í" => "i",
    "ì" => "i",
    "î" => "i",
    "ï" => "i",
    "\x{131}" => "i", # Kl. punktloses i
    "\x{12b}" => "i", # Kl. i mit Ueberstrich" => "Macron
    "\x{12d}" => "i", # Kl. i mit Hacek" => "Breve

    
    "Í" => "I",
    "Ì" => "I",
    "Î" => "I",
    "Ï" => "I",
    "\x{130}" => "I", # Gr. I mit Punkt
    "\x{12a}" => "I", # Gr. i mit Ueberstrich" => "Macron
    "\x{12c}" => "I", # Gr. i mit Hacek" => "Breve

    "Ú" => "U",
    "Ù" => "U",
    "Û" => "U",
    "\x{168}" => "U", # Gr. U mit Tilde
    "\x{16a}" => "U", # Gr. U mit Ueberstrich" => "Macron
    "\x{16c}" => "U", # Gr. U mit Hacek" => "Breve
    "\x{170}" => "U", # Gr. U mit Doppel-Acute
    "\x{16e}" => "U", # Gr. U mit Ring oben

    "ú" => "u",
    "ù" => "u",
    "û" => "u",
    "\x{169}" => "u", # Kl. u mit Tilde
    "\x{16b}" => "u", # Kl. u mit Ueberstrich" => "Macron
    "\x{16d}" => "u", # Kl. u mit Hacek" => "Breve
    "\x{171}" => "u", # Kl. u mit Doppel-Acute
    "\x{16f}" => "u", # Kl. u mit Ring oben

    "ø" => "o",
    "Ø" => "o",

    "ñ" => "n",
    "\x{144}" => "n", # Kl. n mit Acute
    "\x{146}" => "n", # Kl. n mit Cedille
    "\x{148}" => "n", # Kl. n mit Caron

    "Ñ" => "N",
    "\x{143}" => "N", # Gr. N mit Acute
    "\x{145}" => "N", # Gr. N mit Cedille
    "\x{147}" => "N", # Gr. N mit Caron

    "\x{155}" => "r", # Kl. r mit Acute
    "\x{157}" => "r", # Kl. r mit Cedille
    "\x{159}" => "r", # Kl. r mit Caron

    "\x{154}" => "R", # Gr. R mit Acute
    "\x{156}" => "R", # Gr. R mit Cedille
    "\x{158}" => "R", # Gr. R mit Caron

    "\x{15b}" => "s", # Kl. s mit Acute
    "\x{15d}" => "s", # Kl. s mit Circumflexe
    "\x{15f}" => "s", # Kl. s mit Cedille
    "š" => "s", # Kl. s mit Caron

    "\x{15a}" => "S", # Gr. S mit Acute
    "\x{15c}" => "S", # Gr. S mit Circumflexe
    "\x{15e}" => "S", # Gr. S mit Cedille
    "Š" => "S", # Gr. S mit Caron

    "\x{167}" => "t", # Kl. t mit Mittelstrich
    "\x{163}" => "t", # Kl. t mit Cedille
    "\x{165}" => "t", # Kl. t mit Caron

    "\x{166}" => "T", # Gr. T mit Mittelstrich
    "\x{162}" => "T", # Gr. T mit Cedille
    "\x{164}" => "T", # Gr. T mit Caron

    "\x{17a}" => "z", # Kl. z mit Acute
    "\x{17c}" => "z", # Kl. z mit Punkt oben
    "ž" => "z", # Kl. z mit Caron

    "\x{179}" => "Z", # Gr. Z mit Acute
    "\x{17b}" => "Z", # Gr. Z mit Punkt oben
    "Ž" => "Z", # Gr. Z mit Caron

    "ç" => "c",
    "\x{107}" => "c", # Kl. c mit Acute
    "\x{108}" => "c", # Kl. c mit Circumflexe
    "\x{10b}" => "c", # Kl. c mit Punkt oben
    "\x{10d}" => "c", # Kl. c mit Caron
    
    "Ç" => "c",
    "\x{106}" => "C", # Gr. C mit Acute
    "\x{108}" => "C", # Gr. C mit Circumflexe
    "\x{10a}" => "C", # Gr. C mit Punkt oben
    "\x{10c}" => "C", # Gr. C mit Caron

    "\x{10f}" => "d", # Kl. d mit Caron
    "\x{10e}" => "D", # Gr. D mit Caron

    "\x{123}" => "g", # Kl. g mit Cedille
    "\x{11f}" => "g", # Kl. g mit Breve
    "\x{11d}" => "g", # Kl. g mit Circumflexe
    "\x{121}" => "g", # Kl. g mit Punkt oben

    "\x{122}" => "G", # Gr. G mit Cedille
    "\x{11e}" => "G", # Gr. G mit Breve
    "\x{11c}" => "G", # Gr. G mit Circumflexe
    "\x{120}" => "G", # Gr. G mit Punkt oben

    "\x{127}" => "h", # Kl. h mit Ueberstrich
    "\x{126}" => "H", # Gr. H mit Ueberstrich

    "\x{137}" => "k", # Kl. k mit Cedille
    "\x{136}" => "K", # Gr. K mit Cedille

    "\x{13c}" => "l", # Kl. l mit Cedille
    "\x{13a}" => "l", # Kl. l mit Acute
    "\x{13e}" => "l", # Kl. l mit Caron
    "\x{140}" => "l", # Kl. l mit Punkt mittig
    "\x{142}" => "l", # Kl. l mit Querstrich

    "\x{13b}" => "L", # Gr. L mit Cedille
    "\x{139}" => "L", # Gr. L mit Acute
    "\x{13d}" => "L", # Gr. L mit Caron
    "\x{13f}" => "L", # Gr. L mit Punkt mittig
    "\x{141}" => "L", # Gr. L mit Querstrick

    "\u20ac" => "e",   # Euro-Zeichen
    "\x{152}" => "oe",  # OE-Ligatur
    "\x{153}" => "oe",  # oe-Ligatur
    "Æ" => "ae",       # AE-Ligatur
    "æ" => "ae",       # ae-Ligatur
    "\x{160}" => "s",   # S hacek
    "\x{161}" => "s",   # s hacek
    "\x{17d}" => "z",   # Z hacek
    "\x{17e}" => "z",   # z hacek
    "\x{178}" => "y",   # Y Umlaut
    "¡" => "i",        # i Ueberstrich
    "¢" => "c",        # Cent
    "£" => "l",        # Pfund
    "¥" => "y",        # Yen
    "µ" => "u",        # Mikro
    
    "Ð" => "e",        # Gr. Islaend. E (durchgestrichenes D)
    "\x{111}" => "e",   # Kl. Islaend. e ? (durchgestrichenes d)

    "Ý" => "y",
    "ý" => "y",
    "Þ" => "th",       # Gr. Thorn
    "þ" => "th",       # kl. Thorn
    "ð" => "d",      # eth

    "\x{02b9}" => "'", # Slavisches Weichheitszeichen (modifier letter prime) als '
    "\x{2019}" => "'", # Slavisches Weichheitszeichen (modifier letter prime) als '
    #"\x{02ba}" => "\x{0022}", # Slavisches hartes Zeichen als "
    #"\x{201d}" => "\x{0022}",

    # Sonstige
    "ā" => "a",
    "ḥ" => "h",
    "š" => "s",
    "Š" => "s",
    "Ḥ" => "h",
    "ī" => "i",
    "ū" => "u",
    "Ṭ" => "t",
    "Ǧ" => "g",
    "ǧ" => "g",
    "ṯ" => "t",
    "ṭ" => "t",
    "a̱" => "a",
    "Ā" => "a",
    "h̄" => "h",
#    "" => "",
#    "" => "",
#    "" => "",
   );

my $chars_to_replace = join '|',
#    map quotemeta, 
    keys %char_replacements;

$chars_to_replace = qr/$chars_to_replace/;

my $valid_lang_code_ref = {
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

my %lang_replacements = (
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
    'Catalan' => 'cat',
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
    'German' => 'ger',
    'nld' => 'dut',
    'dut/nla' => 'dut',
    'dv' => 'div',
    'dz' => 'dzo',
    'English' => 'eng',
    'en' => 'eng',
    'eo' => 'epo',
    'esl/spa' => 'spa',
    'et' => 'est',
    'ee' => 'ewe',
    'Griechisch' => 'gre',
    'el' => 'gre',
    'ell' => 'gre',
    'eu' => 'baq',
    'eus' => 'baq',
    'fa' => 'per',
    'fas' => 'per',
    'Persian' => 'per',
    'French' => 'fre',
    'fr' => 'fre',
    'fra' => 'fre',
    'fra/fre' => 'fre',
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
    'Hebrew' => 'heb',
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
    'Japanese' => 'jpn',
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
    'Lateinisch' => 'lat',
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
    'Dutch' => 'dut',
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
    'Portuguese' => 'por',
    'ps' => 'pus',
    'qu' => 'que',
    'rm' => 'roh',
    'rn' => 'run',
    'ro' => 'rum',
    'ron' => 'rum',
    'ru' => 'rus',
    'Russian' => 'rus',
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
    'Spanish' => 'spa',
    'sc' => 'srd',
    'Slovenian' => 'slo',
    'sk' => 'slo',
    'slk' => 'slo',
    'sq' => 'alb',
    'sqi' => 'alb',
    'sr' => 'srp',
    'ss' => 'ssw',
    'su' => 'sun',
    'sw' => 'swa',
    'sv' => 'swe',
    'sve/swe' => 'swe',
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
    'Chineset' => 'chi',
    'Chinese' => 'chi',
    'zh' => 'chi',
    'zho' => 'chi',
    'zu' => 'zul',
);

my $langs_to_replace = join '|',
    keys %lang_replacements;

$langs_to_replace = qr/$langs_to_replace/;

sub new {
    my $class = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $self = {};

    bless ($self, $class);

    return $self;
}

# Aufruf-Varianten fuer normalize
#
# a) Fuer ein field
# b) Fuer einen typ
# c)

sub normalize {
    my ($self,$arg_ref) = @_;
    
    # Set defaults
    my $content   = exists $arg_ref->{content}
        ? $arg_ref->{content}          : "";

    my $field  = exists $arg_ref->{field}
        ? $arg_ref->{field}            : "";

    my $type   = exists $arg_ref->{type}
        ? $arg_ref->{type}             : "";

    my $option_ref = exists $arg_ref->{option}
        ? $arg_ref->{option}           : {};

    my $searchreq = exists $arg_ref->{searchreq}
        ? $arg_ref->{searchreq}        : undef;

    my $tagging   = exists $arg_ref->{tagging}
        ? $arg_ref->{tagging}          : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return "" unless (defined $content);

    if ($logger->is_debug){
        $logger->debug("IN: $content / Type $type");
    }

    # Spezielle Id-Prefixe verarbeiten
    $content =~s{\(DE-605\)}{hbz}ig;
    $content =~s{\(DE-600\)}{zdb}ig;
    $content =~s{\(DE-588\)}{gnd}ig;
    $content =~s{\(DE-38\)}{usb}ig;
        
#    my $chars_to_replace   = $self->{chars_to_replace};
#    my %char_replacements  = %{$self->{char_replacements}};
    
    $content =~ s/($chars_to_replace)/$char_replacements{$1}/g;

    # Normalisierung auf Kleinschreibung
    $content = lc($content);

    # Typ Integer kann sofort normiert werden

    if ($type eq "integer"){
        $logger->debug("Processing Type $type");
                
        $content =~s/[^0-9-]//g;

        $logger->debug("OUT: $content / Type $type");
        
        return $content;
    }
    elsif ($type eq "id"){
        $logger->debug("Processing Type $type");
        
        # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
        # weil der Xapian QueryParser keine Recherche nach IDs mit Satzzeichen
        # (z.B. -) zulaesst, daher effektiv ala String-Suche
        #$content=~s/[^\p{Alphabetic}0-9]/_/g;
        $content=~s/ //g;

        $logger->debug("OUT: $content / Type $type");
        
        return $content;
    }
    
    # Sonderbehandlung verschiedener Kategorien

    # Korrektur fehlerhafter Inhalte mit abschliessenden Leerzeichen
    $content=~s/\s+$//g;
        
    # Datum normalisieren

    if ($field eq 'T0002'){
        if ($content =~ /^(\d\d)\.(\d\d)\.(\d\d\d\d)$/){
            $content=$3.$2.$1;
            return $content;
        }
    }

    # ISBN filtern
    if (defined $option_ref->{'filter_isbn'} || $field eq "isbn" || $field eq "T0540" || $field eq "T0541" || $field eq "T0547" || $field eq "T0553" || $field eq "T0634" || $field eq "T1586" || $field eq "T1587" || $field eq "T1588" || $field eq "T1589" || $field eq "T1590" || $field eq "T1591" || $field eq "T1592" || $field eq "T1593"){
        # Entfernung der Minus-Zeichen bei der ISBN zuerst 13-, dann 10-stellig
        $content=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;

        return $content unless (defined $option_ref->{'filter_isbn'}); # Short circuit for field-specific normalization
    }
    
    # ISSN filtern
    if (defined $option_ref->{'filter_issn'} || $field eq "issn" || $field eq "T0543" || $field eq "T0544" || $field eq "T0585" || $field eq "T1550" || $field eq "T1551" || $field eq "T1552" || $field eq "T1553" || $field eq "T1567" ){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8/g;

        return $content unless (defined $option_ref->{'filter_issn'}); # Short circuit for field-specific normalization
    }

    # Hashes wg. Signaturen auf _ vereinheitlichen
    $content=~s/\#/_/g;
    
    # Nichtsortierzeichen entfernen
    $content=~s/¬//g;

    # RAK-Zeilenumbruch bei alten Drucken usw. entfernen
    $content=~s/-\|\|//g; 
    $content=~s/ \|\| / /g;

    # Ausfiltern spezieller HTML-Tags
    $content=~s/&[gl]t;//g;
    $content=~s/&quot;//g;
    $content=~s/&amp;//g;
    # insbesonder > und <
    $content=~s/&[gl]t;//g;
    $content=~s/<//g;
    $content=~s/>//g;    

    # Ausfiltern von Supplements in []
    # $content=~s/\[.*?\]//g;
    
    # Fall: C++, C# und .Net
    #$content=~s/(?<=(\w|\+))\+/plus/g;
    $content=~s/(c)\#/$1sharp/ig;
    $content=~s/\.(net)/dot$1/ig;

    # Stopwoerter fuer versch. Kategorien ausfiltern (Titel-String)

#    if (defined $option_ref->{strip_first_stopword}){
#        $content=OpenBib::Common::Stopwords::strip_first_stopword($content);
#    }

    if (defined $option_ref->{strip_bracket_content}){
        $content=~s/\s+$//;
        $content=~s/\s+<.*?>//g;
    }

    $logger->debug("Checkpoint 1: '$content'");
    
    # Restliche Sonderzeichen quick and dirty mit Text::Unidecode umwandeln
    $content=unidecode($content);
    
    # Kleinschreibung nachtraeglich fuer ggf. von unidecode in Grossbuchstaben umgewandelte Zeichen
    $content=lc($content);
 
    $logger->debug("Checkpoint post unidecode: '$content'");

    # Recherche
    if ($searchreq){
        if ($type eq 'string'){
            $logger->debug("Processing Type $type");

	    # Punctuation am Feld-Ende entfernen (MARC21 Absonderlichkeit z.B Punkt in 245$a ('Der Staat.')
	    
	    # $content=~s/\p{XPosixPunct}*$//;
	    $content=~s/[.:]$//;	    
            
            # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
            # * wird fuer die Recherche als Wildcard nicht angefasst
            $content=~s/[^\p{Alphabetic}0-9*]/_/g;
        }
        else {
            # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
            $content=~s/[^-+\p{Alphabetic}\p{Sc}0-9\/: '()"^*_]//g;
            
            # Verbundene Terme splitten
            $content=~s/(\w)\"(\w)/$1 $2/g;
            $content=~s/(\w)\x{02ba}(\w)/$1 $2/g; # Hartes Zeichen Slavistik
            $content=~s/(\w)\x{201d}(\w)/$1 $2/g; # Hartes Zeichen Slavistik
            $content=~s/(\w)-(\w)/$1 $2/g;
            $content=~s/(\w)'(\w)/$1 $2/g;
            
            # Bei Termen mit abschliessendem Bindestrich diesen entfernen
            $content=~s/(\w)-(\s)/$1$2/g;
            $content=~s/(\w)-$/$1/g;
        }
    }
    # Normierung der Tags bei Nutzereingabe
    elsif ($tagging){
        $content=~s/[^-+\p{Alphabetic}\p{Sc}0-9._]//g;

    }
    # Indexierung
    else {
        if ($type eq 'string'){
            $logger->debug("Processing Type $type");
	    # Punctuation am Feld-Ende entfernen (MARC21 Absonderlichkeit z.B Punkt in 245$a ('Der Staat.')
	    
	    # $content=~s/\p{XPosixPunct}*$//;
	    $content=~s/[.:]$//;	    
            # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
            # * wird fuer die Indexierung auf _ normiert
            $content=~s/[^\p{Alphabetic}0-9]/_/g;
        }
        else {
            # Ausfiltern nicht akzeptierter Zeichen (Postitivliste)
            $content=~s/[^-+\p{Alphabetic}\p{Sc}0-9\/:* '_]//g;
            
	    # Verbundene Terme splitten
            $content=~s/(\w)\"(\w)/$1 $2/g;

	    # Memory leak https://github.com/Perl/perl5/issues/17218
            # $content=~s/(\w)\x{02ba}(\w)/$1 $2/g; # Hartes Zeichen Slavistik
            # $content=~s/(\w)\x{201d}(\w)/$1 $2/g; # Hartes Zeichen Slavistik

            $content=~s/(\w)-(\w)/$1 $2/g;
            $content=~s/(\w)'(\w)/$1 $2/g;
            
            # Bei Termen mit abschliessendem Bindestrich diesen entfernen
            $content=~s/(\w)-(\s)/$1$2/g;
            $content=~s/(\w)-$/$1/g;

            # Sonderbehandlung : fuer die Indexierung (bei der Recherche wird : fuer intitle: usw. benoetigt)
            $content=~s/:/ /g;
        }
    }
    
     $logger->debug("Checkpoint 2: '$content'");
    
    # Leerzeichen bei CJK einfuegen

    # $content=~s/(\p{InKatakana}|\p{InHiragana}|\p{InCJKCompatibility}|\p{InCJKCompatibilityForms}|\p{InCJKCompatibilityIdeographs}|\p{InCJKCompatibilityIdeographsSupplement}|\p{InCJKRadicalsSupplement}|\p{InCJKStrokes}|\p{InCJKSymbolsAndPunctuation}|\p{InCJKUnifiedIdeographs}|\p{InCJKUnifiedIdeographsExtensionA}|\p{InCJKUnifiedIdeographsExtensionB}|\p{InEnclosedCJKLettersAndMonths})/$1 /g;

    $logger->debug("OUT: $content / Type $type");
    
    return $content;
}

sub normalize_lang {
    my $self      = shift;
    my $inputlang = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("IN: ->$inputlang<-");
    }
    
    return $inputlang if (defined $valid_lang_code_ref->{$inputlang});

#    my $langs_to_replace  = $self->{langs_to_replace};
#    my %lang_replacements = %{$self->{lang_replacements}};
    
    $inputlang =~ s/($langs_to_replace)/$lang_replacements{$1}/g;

    if ($logger->is_debug){
        $logger->debug("OUT: ->$inputlang<-");
    }
    
    if ($valid_lang_code_ref->{$inputlang}){
        return $inputlang;
    }

    return;
}

sub gen_bibkey_base {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields_ref  = exists $arg_ref->{fields}
        ? $arg_ref->{fields}             : undef;

    my $scheme      = exists $arg_ref->{scheme}
        ? $arg_ref->{scheme}             : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    return "" unless (defined $fields_ref);

    if ($scheme eq "marc"){
	return $self->gen_bibkey_base_marc($arg_ref);
    }
    else {
	return $self->gen_bibkey_base_mab($arg_ref);
    }
}

sub gen_bibkey_base_marc {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields_ref  = exists $arg_ref->{fields}
        ? $arg_ref->{fields}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return "" unless (defined $fields_ref);

    if ($logger->is_debug){
        $logger->debug("Trying to generate bibkey with fields: ".YAML::Dump($fields_ref));
    }
    
    # Nur Bibkeys mit allen relevanten Informationen sinnvoll!
    
    return "" unless ( (defined $fields_ref->{'T0100'} || defined $fields_ref->{'T0700'} ) && defined $fields_ref->{'T0245'} && defined $fields_ref->{'T0264'} );
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $field (qw/T0100 T0700/){
        next if (!exists $fields_ref->{$field});
        foreach my $part_ref (@{$fields_ref->{$field}}){
            next unless (defined $part_ref->{'content'});

	    if ($part_ref->{'subfield'} eq "a"){
	    
		my $single_person = lc($part_ref->{'content'});
		$single_person    =~ s/[^0-9\p{L}\. ]+//g;
		my ($lastname,$firstname) = split(/\s+/,$single_person);
		
		if (defined $firstname){
		    if ($firstname eq $lastname){
			$single_person    = $lastname;
		    }
		    else {
			$single_person    = substr($firstname,0,1).".".$lastname;
		    }
		}
		else {
		    $single_person    = $lastname;
		}
		
		if (defined $part_ref->{'supplement'} && $part_ref->{'supplement'} =~ /Hrsg/){
		    push @$editors_ref, $single_person;
		}
		else {
		    push @$authors_ref, $single_person;
		}
	    }
        }
    }

    my $persons_ref=(defined $authors_ref && @$authors_ref)?$authors_ref:
    (defined $editors_ref && @$editors_ref)?$editors_ref:[];

    my $author = "";
    $author    = "[".join(",", sort(@$persons_ref))."]" if (defined $persons_ref && @$persons_ref);
    
    # Titel
    my $title  = "";

    foreach my $part_ref (@{$fields_ref->{'T0245'}}){
	if ($part_ref->{'subfield'} eq "a"){
	    $title = lc($part_ref->{'content'});
	    last;
	}
    }
    
    $title     =~ s/[^0-9\p{L}\x{C4}]+//g if ($title);

    # Jahr
    my $year   = "";

    foreach my $part_ref (@{$fields_ref->{'T0264'}}){
	if ($part_ref->{'subfield'} eq "c"){
	    $year = $part_ref->{'content'};
	    last;
	}
    }

    $year      =~ s/[^0-9]+//g if ($year);

    if ($logger->is_debug){
        $logger->debug("Got title: $title / author: $author / year: $year");
    }
    
    if ($author && $title && $year){
        return $title." ".$author." ".$year;
    }
    else {
        return "";
    }
}

sub gen_bibkey_base_mab {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields_ref  = exists $arg_ref->{fields}
        ? $arg_ref->{fields}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return "" unless (defined $fields_ref);

    if ($logger->is_debug){
        $logger->debug("Trying to generate bibkey with fields: ".YAML::Dump($fields_ref));
    }
    
    # Nur Bibkeys mit allen relevanten Informationen sinnvoll!
    
    return "" unless ( (defined $fields_ref->{'T0100'} || defined $fields_ref->{'T0101'} ) && defined $fields_ref->{'T0331'} && defined $fields_ref->{'T0425'} );
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $field (qw/T0100 T0101/){
        next if (!exists $fields_ref->{$field});
        foreach my $part_ref (@{$fields_ref->{$field}}){
            next unless (defined $part_ref->{content});
            
            my $single_person = lc($part_ref->{content});
            $single_person    =~ s/[^0-9\p{L}\. ]+//g;
            my ($lastname,$firstname) = split(/\s+/,$single_person);

            if (defined $firstname){
                if ($firstname eq $lastname){
                    $single_person    = $lastname;
                }
                else {
                    $single_person    = substr($firstname,0,1).".".$lastname;
                }
            }
            else {
                $single_person    = $lastname;
            }

            if (defined $part_ref->{supplement} && $part_ref->{supplement} =~ /Hrsg/){
                push @$editors_ref, $single_person;
            }
            else {
                push @$authors_ref, $single_person;
            }
        }
    }

    my $persons_ref=(defined $authors_ref && @$authors_ref)?$authors_ref:
    (defined $editors_ref && @$editors_ref)?$editors_ref:[];

    my $author = "";
    $author    = "[".join(",", sort(@$persons_ref))."]" if (defined $persons_ref && @$persons_ref);

    # Titel
    my $title  = (defined $fields_ref->{T0331})?lc($fields_ref->{T0331}[0]{content}):"";
    
    $title     =~ s/[^0-9\p{L}\x{C4}]+//g if ($title);

    # Jahr
    my $year   = (defined $fields_ref->{T0425})?$fields_ref->{T0425}[0]{content}:undef;

    $year      =~ s/[^0-9]+//g if ($year);

    if ($logger->is_debug){
        $logger->debug("Got title: $title / author: $author / year: $year");
    }
    
    if ($author && $title && $year){
        return $title." ".$author." ".$year;
    }
    else {
        return "";
    }
}

sub gen_bibkey {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields_ref    = exists $arg_ref->{fields}
        ? $arg_ref->{fields}               : undef;

    my $bibkey_base   = exists $arg_ref->{bibkey_base}
        ? $arg_ref->{bibkey_base}          : undef;

    my $scheme        = exists $arg_ref->{scheme}
        ? $arg_ref->{scheme}             : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($fields_ref){
        $bibkey_base = $self->gen_bibkey_base({fields => $fields_ref, scheme => $scheme});
    }
    
    if ($bibkey_base){
        return "1".md5_hex(encode_utf8($bibkey_base));
    }
    else {
        return "";
    }
}

sub gen_bibkey_from_marc {
    my ($self,$record,$encoding) = @_;

    my $persons_ref = [];
    my $year_ref    = [];
    my $title_ref   = [];
    
    foreach my $fieldno ('100','700'){
	foreach my $field ($record->field($fieldno)){
	    my $person = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
	    
	    push @$persons_ref, {
		content => $person,
	    }
	}
    }
    
    foreach my $field ($record->field('264')){
	my $year = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('c')):decode_utf8($field->as_string('c'));
	
	push @$year_ref, {
	    content => $year,
	};
    }
    
    foreach my $field ($record->field('245')){
	my $title = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
	
	push @$title_ref, {
	    content => $title,
	};
    }
    
    my $fields_ref = {
	'T0331' => $title_ref,
	'T0425' => $year_ref,
	'T0100' => $persons_ref,
    };
    
    my $bibkey = $self->gen_bibkey({ fields => $fields_ref });

    return $bibkey;
}

sub gen_workkeys {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields_ref  = exists $arg_ref->{fields}
        ? $arg_ref->{fields}             : undef;

    my $scheme      = exists $arg_ref->{scheme}
        ? $arg_ref->{scheme}             : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    return "" unless (defined $fields_ref);

    if ($scheme eq "marc"){
	return $self->gen_workkeys_marc($arg_ref);
    }
    else {
	return $self->gen_workkeys_mab($arg_ref);
    }
}

sub gen_workkeys_marc {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields_ref  = exists $arg_ref->{fields}
        ? $arg_ref->{fields}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return () unless (defined $fields_ref);

    if ($logger->is_debug){
        $logger->debug("Trying to generate workkey with fields: ".YAML::Dump($fields_ref));
    }

    my @workkeys = ();
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $field (qw/T0100 T0700/){
        next if (!exists $fields_ref->{$field});
        foreach my $part_ref (@{$fields_ref->{$field}}){
	    if ($part_ref->{'subfield'} eq "a"){
		my $single_person = lc($part_ref->{'content'});
		$single_person    =~ s/[^0-9\p{L}\. ]+//g;
		my ($lastname,$firstname) = split(/\s+/,$single_person);
		
		if (defined $firstname){
		    if ($firstname eq $lastname){
			$single_person    = $lastname;
		    }
		    else {
			$single_person    = substr($firstname,0,1).".".$lastname;
		    }
		}
		else {
		    $single_person    = $lastname;
		}
		
		if (exists $part_ref->{'supplement'} && $part_ref->{'supplement'} =~ /Hrsg/){
		    push @$editors_ref, $single_person;
		}
		else {
		    push @$authors_ref, $single_person;
		}
	    }
	}
    }

    my $persons_ref=(@$authors_ref)?$authors_ref:
    (@$editors_ref)?$editors_ref:[];

    my $workkey_done_ref = {};
    
    # For each person
    foreach my $person (@$persons_ref){
	# and each title
        foreach my $field (qw/T0130 T0240 T0245/){
            next if (!exists $fields_ref->{$field});
            foreach my $part_ref (@{$fields_ref->{$field}}){
		if ($part_ref->{'subfield'} eq "a"){
		    my $title = lc($part_ref->{content});
		    
		    if ($field eq "T0130" || $field eq "T0240"){
			$title =~s/\s+\&lt;.+\&gt;\s*$//;
		    }
		    
		    # Titel
		    $title  =~ s/[^0-9\p{L}\x{C4}]+//g if ($title);
		    
		    # Verlag ??? oder nur Fehlerquelle???
		    
		    my $publisher     = "";
		    my $editionstring = "";
		    
		    foreach my $part_ref (@{$fields_ref->{'T0264'}}){
			if ($part_ref->{'subfield'} eq "c"){
			    $editionstring = $part_ref->{'content'};
			}
			
			if ($part_ref->{'subfield'} eq "b"){
			    $publisher = lc($part_ref->{'content'});
			}
		    }

		    $publisher    =~ s/[^0-9\p{L}\x{C4}]+//g if ($publisher);
		    
		    # Auflage
		    #                my $editionstring = (defined $fields_ref->{T0403})?$fields_ref->{T0403}[0]{content}:"";
		    #                my ($edition) = $editionstring =~ m/^\D*(\d+)/;
		    
		    # Jahr               
		    my ($edition) = $editionstring =~ m/^\D*(\d\d\d\d)/;
		    
		    if ($edition){
			$edition = sprintf "%04d",$edition;
			
		    }
		    else {
			$edition = "0001";
		    }       
		    
		    my $language = "";

		    foreach my $part_ref (@{$fields_ref->{'T4301'}}){
			if ($part_ref->{'subfield'} eq "a"){
			    $language = lc($part_ref->{'content'});
			    last;
			}
		    }
		    
		    $edition = $edition.$language;
		    
		    my $is_online=0;
		    
		    foreach my $part_ref (@{$fields_ref->{'T4400'}}){
			if ($part_ref->{content} eq "online"){
			    $is_online=1;
			    last;
			}
		    }
		    
		    if ($is_online){
			$edition = $edition."online";
		    }
		    
		    if ($logger->is_debug){
			$logger->debug("Got title: $title / person: $person / publisher: $publisher / language: $language / online: $is_online / edition: $edition");
		    }
		    
		    if ($person && $title && $edition){
			my $workkey = $title." [".$person."] <".$edition.">";
			#                    push @workkeys, $title." [".$person."] ".$publisher." <".$edition.">";
			push @workkeys, $workkey unless (defined $workkey_done_ref->{$workkey});
			$workkey_done_ref->{$workkey} = 1;
		    }
		}
            }
        }
    }

    return @workkeys;
}

sub gen_workkeys_mab {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields_ref  = exists $arg_ref->{fields}
        ? $arg_ref->{fields}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return () unless (defined $fields_ref);

    if ($logger->is_debug){
        $logger->debug("Trying to generate workkey with fields: ".YAML::Dump($fields_ref));
    }

    my @workkeys = ();
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $field (qw/T0100 T0101/){
        next if (!exists $fields_ref->{$field});
        foreach my $part_ref (@{$fields_ref->{$field}}){
	    next unless (defined $part_ref->{content});
            my $single_person = lc($part_ref->{content});
            $single_person    =~ s/[^0-9\p{L}\. ]+//g;
            my ($lastname,$firstname) = split(/\s+/,$single_person);

            if (defined $firstname){
                if ($firstname eq $lastname){
                    $single_person    = $lastname;
                }
                else {
                    $single_person    = substr($firstname,0,1).".".$lastname;
                }
            }
            else {
                $single_person    = $lastname;
            }

            if (exists $part_ref->{supplement} && $part_ref->{supplement} =~ /Hrsg/){
                push @$editors_ref, $single_person;
            }
            else {
                push @$authors_ref, $single_person;
            }
        }
    }

    my $persons_ref=(@$authors_ref)?$authors_ref:
    (@$editors_ref)?$editors_ref:[];

    foreach my $person (@$persons_ref){
        foreach my $field (qw/T0304 T0331/){
            next if (!exists $fields_ref->{$field});
            foreach my $part_ref (@{$fields_ref->{$field}}){
		next unless (defined $part_ref->{content});
		
		my $title = lc($part_ref->{content});

                if ($field eq "T0304"){
                    $title =~s/\s+\&lt;.+\&gt;\s*$//;
                }

                # Titel
                $title  =~ s/[^0-9\p{L}\x{C4}]+//g if ($title);

                # Verlag ??? oder nur Fehlerquelle???
                my $publisher = (defined $fields_ref->{T0412})?lc($fields_ref->{T0412}[0]{content}):"";
                $publisher    =~ s/[^0-9\p{L}\x{C4}]+//g if ($publisher);

                # Auflage
#                my $editionstring = (defined $fields_ref->{T0403})?$fields_ref->{T0403}[0]{content}:"";
#                my ($edition) = $editionstring =~ m/^\D*(\d+)/;

                # Jahr
                my $editionstring   = (defined $fields_ref->{T0425})?$fields_ref->{T0425}[0]{content}:
                    (defined $fields_ref->{T0424})?$fields_ref->{T0424}:"";                
                my ($edition) = $editionstring =~ m/^\D*(\d\d\d\d)/;
                
                if ($edition){
                    $edition = sprintf "%04d",$edition;

                }
                else {
                    $edition = "0001";
                }       

                my $language = (defined $fields_ref->{T4301})?lc($fields_ref->{T4301}[0]{content}):"";

                $edition = $edition.$language;
                
                my $is_online=0;

                foreach my $part_ref (@{$fields_ref->{'T4400'}}){
                    if ($part_ref->{content} eq "online"){
                        $is_online=1;
                        last;
                    }
                }

                if ($is_online){
                    $edition = $edition."online";
                }
                
                if ($logger->is_debug){
                    $logger->debug("Got title: $title / person: $person / publisher: $publisher");
                }
                
                if ($person && $title && $publisher){
#                    push @workkeys, $title." [".$person."] ".$publisher." <".$edition.">";
                    push @workkeys, $title." [".$person."] <".$edition.">";
                }
            }
        }
    }

    return @workkeys;
}

sub to_isbn13 {
    my ($self,$thisisbn) = @_;

    return undef unless (defined $thisisbn);
    
    # Normierung auf ISBN13
    my $isbn     = Business::ISBN->new($thisisbn);
    
    if (defined $isbn && $isbn->is_valid){
        $thisisbn = $isbn->as_isbn13->as_string;
    }
    
    $thisisbn = $self->normalize({
        field    => 'T0540',
        content  => $thisisbn,
    });

    return $thisisbn;
}

sub to_issn {
    my ($self,$thisissn) = @_;

    return undef unless (defined $thisissn);
    
    $thisissn = $self->normalize({
        field    => 'T0543',
        content  => $thisissn,
    });

    return $thisissn;
}

1;
__END__

=head1 NAME

OpenBib::Normalizer

=head1 DESCRIPTION

Normalizierung von Begriffen fuer die Suche und Indexierung

=head1 SYNOPSIS

 use OpenBib::Normalizer;

 my $normalizer = new OpenBib::Normalizer;

 my $normalized_content = $normalizer->normalize({ content => $content, field => field, searchfield => $searchfield, searchreq => $searchreq, tagging => $tagging});

=head1 METHODS

=head2 Verschiedenes

=over 4

=item normalize({ content => $content, searchfield => $searchfield, $field => $field, searchreq => $searchreq, tagging => $tagging})

Allgemeine Normierung des Inhaltes $content oder in Abhängigkeit von
der Kategorie $field oder des Suchfeldes $searchfield bei einer Suchanfrage ($searchreq=1)
bzw. beim Tagging ($tagging=1). Neben einer Filterung nach erlaubten
Zeichen erfolgt insbesondere die Rückführung von Zeichen auf ihre
Grundbuchstaben, also ae für ä oder e für é.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
