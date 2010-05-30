#####################################################################
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

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX();
use String::Tokenizer;
use Template;
use Unicode::Semantics;
use YAML ();

use OpenBib::Config;
use OpenBib::Template::Provider;
use OpenBib::Session;

sub get_css_by_browsertype {
    my ($r)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT') || '';

    $logger->debug("User-Agent: $useragent");

    my $stylesheet="";
  
    if ( $useragent=~/Mozilla.5.0/ || $useragent=~/MSIE [5-9]/ || $useragent=~/Konqueror"/ ) {
        if ($useragent=~/MSIE/) {
            $stylesheet="openbib-ie.css";
        }
        else {
            $stylesheet="openbib.css";
        }
    }
    else {
        if ($useragent=~/MSIE/) {
            $stylesheet="openbib-simple-ie.css";
        }
        else {
            $stylesheet="openbib-simple.css";
        }
    }

    return $stylesheet;
}


sub print_warning {
    my ($warning,$r,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $config = OpenBib::Config->instance;
    
    my $stylesheet=get_css_by_browsertype($r);

    my $query=Apache2::Request->new($r);

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    my $session = OpenBib::Session->instance({
        sessionID => $sessionID,
    });
    
    my $view    = $session->get_viewname();

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});

    my $sysprofile= $config->get_viewinfo($view)->{profilename};

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }

    my $templatename = $config->{tt_error_tname};

    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '',
        view         => $view,
        profile      => $sysprofile,
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");

    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        OUTPUT         => $r,    # Output geht direkt an Apache Request
        RECURSION      => 1,
    });
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        sysprofile => $sysprofile,
        stylesheet => $stylesheet,
        loginname  => $loginname,
        sessionID  => $session->{ID},
        errmsg     => $warning,
        config     => $config,
        user       => $user,
        msg        => $msg,
    };
  
    # Dann Ausgabe des neuen Headers
    $r->content_type("text/html");
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
  
    return;
}

sub print_info {
    my ($info,$r,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;
    
    my $stylesheet=get_css_by_browsertype($r);

    my $query=Apache2::Request->new($r);

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    my $session = OpenBib::Session->instance({sessionID => $sessionID});

    my $view    = $session->get_viewname();

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }
    
    my $templatename = $config->{tt_info_message_tname};
    
    if ($view && -e "$config->{tt_include_path}/views/$view/$templatename") {
        $templatename="views/$view/$templatename";
    }

    $logger->debug("Using Template $templatename");
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        OUTPUT         => $r,    # Output geht direkt an Apache Request
        RECURSION      => 1,
    });
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        loginname  => $loginname,
        info_msg   => $info,
        config     => $config,
        user       => $user,
        msg        => $msg,
    };
  
    # Dann Ausgabe des neuen Headers
    $r->content_type("text/html");
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
  
    return;
}   

sub print_page {
    my ($templatename,$ttdata,$r)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $content_type = $ttdata->{'content_type'} || 'text/html';
    
    # View- und Datenbank-spezifisches Templating
    my $database  = $ttdata->{'database'};
    my $sessionID = $ttdata->{'sessionID'};
    
    my $session   = OpenBib::Session->instance({ sessionID => $sessionID });

    my $view;
    if ($ttdata->{'view'}){
        $view = $ttdata->{'view'};
    }
    else {
        $view = $session->get_viewname;
        $ttdata->{'view'} = $view;
    }

    my $sysprofile= $config->get_viewinfo($view)->{profilename};
    
    my $user      = OpenBib::User->instance({sessionID => $sessionID});

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }

    # TT-Data anreichern
    $ttdata->{'loginname'}  = $loginname;
    $ttdata->{'sysprofile'} = $sysprofile;

    $logger->debug("Using base Template $templatename");

    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database,
        view         => $view,
        profile      => $sysprofile,
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");
  
    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
        }) ],
         OUTPUT         => $r,    # Output geht direkt an Apache Request
         RECURSION      => 1,
    });
  
    # Dann Ausgabe des neuen Headers
    $r->content_type($content_type);
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
  
    return;
}

sub grundform {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $content   = exists $arg_ref->{content}
        ? $arg_ref->{content}             : "";

    my $category  = exists $arg_ref->{category}
        ? $arg_ref->{category}            : "";

    my $searchreq = exists $arg_ref->{searchreq}
        ? $arg_ref->{searchreq}           : undef;

    my $tagging   = exists $arg_ref->{tagging}
        ? $arg_ref->{tagging}             : undef;

    # Normalisierung auf Kleinschreibung
    $content = lc($content);
    
    # Sonderbehandlung verschiedener Kategorien

    # Datum normalisieren

    if ($category eq '0002'){
        if ($content =~ /^(\d\d)\.(\d\d)\.(\d\d\d\d)$/){
            $content=$3.$2.$1;
            return $content;
        }
    }
    
    # ISBN filtern
    if ($category eq "0540" || $category eq "0553"){
        # Entfernung der Minus-Zeichen bei der ISBN zuerst 13-, dann 10-stellig
        $content=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
        return $content;
    }

    # ISSN filtern
    if ($category eq "0543"){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8/g;
        return $content;
    }

    $content=~s/¬//g;

    # Stopwoerter fuer versch. Kategorien ausfiltern (Titel-String)

    if ($category eq "0304" || $category eq "0310" || $category eq "0331"
            || $category eq "0341" || $category eq "0370"){

        $content=~s/\s+$//;
        $content=~s/\s+<.*?>//g;

        $content=OpenBib::Common::Stopwords::strip_first_stopword($content);
    }
    
    # Ausfiltern spezieller HTML-Tags
    $content=~s/&[gl]t;//g;
    $content=~s/&quot;//g;
    $content=~s/&amp;//g;

    # Ausfiltern von Supplements in []
    $content=~s/\[.*?\]//g;
    
    # Fall: C++, C# und .Net
    $content=~s/(?<=(\w|\+))\+/plus/g;
    $content=~s/(c)\#/$1sharp/ig;
    $content=~s/\.(net)/dot$1/ig;
    
    if ($searchreq){
        # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
        $content=~s/[^-+\p{Alphabetic}0-9\/: '()"^*_]//g;

        # Verbundene Terme splitten
        $content=~s/(\w)-(\w)/$1 $2/g;
        $content=~s/(\w)'(\w)/$1 $2/g;

        # Bei Termen mit abschliessendem Bindestrich diesen entfernen
        $content=~s/(\w)-(\s)/$1$2/g;
        $content=~s/(\w)-$/$1/g;
    }
    elsif ($tagging){
        $content=~s/[^-+\p{Alphabetic}0-9._]//g;

    }
    else {
        # Ausfiltern nicht akzeptierter Zeichen (Postitivliste)
        $content=~s/[^-+\p{Alphabetic}0-9\/: ']//g;

        # Verbundene Terme splitten
        $content=~s/(\w)-(\w)/$1 $2/g;
        $content=~s/(\w)'(\w)/$1 $2/g;

        # Bei Termen mit abschliessendem Bindestrich diesen entfernen
        $content=~s/(\w)-(\s)/$1$2/g;
        $content=~s/(\w)-$/$1/g;
        
	# Sonderbehandlung : fuer die Indexierung (bei der Recherche wird : fuer intitle: usw. benoetigt)
	$content=~s/:/ /g;
    }

    # Leerzeichen bei CJK einfuegen

    $content=~s/(\p{InKatakana}|\p{InHiragana}|\p{InCJKCompatibility}|\p{InCJKCompatibilityForms}|\p{InCJKCompatibilityIdeographs}|\p{InCJKCompatibilityIdeographsSupplement}|\p{InCJKRadicalsSupplement}|\p{InCJKStrokes}|\p{InCJKSymbolsAndPunctuation}|\p{InCJKUnifiedIdeographs}|\p{InCJKUnifiedIdeographsExtensionA}|\p{InCJKUnifiedIdeographsExtensionB}|\p{InEnclosedCJKLettersAndMonths})/$1 /g;
    
    # Zeichenersetzungen
    $content=~s/'/ /g;
    $content=~s/\// /g;
    #$content=~s/:/ /g;
    $content=~s/  / /g;

    # Buchstabenersetzungen
    $content=~s/ü/ue/g;
    $content=~s/ä/ae/g;
    $content=~s/ö/oe/g;
    $content=~s/Ü/Ue/g;
    $content=~s/Ö/Oe/g;
    $content=~s/Ä/Ae/g;
    $content=~s/ß/ss/g;

    $content=~s/é/e/g;
    $content=~s/è/e/g;
    $content=~s/ê/e/g;
    $content=~s/ë/e/g;
    $content=~s/\x{113}/e/g; # Kl. e mit Ueberstrich/Macron
    $content=~s/\x{115}/e/g; # Kl. e mit Hacek/Breve
    $content=~s/\x{11b}/e/g; # Kl. e mit Caron
    $content=~s/\x{117}/e/g; # Kl. e mit Punkt
    
    $content=~s/É/E/g;
    $content=~s/È/E/g;
    $content=~s/Ê/E/g;
    $content=~s/Ë/E/g;
    $content=~s/\x{112}/E/g; # Gr. E mit Ueberstrich/Macron
    $content=~s/\x{114}/E/g; # Gr. E mit Hacek/Breve
    $content=~s/\x{11a}/E/g; # Gr. E mit Caron
    $content=~s/\x{116}/E/g; # Gr. E mit Punkt
    
    $content=~s/á/a/g;
    $content=~s/à/a/g;
    $content=~s/â/a/g;
    $content=~s/ã/a/g;
    $content=~s/å/a/g;
    $content=~s/\x{101}/a/g; # Kl. a mit Ueberstrich/Macron
    $content=~s/\x{103}/a/g; # Kl. a mit Hacek/Breve
    
    $content=~s/Á/A/g;
    $content=~s/À/A/g;
    $content=~s/Â/A/g;
    $content=~s/Ã/A/g;
    $content=~s/Å/A/g;
    $content=~s/\x{100}/A/g; # Gr. A mit Ueberstrich/Macron
    $content=~s/\x{102}/A/g; # Gr. A mit Hacek/Breve
    
    $content=~s/ó/o/g;
    $content=~s/ò/o/g;
    $content=~s/ô/o/g;
    $content=~s/õ/o/g;
    $content=~s/\x{14d}/o/g; # Kl. o mit Ueberstrich/Macron
    $content=~s/\x{14f}/o/g; # Kl. o mit Hacek/Breve
    $content=~s/\x{151}/o/g; # Kl. o mit Doppel-Acute
    
    $content=~s/Ó/O/g;
    $content=~s/Ò/O/g;
    $content=~s/Ô/O/g;
    $content=~s/Õ/O/g;
    $content=~s/\x{14c}/O/g; # Gr. O mit Ueberstrich/Macron
    $content=~s/\x{14e}/O/g; # Gr. O mit Hacek/Breve
    $content=~s/\x{150}/O/g; # Gr. O mit Doppel-Acute
    
    $content=~s/í/i/g;
    $content=~s/ì/i/g;
    $content=~s/î/i/g;
    $content=~s/ï/i/g;
    $content=~s/\x{131}/i/g; # Kl. punktloses i
    $content=~s/\x{12b}/i/g; # Kl. i mit Ueberstrich/Macron
    $content=~s/\x{12d}/i/g; # Kl. i mit Hacek/Breve

    
    $content=~s/Í/I/g;
    $content=~s/Ì/I/g;
    $content=~s/Î/I/g;
    $content=~s/Ï/I/g;
    $content=~s/\x{130}/I/g; # Gr. I mit Punkt
    $content=~s/\x{12a}/I/g; # Gr. i mit Ueberstrich/Macron
    $content=~s/\x{12c}/I/g; # Gr. i mit Hacek/Breve

    $content=~s/Ú/U/g;
    $content=~s/Ù/U/g;
    $content=~s/Û/U/g;
    $content=~s/\x{168}/U/g; # Gr. U mit Tilde
    $content=~s/\x{16a}/U/g; # Gr. U mit Ueberstrich/Macron
    $content=~s/\x{16c}/U/g; # Gr. U mit Hacek/Breve
    $content=~s/\x{170}/U/g; # Gr. U mit Doppel-Acute
    $content=~s/\x{16e}/U/g; # Gr. U mit Ring oben

    $content=~s/ú/u/g;
    $content=~s/ù/u/g;
    $content=~s/û/u/g;
    $content=~s/\x{169}/u/g; # Kl. u mit Tilde
    $content=~s/\x{16b}/u/g; # Kl. u mit Ueberstrich/Macron
    $content=~s/\x{16d}/u/g; # Kl. u mit Hacek/Breve
    $content=~s/\x{171}/u/g; # Kl. u mit Doppel-Acute
    $content=~s/\x{16f}/u/g; # Kl. u mit Ring oben

    $content=~s/ø/o/g;
    $content=~s/Ø/o/g;

    $content=~s/ñ/n/g;
    $content=~s/\x{144}/n/g; # Kl. n mit Acute
    $content=~s/\x{146}/n/g; # Kl. n mit Cedille
    $content=~s/\x{148}/n/g; # Kl. n mit Caron

    $content=~s/Ñ/N/g;
    $content=~s/\x{143}/N/g; # Gr. N mit Acute
    $content=~s/\x{145}/N/g; # Gr. N mit Cedille
    $content=~s/\x{147}/N/g; # Gr. N mit Caron

    $content=~s/\x{155}/r/g; # Kl. r mit Acute
    $content=~s/\x{157}/r/g; # Kl. r mit Cedille
    $content=~s/\x{159}/r/g; # Kl. r mit Caron

    $content=~s/\x{154}/R/g; # Gr. R mit Acute
    $content=~s/\x{156}/R/g; # Gr. R mit Cedille
    $content=~s/\x{158}/R/g; # Gr. R mit Caron

    $content=~s/\x{15b}/s/g; # Kl. s mit Acute
    $content=~s/\x{15d}/s/g; # Kl. s mit Circumflexe
    $content=~s/\x{15f}/s/g; # Kl. s mit Cedille
    $content=~s/š/s/g; # Kl. s mit Caron

    $content=~s/\x{15a}/S/g; # Gr. S mit Acute
    $content=~s/\x{15c}/S/g; # Gr. S mit Circumflexe
    $content=~s/\x{15e}/S/g; # Gr. S mit Cedille
    $content=~s/Š/S/g; # Gr. S mit Caron

    $content=~s/\x{167}/t/g; # Kl. t mit Mittelstrich
    $content=~s/\x{163}/t/g; # Kl. t mit Cedille
    $content=~s/\x{165}/t/g; # Kl. t mit Caron

    $content=~s/\x{166}/T/g; # Gr. T mit Mittelstrich
    $content=~s/\x{162}/T/g; # Gr. T mit Cedille
    $content=~s/\x{164}/T/g; # Gr. T mit Caron

    $content=~s/\x{17a}/z/g; # Kl. z mit Acute
    $content=~s/\x{17c}/z/g; # Kl. z mit Punkt oben
    $content=~s/ž/z/g; # Kl. z mit Caron

    $content=~s/\x{179}/Z/g; # Gr. Z mit Acute
    $content=~s/\x{17b}/Z/g; # Gr. Z mit Punkt oben
    $content=~s/Ž/Z/g; # Gr. Z mit Caron

    $content=~s/ç/c/g;
    $content=~s/\x{107}/c/g; # Kl. c mit Acute
    $content=~s/\x{108}/c/g; # Kl. c mit Circumflexe
    $content=~s/\x{10b}/c/g; # Kl. c mit Punkt oben
    $content=~s/\x{10d}/c/g; # Kl. c mit Caron
    
    $content=~s/Ç/c/g;
    $content=~s/\x{106}/C/g; # Gr. C mit Acute
    $content=~s/\x{108}/C/g; # Gr. C mit Circumflexe
    $content=~s/\x{10a}/C/g; # Gr. C mit Punkt oben
    $content=~s/\x{10c}/C/g; # Gr. C mit Caron

    $content=~s/\x{10f}/d/g; # Kl. d mit Caron
    $content=~s/\x{10e}/D/g; # Gr. D mit Caron

    $content=~s/\x{123}/g/g; # Kl. g mit Cedille
    $content=~s/\x{11f}/g/g; # Kl. g mit Breve
    $content=~s/\x{11d}/g/g; # Kl. g mit Circumflexe
    $content=~s/\x{121}/g/g; # Kl. g mit Punkt oben

    $content=~s/\x{122}/G/g; # Gr. G mit Cedille
    $content=~s/\x{11e}/G/g; # Gr. G mit Breve
    $content=~s/\x{11c}/G/g; # Gr. G mit Circumflexe
    $content=~s/\x{120}/G/g; # Gr. G mit Punkt oben

    $content=~s/\x{127}/h/g; # Kl. h mit Ueberstrich
    $content=~s/\x{126}/H/g; # Gr. H mit Ueberstrich

    $content=~s/\x{137}/k/g; # Kl. k mit Cedille
    $content=~s/\x{136}/K/g; # Gr. K mit Cedille

    $content=~s/\x{13c}/l/g; # Kl. l mit Cedille
    $content=~s/\x{13a}/l/g; # Kl. l mit Acute
    $content=~s/\x{13e}/l/g; # Kl. l mit Caron
    $content=~s/\x{140}/l/g; # Kl. l mit Punkt mittig
    $content=~s/\x{142}/l/g; # Kl. l mit Querstrich

    $content=~s/\x{13b}/L/g; # Gr. L mit Cedille
    $content=~s/\x{139}/L/g; # Gr. L mit Acute
    $content=~s/\x{13d}/L/g; # Gr. L mit Caron
    $content=~s/\x{13f}/L/g; # Gr. L mit Punkt mittig
    $content=~s/\x{141}/L/g; # Gr. L mit Querstrick

    $content=~s/\u20ac/e/g;   # Euro-Zeichen
    $content=~s/\x{152}/oe/g;  # OE-Ligatur
    $content=~s/\x{153}/oe/g;  # oe-Ligatur
    $content=~s/Æ/ae/g;       # AE-Ligatur
    $content=~s/æ/ae/g;       # ae-Ligatur
    $content=~s/\x{160}/s/g;   # S hacek
    $content=~s/\x{161}/s/g;   # s hacek
    $content=~s/\x{17d}/z/g;   # Z hacek
    $content=~s/\x{17e}/z/g;   # z hacek
    $content=~s/\x{178}/y/g;   # Y Umlaut
    $content=~s/¡/i/g;        # i Ueberstrich
    $content=~s/¢/c/g;        # Cent
    $content=~s/£/l/g;        # Pfund
    $content=~s/¥/y/g;        # Yen
    $content=~s/µ/u/g;        # Mikro
    
    $content=~s/Ð/e/g;        # Gr. Islaend. E (durchgestrichenes D)
    $content=~s/\x{111}/e/g;   # Kl. Islaend. e ? (durchgestrichenes d)

    $content=~s/Ý/y/g;
    $content=~s/ý/y/g;
    $content=~s/Þ/th/g;       # Gr. Thorn
    $content=~s/þ/th/g;       # kl. Thorn
    $content=~s/ð/d/g;      # eth

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

    push @servertab, $config->get_active_loadbalancertargets;

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
        my $request  = new HTTP::Request GET => "http://$targethost$config->{base_loc}/$view/$config->{handler}{serverload_loc}{name}";
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
    foreach my $category (qw/T0100 T0101/){
        next if (!exists $normset_ref->{$category});
        foreach my $part_ref (@{$normset_ref->{$category}}){
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
    foreach my $category (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $normset_ref->{$category});
        foreach my $part_ref (@{$normset_ref->{$category}}){
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
    my $normdata_ref  = exists $arg_ref->{normdata}
        ? $arg_ref->{normdata}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return "" unless (defined $normdata_ref);
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $category (qw/T0100 T0101/){
        next if (!exists $normdata_ref->{$category});
        foreach my $part_ref (@{$normdata_ref->{$category}}){
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
    $author    = "[".join(",", sort(@$persons_ref))."]" if (@$persons_ref);

    # Titel
    my $title  = (exists $normdata_ref->{T0331})?lc($normdata_ref->{T0331}[0]{content}):"";
    $title     =~ s/[^0-9\p{L}\x{C4}]+//g if ($title);

    # Jahr
    my $year   = (exists $normdata_ref->{T0425})?$normdata_ref->{T0425}[0]{content}:undef;
    $year      =~ s/[^0-9]+//g if ($year);

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
    my $normdata_ref  = exists $arg_ref->{normdata}
        ? $arg_ref->{normdata}             : undef;

    my $bibkey_base   = exists $arg_ref->{bibkey_base}
        ? $arg_ref->{bibkey_base}          : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($normdata_ref){
        $bibkey_base = OpenBib::Common::Util::gen_bibkey_base({normdata => $normdata_ref});
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
    
    $thisisbn = OpenBib::Common::Util::grundform({
        category => '0540',
        content  => $thisisbn,
    });

    return $thisisbn;
}

sub to_issn {
    my ($thisissn) = @_;

    return undef unless (defined $thisissn);
    
    $thisissn = OpenBib::Common::Util::grundform({
        category => '0543',
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

    if ($profile && -e "$config->{tt_include_path}/profile/$profile") {

        # Database-Template ist spezifischer als View-Template und geht vor
        if ($database && -e "$config->{tt_include_path}/profile/$profile/database/$database/$templatename") {
            $templatename="profile/$profile/database/$database/$templatename";
        }
        elsif ($view && -e "$config->{tt_include_path}/profile/$profile/views/$view/$templatename") {
            $templatename="profile/$profile/views/$view/$templatename";
        }
        elsif ($view && -e "$config->{tt_include_path}/profile/$profile/$templatename") {
            $templatename="profile/$profile/$templatename";
        }
        # Database-Template ist spezifischer als View-Template und geht vor
        elsif ($database && -e "$config->{tt_include_path}/database/$database/$templatename") {
            $templatename="database/$database/$templatename";
        }                
        elsif ($view && -e "$config->{tt_include_path}/views/$view/$templatename") {
            $templatename="views/$view/$templatename";
        }
        
    }
    else {
        # Database-Template ist spezifischer als View-Template und geht vor
        if ($database && -e "$config->{tt_include_path}/database/$database/$templatename") {
            $templatename="database/$database/$templatename";
        }
        elsif ($view && -e "$config->{tt_include_path}/views/$view/$templatename") {
            $templatename="views/$view/$templatename";
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

 my $nomalized_content = OpenBib::Common::Util::grundform({ content => $content, $category => $category, searchreq => $searchreq, tagging => $tagging});

 my $server_to_use = OpenBib::Common::Util::get_loadbalanced_servername;

 my $bibtex_entry = OpenBib::Common::Util::normset2bibtex($normset_ref,$utf8);

 my $bibkey = OpenBib::Common::Util::gen_bibkey({ normdata => $normdata_ref});

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

=item grundform({ content => $content, $category => $category, searchreq => $searchreq, tagging => $tagging})

Allgemeine Normierung des Inhaltes $content oder in Abhängigkeit von
der Kategorie $category, bei einer Suchanfrage ($searchreq=1)
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

=item gen_bibkey_base({ normdata => $normdata_ref })

Generiere die Basiszeichenkette aus den bibliographischen Daten für
die Bildung des BibKeys. Dies ist eine Hilfsfunktion für gen_bibkey

=item gen_bibkey({ normdata => $normdata_ref, bibkey_base => $bibkey_base})

Erzeuge einen BibKey entweder aus den bibliographischen Daten
$normdata_ref oder aus einer schon generierten Basis-Zeichenkette
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

=item print_info($info,$r,$msg)

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
