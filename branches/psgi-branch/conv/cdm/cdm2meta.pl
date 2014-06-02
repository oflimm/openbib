#!/usr/bin/perl

#####################################################################
#
#  cdm2meta.pl
#
#  Konvertierung des CDM XML-Formates in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008-2013 Oliver Flimm <flimm@openbib.org>
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
use XML::Simple;

use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

our $mexidn  =  1;

our %have_title = ();

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

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/metadata/record" => \&parse_titset
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

    my $title_ref = {
        'fields' => {},
    };

    $title_ref->{id} = $titset->first_child($convconfig->{uniqueidfield})->text();

    next unless ($title_ref->{id});
    
    next if (exists $have_title{$title_ref->{id}});

    $have_title{$title_ref->{id}} = 1;
    
    # Erstellungsdatum
    if(defined $titset->first_child('cdmcreated') && $titset->first_child('cdmcreated')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmcreated')->text());

        push @{$title_ref->{fields}{'0002'}}, {
            content  => "$day.$month.$year",
            subfield => '',
            mult     => 1,
        };
    }
    
    # Aenderungsdatum
    if(defined $titset->first_child('cdmmodified') && $titset->first_child('cdmmodified')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmmodified')->text());

        push @{$title_ref->{fields}{'0003'}}, {
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

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($convconfig->{filter}{$kateg}{filter_add_year}){
                my $new_content = filter_match($content,$convconfig->{filter}{$kateg}{filter_add_year}{regexp});
                push @{$title_ref->{fields}{$convconfig->{filter}{$kateg}{filter_add_year}{category}}}, {
                    content  => $new_content,
                    subfield => '',
                    mult     => $mult,
                };
            }
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }

                foreach my $part (@parts){
                    push @{$title_ref->{fields}{$convconfig->{title}{$kateg}}}, {
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
        my $mult = 1;
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
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $person_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print PERSON encode_json $item_ref, "\n";
                    }

                    my $new_category = $convconfig->{pers}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        content    => $part,
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
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $corporatebody_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print CORPORATEBODY encode_json $item_ref, "\n";
                    }
                    
                    my $new_category = $convconfig->{corp}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        content    => $part,
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
                    my ($classification_id,$new)=OpenBib::Conv::Common::Util::get_classification_id($part);
                
                    if ($new){
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

                    my $new_category = $convconfig->{sys}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        content    => $part,
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
        my $mult = 1;
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

                    my $new_category = $convconfig->{subj}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        content    => $part,
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

    # Strukturdaten    
    if (defined $titset->first_child('structure')){
        my $structure = $titset->first_child('structure')->sprint();
        
        my $xs = new XML::Simple(ForceArray => ['node','page','pagefile']);
        
        my $structure_ref = $xs->XMLin($structure);
        
        print YAML::Syck::Dump($structure_ref);
        
        
        if (@{$structure_ref->{page}} > 0){
            my $mult = 1;
            
            foreach my $page_ref (@{$structure_ref->{page}}){
                push @{$title_ref->{fields}{'6050'}}, {
                    mult       => $mult,
                    subfield   => '',
                    content    => $page_ref->{pagetitle},
                } if (defined $page_ref->{pagetitle});

                foreach my $pagefile_ref (@{$page_ref->{pagefile}}){
                    if ($pagefile_ref->{pagefiletype} eq "access"){
                        push @{$title_ref->{fields}{'6051'}}, {
                            mult       => $mult,
                            subfield   => '',
                            content    => $pagefile_ref->{pagefilelocation},
                        } if (defined $pagefile_ref->{pagefilelocation});
                    }
                    
                    
                    if ($pagefile_ref->{pagefiletype} eq "thumbnail"){
                        push @{$title_ref->{fields}{'6052'}}, {
                            mult       => $mult,
                            subfield   => '',
                            content    => $pagefile_ref->{pagefilelocation},
                        } if (defined $pagefile_ref->{pagefilelocation});
                    }
                }
                push @{$title_ref->{fields}{'6053'}}, {
                    mult       => $mult,
                    subfield   => '',
                    content    => $page_ref->{pagetext},
                } if (defined $page_ref->{pagetext});

                push @{$title_ref->{fields}{'6054'}}, {
                    mult       => $mult,
                    subfield   => '',
                    content    => $page_ref->{pageptr},
                } if (defined $page_ref->{pageptr});
                $mult++;
            }   
        }

        if (@{$structure_ref->{node}} > 0){

            foreach my $node_ref (@{$structure_ref->{node}}){
                my $i = 1;
            
                foreach my $page_ref (@{$node_ref->{page}}){
                    push @{$title_ref->{fields}{'6050'}}, {
                        mult       => $mult,
                        subfield   => '',
                        content    => $page_ref->{pagetitle},
                    } if (defined $page_ref->{pagetitle});
                    
                    foreach my $pagefile_ref (@{$page_ref->{pagefile}}){
                        if ($pagefile_ref->{pagefiletype} eq "access"){
                            push @{$title_ref->{fields}{'6051'}}, {
                                mult       => $mult,
                                subfield   => '',
                                content    => $pagefile_ref->{pagefilelocation},
                            } if (defined $pagefile_ref->{pagefilelocation});
                        }
                        
                        
                        if ($pagefile_ref->{pagefiletype} eq "thumbnail"){
                            push @{$title_ref->{fields}{'6052'}}, {
                                mult       => $mult,
                                subfield   => '',
                                content    => $pagefile_ref->{pagefilelocation},
                            } if (defined $pagefile_ref->{pagefilelocation});
                        }
                    }
                    
                    push @{$title_ref->{fields}{'6053'}}, {
                        mult       => $mult,
                        subfield   => '',
                        content    => $page_ref->{pagetext},
                    } if (defined $page_ref->{pagetext});
                    
                    push @{$title_ref->{fields}{'6054'}}, {
                        mult       => $mult,
                        subfield   => '',
                        content    => $page_ref->{pageptr},
                    } if (defined $page_ref->{pageptr});
                    $mult++;
                }
            }
        }
    }
        
        
#         m
#         my $structure_ref = {};
#         foreach my $node ($structure->children('node'){
#             if(defined $titset->first_child('nodetitle') && $titset->first_child('nodetitle')->text()){
#                 $structure_ref->{nodetitle} = konv($titset->first_child('nodetitle')->text());
#             }

#             my $page_ref = [];
#             foreach my $page ($node->children('page'){
#                 my $thispage_ref = {};
#                 if(defined $titset->first_child('pagetitle') && $titset->first_child('pagetitle')->text()){
#                     $thispage_ref->{pagetitle} = konv($titset->first_child('pagetitle')->text());
#                 }
#                 if(defined $titset->first_child('pageptr') && $titset->first_child('pageptr')->text()){
#                     $thispage_ref->{pageptr} = konv($titset->first_child('pageptr')->text());
#                 }

                
#             }            
#         }                


    my $mexdaten_ref = {};
    
    # Exemplardaten abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{exempl}}){
        my ($new_category)=$convconfig->{exempl}{$kateg}=~m/^(\d\d\d\d)/;
        my ($new_mult)    =$convconfig->{exempl}{$kateg}=~m/^\d\d\d\d\.(\d\d\d)/;
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            
            if ($content){
                if (exists $convconfig->{category_split_chars}{$kateg}){
                    my @parts = ();
                    if ($content=~/$convconfig->{category_split_chars}{$kateg}/){
                        push @parts, split($convconfig->{category_split_chars}{$kateg},$content);
                    }
                    else {
                        push @parts, $content;
                    }
                    
                    my $idx=1;
                    foreach my $part (@parts){
                        $f_idx=sprintf "%03d", $idx;;
                        $mexdaten_ref->{$f_idx}{$new_category}=$part;
                        $idx++;
                    }

                }
                else {
                    $mexdaten_ref->{$new_mult}{$new_category}=$content;
                }
            }
        }
    }

    foreach my $idx (keys %$mexdaten_ref){
        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $mexidn;
        push @{$item_ref->{fields}{'0004'}}, {
            mult     => 1,
            subfield => '',
            content  => $titset->first_child($convconfig->{uniqueidfield})->text(),
        };

        foreach my $new_category (keys %{$mexdaten_ref->{$idx}}){
            push @{$item_ref->{fields}{$new_category}}, {
                mult     => $idx,
                subfield => '',
                content  => $mexdaten_ref->{$idx}->{$new_category},
            };
        }
        
        print HOLDING encode_json $item_ref, "\n";
        $mexidn++;
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

# Filter

sub filter_junk {
    my ($content) = @_;

    $content=~s/\W/ /g;
    $content=~s/\s+/ /g;
    $content=~s/\s\D\s/ /g;

    
    return $content;
}

sub filter_newline2br {
    my ($content) = @_;

    $content=~s/\n/<br\/>/g;
    
    return $content;
}

sub filter_match {
    my ($content,$regexp) = @_;

    my ($match)=$content=~m/($regexp)/g;
    
    return $match;
}

