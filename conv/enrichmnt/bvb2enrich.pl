#!/usr/bin/perl

#####################################################################
#
#  bvb2enrich.pl
#
#  Extrahierung von Informationen aus den BVB Open Data Dumps
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2013-2024 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;
use utf8;

use YAML;


use Business::ISBN;
use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use XML::Twig::XPath;
use XML::Simple;
use JSON::XS;

use OpenBib::Common::Util;
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;

my ($help,$initrvk,$initddc,$initsubjects,$inittocurls,$initlang,$jsonimportfile,$jsonsuffix,$inputfile,$logfile,$loglevel);

&GetOptions("help"              => \$help,

            "init-rvk"          => \$initrvk,
            "init-ddc"          => \$initddc,
            "init-subjects"     => \$initsubjects,
            "init-tocurls"      => \$inittocurls,
            "init-lang"         => \$initlang,
            "init-topics"       => \$inittopics,
	    
            "inputfile=s"       => \$inputfile,
            "json-importfile=s" => \$jsonimportfile,
            "json-suffix=s"     => \$jsonsuffix,
            "logfile=s"         => \$logfile,
            "loglevel=s"        => \$loglevel,
	    );

if ($help){
   print_help();
}

$logfile=($logfile)?$logfile:"/var/log/openbib/bvb-enrichmnt.log";
$loglevel=($loglevel)?$loglevel:"INFO";

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

my $enrichment = new OpenBib::Enrichment;

my $origin = 24;

$logger->debug("Origin: $origin");

my $twig= XML::Twig::XPath->new(
   TwigHandlers => {
     "marc:collection/marc:record" => \&parse_record
   }
 );

if ($initrvk){
    $logger->info("Loeschen RVKs");
    $enrichment->init_enriched_content({ field => '4101', origin => $origin });
}

if ($initddc){
    $logger->info("Loeschen Topics");
    $enrichment->init_enriched_content({ field => '4102', origin => $origin });
}

if ($initddc){
    $logger->info("Loeschen DDCs");
    $enrichment->init_enriched_content({ field => '4103', origin => $origin });
}
    
if ($inittocurls){
    $logger->info("Loeschen TocURLs");
    $enrichment->init_enriched_content({ field => '4110', origin => $origin });
}
    
if ($initsubjects){
    $logger->info("Loeschen Schlagworte");
    $enrichment->init_enriched_content({ field => '4300', origin => $origin });
}
    
if ($initlang){
    $logger->info("Loeschen Sprachen");
    $enrichment->init_enriched_content({ field => '4301', origin => $origin });
}

our $count=1;

our $tuple_count = 0;

our $enrich_data_by_isbn_ref   = [];

if ($jsonimportfile){
    if (! -e $jsonimportfile){
        $logger->error("JSON-Einladedatei $jsonimportfile existiert nicht");
        exit;
    }
    open(JSON,$jsonimportfile);
    
    $logger->info("Einlesen und -laden der neuen Daten");

    while (<JSON>){
        my $item_ref = decode_json($_);

        push @{$enrich_data_by_isbn_ref}, $item_ref if (defined $item_ref->{isbn});

        $tuple_count++;
        
        if ($count % 10000 == 0){
	    $logger->info("$count records done");
            $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
            $enrich_data_by_isbn_ref   = [];
        }
        $count++;
    }

    $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
    
    $logger->info("$tuple_count Tupel eingefuegt");

    if ($jsonimportfile){
        close(JSON);
    }
    
}
else {
    if (! -e $inputfile){
	$logger->error("Eingabedatei $inputfile existiert nicht");
	exit;
    }
    
    if ($jsonsuffix){
        open(JSONTOCS    ,">tocurls-${jsonsuffix}.json");
	open(JSONSUBJECTS,">subjects-${jsonsuffix}.json");
	open(JSONRVK     ,">rvk-${jsonsuffix}.json");
	open(JSONDDC     ,">ddc-${jsonsuffix}.json");
	open(JSONLANG    ,">lang-${jsonsuffix}.json");
    }
    else {
	$logger->error("Suffix fuer Ausgabedateien fehlt");
	exit;
    }

    $logger->info("Einlesen der neuen Daten");
    
    $twig->safe_parsefile($inputfile);
    
    $logger->info("$count done");
    
    $logger->info("$tuple_count Tupel eingefuegt");

    if ($jsonsuffix){
        close(JSONTOCS);
	close(JSONSUBJECTS);
	close(JSONRVK);
	close(JSONDDC);
	close(JSONLANG);
    }

}

sub print_help {
    print << "ENDHELP";
bvb2enrich.pl - Anreicherung mit Informationen aus den offenen Daten des BVB

   Optionen:
   -help                 : Diese Informationsseite

   -init                 : Zuerst Eintraege fuer dieses Feld und Origin aus Anreicherungsdatenbank loeschen

   --inputfile=...       : Name der BVB-Datei im MARC-XML-Format
   --json-importfile=... : Name der JSON-Einlade-Datei
   --json-suffix=...     : Suffix der JSON-Ausgabe-Dateien

   --logfile=...         : Name der Log-Datei
   --loglevel=...        : Loglevel (default: INFO)

ENDHELP
    exit;
}

sub parse_record {
    my($t, $titset)= @_;

    my $logger = get_logger();

    $logger->debug("Processing record");
    
    my @isbns = ();
    
    {
	my @elements = $titset->findnodes('//marc:datafield[@tag="020"]/marc:subfield[@code="a"]');

	foreach my $element (@elements){
	    
	    my $isbn = $element->text();

	    $isbn=~s/\s+\(.+?\)\s*$//;
	    
	    if ($isbn){
		my $isbn = $isbn;
		my $isbnXX = Business::ISBN->new($isbn);
		
		if (defined $isbnXX && $isbnXX->is_valid){
		    $isbn = $isbnXX->as_isbn13->as_string;
		}
		else {
		    $logger->error("$isbn NOT valid!");
		    next;
		}
		
		$isbn = OpenBib::Common::Util::normalize({
		    field    => 'T0540',
		    content  => $isbn,
							 });
		
		push @isbns, $isbn;
	    }
	}
    }       
    my %seen_terms  = ();
    my @unique_isbns    = grep { ! $seen_terms{$_} ++ } @isbns;

    if ($logger->is_debug()){
	$logger->debug("ISBNs: ".join(";",@unique_isbns));
    }
    
    # RVK
    my @rvks = ();
    {
	$logger->debug("Processing RVK");

	# RVKs
	my @elements = $titset->findnodes('//marc:datafield[@tag="084"]');
	
	foreach my $element (@elements){	    

	    my $rvk  = $element->findvalue('marc:subfield[@code="a"]');
	    my $desc = $element->findvalue('marc:subfield[@code="2"]');;

	    next unless ($desc=~/rvk/);

	    $logger->debug("RVK: $rvk - Desc: $desc");

	    push @rvks, {
		content  => $rvk,
		subfield => 'a'
	    } if ($rvk);
	}
    }
    %seen_terms  = ();
    my @unique_rvks = grep { ! $seen_terms{$_->{content}} ++ } @rvks; 

    if ($logger->is_debug()){
	$logger->debug("RVK: ".YAML::Dump(@unique_rvks));
    }

    # DDC
    my @ddcs = ();
    {        
	$logger->debug("Processing DDC");

	# DDCs
	my @elements = $titset->findnodes('//marc:datafield[@tag="082"]');
	
	foreach my $element (@elements){	    

	    my $ddc  = $element->findvalue('marc:subfield[@code="a"]');

	    $logger->debug("DDC: $ddc");

	    push @ddcs, {
		content  => $ddc,
		subfield => 'a'
	    } if ($ddc);
	}
    }
    %seen_terms  = ();
    my @unique_ddcs = grep { ! $seen_terms{$_->{content}} ++ } @ddcs; 

    if ($logger->is_debug()){
	$logger->debug("DDC: ".YAML::Dump(@unique_ddcs));
    }
    
    # Tocurls
    my @tocurls = ();
    {        
	$logger->debug("Processing TOC");

	# Tocs
	my @elements = $titset->findnodes('//marc:datafield[@tag="856"]');
	
	foreach my $element (@elements){	    

	    my $url  = $element->findvalue('marc:subfield[@code="u"]');
	    my $desc = $element->findvalue('marc:subfield[@code="3"]');;

	    next unless ($desc=~/Inhaltsverzeichnis/);

	    $logger->debug("TocURL: $url - Desc: $desc");

	    push @tocurls, {
		content  => $url,
		subfield => 'u'
	    } if ($url);


	}
    }
    %seen_terms  = ();
    my @unique_tocurls = grep { ! $seen_terms{$_->{content}} ++ } @tocurls; 

    if ($logger->is_debug()){
	$logger->debug("TOC: ".YAML::Dump(@unique_tocurls));
    }

    # Subjects
    my @subjects = ();
    {        
	$logger->debug("Processing subjects");

	# Schlagwort
	my @elements = $titset->findnodes('//marc:datafield[@tag="650" or @tag="651"]/marc:subfield[@code="a" or @code="x" or @code="y" or @code="z"]');
	
	foreach my $element (@elements){
	    
	    my $subject = $element->text();
	    my $code    = $element->att("code");

	    $logger->debug("SW: $subject - Code: $code");
	    push @subjects, {
		content  => konv($subject),
		subfield => $code
	    } if ($subject);
	}
    }
    %seen_terms  = ();
    my @unique_subjects = grep { ! $seen_terms{$_->{content}} ++ } @subjects; 

    if ($logger->is_debug()){
	$logger->debug("Subject: ".YAML::Dump(@unique_subjects));
    }
    
    # Sprachen
    my @langs = ();
    {        
	$logger->debug("Processing languages");

	# Sprachen
	my @elements = $titset->findnodes('//marc:datafield[@tag="041"]/marc:subfield[@code="a" or @code="b" or @code="g"]');
	
	foreach my $element (@elements){	    
	    my $lang_full = $element->text();
	    my $code      = $element->att("code");
	    
	    $logger->debug("Lang: $lang_full - Code: $code");

	    foreach my $lang (split /\s+/, $lang_full){
		push @langs, {
		    content  => $lang,
		    subfield => $code
		} if ($lang);
	    }
	}
    }
    %seen_terms  = ();
    my @unique_langs = grep { ! $seen_terms{$_->{content}} ++ } @langs; 

    if ($logger->is_debug()){
	$logger->debug("Lang: ".YAML::Dump(@unique_langs));
    }
    
    foreach my $isbn (@unique_isbns){
	# RVKs
	{
	    foreach my $rvk (@unique_rvks){
		$logger->debug("Found $isbn -> $rvk->{content}");
		my $rvk_ref = {
		    isbn     => $isbn,
		    origin   => $origin,
		    field    => '4101',
		    subfield => $rvk->{subfield},
		    content  => $rvk->{content},
		};
		
		print JSONRVK encode_json($rvk_ref),"\n";
	    }
	}

	# DDCs
	{
	    foreach my $ddc (@unique_ddcs){
		$logger->debug("Found $isbn -> $ddc->{content}");
		my $ddc_ref = {
		    isbn     => $isbn,
		    origin   => $origin,
		    field    => '4103',
		    subfield => $ddc->{subfield},
		    content  => $ddc->{content},
		};
		
		print JSONDDC encode_json($ddc_ref),"\n";
	    }
	}
	
	# Tocurls
	{
	    foreach my $tocurl (@tocurls){
		$logger->debug("Found $isbn -> $tocurl->{content}");
		my $tocurl_ref = {
		    isbn     => $isbn,
		    origin   => $origin,
		    field    => '4110',
		    subfield => $tocurl->{subfield},
		    content  => $tocurl->{content},
		};
		
		print JSONTOCS encode_json($tocurl_ref),"\n";
	    }
	}
	
	# Subjects
	{
	    foreach my $subject (@unique_subjects){
		$logger->debug("Found $isbn -> $subject->{content}");
		my $item_ref = {
		    isbn     => $isbn,
		    origin   => $origin,
		    field    => '4300',
		    subfield => $subject->{subfield},
		    content  => $subject->{content},
		};
		
		print JSONSUBJECTS encode_json($item_ref),"\n";
	    }
	}

	# Sprachen
	{
	    foreach my $lang (@unique_langs){
		$logger->debug("Found $isbn -> $lang->{content}");
		my $item_ref = {
		    isbn     => $isbn,
		    origin   => $origin,
		    field    => '4300',
		    subfield => $lang->{subfield},
		    content  => $lang->{content},
		};
		
		print JSONLANG encode_json($item_ref),"\n";
	    }
	}
	
	$tuple_count++;
    }
    
    if ($count % 1000 == 0){
	$logger->info("$count done");
    }
    $count++;
    
    # Release memory of processed tree
    # up to here
    $t->purge();

}

sub konv {
    my $content = shift;

    $content=~s/\s*[.,:]\s*$//g;
    $content=~s/&/&amp;/g;
    $content=~s/</&lt;/g;
    $content=~s/>/&gt;/g;
    # Buchstabenersetzungen Grundbuchstabe plus Diaeresis
    $content=~s/u\x{0308}/ü/g;
    $content=~s/a\x{0308}/ä/g;
    $content=~s/o\x{0308}/ö/g;
    $content=~s/U\x{0308}/Ü/g;
    $content=~s/A\x{0308}/Ä/g;
    $content=~s/O\x{0308}/Ö/g;

    return $content;
}
