#!/usr/bin/perl

#####################################################################
#
#  gutenberg2meta.pl
#
#  Konvertierung des Gutenberg RDF-Formates in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2009 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode';
use Getopt::Long;
use XML::LibXML;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
gutenberg2meta.pl - Aufrufsyntax

    gutenberg2meta.pl --inputfile=xxx
HELP
exit;
}

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $parser = XML::LibXML->new();
$parser->keep_blanks(0);

my $tree = $parser->parse_file($inputfile);
my $root = $tree->getDocumentElement;

foreach my $etext_node ($root->findnodes('/rdf:RDF/pgterms:etext')){
    my $etext_number = $etext_node->getAttribute ('rdf:ID');
    $etext_number =~ s/^etext//;
    
    next unless ($etext_number);
    
    print TIT "0000:$etext_number\n";
    
    # Neuaufnahmedatum
    foreach my $item ($etext_node->findnodes ('dc:created//text()')) {
        my ($year,$month,$day)=split("-",$item->textContent);
        print TIT "0002:$day.$month.$year\n";
    }
    
    # Sprache
    foreach my $item ($etext_node->findnodes ('dc:language//text()')) {
        print TIT "0015:".$item->textContent."\n";
    }
    
    # Verfasser, Personen
    # Einzelner Verfasser
    foreach my $item ($etext_node->findnodes ('dc:creator//text()')) {
        my $content = $item->textContent;
        my $autidn  = OpenBib::Conv::Common::Util::get_autidn($content);
        
        if ($autidn > 0){
            print AUT "0000:$autidn\n";
            print AUT "0001:$content\n";
            print AUT "9999:\n";
        }
        else {
            $autidn=(-1)*$autidn;
        }
        
        print TIT "0100:IDN: $autidn\n";
    }
    
    # Verfasser, Personen
    foreach my $item ($etext_node->findnodes ('dc:contributor//text()')) {
        my $content = $item->textContent;
        my $autidn  = OpenBib::Conv::Common::Util::get_autidn($content);
        
        if ($autidn > 0){
            print AUT "0000:$autidn\n";
            print AUT "0001:$content\n";
            print AUT "9999:\n";
        }
        else {
            $autidn=(-1)*$autidn;
        }
        
        print TIT "0101:IDN: $autidn\n";
    }
    
    # Titel
    foreach my $item ($etext_node->findnodes ('dc:title//text()')) {
        my $content = $item->textContent;
        if (my ($hst,$zusatz)=$content=~m/^(.+?)\n(.*)/ms){
            $zusatz=~s/\n/ /msg;
            print TIT "0331:$hst\n";
            print TIT "0335:$zusatz\n";
        }
        else {
            print TIT "0331:$content\n";
        }
        
    }
    
    # Verlag
    print TIT "0412:Project Gutenberg\n";
    
    # E-Text-URL
    print TIT "0662:http://www.gutenberg.org/etext/$etext_number\n";
    
    # Beschreibung
    foreach my $item ($etext_node->findnodes ('dc:description//text()')) {
        my $content = $item->textContent;
        print TIT "0501:$content\n";
    }
    
    # Medientyp
    foreach my $item ($etext_node->findnodes ('dc:type//text()')) {
        my $content = $item->textContent;
        print TIT "0800:$content\n";
    }
    
    # Schlagworte
    foreach my $item ($etext_node->findnodes ('dc:subject/dcterms:LCSH//text()')) {
        my $content = $item->textContent;
        my $swtidn  = OpenBib::Conv::Common::Util::get_swtidn($content);
        
        if ($swtidn > 0){
            print SWT "0000:$swtidn\n";
            print SWT "0001:$content\n";
            print SWT "9999:\n";
        }
        else {
            $swtidn=(-1)*$swtidn;
        }
        
        print TIT "0710:IDN: $swtidn\n";
    }
    
    print TIT "9999:\n";
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}
