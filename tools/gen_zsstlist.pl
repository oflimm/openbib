#!/usr/bin/perl

#####################################################################
#
#  gen_zsstlist.pl
#
#  Extrahieren der Zeitschriftenliste eines Instituts
#
#  Dieses File ist (C) 2006-2024 Oliver Flimm <flimm@openbib.org>
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
use Log::Log4perl qw(get_logger :levels);
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Config::LocationInfoTable;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Template::Provider;
use OpenBib::Catalog::Subset;

use DBI;
use Encode qw/decode_utf8 encode decode/;
use Template;
use Text::CSV_XS;
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$sigel,$showall,$mode,$enrichnatfile,$bibsort,$marksort,$logfile,$loglevel);

&GetOptions(
	    "help"     => \$help,
	    "sigel=s"  => \$sigel,
	    "mode=s"   => \$mode,
	    "showall"  => \$showall,
            "bibsort"  => \$bibsort,
            "marksort" => \$marksort,
            "logfile=s"  => \$logfile,
            "loglevel=s" => \$loglevel,
            "enrichnatfile=s" => \$enrichnatfile,
	    );

if ($help){
    print_help();
}

if (!$mode){
  $mode="tex";
}

$logfile=($logfile)?$logfile:'/var/log/openbib/gen_zsstlist.log';
$loglevel=($loglevel)?$loglevel:'INFO';

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

print "Generating $sigel\n";

if ($mode ne "tex" && $mode ne "pdf"){
  $logger->error("Mode muss enweder tex oder pdf sein.");
  exit;
}

my $issn_nationallizenzen_ref = {};

if ($enrichnatfile){
    my $csv_options = {
#	'diag_verbose' => 1,
	    'auto_diag' => 1,
	    'allow_loose_quotes' => 1,
	    'allow_loose_escapes' => 1,
	    'allow_unquoted_escape' => 1,
	    'eol' => "\n", 
	    'sep_char' => "\t", 
	    'quote_char' =>  '', #"\"", 
	    'escape_char' => '', #"\"", 
	    
    }; 
    
    open my $in,   "<:utf8",$enrichnatfile; 
    
    our $csv = Text::CSV_XS->new($csv_options); 
    
    my @cols = @{$csv->getline ($in)}; 
    our $row = {}; 

    $csv->bind_columns (\@{$row}{@cols}); 
    
    while (safe_getline($in)){ 
        my @issns = (); 
        
        foreach my $issn (split /\s*;\s*/, $row->{'E-ISSN'}){ 
            push @issns, $issn; 
        } 
        
        foreach my $issn (split /\s*;\s*/, $row->{'P-ISSN'}){ 
            push @issns, $issn; 
        } 
        
        my $erstes_jahr   = $row->{'Erstes Jahr'}; 
        my $erstes_volume = $row->{'Erster Jahrgang'}; 
        my $erstes_issue  = $row->{'Erstes Heft'}; 
        
        my $letztes_jahr   = $row->{'Letztes Jahr'}; 
        my $letztes_volume = $row->{'Letzter Jahrgang'}; 
        my $letztes_issue  = $row->{'Letztes Heft'}; 
        
        my $moving_wall  = $row->{'Moving Wall'}; 
        
        my $bestandsverlauf = "$erstes_jahr";

        if ($erstes_jahr){
            if ($erstes_volume){ 
                $bestandsverlauf="$erstes_volume.$bestandsverlauf"; 
            }
            elsif ($erstes_issue){
                $bestandsverlauf="$erstes_issue.$bestandsverlauf"; 
            }
        }
        else {
            if ($erstes_volume){ 
                $bestandsverlauf="$erstes_volume"; 
            }
            elsif ($erstes_issue){
                $bestandsverlauf="$erstes_issue"; 
            }
        }
        
        if ($moving_wall){ 
            $bestandsverlauf = "$bestandsverlauf - Moving Wall: $moving_wall"; 
        }
        else {
            if ($letztes_jahr){
                if ($letztes_volume){
                    $letztes_jahr="$letztes_volume.$letztes_jahr"; 
                }
                elsif ($letzes_issue){
                    $letztes_jahr="$letztes_issue.$letztes_jahr"; 
                }
                
                $bestandsverlauf="$bestandsverlauf - $letztes_jahr"; 
            }
            else {
                if ($letztes_volume){
                    $letztes_jahr="$letzes_volume.$letztes_jahr"; 
                }
                elsif ($letzes_issue){
                    $letztes_jahr="$letztes_issue.$letztes_jahr"; 
                }
                
                $bestandsverlauf="$bestandsverlauf - $letztes_jahr"; 
            }
        } 

        my $verfuegbar  = $row->{'Available'};
	$logger->debug("Verfuegbarkeit: $verfuegbar");
	$logger->debug("ISSNs: ".join(',',@issns));
	$logger->debug("Bestandsverlauf: $bestandsverlauf");

        if ($verfuegbar =~/National/){	    
	    foreach my $issn (@issns){ 
		$issn_nationallizenzen_ref->{$issn} = $bestandsverlauf; 
	    }
	}
    }
}

if ($logger->is_debug){
    $logger->debug("Bestandsverlaeufe zu ISSNs aus Nationallizenzen". YAML::Dump($issn_nationallizenzen_ref));
}

my $config       = OpenBib::Config->new;
my $dbinfotable  = OpenBib::Config::DatabaseInfoTable->new;
my $locinfotable = OpenBib::Config::LocationInfoTable->new;

my $subset = new OpenBib::Catalog::Subset("uzkzeitschriften","who_cares");
$subset->identify_by_field_content('holding',[{ field => 3330, content => $sigel }]);

my %titleids = %{$subset->get_titleid};

my $externzahl=0;
my $natlizzahl=0;

my @recordlist = ();

foreach $titleid (keys %titleids){
    my $record = new OpenBib::Record::Title({database => 'uzkzeitschriften', id => $titleid, config => $config})->load_full_record();

    my $sortfield = "";

    my $fields_ref          = $record->get_fields;
    my $abstract_fields_ref = $record->to_abstract_fields;
    
    my $urheber = $abstract_fields_ref->{corp};
    
    $urheber = (defined $urheber)?$urheber->[0]:"";
    
    my $ast = "";
    
    if (defined $fields_ref->{'T0246'}){
	foreach my $item_ref (@{$fields_ref->{'T0246'}}){
	    if ($item_ref->{ind} =~m/9$/ && $item_ref->{subfield} eq "a"){
		$ast = $item_ref->{content};
		last;
	    }
	}
    }
    
    if ($ast){
        $ast = OpenBib::Common::Stopwords::strip_first_stopword($ast);
        $sortfield = "$urheber$ast";
    }
    else {
        my $hst = $abstract_fields_ref->{title} || "";
        
        $hst = OpenBib::Common::Stopwords::strip_first_stopword($hst);
        $sortfield = "$urheber$hst";
    }

    $record->set_field({ field => 'sortfield', content => $sortfield});
    
    my $mexnormdata_ref = $record->get_holding;

    # print YAML::Dump($record);
    # Titel auch in anderen Bibliotheken?

    my $is_extern=0;

    my $nat_bestandsverlauf = "";

    my $is_natlizenz=0;
    # Nationallizenzen anreichern?
    if ($enrichnatfile){
        my $issns_ref = $record->get_field({ field => 'T0022', subfield => 'a'});

        foreach my $issn_ref (@$issns_ref){
        
            if (!$is_natlizenz && defined $issn_nationallizenzen_ref->{$issn_ref->{content}}){
                $nat_bestandsverlauf = $issn_nationallizenzen_ref->{$issn_ref->{content}};

                $logger->debug("Angereichert: $issn_ref->{content} - $nat_bestandsverlauf");

                push @$mexnormdata_ref, {
                    'X3330' => { 'content' => 'Nationallizenzen' },
                    #                 'X0016' => [
                    #                     { 'content' => 'Nationallizenzen' },
                    #                 ],
                    #                 'X3330' => [
                    #                     { 'content' => 'nationallizenzen' },
                    #                 ],
                    'X1204' => { 'content' => $nat_bestandsverlauf },
                };
                $is_natlizenz = 1;
            }
            
        }
        $record->set_holding($mexnormdata_ref);
    }
    foreach my $mexitem_ref (@$mexnormdata_ref){
        if (exists $mexitem_ref->{X3330}){
            my $thissigel=$mexitem_ref->{X3330}{content};
            
            if ($thissigel ne $sigel){
                $is_extern=1;
            }
        }
    }

    if ($is_extern == 1){
        $externzahl++;
    }
    
    if ($is_natlizenz == 1){
        $natlizzahl++;
    }
    
    push @recordlist, $record;
}

# Sortierung

my @sortedrecordlist = sort by_title @recordlist;

my $outputbasename="zeitschriften-$sigel";

if ($showall){
    $outputbasename.="-all";
}

# Sortierung nach Titel
my $template = Template->new({
    LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
    }) ],
    #        INCLUDE_PATH   => $config->{tt_include_path},
    #        ABSOLUTE       => 1,
    OUTPUT_PATH   => '/var/www/zeitschriftenlisten',
    OUTPUT        => "$outputbasename.$mode",
});


my $ttdata = {
    sigel        => $sigel,
    dbinfo       => $dbinfotable,
    locinfo      => $locinfotable,
    recordlist   => \@sortedrecordlist,
    showall      => $showall,
    gesamtzahl   => $#recordlist+1,
    externzahl   => $externzahl,
    natlizzahl   => $natlizzahl,

    filterchars  => \&filterchars,
};

$template->process("zsstlist_$mode", $ttdata) || do { 
    print $template->error();
};


if ($bibsort){
    # Sortierung nach Urheber, dann Titel
    
    @sortedrecordlist = sort by_sortfield @recordlist;
    
    $outputbasename.="-bibsort";
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        INCLUDE_PATH   => $config->{tt_include_path},
        #        ABSOLUTE       => 1,
        OUTPUT_PATH   => '/var/www/zeitschriftenlisten',
        OUTPUT        => "$outputbasename.$mode",
    });
    
    
    my $ttdata = {
        bibsort      => 1,
        sigel        => $sigel,
        dbinfo       => $dbinfotable,
        recordlist   => \@sortedrecordlist,
        showall      => $showall,
        gesamtzahl   => $#recordlist+1,
        externzahl   => $externzahl,
        natlizzahl   => $natlizzahl,
        
        filterchars  => \&filterchars,
    };
    
    $template->process("zsstlist_$mode", $ttdata) || do { 
        print $template->error();
    };
}

if ($marksort){
    # Sortierung nach Signatur
    
    @sortedrecordlist = sort by_mark @recordlist;
    
    $outputbasename.="-marksort";
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        INCLUDE_PATH   => $config->{tt_include_path},
        #        ABSOLUTE       => 1,
        OUTPUT_PATH   => '/var/www/zeitschriftenlisten',
        OUTPUT        => "$outputbasename.$mode",
    });
    
    
    my $ttdata = {
        bibsort      => 1,
        sigel        => $sigel,
        dbinfo       => $dbinfotable,
        recordlist   => \@sortedrecordlist,
        showall      => $showall,
        gesamtzahl   => $#recordlist+1,
        externzahl   => $externzahl,
        natlizzahl   => $natlizzahl,
        
        filterchars  => \&filterchars,
    };
    
    $template->process("zsstlist_$mode", $ttdata) || do { 
        print $template->error();
    };
}


sub print_help {
    print "gen-zsstlist.pl - Erzeugen von Zeitschiftenlisten pro Sigel\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n";
    print "  --sigel=514             : Sigel der Bibliothek\n";
    print "  --mode=[pdf|tex]        : Typ des Ausgabedokumentes\n";
    print "  -showall                : Alle Sigel/Eigentümer anzeigen\n";
    print "  -bibsort                : Zusätzliche bibliothakar. Sortierung\n";
    print "  -marksort               : Zusätzliche Sortierung nach Signatur\n\n";
    
    exit;
}

sub filterchars {
  my ($content)=@_;

  $content=~s/<br.*?>/ /g;

  $content=~s/\$/\\\$/g;
  $content=~s/\&gt\;/\$>\$/g;
  $content=~s/\&lt\;/\$<\$/g;
  $content=~s/\{/\\\{/g;
  $content=~s/\}/\\\}/g;
  $content=~s/#/\\\#/g;

  # Entfernen
  $content=~s/đ//g;
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
  $content=~s/\"/\'\'/g;
  $content=~s/\%/\\\%/g;
  $content=~s/ð/d/g;      # eth

  $content=~s/\x{02b9}/\'/g;      #
  $content=~s/\x{2019}/\'/g;      #
  $content=~s/\x{02ba}/\'\'/g;      #
  $content=~s/\x{201d}/\'\'/g;      #
  $content=~s/\x{02bb}//g;      #
  $content=~s/\x{02bc}//g;      #
  $content=~s/\x{0332}//g;      #
  $content=~s/\x{02b9}//g;      #

  $content = encode("utf8",$content);

  $content=~s/\x{cc}\x{8a}//g;  
  $content=~s/\x{cc}\x{81}//g;
  $content=~s/\x{cc}\x{82}//g;
  $content=~s/\x{cc}\x{84}//g;
  $content=~s/\x{cc}\x{85}//g;
  $content=~s/\x{cc}\x{86}//g;
  $content=~s/\x{cc}\x{87}//g;  
  $content=~s/\x{cc}\x{88}/l/g;
  $content=~s/\x{cc}\x{a7}//g;
  $content=~s/\x{c4}\x{99}/e/g;
  $content=~s/\x{c4}\x{90}/D/g;
  $content=~s/\x{c4}\x{85}/\\c{a}/g;
  $content=~s/\x{c5}\x{b3}/u/g;
  $content=~s/c\x{cc}\x{a8}/\\c{c}/g;

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

  return $content;
}

sub by_mark {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?cleanrl($line1{X0014}[0]{content}):"0";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?cleanrl($line2{X0014}[0]{content}):"0";

    $line1 cmp $line2;
}

sub by_title {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?cleanrl($line2{T0331}[0]{content}):"";

    $line1=OpenBib::Common::Stopwords::strip_first_stopword($line1);
    $line2=OpenBib::Common::Stopwords::strip_first_stopword($line2);
    
    $line1 cmp $line2;
}


sub by_sortfield {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{sortfield}[0]{content} && defined $line1{sortfield}[0]{content})?cleanrl($line1{sortfield}[0]{content}):"";
    my $line2=(exists $line2{sortfield}[0]{content} && defined $line2{sortfield}[0]{content})?cleanrl($line2{sortfield}[0]{content}):"";

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

sub safe_getline {
    my $in = shift;

    eval {
	$csv->getline ($in);
    };
    
}
