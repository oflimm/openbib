####################################################################
#
#  OpenBib::Common::Util
#
#  Dieses File ist (C) 2004-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Common::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Benchmark ':hireswallclock';
use DBI;
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX();
use String::Tokenizer;
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

    # Buchstabenersetzungen
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
    
   );

my $chars_to_replace = join '|',
#    map quotemeta, 
    keys %char_replacements;

$chars_to_replace = qr/$chars_to_replace/;

# Aufruf-Varianten fuer normalize
#
# a) Fuer ein field
# b) Fuer einen typ
# c)

sub normalize {
    my ($arg_ref) = @_;
    
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

    $logger->debug("IN: $content / Type $type");
    
    return "" unless (defined $content);
    
    # Typ Integer kann sofort normiert werden

    if ($type eq "integer"){
        $logger->debug("Processing Type $type");
                
        $content =~s/\D//g;

        return $content;
    }
    
    # Normalisierung auf Kleinschreibung
    $content = lc($content);
    
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
    if (defined $option_ref->{'filter_isbn'} || $field eq "T0540" || $field eq "T0541" || $field eq "T0547" || $field eq "T0553" || $field eq "T0634" || $field eq "T1586" || $field eq "T1587" || $field eq "T1588" || $field eq "T1589" || $field eq "T1590" || $field eq "T1591" || $field eq "T1592" || $field eq "T1593"){
        # Entfernung der Minus-Zeichen bei der ISBN zuerst 13-, dann 10-stellig
        $content=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;

        return $content unless (defined $option_ref->{'filter_isbn'}); # Short circuit for field-specific normalization
    }
    
    # ISSN filtern
    if (defined $option_ref->{'filter_issn'} || $field eq "T0543" || $field eq "T0544" || $field eq "T0585" || $field eq "T1550" || $field eq "T1551" || $field eq "T1552" || $field eq "T1553" || $field eq "T1567" ){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8/g;

        return $content unless (defined $option_ref->{'filter_issn'}); # Short circuit for field-specific normalization
    }

    # Nichtsortierzeichen entfernen
    $content=~s/¬//g;

    # RAK-Zeilenumbruch bei alten Drucken usw. entfernen
    $content=~s/-\|\|//g; 
    $content=~s/ \|\| / /g;

    # Ausfiltern spezieller HTML-Tags
    $content=~s/&[gl]t;//g;
    $content=~s/&quot;//g;
    $content=~s/&amp;//g;

    # Ausfiltern von Supplements in []
    # $content=~s/\[.*?\]//g;
    
    # Fall: C++, C# und .Net
    $content=~s/(?<=(\w|\+))\+/plus/g;
    $content=~s/(c)\#/$1sharp/ig;
    $content=~s/\.(net)/dot$1/ig;

    # Stopwoerter fuer versch. Kategorien ausfiltern (Titel-String)

    if (defined $option_ref->{strip_first_stopword}){
        $content=OpenBib::Common::Stopwords::strip_first_stopword($content);
    }

    if (defined $option_ref->{strip_bracket_content}){
        $content=~s/\s+$//;
        $content=~s/\s+<.*?>//g;
    }
    
    $logger->debug("Checkpoint 1: $content");

    # Recherche
    if ($searchreq){
        if ($type eq 'string'){
            $logger->debug("Processing Type $type");
            
            # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
            # * wird fuer die Recherche als Wildcard nicht angefasst
            $content=~s/[^\p{Alphabetic}0-9*]/_/g;
        }
        else {
            # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
            $content=~s/[^-+\p{Alphabetic}\p{Sc}0-9\/: '()"^*_]//g;
            
            # Verbundene Terme splitten
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
            # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
            # * wird fuer die Indexierung auf _ normiert
            $content=~s/[^\p{Alphabetic}0-9]/_/g;
        }
        else {
            # Ausfiltern nicht akzeptierter Zeichen (Postitivliste)
            $content=~s/[^-+\p{Alphabetic}\p{Sc}0-9\/:* ']//g;
            
            # Verbundene Terme splitten
            $content=~s/(\w)-(\w)/$1 $2/g;
            $content=~s/(\w)'(\w)/$1 $2/g;
            
            # Bei Termen mit abschliessendem Bindestrich diesen entfernen
            $content=~s/(\w)-(\s)/$1$2/g;
            $content=~s/(\w)-$/$1/g;
            
            # Sonderbehandlung : fuer die Indexierung (bei der Recherche wird : fuer intitle: usw. benoetigt)
            $content=~s/:/ /g;
        }
    }

     $logger->debug("Checkpoint 2: $content");
    
    # Leerzeichen bei CJK einfuegen

    # $content=~s/(\p{InKatakana}|\p{InHiragana}|\p{InCJKCompatibility}|\p{InCJKCompatibilityForms}|\p{InCJKCompatibilityIdeographs}|\p{InCJKCompatibilityIdeographsSupplement}|\p{InCJKRadicalsSupplement}|\p{InCJKStrokes}|\p{InCJKSymbolsAndPunctuation}|\p{InCJKUnifiedIdeographs}|\p{InCJKUnifiedIdeographsExtensionA}|\p{InCJKUnifiedIdeographsExtensionB}|\p{InEnclosedCJKLettersAndMonths})/$1 /g;

    $content =~ s/($chars_to_replace)/$char_replacements{$1}/g;

    return $content;
}

sub get_loadbalanced_servername {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $view=$config->{defaultview};
    
    my $ua=new LWP::UserAgent(timeout => 5);

    # Aktuellen Load der Server holen zur dynamischen Lastverteilung au
    my @servertab=();

    foreach my $item ($config->get_serverinfo->search_rs(
        {
            active => 1,
        },
        {
            order_by => 'host'
        }
    )->all){
        push @servertab, $item->host;
    }

    $logger->debug("Got Servers ".YAML::Dump(\@servertab));
    
    if (!@servertab){
        push @servertab, $config->{servername};
    }
    
    my %serverload=();

    foreach my $target (@servertab) {
        $serverload{"$target"}=-1.0;
    }
  
    my $problem=0;
  
    # Fuer jeden Server, auf den verteilt werden soll, wird nun
    # per LWP der Load bestimmt.
    foreach my $targethost (@servertab) {
        my $request  = new HTTP::Request GET => "http://$targethost$config->{base_loc}/$view/$config->{serverload_loc}";
        my $response = $ua->request($request);

        if ($response->is_success) {
            $logger->debug("Getting ", $response->content);
        }
        else {
            $logger->error("Getting ", $response->status_line);
        }
    
        my $content=$response->content();
    
        if ($content eq "" || $content=~m/SessionDB: offline/m) {
            $problem=1;
        }
        elsif ($content=~m/^Load: (\d+\.\d+)/m) {
            my $load=$1;
            $serverload{$targethost}=$load;
        }
    
        # Wenn der Load fuer einen Server nicht bestimmt werden kann,
        # dann wird der Admin darueber benachrichtigt
    
        if ($problem == 1) {
            OpenBib::LoadBalancer::Util::benachrichtigung("Es ist der Server $targethost ausgefallen");
            $problem=0;
            next;
        }
    }
  
    my $minload="1000.0";
    my $bestserver="";

    # Nun wird der Server bestimmt, der den geringsten Load hat

    foreach my $targethost (@servertab) {
        if ($serverload{$targethost} > -1.0 && $serverload{$targethost} <= $minload) {
            $bestserver=$targethost;
            $minload=$serverload{$targethost};
        }
    }

    return $bestserver;
}

sub normset2bibtex {
    my ($normset_ref,$utf8)=@_;

    my $bibtex_ref=[];

    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $field (qw/T0100 T0101/){
        next if (!exists $normset_ref->{$field});
        foreach my $part_ref (@{$normset_ref->{$field}}){
            if ($part_ref->{supplement} =~ /Hrsg/){
                push @$editors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
            else {
                push @$authors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
        }
    }
    my $author = join(' and ',@$authors_ref);
    my $editor = join(' and ',@$editors_ref);

    # Schlagworte
    my $keywords_ref=[];
    foreach my $field (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $normset_ref->{$field});
        foreach my $part_ref (@{$normset_ref->{$field}}){
            push @$keywords_ref, utf2bibtex($part_ref->{content},$utf8);
        }
    }
    my $keyword = join(' ; ',@$keywords_ref);
    
    # Auflage
    my $edition   = (exists $normset_ref->{T0403})?utf2bibtex($normset_ref->{T0403}[0]{content},$utf8):'';

    # Verleger
    my $publisher = (exists $normset_ref->{T0412})?utf2bibtex($normset_ref->{T0412}[0]{content},$utf8):'';

    # Verlagsort
    my $address   = (exists $normset_ref->{T0410})?utf2bibtex($normset_ref->{T0410}[0]{content},$utf8):'';

    # Titel
    my $title     = (exists $normset_ref->{T0331})?utf2bibtex($normset_ref->{T0331}[0]{content},$utf8):'';

    # Zusatz zum Titel
    my $titlesup  = (exists $normset_ref->{T0335})?utf2bibtex($normset_ref->{T0335}[0]{content},$utf8):'';

    if ($title && $titlesup){
        $title = "$title : $titlesup";
    }

    # Jahr
    my $year      = (exists $normset_ref->{T0425})?utf2bibtex($normset_ref->{T0425}[0]{content},$utf8):'';

    # ISBN
    my $isbn      = (exists $normset_ref->{T0540})?utf2bibtex($normset_ref->{T0540}[0]{content},$utf8):'';

    # ISSN
    my $issn      = (exists $normset_ref->{T0543})?utf2bibtex($normset_ref->{T0543}[0]{content},$utf8):'';

    # Sprache
    my $language  = (exists $normset_ref->{T0516})?utf2bibtex($normset_ref->{T0516}[0]{content},$utf8):'';

    # Abstract
    my $abstract  = (exists $normset_ref->{T0750})?utf2bibtex($normset_ref->{T0750}[0]{content},$utf8):'';

    # Origin
    my $origin    = (exists $normset_ref->{T0590})?utf2bibtex($normset_ref->{T0590}[0]{content},$utf8):'';

    if ($author){
        push @$bibtex_ref, "author    = \"$author\"";
    }
    if ($editor){
        push @$bibtex_ref, "editor    = \"$editor\"";
    }
    if ($edition){
        push @$bibtex_ref, "edition   = \"$edition\"";
    }
    if ($publisher){
        push @$bibtex_ref, "publisher = \"$publisher\"";
    }
    if ($address){
        push @$bibtex_ref, "address   = \"$address\"";
    }
    if ($title){
        push @$bibtex_ref, "title     = \"$title\"";
    }
    if ($year){
        push @$bibtex_ref, "year      = \"$year\"";
    }
    if ($isbn){
        push @$bibtex_ref, "ISBN      = \"$isbn\"";
    }
    if ($issn){
        push @$bibtex_ref, "ISSN      = \"$issn\"";
    }
    if ($keyword){
        push @$bibtex_ref, "keywords  = \"$keyword\"";
    }
    if ($language){
        push @$bibtex_ref, "language  = \"$language\"";
    }
    if ($abstract){
        push @$bibtex_ref, "abstract  = \"$abstract\"";
    }

    if ($origin){
        # Pages
        if ($origin=~/ ; (S\. *\d+.*)$/){
            push @$bibtex_ref, "pages     = \"$1\"";
        }
        elsif ($origin=~/, (S\. *\d+.*)$/){
            push @$bibtex_ref, "pages     = \"$1\"";
        }

        # Journal and/or Volume
        if ($origin=~/^(.+?) ; (.*?) ; S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?)\. (.*?), (\d\d\d\d), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;
            my $year    = $3;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?)\. (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?) ; (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.*?) ; S\. *\d+.*$/){
            my $journal = $1;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
        }
    }

    my $identifier=substr($author,0,4).substr($title,0,4).$year;
    $identifier=~s/[^A-Za-z0-9]//g;

    my $bibtex="";

    if ($origin){
        unshift @$bibtex_ref, "\@article {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }
    elsif ($isbn){
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }
    else {
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }

    
    return $bibtex;
}

sub utf2bibtex {
    my ($string,$utf8)=@_;

    return "" if (!defined $string);
    
    # {} werden von BibTeX verwendet und haben in den Originalinhalten
    # nichts zu suchen
    $string=~s/\{//g;
    $string=~s/\}//g;
    # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
    $string=~s/[^-+\p{Alphabetic}0-9\n\/&;#: '()@<>\\,.="^*[]]//g;
    $string=~s/&lt;/</g;
    $string=~s/&gt;/>/g;
    $string=~s/&amp;/&/g;

    # Wenn utf8 ausgegeben werden soll, dann sind wir hier fertig
    return $string if ($utf8);

    # ... ansonsten muessen weitere Sonderzeichen umgesetzt werden.
    $string=~s/&#172;//g;
    $string=~s/&#228;/{\\"a}/g;
    $string=~s/&#252;/{\\"u}/g;
    $string=~s/&#246;/{\\"o}/g;
    $string=~s/&#223;/{\\"s}/g;
    $string=~s/&#214;/{\\"O}/g;
    $string=~s/&#220;/{\\"U}/g;
    $string=~s/&#196;/{\\"A}/g;
    $string=~s/&auml;/{\\"a}/g;
    $string=~s/&ouml;/{\\"o}/g;
    $string=~s/&uuml;/{\\"u}/g;
    $string=~s/&Auml;/{\\"A}/g;
    $string=~s/&Ouml;/{\\"O}/g;
    $string=~s/&Uuml;/{\\"U}/g;
    $string=~s/&szlig;/{\\"s}/g;
    $string=~s/ä/{\\"a}/g;
    $string=~s/ö/{\\"o}/g;
    $string=~s/ü/{\\"u}/g;
    $string=~s/Ä/{\\"A}/g;
    $string=~s/Ö/{\\"O}/g;
    $string=~s/Ü/{\\"U}/g;
    $string=~s/ß/{\\"s}/g;

    return $string;
}

sub gen_bibkey_base {
    my ($arg_ref) = @_;

    # Set defaults
    my $fields_ref  = exists $arg_ref->{fields}
        ? $arg_ref->{fields}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return "" unless (defined $fields_ref);

    $logger->debug("Trying to generate bibkey with fields: ".YAML::Dump($fields_ref));
    
    # Nur Bibkeys mit allen relevanten Informationen sinnvoll!
    
    return "" unless ( (exists $fields_ref->{'T0100'} || exists $fields_ref->{'T0101'} ) && exists $fields_ref->{'T0331'} && exists $fields_ref->{'T0425'} );
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $field (qw/T0100 T0101/){
        next if (!exists $fields_ref->{$field});
        foreach my $part_ref (@{$fields_ref->{$field}}){
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

    my $author = "";
    $author    = "[".join(",", sort(@$persons_ref))."]" if (defined $persons_ref && @$persons_ref);

    # Titel
    my $title  = (exists $fields_ref->{T0331})?lc($fields_ref->{T0331}[0]{content}):"";
    
    $title     =~ s/[^0-9\p{L}\x{C4}]+//g if ($title);

    # Jahr
    my $year   = (exists $fields_ref->{T0425})?$fields_ref->{T0425}[0]{content}:undef;

    $year      =~ s/[^0-9]+//g if ($year);

    $logger->debug("Got title: $title / author: $author / year: $year");
    
    if ($author && $title && $year){
        return $title." ".$author." ".$year;
    }
    else {
        return "";
    }
}

sub gen_bibkey {
    my ($arg_ref) = @_;

    # Set defaults
    my $fields_ref    = exists $arg_ref->{fields}
        ? $arg_ref->{fields}               : undef;

    my $bibkey_base   = exists $arg_ref->{bibkey_base}
        ? $arg_ref->{bibkey_base}          : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($fields_ref){
        $bibkey_base = OpenBib::Common::Util::gen_bibkey_base({fields => $fields_ref});
    }
    
    if ($bibkey_base){
        return "1".md5_hex(encode_utf8($bibkey_base));
    }
    else {
        return "";
    }
}

sub to_isbn13 {
    my ($thisisbn) = @_;

    return undef unless (defined $thisisbn);
    
    # Normierung auf ISBN13
    my $isbn     = Business::ISBN->new($thisisbn);
    
    if (defined $isbn && $isbn->is_valid){
        $thisisbn = $isbn->as_isbn13->as_string;
    }
    
    $thisisbn = OpenBib::Common::Util::normalize({
        field => 'T0540',
        content  => $thisisbn,
    });

    return $thisisbn;
}

sub to_issn {
    my ($thisissn) = @_;

    return undef unless (defined $thisissn);
    
    $thisissn = OpenBib::Common::Util::normalize({
        field => 'T0543',
        content  => $thisissn,
    });

    return $thisissn;
}

sub get_cascaded_templatepath {
    my ($arg_ref) = @_;

    # Set defaults
    my $database     = exists $arg_ref->{database}
        ? $arg_ref->{database}             : undef;

    my $view         = exists $arg_ref->{view}
        ? $arg_ref->{view}                 : undef;

    my $profile      = exists $arg_ref->{profile}
        ? $arg_ref->{profile}              : undef;

    my $templatename = exists $arg_ref->{templatename}
        ? $arg_ref->{templatename}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if ($profile && -e "$config->{tt_include_path}/_profile/$profile") {

        # Database-Template ist spezifischer als View-Template und geht vor
        if ($database && -e "$config->{tt_include_path}/_profile/$profile/_database/$database/$templatename") {
            $templatename="_profile/$profile/_database/$database/$templatename";
        }
        elsif ($view && -e "$config->{tt_include_path}/_profile/$profile/_view/$view/$templatename") {
            $templatename="_profile/$profile/_view/$view/$templatename";
        }
        elsif ($view && -e "$config->{tt_include_path}/_profile/$profile/$templatename") {
            $templatename="_profile/$profile/$templatename";
        }
        # Database-Template ist spezifischer als View-Template und geht vor
        elsif ($database && -e "$config->{tt_include_path}/_database/$database/$templatename") {
            $templatename="_database/$database/$templatename";
        }                
        elsif ($view && -e "$config->{tt_include_path}/_view/$view/$templatename") {
            $templatename="_view/$view/$templatename";
        }
        
    }
    else {
        # Database-Template ist spezifischer als View-Template und geht vor
        if ($database && -e "$config->{tt_include_path}/_database/$database/$templatename") {
            $templatename="_database/$database/$templatename";
        }
        elsif ($view && -e "$config->{tt_include_path}/_view/$view/$templatename") {
            $templatename="_view/$view/$templatename";
        }        
    }

    return $templatename;
}

sub gen_cloud_class {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $items_ref    = exists $arg_ref->{items}
        ? $arg_ref->{items}   : [];
    my $mincount     = exists $arg_ref->{min}
        ? $arg_ref->{min}     : 0;
    my $maxcount     = exists $arg_ref->{max}
        ? $arg_ref->{max}     : 0;
    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}    : 'log';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($type eq 'log'){

      if ($maxcount-$mincount > 0){
	
	my $delta = ($maxcount-$mincount) / 6;
	
	my @thresholds = ();
	
	for (my $i=0 ; $i<=6 ; $i++){
	  $thresholds[$i] = 100 * log(($mincount + $i * $delta) + 2);
	}

        $logger->debug(YAML::Dump(\@thresholds)." - $delta");

	foreach my $item_ref (@$items_ref){
	  my $done = 0;
	
	  for (my $class=0 ; $class<=6 ; $class++){
	    if ((100 * log($item_ref->{count} + 2) <= $thresholds[$class]) && !$done){
	      $item_ref->{class} = $class;
              $logger->debug("Klasse $class gefunden");
	      $done = 1;
	    }
	  }
	}
      }
    }
    elsif ($type eq 'linear'){
      if ($maxcount-$mincount > 0){
	foreach my $item_ref (@$items_ref){
	  $item_ref->{class} = int(($item_ref->{count}-$mincount) / ($maxcount-$mincount) * 6);
	}
      }
    }

    $logger->debug(YAML::Dump($items_ref));
    return $items_ref;
}

sub dispatch_to_content_type {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $uri          = exists $arg_ref->{uri}
        ? $arg_ref->{uri}     : undef;
    my $r            = exists $arg_ref->{apreq}
        ? $arg_ref->{apreq}   : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $content_type_map_ref = {
        "application/rdf+xml" => "rdf+xml",
        "text/rdf+n3"         => "rdf+n3",
    };

    my $accept       = $r->headers_in->{Accept} || '';
    my @accept_types = map { (split ";", $_)[0] } split /\*s,\*s/, $accept;
        
    my $information_found = 0;
    foreach my $information_type (keys %{$content_type_map_ref}){            
        if (any { $_ eq $information_type } @accept_types) {
            $r->content_type($information_type);
            my $new_location = $uri."/".$content_type_map_ref->{$information_type};
            $logger->debug("Redirecting to $new_location");
            $r->headers_out->add("Location" => $new_location);
            $information_found = 1;
            $logger->debug("Information Resource Type: $information_type");
        }                                                
    }
    
    if (!$information_found){
        my $information_type="text/html";
        $r->content_type($information_type);
        $r->headers_out->add("Location" => "$uri/html");
        $logger->debug("Information Resource Type: $information_type");
    }
    
    $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accept_types));

    return Apache2::Const::HTTP_SEE_OTHER;
}

sub query2hashref {
    my $query=shift;

    my $args_ref = {};
    my @param_names = $query->param;
    foreach my $param (@param_names){
        $args_ref->{$param} = $query->param($param);
    }

    return $args_ref;
}

sub dec2bin {
    my $str = unpack("B32", pack("N", shift));
    $str =~ s/^0+(?=\d)//;   # strip leading zeroes
    return $str;
}
sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}

1;
__END__

=head1 NAME

OpenBib::Common::Util - Gemeinsame Funktionen der OpenBib-Module

=head1 DESCRIPTION

In OpenBib::Common::Util sind all jene Funktionen untergebracht, die
von mehr als einem mod_perl-Modul verwendet werden.

=head1 SYNOPSIS

 use OpenBib::Common::Util;

 my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

 my $normalized_content = OpenBib::Common::Util::normalize({ content => $content, field => field, searchfield => $searchfield, searchreq => $searchreq, tagging => $tagging});

 my $server_to_use = OpenBib::Common::Util::get_loadbalanced_servername;

 my $bibtex_entry = OpenBib::Common::Util::normset2bibtex($normset_ref,$utf8);

 my $bibkey = OpenBib::Common::Util::gen_bibkey({ fields => $fields_ref});

 my $nomalized_isbn13 = OpenBib::Common::Util::to_isbn13($isbn10);

 my $effective_path_to_template = OpenBib::Common::Util::get_cascaded_templatepath({ database => $database, view => $view, profile => $profile, templatename => $templatename });

 my $items_with_cloudinfo_ref = OpenBib::Common::Util::gen_cloud_class({ items => $items_ref, min => $mincount, max => $maxcount, type => $type});

 OpenBib::Common::Util::print_page($templatename,$ttdata,$r);
 OpenBib::Common::Util::print_info($warning,$r,$msg);
 OpenBib::Common::Util::print_warning($warning,$r,$msg);

=head1 METHODS

=head2 Verschiedenes

=over 4

=item get_css_by_browertype

Liefert den Namen des CSS Stylesheets entsprechend des aufrufenden
HTTP_USER_AGENT zurück. Das ist im Fall der aktuellen MSIE-Versionen
5-9 das Stylesheet openbib-ie.css, im Fall von Mozilla 5.0 das
Stylesheet openbib.css. Bei anderen Browser-Version wird im Falle von
MSIE sonst openbib-simple-ie.css bzw. bei allen anderen Browsern
openbib-simple.css verwendet.

=item normalize({ content => $content, searchfield => $searchfield, $field => $field, searchreq => $searchreq, tagging => $tagging})

Allgemeine Normierung des Inhaltes $content oder in Abhängigkeit von
der Kategorie $field oder des Suchfeldes $searchfield bei einer Suchanfrage ($searchreq=1)
bzw. beim Tagging ($tagging=1). Neben einer Filterung nach erlaubten
Zeichen erfolgt insbesondere die Rückführung von Zeichen auf ihre
Grundbuchstaben, also ae für ä oder e für é.

=item get_loadbalanced_servername

Liefert den Namen des Servers aus der Menge aktiver Produktionsserver
zurück, der am wenigsten belastet ist (bzgl. Load) und dessen
Session-Datenbank korrekt funktioniert.

=item normset2bibtex($normset_ref,$utf8)

Wandelt den bibliographischen Datensatz $normset_ref in das
BibTeX-Format um. Über $utf8 kann spezifiziert werden, ob in diesem
Eintrag UTF8-Kodierung verwendet werden soll oder plain (La)TeX.

=item utf2bibtex($string,$utf8)

Filtert nicht akzeptierte Zeichen aus $string und wandelt die
UTF8-kodierten Sonderzeichen des Strings $string, wenn $utf8 nicht
besetzt ist, in das plain (La)TeX-Format.

=item gen_bibkey_base({ fields => $fields_ref })

Generiere die Basiszeichenkette aus den bibliographischen Daten für
die Bildung des BibKeys. Dies ist eine Hilfsfunktion für gen_bibkey

=item gen_bibkey({ fields => $fields_ref, bibkey_base => $bibkey_base})

Erzeuge einen BibKey entweder aus den bibliographischen Daten
$fields_ref oder aus einer schon generierten Basis-Zeichenkette
$bibkey_base.

=item to_isbn13($isbn10)

Erzeuge eine ISBN13 aus einer ISBN und liefere diese normiert (keine
Leerzeiche oder Bindestricke, Kleinschreibung) zurück.

=item get_cascaded_templatepath({ database => $database, view => $view, profile => $profile, templatename => $templatename })

Liefert in Abhängigkeit der Datenbank $database, des View $view und des
Katalogprofils $profile den effektiven Pfad zum jeweiligen Template
$templatename zurück.

=item gen_cloud_class({ items => $items_ref, min => $mincount, max => $maxcount, type => $type})

Reichere eine Liste quantifizierter Begriffe $items_ref entsprechend
schon bestimmten minimalen und maximalen Vorkommens $mincount
bzw. $maxcount für den type 'linear/log' mit Klasseninformatinen für
die Bildung einer Wortwolke an.

=back

=head2 Ausgabe über Apache-Handler

=over 4


=item print_page($templatename,$ttdata,$r)

Ausgabe des Templates $templatename mit den Daten $ttdata über den
Apache-Handler $r

=item print_warning($warning,$r,$msg)

Ausgabe des Warnhinweises $warning über den Apache-Handler $r unter
Verwendung des Message-Katalogs $msg

=item print_info($info,$r,$msg,$representation,$content_type)

Ausgabe des Informationstextes $info an den Apache-Handler $r unter
Verwendung des Message-Katalogs $msg

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
