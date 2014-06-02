#!/usr/bin/perl

#####################################################################
#
#  tellico_music2meta.pl
#
#  Konvertierung des Tellico XML-Formates (Musik) in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

use XML::Twig;
use JSON::XS;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $inputfile=$ARGV[0];

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/tellico/collection/entry" => \&parse_titset
   }
 );


$twig->safe_parsefile($inputfile);

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub parse_titset {
    my($t, $titset)= @_;

    #  Beispiel:
    #
    #  <entry id="1" >
    #   <title>Autour de Lucie</title>
    #   <artists>
    #    <artist>Autour de Lucie</artist>
    #   </artists>
    #   <year>2001</year>
    #   <anzahl-titel>11</anzahl-titel>
    #   <besitzer>Oliver Flimm</besitzer>
    #  </entry>

    my $title_ref = {
        'fields' => {},
    };
    
    my $id = int($titset->{'att'}->{'id'});

    $title_ref->{id} = $id;
               
    # Verfasser/Personen
    my $mult = 1;
    
    foreach my $desk ($titset->children('artists')){
        my $ans=$desk->text();
        if ($ans){
            my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($ans);
            
            if ($new){
                my $item_ref = {
                    'fields' => {},
                };
                $item_ref->{id} = $person_id;
                push @{$item_ref->{fields}{'0800'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $ans,
                };
                
                print PERSON encode_json $item_ref, "\n";
            }
            
            my $new_category = "0100";

            push @{$title_ref->{fields}{$new_category}}, {
                mult       => $mult,
                subfield   => '',
                id         => $person_id,
                supplement => '',
            };

            $mult++;
        }
    }

    # Titelkategorien

    # Titel
    if(defined $titset->first_child('title')){
        push @{$title_ref->{fields}{'0331'}}, {
            mult     => 1,
            subfield => '',
            content  => $titset->first_child('title')->text(),
        };
    }


    # Anzahl Titel
    if(defined $titset->first_child('anzahl-titel')){
        push @{$title_ref->{fields}{'0433'}}, {
            mult     => 1,
            subfield => '',
            content  => $titset->first_child('anzahl-titel')->text(),
        };
    }

    # Anzahl Medien
    if(defined $titset->first_child('anzahl-medien')){
        push @{$title_ref->{fields}{'0512'}}, {
            mult     => 1,
            subfield => '',
            content  => $titset->first_child('anzahl-medien')->text(),
        };
    }

    # Medienart
    if(defined $titset->first_child('medium')){
        push @{$title_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $titset->first_child('medium')->text(),
        };
    }
    
    # Jahr
    if(defined $titset->first_child('year')){
        push @{$title_ref->{fields}{'0425'}}, {
            mult     => 1,
            subfield => '',
            content  => $titset->first_child('year')->text(),
        };
    }

    print TITLE encode_json $title_ref, "\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}
