#!/usr/bin/perl

#####################################################################
#
#  oai2meta.pl
#
#  Konvertierung des OAI_DC XML-Formates in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2005-2006 Oliver Flimm <flimm@openbib.org>
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

binmode(TIT,     ":utf8");
binmode(AUT,     ":utf8");
binmode(KOR,     ":utf8");
binmode(NOTATION,":utf8");
binmode(SWT,     ":utf8");
binmode(MEX,     ":utf8");

my $twig= XML::Twig->new(
    TwigHandlers => {
        "/oairesponse/record" => \&parse_titset
    },
 );


$twig->parsefile($inputfile);

sub parse_titset {
    my($t, $titset)= @_;

    # Id
    foreach my $desk ($titset->children('id')){
        my $id=$desk->text();

        print TIT "0000:$id\n";

        last; # Nur ein Durchlauf, d.h. erste gefundene ID wird genommen
    }

    foreach my $mdnode ($titset->children('metadata')){
        foreach my $oainode ($mdnode->children('oai_dc:dc')){
            
            # Verfasser/Personen
            foreach my $desk ($oainode->children('dc:creator')){
                my $content = $desk->text();
                
                my ($autidn,$new) = OpenBib::Conv::Common::Util::get_person_id($content);
                
                if ($autidn > 0) {
                    print AUT "0000:$autidn\n";
                    print AUT "0001:$content\n";
                    print AUT "9999:\n";
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                print TIT "0100:IDN: $autidn\n";
            }
            
            # Koerperschaften
            foreach my $desk ($oainode->children('dc:publisher')){
                my $content = $desk->text();
                
                my ($koridn,$new)  = OpenBib::Conv::Common::Util::get_corporatebody_id($content);
                
                if ($koridn > 0) {
                    print KOR "0000:$koridn\n";
                    print KOR "0001:$content\n";
                    print KOR "9999:\n";
                }
                else {
                    $koridn=(-1)*$koridn;
                }
                
                print TIT "0201:IDN: $koridn\n";

            }
        
            # Schlagworte
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
                        my ($swtidn,$new) = OpenBib::Conv::Common::Util::get_subject_id($part);
                        
                        if ($swtidn > 0) {
                            print SWT "0000:$swtidn\n";
                            print SWT "0001:$part\n";
                            print SWT "9999:\n";
                        }
                        else {
                            $swtidn=(-1)*$swtidn;
                        }
                        
                        print TIT "0710:IDN: $swtidn\n";
                    }
                }
            }
            
            # Titelkategorien
            
            # Titel
            if($oainode->first_child('dc:title')->text()){
                print TIT "0331:".$oainode->first_child('dc:title')->text()."\n";
            }
            
            # Datum
            if($oainode->first_child('dc:date')->text()){
                print TIT "0002:".$oainode->first_child('dc:date')->text()."\n";
            }
            
            # HSFN
            if ($oainode->first_child('dc:type')->text()) {
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

                print TIT "0519:$type\n";
            }

            # Abstract
            foreach my $desk ($oainode->children('dc:description')) {
                my $abstract = $desk->text();
        
                $abstract=~s/&lt;(\S{1,5})&gt;/<$1>/g;
                $abstract=~s/&amp;(\S{1,8});/&$1;/g;
                $abstract=~s/\n/<br>/g;
                $abstract=~s/^Zusammenfassung<br>//g;
                $abstract=~s/^Summary<br>//g;
                $abstract=~s/\|/&#124;/g;

                print TIT "0750:$abstract\n";
            }

            # URL
            foreach my $desk ($oainode->children('dc:identifier')) {
                my $url=$desk->text();

                print TIT "0662:$url\n" if ($url=~/http/);
            }

            # Format
            foreach my $desk ($oainode->children('dc:format')) {
                my $format=$desk->text();

                print TIT "0435:$format\n";
            }

            # Sprache
            foreach my $desk ($oainode->children('dc:language')) {
                my $lang=$desk->text();

                print TIT "0516:$lang\n";
            }

    
            # Jahr
            if ($oainode->first_child('dc:date')->text()) {
                print TIT "0425:".$oainode->first_child('dc:date')->text()."\n";
            }
        }
    }
    

    print TIT "9999:\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}

