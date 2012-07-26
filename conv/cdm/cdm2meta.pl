#!/usr/bin/perl

#####################################################################
#
#  cdm2meta.pl
#
#  Konvertierung des CDM XML-Formates in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
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
use JSON::XS;
use XML::Twig;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

our ($mexidn);

$mexidn  =  1;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
cdm2meta.pl - Aufrufsyntax

    cdm2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

open (TITLE,     ">:utf8","meta.title");
open (PERSON,     ">:utf8","meta.person");
open (CORPORATEBODY,     ">:utf8","meta.corporatebody");
open (CLASSIFICATION,">:utf8","meta.classification");
open (SUBJECT,     ">:utf8","meta.subject");
open (HOLDING,     ">:utf8","meta.holding");

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/metadata/record" => \&parse_titset
   }
 );


$twig->parsefile($inputfile);

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub parse_titset {
    my($t, $titset)= @_;

    my $title_ref = {};

    $title_ref->{id} = $titset->first_child($convconfig->{uniqueidfield})->text();

    # Erstellungsdatum
    if(defined $titset->first_child('cdmcreated') && $titset->first_child('cdmcreated')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmcreated')->text());

        push @{$title_ref->{'0002'}}, {
            content  => "$day.$month.$year",
            subfield => '',
            mult     => 1,
        };
    }
    
    # Aenderungsdatum
    if(defined $titset->first_child('cdmmodified') && $titset->first_child('cdmmodified')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmmodified')->text());
        push @{$title_ref->{'0003'}}, {
            content  => "$day.$month.$year",
            subfield => '',
            mult     => 1,
        };
    }

    foreach my $kateg (keys %{$convconfig->{title}}){
        my $mult = 1;

        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
#            my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }

                foreach my $part (@parts){
                    push @{$title_ref->{$convconfig->{title}{$kateg}}}, {
                        content  => $part,
                        subfield => '',
                        mult     => $mult,
                    };
                    $mult++;
                }
            }
        }
    }
    
    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{pers}}){
        if (defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            #my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my ($person_id,$new)=OpenBib::Conv::Common::Util::get_person_id($part);
                    
                    if ($new){
                        my $item_ref = {};
                        $item_ref->{id} = $person_id;
                        push @{$item_ref->{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print PERSON encode_json $item_ref, "\n";
                    }

                    my $new_category = $convconfig->{pers}{$kateg};
                    
                    push @{$title_ref->{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $person_id,
                        supplement => '',
                    };
                    
                    $mult++;
                }
            }
            # Autoren abarbeiten Ende
        }
    }

    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corp}}){
        my $mult = 1;
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            #my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my ($corporatebody_id,$new)=OpenBib::Conv::Common::Util::get_corporatebody_id($part);
                    
                    if ($new){
                        my $item_ref = {};
                        $item_ref->{id} = $corporatebody_id;
                        push @{$item_ref->{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print CORPORATEBODY encode_json $item_ref, "\n";
                    }
                    
                    my $new_category = $convconfig->{corp}{$kateg};
                    
                    push @{$title_ref->{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $corporatebody_id,
                        supplement => '',
                    };
                    
                    $mult++;
                }
            }
        }
    }
    # Koerperschaften abarbeiten Ende

    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{sys}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            #my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my ($classification_id,$new)=OpenBib::Conv::Common::Util::get_classification_id($part);
                
                    if ($new){
                        my $item_ref = {};
                        $item_ref->{id} = $classification_id;
                        push @{$item_ref->{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print CLASSIFICATION encode_json $item_ref, "\n";
                    }

                    my $new_category = $convconfig->{sys}{$kateg};
                    
                    push @{$title_ref->{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $classification_id,
                        supplement => '',
                    };
                    
                    $mult++;
                }
            }
        }
    }
    # Notationen abarbeiten Ende
        
    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subj}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
#            $content    = decode($convconfig->{encoding},$content) if (exists $convconfig->{encoding});
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my ($subject_id,$new)=OpenBib::Conv::Common::Util::get_subject_id($part);
                    
                    if ($new){	  
                        my $item_ref = {};
                        $item_ref->{id} = $subject_id;
                        push @{$item_ref->{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print SUBJECT encode_json $item_ref, "\n";
                    }

                    my $new_category = $convconfig->{subj}{$kateg};
                    
                    push @{$title_ref->{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $subject_id,
                        supplement => '',
                    };
                    
                    $mult++;
                }
            }
        }
    }
    # Schlagworte abarbeiten Ende
    
    # Exemplardaten abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{exempl}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }

                foreach my $part (@parts){
                    my $item_ref = {};
                    $item_ref->{id} = $mexidn;
                    push @{$item_ref->{'0004'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $titset->first_child($convconfig->{uniqueidfield})->text(),
                    };

                    push @{$item_ref->{$convconfig->{exempl}{$kateg}}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $part,
                    };

                    print HOLDING encode_json $item_ref, "\n"; 
                    $mexidn++;
                }
            }
        }
    }
    # Exemplardaten abarbeiten Ende

    print TITLE encode_json $title_ref, "\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}
                                   
sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}
