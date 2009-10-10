#!/usr/bin/perl

#####################################################################
#
#  repec2meta.pl
#
#  Konvertierung des RePEc-amf-Formates in das OpenBib
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

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our $mexidn  =  1;

my ($inputdir,$idmappingfile);

&GetOptions(
	    "inputdir=s"           => \$inputdir,
            "idmappingfile=s"      => \$idmappingfile,
	    );

if (!$inputdir || !$idmappingfile){
    print << "HELP";
repec2meta.pl - Aufrufsyntax

    repec2meta.pl --inputdir=xxx --idmappingfile=yyy
HELP
exit;
}

open (TIT,     ,"|gzip > unload.TIT.gz");
open (AUT,     ,"|gzip > unload.PER.gz");
open (KOR,     ,"|gzip > unload.KOE.gz");
open (NOTATION ,"|gzip > unload.SYS.gz");
open (SWT,     ,"|gzip > unload.SWD.gz");
open (MEX,     ,"|gzip > unload.MEX.gz");

binmode(TIT,     ":utf8");
binmode(AUT,     ":utf8");
binmode(KOR,     ":utf8");
binmode(NOTATION,":utf8");
binmode(SWT,     ":utf8");
binmode(MEX,     ":utf8");

binmode(TIT, ":utf8");

our %numericidmapping;

tie %numericidmapping,             'DB_File', $idmappingfile
    or die "Could not tie idmapping.\n";

if (! exists $numericidmapping{'next_unused_id'}){
    $numericidmapping{'next_unused_id'}=1;
}
our $parser = XML::LibXML->new();
#    $parser->keep_blanks(0);
#    $parser->recover(2);
#    $parser->clean_namespaces( 1 );

sub process_file {
    return unless ($File::Find::name=~/.amf.xml$/);

#    print "Processing ".$File::Find::name."\n";

    # Workaround: XPATH-Problem mit Default-Namespace. Daher alle
    # Namespaces entfernen.

    my $slurped_file = read_file($File::Find::name);

    $slurped_file=~s/<amf.*?>/<amf>/g;
    $slurped_file=~s/repec:/repec_/g;
    $slurped_file=~s/xsi:/xsi_/g;

#    print "----------------\n".$slurped_file,"\n";

    my $tree = $parser->parse_string($slurped_file);
#    my $tree = $parser->parse_file($File::Find::name);
    my $root = $tree->getDocumentElement;

    #    my $xc   = XML::LibXML::XPathContext->new($root);
#    $xc->registerNs(repec   => 'http://repec.openlib.org');
#    $xc->registerNs(default => 'http://amf.openlib.org');
    
    #######################################################################
    # Collection
    foreach my $node ($root->findnodes('/amf/collection')) {
        my $id    = $node->getAttribute ('id');
        my ($intid,$is_new) = get_next_numeric_id($id);
        
        print TIT "0000:$intid\n";
        print TIT "0010:$id\n";

        # Herausgeber
        foreach my $item ($node->findnodes ('haseditor/person/name//text()')) {
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
        foreach my $item ($node->findnodes ('title//text()')) {
            my $content = $item->textContent;
            print TIT "0331:$content\n";
        }

        # Beschreibung
        foreach my $item ($node->findnodes ('description//text()')) {
            my $content = $item->textContent;
            print TIT "0750:$content\n";
        }

        # Ueberordnung
        foreach my $item ($node->findnodes ('ispartof/collection')) {
            my $id = $item->getAttribute ('ref');
            last if ($id=~/^RePEc$/); # Root-Node wird nicht verlinkt
            my ($intid,$is_new) = get_next_numeric_id($id);
            print TIT "0004:$id\n";
        }

        # Verlag
        foreach my $item ($node->findnodes ('haspublisher/organization/name//text()')) {
            my $content = $item->textContent;
            print TIT "0412:$content\n";
        }

        # Medientyp
        foreach my $item ($node->findnodes ('type//text()')) {
            my $content = $item->textContent;
            print TIT "0800:$content\n";
        }

        # Homepage
        foreach my $item ($node->findnodes ('homepage//text()')) {
            my $content = $item->textContent;
            print TIT "0662:$content\n";
        }

        print TIT "9999:\n";
    }

    #######################################################################
    # Text
    foreach my $node ($root->findnodes('/amf/text')) {
        my $id    = $node->getAttribute ('id');
        my ($intid,$is_new) = get_next_numeric_id($id);
        
        print TIT "0000:$intid\n";
        print TIT "0010:$id\n";

        # Verfasser
        foreach my $item ($node->findnodes ('hasauthor/person/name//text()')) {
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
        foreach my $item ($node->findnodes ('haseditor/person/name//text()')) {
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
        foreach my $item ($node->findnodes ('title//text()')) {
            my $content = $item->textContent;
            print TIT "0331:$content\n";
        }

        # Beschreibung
        foreach my $item ($node->findnodes ('abstract//text()')) {
            my $content = $item->textContent;
            print TIT "0750:$content\n";
        }

        # Ueberordnung
        foreach my $item ($node->findnodes ('ispartof/collection')) {
            my $id = $item->getAttribute ('ref');
            last if ($id=~/^RePEc$/); # Root-Node wird nicht verlinkt
            my ($intid,$is_new) = get_next_numeric_id($id);
            print TIT "0004:$intid\n";
        }

        # Verlag
        foreach my $item ($node->findnodes ('haspublisher/organization/name//text()')) {
            my $content = $item->textContent;
            print TIT "0412:$content\n";
        }

        # Medientyp
        foreach my $item ($node->findnodes ('type//text()')) {
            my $content = $item->textContent;
            print TIT "0800:$content\n";
        }

        # Link zum Volltext
        foreach my $item ($node->findnodes ('file/url//text()')) {
            my $content = $item->textContent;
            print TIT "0662:$content\n";
        }

        # Beschreibung des Links zum Volltext
        foreach my $item ($node->findnodes ('file/repec_function//text()')) {
            my $content = $item->textContent;
            print TIT "0663:$content\n";
        }

        my $issue        = "";
        my $issuedate    = "";
        my $volume       = "";
        my $journaltitle = "";
        my $startpage    = "";
        my $endpage      = "";

        # Serial-Information
        foreach my $item ($node->findnodes ('serial/issue//text()')) {
            $issue = $item->textContent;
        }
        foreach my $item ($node->findnodes ('serial/issuedate//text()')) {
            $issuedate = $item->textContent;
        }
        foreach my $item ($node->findnodes ('serial/volume//text()')) {
            $volume = $item->textContent;
        }
        foreach my $item ($node->findnodes ('serial/journaltitle//text()')) {
            $journaltitle = $item->textContent;
        }
        foreach my $item ($node->findnodes ('serial/startpage//text()')) {
            $startpage = $item->textContent;
        }
        foreach my $item ($node->findnodes ('serial/endpage//text()')) {
            $endpage = $item->textContent;
        }

        if ($journaltitle){
            print TIT "0590:$journaltitle".(($volume)?" Volume $volume ":"").(($issue)?" Issue $issue ":"").(($issuedate)?" ($issuedate) ":"").(($startpage && $endpage)?" Pages $startpage - $endpage":"")."\n";
        }

        # Schlagworte
        foreach my $item ($node->findnodes ('keywords//text()')) {
            my $content = $item->textContent;

            if ($content){

                my @parts = ();
                if ($content=~/(?:,|;\s*)/){
                    @parts = split('(?:\s*,\s*|\s*;\s*)',$content);
                }
                else {
                    push @parts, $content;
                }

                foreach my $part (@parts){
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
        
        print TIT "9999:\n";
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

sub get_next_numeric_id {
    my $alnumidentifier = shift;

    if (exists $numericidmapping{$alnumidentifier}){
        # (Id,New?)
        return ($numericidmapping{$alnumidentifier},0);
    }
    else {
        $numericidmapping{$alnumidentifier}= $numericidmapping{'next_unused_id'};
        $numericidmapping{'next_unused_id'}=$numericidmapping{'next_unused_id'}+1;

        # (Id,New?)
        return ($numericidmapping{$alnumidentifier},1);
    }
}
