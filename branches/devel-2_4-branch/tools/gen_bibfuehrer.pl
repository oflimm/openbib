#!/usr/bin/perl

#####################################################################
#
#  gen_bibfuehrer.pl
#
#  Aufbau eines elektronischen Bibliotheksfuehrers im pdf-Format
#  aus den Informationen in der OpenBib Config-Datenbank
#
#  Dieses File ist (C) 2010 Oliver Flimm <flimm@openbib.org>
#
#  Diese Datei ist abgeleitet aus der Datei gen_zsstlist.pl
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

#####################################################################
# Einladen der benoetigten Perl-Module 
#####################################################################

use utf8;

use Getopt::Long;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Template::Provider;
use OpenBib::L10N;
use LWP::Simple;

use DBI;
use Encode qw/decode_utf8 encode decode/;
use Log::Log4perl qw(get_logger :levels);
use Template;
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$mode,$lang,$logfile);

&GetOptions(
	    "help"      => \$help,
	    "mode=s"    => \$mode,
            "lang=s"    => \$lang,
            "logfile=s" => \$logfile,            
	    );

if ($help){
    print_help();
}

if (!$mode){
  $mode="tex";
}


if ($mode ne "tex" && $mode ne "pdf"){
  print "Mode muss enweder tex oder pdf sein.\n";
  exit;
}

$lang = ($lang)?$lang:"de";

$logfile=($logfile)?$logfile:'/var/log/openbib/gen_bibfuehrer.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

# Message Katalog laden
my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
$msg->fail_with( \&OpenBib::L10N::failure_handler );

my $config      = OpenBib::Config->instance;
my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

foreach my $database (keys %{$dbinfotable->{use_libinfo}}){
    my $libinfo = $config->get_libinfo($database);
    my $coordinates = $libinfo->{"I1000"}->[0]->{content};
    my ($lat,$long) = split("\\s*,\\s*",$coordinates);

    $coordinates=~s/\s*,\s*/-/g;
    $coordinates=~s/\./_/g;
    
    my $filename="${coordinates}_map.png";
    
    if ($lat && $long && ! -e $filename){
        # URL fuer dne StaticMap-Dienst des OpenStreetMap-Projektes
        my $url = "http://ojw.dev.openstreetmap.org/StaticMap/?lat=$lat&lon=$long&z=15&h=500&mlat0=$lat&mlon0=$long&show=1";

        $logger->info("Hole OSM-Karte via $url");
                
        my $image = get($url);

        open(IMAGE,">$filename");
        print IMAGE $image;
        close(IMAGE);
    }
}

my $outputbasename="bibliotheksfuehrer";

my $template = Template->new({
    LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
    }) ],
    OUTPUT_PATH   => './',
    OUTPUT        => "$outputbasename.tex",
});


my $ttdata = {
    dbinfo       => $dbinfotable,
    config       => $config,
    filterchars  => \&filterchars,
    msg          => $msg,
};

$template->process("bibfuehrer_tex", $ttdata) || do { 
    print $template->error();
};

if ($mode eq "pdf"){
    system("pdflatex $outputbasename.tex");
    system("pdflatex $outputbasename.tex");
}

sub print_help {
    print "gen-bibfuehrer.pl - Erzeugen des Bibliotheksfuehrers\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n";
    print "  --mode=[pdf|tex]        : Typ des Ausgabedokumentes\n";
    
    exit;
}

sub filterchars {
  my ($content,$chapter)=@_;

  # Log4perl logger erzeugen
  my $logger = get_logger();

  $logger->debug("Vorher: '$content'");

  # URL's sind verlinkt
  $content=~s/>(http:\S+)</>\\url{$1}</g;    
  $content=~s/<a.*?>//g;
  $content=~s/<\/a>//g;
  $content=~s/^\s+//g;
  $content=~s/\s+$//g;
  $content=~s/<br \/>$/ /g;
  $content=~s/<br.*?>/\\newline /g unless ($chapter);
#  $content=~s/ (http:\S+)/ \\url{$1}/g;    
  $content=~s/<.*?>//g;
  $content=~s/\$/\\\$/g;
  $content=~s/\&gt\;/\$>\$/g;
  $content=~s/\&lt\;/\$<\$/g;
  $content=~s/\&\#\d+\;//g;
#  $content=~s/\{/\\\{/g;
#  $content=~s/\}/\\\}/g;
#  $content=~s/#/\\\#/g;

  # Entfernen
  $content=~s/±//g;
  $content=~s/÷//g;
  $content=~s/·//g;
  $content=~s/×//g;
  $content=~s/¾//g;
  $content=~s/¬//g;
  $content=~s/¹//g;
  $content=~s/_//g;
  $content=~s/¸//g;
  $content=~s/þ//g;
  $content=~s/Ð//g;
  $content=~s/\^/\\\^\{\}/g;
  $content=~s/µ/\$µ\$/g;
  $content=~s/\&amp\;/\\&/g;
  $content=~s/\&/\\&/g;
  $content=~s/\"/\'\'/g;
  $content=~s/\%/\\\%/g;
  $content=~s/ð/d/g;      # eth

  $content = encode("utf8",$content);
  $content=~s/\x{c2}\x{a0}//g;
  $content=~s/\x{e2}\x{80}\x{89}//g;
  # Umlaute
  #$content=~s/\&uuml\;/ü/g;
  #$content=~s/\&auml\;/ä/g;
  #$content=~s/\&Auml\;/Ä/g;
  #$content=~s/\&Uuml\;/Ü/g;
  #$content=~s/\&ouml\;/ö/g;
  #$content=~s/\&Ouml\;/Ö/g;
  #$content=~s/\&szlig\;/ß/g;

  # Caron
  #$content=~s/\&#353\;/\\v\{s\}/g; # s hacek
  #$content=~s/\&#352\;/\\v\{S\}/g; # S hacek
  #$content=~s/\&#269\;/\\v\{c\}/g; # c hacek
  #$content=~s/\&#268\;/\\v\{C\}/g; # C hacek
  #$content=~s/\&#271\;/\\v\{d\}/g; # d hacek
  #$content=~s/\&#270\;/\\v\{D\}/g; # D hacek
  #$content=~s/\&#283\;/\\v\{e\}/g; # d hacek
  #$content=~s/\&#282\;/\\v\{E\}/g; # D hacek
  #$content=~s/\&#318\;/\\v\{l\}/g; # l hacek
  #$content=~s/\&#317\;/\\v\{L\}/g; # L hacek
  #$content=~s/\&#328\;/\\v\{n\}/g; # n hacek
  #$content=~s/\&#327\;/\\v\{N\}/g; # N hacek
  #$content=~s/\&#345\;/\\v\{r\}/g; # r hacek
  #$content=~s/\&#344\;/\\v\{R\}/g; # R hacek
  #$content=~s/\&#357\;/\\v\{t\}/g; # t hacek
  #$content=~s/\&#356\;/\\v\{T\}/g; # T hacek
  #$content=~s/\&#382\;/\\v\{z\}/g; # n hacek
  #$content=~s/\&#381\;/\\v\{Z\}/g; # N hacek

  # Macron
  #$content=~s/\&#275\;/\\=\{e\}/g; # e oberstrich
  #$content=~s/\&#274\;/\\=\{E\}/g; # e oberstrich
  #$content=~s/\&#257\;/\\=\{a\}/g; # a oberstrich
  #$content=~s/\&#256\;/\\=\{A\}/g; # A oberstrich
  #$content=~s/\&#299\;/\\=\{i\}/g; # i oberstrich
  #$content=~s/\&#298\;/\\=\{I\}/g; # I oberstrich
  #$content=~s/\&#333\;/\\=\{o\}/g; # o oberstrich
  #$content=~s/\&#332\;/\\=\{O\}/g; # O oberstrich
  #$content=~s/\&#363\;/\\=\{u\}/g; # u oberstrich
  #$content=~s/\&#362\;/\\=\{U\}/g; # U oberstrich

  $logger->debug("Nachher: '$content'");
  
  return $content;
}

# sub by_signature {
#     my %line1=%$a;
#     my %line2=%$b;

#     # Sortierung anhand erster Signatur
#     my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?cleanrl($line1{X0014}[0]{content}):"0";
#     my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?cleanrl($line2{X0014}[0]{content}):"0";

#     $line1 cmp $line2;
# }

sub by_title {
    my %line1=%{$a->get_normdata()};
    my %line2=%{$b->get_normdata()};

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?cleanrl($line2{T0331}[0]{content}):"";

    $line1=OpenBib::Common::Stopwords::strip_first_stopword($line1);
    $line2=OpenBib::Common::Stopwords::strip_first_stopword($line2);
    
    $line1 cmp $line2;
}

sub cleanrl {
    my ($line)=@_;

    $line=~s/Ü/Ue/g;
    $line=~s/Ä/Ae/g;
    $line=~s/Ö/Oe/g;
    $line=lc($line);
    $line=~s/&(.)uml;/$1e/g;
    $line=~s/^ +//g;
    $line=~s/^¬//g;
    $line=~s/^"//g;
    $line=~s/^'//g;

    return $line;
}
