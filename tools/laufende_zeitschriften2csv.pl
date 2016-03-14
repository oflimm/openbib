#!/usr/bin/perl

#####################################################################
#
#  laufende_zeitschriften2csv.pl
#
#  Extrahieren der laufenden Zeitschriftenliste eines Instituts
#  und Ausgabe als CSV-Datei
#
#  Dieses File ist (C) 2016 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;

use Getopt::Long;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Record::Title;

use DBI;
use Encode qw/decode_utf8 encode decode/;
use List::MoreUtils qw/ uniq /;
use Text::CSV_XS;
use YAML;
use DBIx::Class::ResultClass::HashRefInflator;

my ($help,$enrichnatfile);

&GetOptions(
	    "help"     => \$help,
            "enrichnatfile=s" => \$enrichnatfile,
	    );

if ($help){
    print_help();
}

my $issn_nationallizenzen_ref = {};

if ($enrichnatfile){
    my $csv_options = { 
        'eol' => "\n", 
        'sep_char' => "\t", 
        'quote_char' =>  "\"", 
        'escape_char' => "\"", 
        
    }; 
    
    open my $in,   "<:utf8",$enrichnatfile; 
    
    my $csv = Text::CSV_XS->new($csv_options); 
    
    my @cols = @{$csv->getline ($in)}; 
    my $row = {}; 

    $csv->bind_columns (\@{$row}{@cols}); 
    
    while ($csv->getline ($in)){ 
        my @issns = (); 
        
        foreach my $issn (split /\s*;\s*/, $row->{'E-ISSN'}){ 
            push @issns, $issn; 
        } 
        
        foreach my $issn (split /\s*;\s*/, $row->{'P-ISSN'}){ 
            push @issns, $issn; 
        } 
        
        my $erstes_jahr   = $row->{'erstes Jahr'}; 
        my $erstes_volume = $row->{'erstes volume'}; 
        my $erstes_issue  = $row->{'erstes issue'}; 
        
        my $letztes_jahr   = $row->{'letztes Jahr'}; 
        my $letztes_volume = $row->{'letztes volume'}; 
        my $letztes_issue  = $row->{'letztes issue'}; 
        
        my $moving_wall  = $row->{'moving wall'}; 
        
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
                elsif ($letztes_issue){
                    $letztes_jahr="$letztes_issue.$letztes_jahr"; 
                }
                
                $bestandsverlauf="$bestandsverlauf - $letztes_jahr"; 
            }
            else {
                if ($letztes_volume){
                    $letztes_jahr="$letztes_volume.$letztes_jahr"; 
                }
                elsif ($letztes_issue){
                    $letztes_jahr="$letztes_issue.$letztes_jahr"; 
                }
                
                $bestandsverlauf="$bestandsverlauf - $letztes_jahr"; 
            }
        } 
        
        my $verfuegbar  = $row->{'verfuegbar'}; 
        next unless ($verfuegbar eq "Nationallizenz"); 
        
        foreach my $issn (@issns){ 
            $issn_nationallizenzen_ref->{$issn} = $bestandsverlauf; 
        }
    }
}

my $config      = OpenBib::Config->new;
my $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;

my $out;

open $out, ">:encoding(utf8)", "laufende_zeitschriften.csv";

my $outputcsv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});

my $out_ref = [];

push @{$out_ref}, ('id','Bibliothek','Person/Körperschaft','AST','Titel','Zusatz','Auflage','Verlag','ISBN','ISSN','Signatur','Standort','Verlauf');

$outputcsv->print($out,$out_ref);

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => 'instzs'});

my $laufende_zeitschriften = $catalog->get_schema->resultset('Holding')->search(
    {
	'holding_fields.field' => 1204,
	-or => [
	    'holding_fields.content' => { '~' => '- *$' }, 
	    'holding_fields.content' => { '~' => '- \[[^[]\]$' }, 
	    ], 
    },
    {
	select => ['holding_fields.content','title_holdings.titleid','me.id'],
	as     => ['thisverlauf','thistitleid','thisholdingid'],
	join   => ['holding_fields','title_holdings'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',

    }
    
    );

while (my $laufende_zeitschrift = $laufende_zeitschriften->next()){
    my $titleid    = $laufende_zeitschrift->{thistitleid};
    my $holdingid  = $laufende_zeitschrift->{thisholdingid};
    my $verlauf    = cleanup_content($laufende_zeitschrift->{thisverlauf});

#    print STDERR "$titleid / $holdingid -> $verlauf\n";

    $out_ref = [];    

    my $record = OpenBib::Record::Title->new({ id => $titleid, database => 'instzs'})->load_full_record;
    
    my @pers_korp  = ();
    my @ast        = ();
    my @titel      = ();
    my @zusatz     = ();
    my @verlag     = ();
    my @issn       = ();
    my $signatur   = "";
    my $standort   = "";
    my $besitzer   = "";

    my $fields_ref   = $record->get_fields;
    my $holdings_ref = $record->get_holding;

    my $this_holding_ref = {};

#    print YAML::Dump($holdings_ref),"\n";

    foreach my $holding (@$holdings_ref){
	if ($holding->{id} eq $holdingid){
	    $signatur = cleanup_content($holding->{'X0014'}{content});
	    $standort = cleanup_content($holding->{'X0016'}{content});
	    $besitzer = cleanup_content($holding->{'X3330'}{content});
	    last;
	}
    }

    foreach my $item_ref (@{$fields_ref->{T0200}}){
        push @pers_korp, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$fields_ref->{T0201}}){
        push @pers_korp, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$fields_ref->{T0100}}){
        push @pers_korp, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$fields_ref->{T0101}}){
        push @pers_korp, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$fields_ref->{T0310}}){
        push @ast, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$fields_ref->{T0331}}){
        push @titel, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$fields_ref->{T0335}}){
        push @zusatz, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$fields_ref->{T0412}}){
        push @verlag, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$fields_ref->{T0543}}){
        push @issn, cleanup_content($item_ref->{content});
    }

    
    push @{$out_ref}, ($record->get_id,$besitzer,join(' ; ',@pers_korp),join(' ; ',@ast),join(' ; ',@titel),join(' ; ',@zusatz),join(' ; ',@verlag),join(' ; ',uniq @issn),$signatur,$standort,$verlauf);    

    $outputcsv->print($out,$out_ref);

}

close ($out);

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
    my @line1=@{$a->get_holding()};
    my @line2=@{$b->get_holding()};

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1[0]{X0014}{content} && defined $line1[0]{X0014}{content})?cleanrl($line1[0]{X0014}{content}):"";
    my $line2=(exists $line2[0]{X0014}{content} && defined $line2[0]{X0014}{content})?cleanrl($line2[0]{X0014}{content}):"";

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

sub cleanup_content {
    my $content = shift;

    $content=~s/&lt;/</g;
    $content=~s/&gt;/>/g;
    $content=~s/&amp;/&/g;
    return $content;
}
