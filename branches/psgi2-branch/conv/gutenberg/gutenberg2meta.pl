#!/usr/bin/perl

#####################################################################
#
#  gutenberg2meta.pl
#
#  Konvertierung des Gutenberg RDF-Formates in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2009-2013 Oliver Flimm <flimm@openbib.org>
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
use warnings;
use strict;

use Encode 'decode';
use Getopt::Long;
use XML::LibXML;
use YAML::Syck;
use JSON::XS;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Conv::Common::Util;

my ($inputfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
	    );

if (!$inputfile){
    print << "HELP";
gutenberg2meta.pl - Aufrufsyntax

    gutenberg2meta.pl --inputfile=xxx
HELP
exit;
}

open (TIT,     ">:raw","meta.title");
open (AUT,     ">:raw","meta.person");
open (KOR,     ">:raw","meta.corporatebody");
open (NOTATION,">:raw","meta.classification");
open (SWT,     ">:raw","meta.subject");
open (MEX,     ">:raw","meta.holding");

my $parser = XML::LibXML->new();
$parser->keep_blanks(0);

my $tree = $parser->parse_file($inputfile);
my $root = $tree->getDocumentElement;

my $count=1;
foreach my $etext_node ($root->findnodes('/rdf:RDF/pgterms:etext')){
    my $etext_number = $etext_node->getAttribute ('rdf:ID');
    $etext_number =~ s/^etext//;
    
    next unless ($etext_number);

    my $title_ref = {
        'fields' => {},
    };

    $title_ref->{id} = $etext_number;
    
    # Neuaufnahmedatum
    foreach my $item ($etext_node->findnodes ('dc:created//text()')) {
        my ($year,$month,$day)=split("-",$item->textContent);
        push @{$title_ref->{fields}{'0002'}}, {
            mult     => 1,
            subfield => '',
            content  => "$year$month$day",
        };
        last;
    }
    
    # Sprache
    my $mult=1;
    foreach my $item ($etext_node->findnodes ('dc:language//text()')) {
        my $valid_lang = OpenBib::Common::Util::normalize_lang($item->textContent);

        if (defined $valid_lang){
            push @{$title_ref->{fields}{'0015'}}, {
                mult     => $mult,
                subfield => '',
                content  => $valid_lang,
            };
            $mult++;
        }
    }
    
    # Verfasser, Personen
    # Einzelner Verfasser
    $mult=1;
    foreach my $item ($etext_node->findnodes ('dc:creator//text()')) {
        my $content = konv($item->textContent);
        my ($person_id,$new)  = OpenBib::Conv::Common::Util::get_person_id($content);
        
        if ($new){
            my $item_ref = {
                'fields' => {},
            };
            $item_ref->{id} = $person_id;
            push @{$item_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => $content,
            };
            
            print AUT encode_json $item_ref, "\n";
        }

        push @{$title_ref->{fields}{'0100'}}, {
            mult       => $mult,
            subfield   => '',
            id         => $person_id,
            supplement => '',
        };
        
        $mult++;
    }

    # Verfasser, Personen
    foreach my $item ($etext_node->findnodes ('dc:contributor//text()')) {
        my $content = konv($item->textContent);
        my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($content);
        
        if ($new){
            my $item_ref = {
                'fields' => {},
            };
            $item_ref->{id} = $person_id;
            push @{$item_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => $content,
            };
            
            print AUT encode_json $item_ref, "\n";
        }
        
        push @{$title_ref->{fields}{'0101'}}, {
            mult       => $mult,
            subfield   => '',
            id         => $person_id,
            supplement => '',
        };
        
        $mult++;
    }

    # Titel
    $mult=1;
    foreach my $item ($etext_node->findnodes ('dc:title//text()')) {
        my $content = $item->textContent;
        $content=~s/>/&gt;/g;
        $content=~s/</&lt;/g;
        $content=~s/\n/ - /g;

        push @{$title_ref->{fields}{'0331'}}, {
            mult     => $mult,
            subfield => '',
            content  => $content,
        };
        $mult++
    }

    $mult=1;
    foreach my $item ($etext_node->findnodes ('pgterms:friendlytitle//text()')) {
        my $content = konv($item->textContent);
        push @{$title_ref->{fields}{'0370'}}, {
            mult     => $mult,
            subfield => '',
            content  => $content,
        };
        $mult++;
    }
    
    # Verlag
    push @{$title_ref->{fields}{'0412'}}, {
        mult     => 1,
        subfield => '',
        content  => 'Project Gutenberg',
    };
    
    # E-Text-URL
    push @{$title_ref->{fields}{'0662'}}, {
        mult     => 1,
        subfield => '',
        content  => "http://www.gutenberg.org/etext/$etext_number",
    };
    
    # Beschreibung
    $mult=1;
    foreach my $item ($etext_node->findnodes ('dc:description//text()')) {
        my $content = konv($item->textContent);
        push @{$title_ref->{fields}{'0501'}}, {
            mult     => $mult,
            subfield => '',
            content  => $content,
        };
        $mult++;
    }
    
    # Medientyp
    push @{$title_ref->{fields}{'4410'}}, {
        mult     => 1,
        subfield => '',
        content  => 'Digital',
    };
    
    $mult=1;
    foreach my $item ($etext_node->findnodes ('dc:type//text()')) {
        my $content = konv($item->textContent);
        push @{$title_ref->{fields}{'0800'}}, {
            mult     => $mult,
            subfield => '',
            content  => $content,
        };
        $mult++;
    }
    
    # Schlagworte
    $mult=1;
    foreach my $item ($etext_node->findnodes ('dc:subject/dcterms:LCSH//text()')) {
        my $content = konv($item->textContent);
        my ($subject_id,$new)  = OpenBib::Conv::Common::Util::get_subject_id($content);
        
        if ($new){
            my $item_ref = {
                'fields' => {},
            };
            $item_ref->{id} = $subject_id;
            push @{$item_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => $content,
            };
            
            print SWT encode_json $item_ref, "\n";
        }

        push @{$title_ref->{fields}{'0710'}}, {
            mult       => $mult,
            subfield   => '',
            id         => $subject_id,
            supplement => '',
        };
        
        $mult++;
    }

    # Klassifikation LCC
    $mult=1;
    foreach my $item ($etext_node->findnodes ('dc:subject/dcterms:LCC//text()')) {
        my $content = konv($item->textContent);
        my ($classification_id,$new)  = OpenBib::Conv::Common::Util::get_classification_id($content);
        
        if ($new){
            my $item_ref = {
                'fields' => {},
            };
            $item_ref->{id} = $classification_id;
            push @{$item_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => $content,
            };
            
            print NOTATION encode_json $item_ref, "\n";
        }

        push @{$title_ref->{fields}{'0700'}}, {
            mult       => $mult,
            subfield   => '',
            id         => $classification_id,
            supplement => '',
        };
        
        $mult++;
    }

    print TIT encode_json $title_ref, "\n";

    if ($count % 1000 == 0){
        print STDERR "$count Titel konvertiert\n";
    }
    
    $count++
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
    $content=~s/\n/<br\/>/g;

    return $content;
}
