#!/usr/bin/perl

#####################################################################
#
#  simplexml2meta.pl
#
#  Konvertierung eines flachen XML-Formates in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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
use strict;
use warnings;

use Encode 'decode';
use Getopt::Long;
use XML::Twig::XPath;
use XML::Simple;
use JSON::XS;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile || !$configfile){
    print << "HELP";
simplexml2meta.pl - Aufrufsyntax

    simplexml2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

open (TITLE,         ">:utf8","meta.title");
open (PERSON,        ">:utf8","meta.person");
open (CORPORATEBODY, ">:utf8","meta.corporatebody");
open (CLASSIFICATION,">:utf8","meta.classification");
open (SUBJECT,       ">:utf8","meta.subject");
open (HOLDING,       ">:utf8","meta.holding");

my $twig= XML::Twig::XPath->new(
   TwigHandlers => {
     "$convconfig->{recordselector}" => \&parse_record
   }
 );

our $counter = 0;
our $mexidn  = 1;

$twig->safe_parsefile($inputfile);

print STDERR "All $counter records converted\n";

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub parse_record {
    my($t, $titset)= @_;

    my $title_ref = {};

    my @ids= $titset->get_xpath($convconfig->{uniqueidfield});

    $title_ref->{id} = $ids[0]->first_child()->text();

    foreach my $kateg (keys %{$convconfig->{title}}){

        my @elements = $titset->get_xpath($kateg);

        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

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

                push @{$title_ref->{$convconfig->{filter}{$kateg}{filter_add_year}{category}}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $new_content,
                };
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
    
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
        foreach my $part (@parts){
            push @{$title_ref->{$convconfig->{title}{$kateg}}}, {
                mult     => $mult,
                subfield => '',
                content  => $part,
            };
        }
    }
    
    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{person}}){
        my @elements = $titset->get_xpath($kateg);

        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }
                
            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                                              
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);                    
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
        foreach my $part (@parts){
            my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($part);
            
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
            
            my $new_category = $convconfig->{person}{$kateg};

            push @{$title_ref->{$new_category}}, {
                mult       => $mult,
                subfield   => '',
                id         => $person_id,
                supplement => '',
            };

            $mult++;
        }
        # Autoren abarbeiten Ende
    }

    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corporatebody}}){
        my @elements = $titset->get_xpath($kateg);
        
        my @parts = ();

        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
        foreach my $part (@parts){
            my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($part);
            
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
            
            my $new_category = $convconfig->{corporatebody}{$kateg};

            push @{$title_ref->{$new_category}}, {
                mult       => $mult,
                subfield   => '',
                id         => $corporatebody_id,
                supplement => '',
            };

            $mult++;
        }
    }
    # Koerperschaften abarbeiten Ende

    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{classification}}){
        my @elements = $titset->get_xpath($kateg);
        
        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
        foreach my $part (@parts){
            my ($classification_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($part);
            
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
            
            my $new_category = $convconfig->{classification}{$kateg};

            push @{$title_ref->{$new_category}}, {
                mult       => $mult,
                subfield   => '',
                id         => $classification_id,
                supplement => '',
            };

            $mult++;
        }
    }
    # Notationen abarbeiten Ende
        
    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subject}}){
        my @elements = $titset->get_xpath($kateg);

        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
        foreach my $part (@parts){
            my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($part);
            
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
            
            my $new_category = $convconfig->{subject}{$kateg};

            push @{$title_ref->{$new_category}}, {
                mult       => $mult,
                subfield   => '',
                id         => $subject_id,
                supplement => '',
            };

            $mult++;
        }
    }
    # Schlagworte abarbeiten Ende

    my %mex = ();
    
    # Exemplare abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{holding}}){
        my @elements = $titset->get_xpath($kateg);
        
        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());
            
            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }
            
            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $multiple = 1;

        foreach my $part (@parts){
            $mex{$multiple}{$convconfig->{holding}{$kateg}} = $part; 
        }

    }

    foreach my $part (keys %mex){
        my $item_ref = {};
        $item_ref->{id} = $mexidn;
        push @{$item_ref->{'0004'}}, {
            mult     => 1,
            subfield => '',
            content  => $title_ref->{id},
        };

        foreach my $category (keys %{$mex{$part}}){
            push @{$item_ref->{$category}}, {
                mult     => 1,
                subfield => '',
                content  => $mex{$part}{$category},
            };
        }
        
        $mexidn++;
        
        print HOLDING encode_json $item_ref, "\n";
    }


    # Exemplare abarbeiten Ende

    
    if ($convconfig->{defaultmediatype}){
        push @{$title_ref->{'4410'}}, {
            mult     => 1,
            subfield => '',
            content  => $convconfig->{defaultmediatype},
        };
    }

    print TITLE encode_json $title_ref, "\n";

    $counter++;

    if ($counter % 1000 == 0){
        print STDERR "$counter records converted\n";
    }
    
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

