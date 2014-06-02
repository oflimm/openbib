#!/usr/bin/perl

#####################################################################
#
#  repec2meta.pl
#
#  Konvertierung des RePEc-amf-Formates in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2009-2012 Oliver Flimm <flimm@openbib.org>
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
use JSON::XS;
use XML::LibXML;
use XML::LibXML::XPathContext;
use YAML::Syck;
use DB_File;
use Encode qw /decode_utf8/;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our $mexidn  =  1;
our %have_id = ();
 
my ($inputdir,$idmappingfile);

&GetOptions(
	    "inputdir=s"           => \$inputdir,
	    );

if (!$inputdir){
    print << "HELP";
repec2meta.pl - Aufrufsyntax

    repec2meta.pl --inputdir=xxx
HELP
exit;
}

our $mediatype_ref = {
    'article'  => 'Aufsatz',
    'preprint' => 'Preprint',
    'series'   => 'Reihe',
    'archive'  => 'Archiv',
    'book'     => 'Buch',
};

open (TITLE,     ,"|buffer | gzip > meta.title.gz");
open (PERSON,     ,"|buffer | gzip > meta.person.gz");
open (CORPORATEBODY,     ,"|buffer | gzip > meta.corporatebody.gz");
open (CLASSIFICATION ,"|buffer | gzip > meta.classification.gz");
open (SUBJECT,     ,"|buffer | gzip > meta.subject.gz");
open (HOLDING,     ,"|buffer | gzip > meta.holding.gz");

binmode(TITLE);
binmode(PERSON);
binmode(CORPORATEBODY);
binmode(CLASSIFICATION);
binmode(SUBJECT);
binmode(HOLDING);

our $parser = XML::LibXML->new();
#    $parser->keep_blanks(0);
#    $parser->recover(2);
#    $parser->clean_namespaces( 1 );

sub process_file {
    return unless ($File::Find::name=~/.amf.xml$/);

    my $title_ref = {
        'fields' => {},
    };
    
    my $multcount_ref = {};
    
#    print "Processing ".$File::Find::name."\n";

    # Workaround: XPATH-Problem mit Default-Namespace. Daher alle
    # Namespaces entfernen.

    my $slurped_file = decode_utf8(read_file($File::Find::name));

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
        $id=~s/\//slash/g;

	if (exists $have_id{$id}){
	    print STDERR "Double ID $id in ".$File::Find::name."\n";;
	    return ;
	}

        $title_ref->{id} = $id;
	
	$have_id{$id} = 1;
	
        # Herausgeber
        foreach my $item ($node->findnodes ('haseditor/person/name//text()')) {
            my $content = $item->textContent;
            my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($content);
                    
            if ($new) {
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

            
            my $mult = ++$multcount_ref->{'0101'};

            push @{$title_ref->{fields}{'0101'}}, {
                mult       => $mult,
                subfield   => '',
                id         => $person_id,
                supplement => '[Hrsg.]',
            };

        }
        
        # Titel
        foreach my $item ($node->findnodes ('title//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0331'};

            push @{$title_ref->{fields}{'0331'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Beschreibung
        foreach my $item ($node->findnodes ('description//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0750'};

            push @{$title_ref->{fields}{'0750'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Ueberordnung
        foreach my $item ($node->findnodes ('ispartof/collection')) {
            my $id = $item->getAttribute ('ref');
            $id=~s/\//slash/g;
            last if ($id=~/^RePEc$/); # Root-Node wird nicht verlinkt

            my $mult = ++$multcount_ref->{'0004'};

            push @{$title_ref->{fields}{'0004'}}, {
                mult     => $mult,
                subfield => '',
                content  => $id,
            };
        }

        # Verlag
        foreach my $item ($node->findnodes ('haspublisher/organization/name//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0412'};

            push @{$title_ref->{fields}{'0412'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Medientyp
        foreach my $item ($node->findnodes ('type//text()')) {
            my $content = $item->textContent;
            $content = (exists $mediatype_ref->{$content})?$mediatype_ref->{$content}:$content;

            my $mult = ++$multcount_ref->{'0800'};

            push @{$title_ref->{fields}{'0800'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Homepage
        foreach my $item ($node->findnodes ('homepage//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0662'};

            push @{$title_ref->{fields}{'0662'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        print TITLE encode_json $title_ref, "\n";
    }

    #######################################################################
    # Text
    foreach my $node ($root->findnodes('/amf/text')) {
        my $id    = $node->getAttribute ('id');
        $id=~s/\//slash/g;

	if (exists $have_id{$id}){
	    print STDERR "Double ID $id in ".$File::Find::name."\n";
	    return ;
	}

        $title_ref->{id} = $id;
	
	$have_id{$id} = 1;

        # Verfasser
        foreach my $item ($node->findnodes ('hasauthor/person/name//text()')) {
            my $content = $item->textContent;
            my ($person_id,$new)  = OpenBib::Conv::Common::Util::get_person_id($content);
                    
            if ($new) {
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

            my $mult = ++$multcount_ref->{'0100'};

            push @{$title_ref->{fields}{'0100'}}, {
                mult       => $mult,
                subfield   => '',
                id         => $person_id,
                supplement => '',
            };
        }

        # Herausgeber
        foreach my $item ($node->findnodes ('haseditor/person/name//text()')) {
            my $content = $item->textContent;
            my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($content);
                    
            if ($new) {
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

            my $mult = ++$multcount_ref->{'0101'};

            push @{$title_ref->{fields}{'0101'}}, {
                mult       => $mult,
                subfield   => '',
                id         => $person_id,
                supplement => '[Hrsg.]',
            };
        }

        # Titel
        foreach my $item ($node->findnodes ('title//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0331'};

            push @{$title_ref->{fields}{'0331'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Beschreibung
        foreach my $item ($node->findnodes ('abstract//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0750'};

            push @{$title_ref->{fields}{'0750'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Ueberordnung
        foreach my $item ($node->findnodes ('ispartof/collection')) {
            my $id = $item->getAttribute ('ref');
            $id=~s/\//slash/g;
            last if ($id=~/^RePEc$/); # Root-Node wird nicht verlinkt

            my $mult = ++$multcount_ref->{'0004'};

            push @{$title_ref->{fields}{'0004'}}, {
                mult     => $mult,
                subfield => '',
                content  => $id,
            };
        }

        # Verlag
        foreach my $item ($node->findnodes ('haspublisher/organization/name//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0412'};

            push @{$title_ref->{fields}{'0412'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Medientyp
        foreach my $item ($node->findnodes ('type//text()')) {
            my $content = $item->textContent;
            $content = (exists $mediatype_ref->{$content})?$mediatype_ref->{$content}:$content;

            my $mult = ++$multcount_ref->{'0800'};

            push @{$title_ref->{fields}{'0800'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

	# Alle Texte sind online
	push @{$title_ref->{fields}{'4400'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => 'online',
	};

        # Link zum Volltext
        foreach my $item ($node->findnodes ('file/url//text()')) {
            my $content = $item->textContent;

            my $mult = ++$multcount_ref->{'0662'};
            
            push @{$title_ref->{fields}{'0662'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        # Beschreibung des Links zum Volltext
        foreach my $item ($node->findnodes ('file/repec_function//text()')) {
            my $content = $item->textContent;
            my $mult = ++$multcount_ref->{'0663'};
            
            push @{$title_ref->{fields}{'0663'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };
        }

        foreach my $item ($node->findnodes ('date//text()')) {
            my ($date) = $item->textContent =~/^(\d\d\d\d)-\d\d-\d\d/;

            my $mult = ++$multcount_ref->{'0425'};
            
            push @{$title_ref->{fields}{'0425'}}, {
                mult     => $mult,
                subfield => '',
                content  => $date,
            } if ($date);
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

            my $mult = ++$multcount_ref->{'0425'};
            
            push @{$title_ref->{fields}{'0425'}}, {
                mult     => $mult,
                subfield => '',
                content  => $issuedate,
            };            
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
            my $mult = ++$multcount_ref->{'0590'};

            my $content = $journaltitle.(($volume)?" Volume $volume ":"").(($issue)?" Issue $issue ":"").(($issuedate)?" ($issuedate) ":"").(($startpage && $endpage)?" Pages $startpage - $endpage":"");

            push @{$title_ref->{fields}{'0590'}}, {
                mult     => $mult,
                subfield => '',
                content  => $content,
            };            
        }

        # Schlagworte
        foreach my $item ($node->findnodes ('keywords//text()')) {
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
                    my ($subject_id,$new)  = OpenBib::Conv::Common::Util::get_subject_id($part);
                    
                    if ($new) {
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

                    my $mult = ++$multcount_ref->{'0710'};

                    push @{$title_ref->{fields}{'0710'}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $subject_id,
                        supplement => '',
                    };
                }
            }
        }

        # Klassifikation
        foreach my $item ($node->findnodes ('classification//text()')) {
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
                    my ($classification_id,$new) = OpenBib::Conv::Common::Util::get_classification_id($part);
                    
                    if ($new) {
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $classification_id;
                        
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print CLASSIFICATION encode_json $item_ref, "\n";
                    }
                    
                    my $mult = ++$multcount_ref->{'0700'};
                    
                    push @{$title_ref->{fields}{'0700'}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $classification_id,
                        supplement => '',
                    };
                }
            }
        }
    
    print TITLE encode_json $title_ref, "\n";

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
