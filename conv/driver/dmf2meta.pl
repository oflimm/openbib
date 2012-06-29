#!/usr/bin/perl

#####################################################################
#
#  dmf2meta.pl
#
#  Konvertierung des DRIVER-XML-Formates DMF in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2010 Oliver Flimm <flimm@openbib.org>
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

our $have_titid_ref = {};

our $mediatype_ref = {
    'article'  => 'Aufsatz',
    'preprint' => 'Preprint',
    'series'   => 'Reihe',
    'archive'  => 'Archiv',
    'book'     => 'Buch',
};

open (TIT,     ,"|buffer | gzip > unload.TIT.gz");
open (AUT,     ,"|buffer | gzip > unload.PER.gz");
open (KOR,     ,"|buffer | gzip > unload.KOE.gz");
open (NOTATION ,"|buffer | gzip > unload.SYS.gz");
open (SWT,     ,"|buffer | gzip > unload.SWD.gz");
open (MEX,     ,"|buffer | gzip > unload.MEX.gz");

binmode(TIT,     ":utf8");
binmode(AUT,     ":utf8");
binmode(KOR,     ":utf8");
binmode(NOTATION,":utf8");
binmode(SWT,     ":utf8");
binmode(MEX,     ":utf8");

binmode(TIT, ":utf8");

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
                $id=undef;
                next;
            }
            
#            $id    =~s/\//|/g;

            if ($have_titid_ref->{$id}){
                print STDERR  "Doppelte ID: $id\n";
                return;
            }
            
            $have_titid_ref->{$id} = 1;
            
            last;
        }

    }

    return unless ($id);
    
    print TIT "0000:$id\n";
    
    # Metadata
    foreach my $node ($xc->findnodes('/record/metadata')) {
        
        # Verfasser
        foreach my $item ($node->findnodes ('dc:creator//text()')) {
            my $content = $item->textContent;
            my $autidn  = OpenBib::Conv::Common::Util::get_autidn($content);
                    
            if ($autidn > 0) {
                print AUT "0000:$autidn\n";
                print AUT "0001:$content\n";
                print AUT "9999:\n";
            } else {
                $autidn=(-1)*$autidn;
            }
            
            print TIT "0100:IDN: $autidn\n";
        }
        
        # Herausgeber
        foreach my $item ($node->findnodes ('dc:publisher//text()')) {
            my $content = $item->textContent;
            my $autidn  = OpenBib::Conv::Common::Util::get_autidn($content);
            
            if ($autidn > 0) {
                print AUT "0000:$autidn\n";
                print AUT "0001:$content\n";
                print AUT "9999:\n";
            } else {
                $autidn=(-1)*$autidn;
            }
                    
            print TIT "0101:IDN: $autidn ; [Hrsg.]\n";
        }
        
        # Titel
        foreach my $item ($node->findnodes ('dc:title//text()')) {
            my $content = $item->textContent;
            print TIT "0331:$content\n";
        }

        # Beschreibung
        foreach my $item ($node->findnodes ('dc:description//text()')) {
            my $content = $item->textContent;
            print TIT "0750:$content\n";
        }

        # Quelle
        foreach my $item ($node->findnodes ('dc:source//text()')) {
            my $content = $item->textContent;
            print TIT "0590:$content\n";
        }

        # Verlag
        foreach my $item ($node->findnodes ('dc:publisher//text()')) {
            my $content = $item->textContent;
            print TIT "0412:$content\n";
        }

        # Sprache
        foreach my $item ($node->findnodes ('dc:language//text()')) {
            my $content = $item->textContent;
            print TIT "0015:$content\n";
        }

        my $urlidx=1;
        # Link zum Volltext
        foreach my $item ($node->findnodes ('dc:identifier//text()')) {
            my $content = $item->textContent;
            printf TIT "0662.%03d:%s\n",$urlidx,$content;
            $urlidx++;
        }

        foreach my $item ($node->findnodes ('dc:date//text()')) {
            my ($date) = $item->textContent =~/^(\d\d\d\d)-\d\d-\d\d/;
            
            print TIT "0425:$date\n" if ($date);
        }


        # Schlagworte
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
                    my $swtidn  = OpenBib::Conv::Common::Util::get_swtidn($part);
                    
                    if ($swtidn > 0) {
                        print SWT "0000:$swtidn\n";
                        print SWT "0001:$part\n";
                        print SWT "9999:\n";
                    } else {
                        $swtidn=(-1)*$swtidn;
                    }
                    
                    print TIT "0710:IDN: $swtidn\n";
                }
            }
        }

    }

    print TIT "9999:\n";

    $fileidx++;
    
    if ($fileidx % 1000 == 0){
        print STDERR "$fileidx Saetze indexiert\n";

    }
#
#    print "Processing done\n";
}

find(\&process_file, $inputdir);

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
