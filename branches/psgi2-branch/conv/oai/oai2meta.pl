#!/usr/bin/perl

#####################################################################
#
#  oai2meta.pl
#
#  Konvertierung des OAI_DC XML-Formates in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2005-2013 Oliver Flimm <flimm@openbib.org>
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

use XML::Twig;
use Getopt::Long;
use YAML::Syck;
use JSON::XS;
use Encode qw /decode_utf8/;

use OpenBib::Conv::Common::Util;
use OpenBib::Config;

our $mexidn  =  1;

my ($inputfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
	    );

if (!$inputfile){
    print << "HELP";
oai2meta.pl - Aufrufsyntax

    oai2meta.pl --inputfile=xxx
HELP
exit;
}

open (TIT,     ,"|buffer | gzip > meta.title.gz");
open (AUT,     ,"|buffer | gzip > meta.person.gz");
open (KOR,     ,"|buffer | gzip > meta.corporatebody.gz");
open (NOTATION ,"|buffer | gzip > meta.classification.gz");
open (SWT,     ,"|buffer | gzip > meta.subject.gz");
open (MEX,     ,"|buffer | gzip > meta.holding.gz");

binmode(TIT);
binmode(AUT);
binmode(KOR);
binmode(NOTATION);
binmode(SWT);
binmode(MEX);

my $twig= XML::Twig->new(
    TwigHandlers => {
        "/oairesponse/record" => \&parse_titset
    },
 );


$twig->parsefile($inputfile);

sub parse_titset {
    my($t, $titset)= @_;

    my $title_ref = {
        'fields' => {},
    };
    
    # Id
    foreach my $desk ($titset->children('id')){
        my $id=$desk->text();
        $title_ref->{id}=$id;
        last; # Nur ein Durchlauf, d.h. erste gefundene ID wird genommen
    }

    foreach my $mdnode ($titset->children('metadata')){
        foreach my $oainode ($mdnode->children('oai_dc:dc')){
            
            # Verfasser/Personen
            my $mult = 1;
            foreach my $desk ($oainode->children('dc:creator')){
                my $content = $desk->text();
                
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
            
            # Koerperschaften
            $mult=1;
            foreach my $desk ($oainode->children('dc:publisher')){
                my $content = $desk->text();
                
                my ($corporatebody_id,$new)  = OpenBib::Conv::Common::Util::get_corporatebody_id($content);

                if ($new) {
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $corporatebody_id;
                    push @{$item_ref->{fields}{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $content,
                    };

                    print KOR encode_json $item_ref, "\n";
                }

                push @{$title_ref->{fields}{'0201'}}, {
                    mult       => $mult,
                    subfield   => '',
                    id         => $corporatebody_id,
                    supplement => '',
                };
                $mult++;
            }
        
            # Schlagworte
            $mult=1;
            foreach my $desk ($oainode->children('dc:subject')){
                my $content = $desk->text();

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
                }
            }
            
            # Titelkategorien
            
            # Titel
            if(defined $oainode->first_child('dc:title') && $oainode->first_child('dc:title')->text()){
                push @{$title_ref->{fields}{'0331'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $oainode->first_child('dc:title')->text(),
                };
            }
            
            # Datum
#            if($oainode->first_child('dc:date')->text()){
#                print TIT "0002:".$oainode->first_child('dc:date')->text()."\n";
#            }
            
            # HSFN
            if (defined $oainode->first_child('dc:type') && $oainode->first_child('dc:type')->text()) {
                my $type=$oainode->first_child('dc:type')->text();

                if ($type=~/Text.Thesis.Doctoral/) {
                    $type="Dissertation";
                }
                elsif ($type=~/Text.Thesis.Habilitation/) {
                    $type="Habilitation";
                }
                elsif ($type=~/Text.Thesis.Doctoral.Abstract/) {
                    $type="Dissertations-Abstract";
                }

                push @{$title_ref->{fields}{'0519'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $type,
                };
            }

            # Abstract
            $mult=1;
            foreach my $desk ($oainode->children('dc:description')) {
                my $abstract = $desk->text();
        
                $abstract=~s/&lt;(\S{1,5})&gt;/<$1>/g;
                $abstract=~s/&amp;(\S{1,8});/&$1;/g;
                $abstract=~s/\n/<br>/g;
                $abstract=~s/^Zusammenfassung<br>//g;
                $abstract=~s/^Summary<br>//g;
                $abstract=~s/\|/&#124;/g;

                push @{$title_ref->{fields}{'0750'}}, {
                    mult     => $mult,
                    subfield => '',
                    content  => $abstract,
                };
                $mult++;
            }

            # URL
            $mult=1;
            foreach my $desk ($oainode->children('dc:identifier')) {
                my $url=$desk->text();

                if ($url=~/http/){
                    push @{$title_ref->{fields}{'0662'}}, {
                        mult     => $mult,
                        subfield => '',
                        content  => $url,
                    };
                    $mult++;
                }
            }

            # Format
            $mult=1;
            foreach my $desk ($oainode->children('dc:format')) {
                my $format=$desk->text();

                push @{$title_ref->{fields}{'0435'}}, {
                    mult     => $mult,
                    subfield => '',
                    content  => $format,
                };
                $mult++;
            }

            # Sprache
            $mult=1;
            foreach my $desk ($oainode->children('dc:language')) {
                my $lang=$desk->text();

                push @{$title_ref->{fields}{'0516'}}, {
                    mult     => $mult,
                    subfield => '',
                    content  => $lang,
                };
                $mult++;
            }

    
            # Jahr
            if (defined $oainode->first_child('dc:date') && $oainode->first_child('dc:date')->text()) {
                push @{$title_ref->{fields}{'0425'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $oainode->first_child('dc:date')->text(),
                };
            }

            # Medientyp Digital
            push @{$title_ref->{fields}{'4410'}}, {
                mult     => 1,
                subfield => '',
                content  => "Digital",
            };
            
        }
    }
    
    print TIT encode_json $title_ref, "\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}

