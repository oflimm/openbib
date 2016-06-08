#!/usr/bin/perl

#####################################################################
#
#  zeitschriften2csv.pl
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
use Log::Log4perl qw(get_logger :levels);
use Encode qw/decode_utf8 encode decode/;
use JSON::XS;
use List::MoreUtils qw/ uniq /;
use Text::CSV_XS;
use YAML;
use DBIx::Class::ResultClass::HashRefInflator;

my ($help,$logfile,$laufend);

&GetOptions(
    "logfile"  => \$logfile,
    "laufend"  => \$laufend,
    "help"     => \$help,
    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/zeitschriften2csv.log';

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

my $config      = OpenBib::Config->new;
my $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;

my $out;

my $filename = ($laufend)?'uzk-zeitschriften-laufend.csv':'uzk-zeitschriften.csv';

open $out, ">:encoding(utf8)", $filename;

my $outputcsv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});

my $out_ref = [];

push @{$out_ref}, ('ZDB-ID','Bibliothek','Person/Körperschaft','AST','Titel','Zusatz','Verlag','ISSN','Signatur','Standort','Verlauf');

$outputcsv->print($out,$out_ref);

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => 'instzs'});


my $where_ref = {
    'title_holdings.titleid' => \'IS NOT NULL',
};


if ($laufend){
   $where_ref = {
    'title_holdings.titleid' => \'IS NOT NULL',
    'holding_fields.field' => 1204,
    -or => [
	'holding_fields.content' => { '~' => '- *$' }, 
	'holding_fields.content' => { '~' => '- \[[^[]\]$' }, 
	], 
   };
}

my $zeitschriften = $catalog->get_schema->resultset('Holding')->search(
    $where_ref,
    {
	select   => ['title_holdings.titleid','me.id','titleid.titlecache'],
	as       => ['thistitleid','thisholdingid','thistitlecache'],
	prefetch => ['title_holdings'],
	group_by => ['title_holdings.id','title_holdings.titleid','me.id','titleid.titlecache'],
	join     => ['holding_fields','title_holdings', { 'title_holdings' => 'titleid' }],
	result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
    
    );

my $idx = 1;

while (my $zeitschrift = $zeitschriften->next()){
    my $titleid    = $zeitschrift->{thistitleid};
    my $holdingid  = $zeitschrift->{thisholdingid};
    my $titlecache = $zeitschrift->{thistitlecache};

#    next unless ($titleid && $holdingid && $titlecache);

    my $verlauf;

    my $fields_ref ;

    eval {
	$fields_ref = JSON::XS::decode_json $titlecache;
    };

    if ($@){
	$logger->error($@);
	$logger->error("$titleid / $holdingid -> $titlecache");
	next;
    }

    $out_ref = [];    

    my @pers_korp  = ();
    my @ast        = ();
    my @titel      = ();
    my @zusatz     = ();
    my @verlag     = ();
    my @issn       = ();
    my $signatur   = "";
    my $standort   = "";
    my $besitzer   = "";

    foreach my $item_ref (@{$fields_ref->{PC0001}}){
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

    my $holdings = $catalog->get_schema->resultset('HoldingField')->search(
	{
	    'holdingid' => $holdingid,
	},
	{
	    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
	}
	);

    while (my $thisholding = $holdings->next()){
	if ($thisholding->{field} == 16){
	    $standort = $thisholding->{content};
	}
	if ($thisholding->{field} == 14){
	    $signatur = $thisholding->{content};
	}
	if ($thisholding->{field} == 1204){
	    $verlauf = $thisholding->{content};
	}
	if ($thisholding->{field} == 3330){
	    $besitzer = $thisholding->{content};
	    if ($besitzer =~/^\d\d\d$/){
		$besitzer = "38/$besitzer";
	    }
	}
    } 

    next unless ($verlauf);

    push @{$out_ref}, ($titleid,$besitzer,join(' ; ',@pers_korp),join(' ; ',@ast),join(' ; ',@titel),join(' ; ',@zusatz),join(' ; ',@verlag),join(' ; ',uniq @issn),$signatur,$standort,$verlauf);    

    $outputcsv->print($out,$out_ref);

    if ($idx % 1000 == 0){
	$logger->info("$idx Records done");
    }

    $idx++;
}

close ($out);

sub print_help {
    print "gen-zsstlist.pl - Erzeugen von Zeitschiftenlisten pro Sigel\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n\n";
    
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
