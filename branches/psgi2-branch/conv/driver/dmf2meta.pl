#!/usr/bin/perl

#####################################################################
#
#  dmf2meta.pl
#
#  Konvertierung des DRIVER-XML-Formates DMF in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2010-2013 Oliver Flimm <flimm@openbib.org>
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
use File::Find;
use File::Slurp;
use Getopt::Long;
use XML::LibXML;
use XML::LibXML::XPathContext;
use YAML::Syck;
use JSON::XS qw(encode_json);
use DB_File;
use Encode qw /decode_utf8/;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our $mexidn  =  1;
our $fileidx =  0;

my ($inputdir,$idmappingfile);

&GetOptions(
	    "inputdir=s"           => \$inputdir,
	    );

if (!$inputdir){
    print << "HELP";
driver2meta.pl - Aufrufsyntax

    driver2meta.pl --inputdir=xxx
HELP
exit;
}

our $have_titleid_ref = {};

our $mediatype_ref = {
    'article'  => 'Aufsatz',
    'preprint' => 'Preprint',
    'series'   => 'Reihe',
    'archive'  => 'Archiv',
    'book'     => 'Buch',
};

open (TITLE,         ,"|buffer | gzip > meta.title.gz");
open (PERSON,        ,"|buffer | gzip > meta.person.gz");
open (CORPORATEBODY, ,"|buffer | gzip > meta.corporatebody.gz");
open (CLASSIFICATION ,"|buffer | gzip > meta.classification.gz");
open (SUBJECT,       ,"|buffer | gzip > meta.subject.gz");
open (HOLDING,       ,"|buffer | gzip > meta.holding.gz");

binmode(TITLE);
binmode(PERSON);
binmode(CORPORATEBODY);
binmode(CLASSIFICATION);
binmode(SUBJECT);
binmode(HOLDING);

our $parser = XML::LibXML->new();
#    $parser->keep_blanks(0);
#    $parser->recover(2);
    $parser->clean_namespaces( 1 );

sub process_file {
    return unless (-f $File::Find::name);

#    print "Processing ".$File::Find::name."\n";
    
    # Workaround: XPATH-Problem mit Default-Namespace. Daher alle
    # Namespaces entfernen.

    my $slurped_file = decode_utf8(read_file($File::Find::name));

    my $tree;

    eval {
        $tree = $parser->parse_string($slurped_file);
    };
        
    if ($@){
        print STDERR $@;
        return;
    }

    my $root = $tree->getDocumentElement;

    my $xc   = XML::LibXML::XPathContext->new($root);
    $xc->registerNs('dr'  => 'http://www.driver-repository.eu/namespace/dr');
    $xc->registerNs('xsi' => 'http://www.w3.org/2001/XMLSchema-instance');
    $xc->registerNs('dri' => 'http://www.driver-repository.eu/namespace/dri');
    $xc->registerNs('dc'  => 'http://purl.org/dc/elements/1.1/');
    $xc->registerNs('noNamespaceSchemaLocation' => 'http://212.87.15.95:8005/config/DMFSchema.xsd');

    #######################################################################
    # Header

    my $id=undef;
    foreach my $node ($xc->findnodes('/record/header')) {
        $id    = $node->findnodes ('dri:recordIdentifier//text()')->[0]->textContent;

        if ($id){
            if ($id =~/\//){
                # IDs mit Slashes lassen sich nicht vernuenftig als URL-Bestandteil abbilden
                print STDERR  "ID mit Slash: $id\n";
                $id    =~s/\//_/g;
            }
            
#            $id    =~s/\//|/g;

            if ($have_titleid_ref->{$id}){
                print STDERR  "Doppelte ID: $id\n";
                return;
            }
            
            $have_titleid_ref->{$id} = 1;
            
            last;
        }

    }

    return unless ($id);

    my $title_ref = {
        'fields' => {},
    };

    $title_ref->{id} = $id;
    
    # Metadata
    foreach my $node ($xc->findnodes('/record/metadata')) {

        my $person_mult = 1;
        # Verfasser
        foreach my $item ($node->findnodes ('dc:creator//text()')) {
            my $content = $item->textContent;

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
                
                print PERSON encode_json $item_ref, "\n";
            }
            
            push @{$title_ref->{fields}{'0100'}}, {
                mult       => $person_mult,
                subfield   => '',
                id         => $person_id,
                supplement => '',
            };
            
            $person_mult++;
        }
        
        # Herausgeber
        foreach my $item ($node->findnodes ('dc:publisher//text()')) {
            my $content = $item->textContent;

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
                
                print PERSON encode_json $item_ref, "\n";
            }
            
            push @{$title_ref->{fields}{'0101'}}, {
                mult       => $person_mult,
                subfield   => '',
                id         => $person_id,
                supplement => '[Hrsg.]',
            };
            
            $person_mult++;
        }
        
        # Titel
        my $title_mult = 1;
        foreach my $item ($node->findnodes ('dc:title//text()')) {
            my $content = $item->textContent;
            push @{$title_ref->{fields}{'0331'}}, {
                content  => $content,
                subfield => '',
                mult     => $title_mult++,
            };
        }

        # Beschreibung
        my $abstract_mult = 1;
        foreach my $item ($node->findnodes ('dc:description//text()')) {
            my $content = $item->textContent;
            push @{$title_ref->{fields}{'0750'}}, {
                content  => $content,
                subfield => '',
                mult     => $abstract_mult++,
            };
        }

        # Quelle
        my $source_mult = 1;
        foreach my $item ($node->findnodes ('dc:source//text()')) {
            my $content = $item->textContent;
            push @{$title_ref->{fields}{'0590'}}, {
                content  => $content,
                subfield => '',
                mult     => $source_mult++,
            };
        }

        # Verlag
        my $publ_mult = 1;
        foreach my $item ($node->findnodes ('dc:publisher//text()')) {
            my $content = $item->textContent;
            push @{$title_ref->{fields}{'0412'}}, {
                content  => $content,
                subfield => '',
                mult     => $publ_mult++,
            };
        }

        # Sprache
        my $lang_mult = 1;
        foreach my $item ($node->findnodes ('dc:language//text()')) {
            my $content = $item->textContent;
            push @{$title_ref->{fields}{'0015'}}, {
                content  => $content,
                subfield => '',
                mult     => $lang_mult++,
            };
        }

        # Zugriff online
        $title_ref->{fields}{'4400'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "online",
            },
        ];

        my $url_mult=1;
        # Link zum Volltext
        foreach my $item ($node->findnodes ('dc:identifier//text()')) {
            my $content = $item->textContent;
            push @{$title_ref->{fields}{'0662'}}, {
                content  => $content,
                subfield => '',
                mult     => $url_mult++,
            };
        }

        my $date_mult = 1;
        foreach my $item ($node->findnodes ('dc:date//text()')) {
            my ($date) = $item->textContent =~/^(\d\d\d\d)-\d\d-\d\d/;
            push @{$title_ref->{fields}{'0425'}}, {
                content  => $date,
                subfield => '',
                mult     => $url_mult++,
            } if ($date);
        }


        # Schlagworte
        my $subject_mult = 1;
        foreach my $item ($node->findnodes ('dc:subject//text()')) {
            my $content = $item->textContent;

            if ($content){

                my @parts = ();
                if ($content=~/(?:\s*,\s*|\s*;\s*)/){
                    @parts = split('(?:\s*,\s*|\s*;\s*)',$content);
                }
                else {
                    push @parts, $content;
                }

                foreach my $part (@parts){
                    $part=~s/^(\w)/\u$1/;
                    my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_subject_id($part);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $subject_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print SUBJECT encode_json $item_ref, "\n";
                    }
                    
                    push @{$title_ref->{fields}{'0710'}}, {
                        mult       => $subject_mult,
                        subfield   => '',
                        id         => $subject_id,
                        supplement => '',
                    };
                    
                    $subject_mult++;
                }
            }
        }

    }

    print TITLE encode_json $title_ref, "\n";
    
    $fileidx++;
    
    if ($fileidx % 1000 == 0){
        print STDERR "$fileidx Saetze indexiert\n";

    }
#
#    print "Processing done\n";
}

find(\&process_file, $inputdir);

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}
