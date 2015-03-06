#!/usr/bin/perl

#####################################################################
#
#  simple2meta.pl
#
#  Konverierung der einfach aufgebauter Daten in das Meta-Format
#
#  Dieses File ist (C) 1999-2012 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

use strict;
use warnings;

use Encode 'decode';
use Getopt::Long;
use DBI;
use JSON::XS;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $mexidn  =  1;

my $config = OpenBib::Config->new;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
simple2meta.pl - Aufrufsyntax

    simple2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

# Einlesen und Reorganisieren

open(DAT,"$inputfile");

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

my $titleid = 1;

my $multcount_ref = {};

my $buffer_ref = {};
while (my $line=<DAT>){
    
    # Ende erreicht
    if ($line=~/^$convconfig->{file}{rec_sep}/){
        #print encode_json $buffer_ref, "\n";
        my $title_ref  = {
            'fields' => {},
        };
        $multcount_ref = {};
        
        if ($convconfig->{uniqueidfield}){
            $titleid=pop @{$buffer_ref->{$convconfig->{uniqueidfield}}};
        }
        
        $title_ref->{id} = $titleid;
        
        if (defined $convconfig->{filter}{join}){
            foreach my $rule_ref (@{$convconfig->{filter}{join}}){
                my $from = $rule_ref->{from};
                my $to   = $rule_ref->{to};

                my @temp = ();
                push @temp, @{$buffer_ref->{$to}} if (defined $buffer_ref->{$to});
                push @temp, @{$buffer_ref->{$from}} if (defined $buffer_ref->{$from});
                
                $buffer_ref->{$to} = [];
                push @{$buffer_ref->{$to}}, join(' ',@temp);
                delete $buffer_ref->{$from};
            }
        }
        
        # convert title fields
        foreach my $field (keys %{$convconfig->{title}}){
            if (defined $buffer_ref->{$field}){
                my $new_field = $convconfig->{title}{$field};
                
                foreach my $content (@{$buffer_ref->{$field}}){
                    my $mult = ++$multcount_ref->{$new_field};
                    
                    push @{$title_ref->{fields}{$new_field}}, {
                        mult     => $mult,
                        subfield => '',
                        content  => $content,
                    };
                }
            }
        }
        
        # convert person fields
        foreach my $field (keys %{$convconfig->{person}}){
            if (defined $buffer_ref->{$field}){
                my $new_field = $convconfig->{person}{$field};
                
                my @parts = ();
                
                foreach my $content (@{$buffer_ref->{$field}}){
                    if (exists $convconfig->{category_split_chars}{$field} && $content=~/$convconfig->{category_split_chars}{$field}/){
                        @parts = split($convconfig->{category_split_chars}{$field},$content);
                    }
                    else {
                        push @parts, $content;
                    }
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
                    
                    my $mult = ++$multcount_ref->{$new_field};
                    
                    push @{$title_ref->{fields}{$new_field}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $person_id,
                        supplement => '',
                    };
                }
            }
        }
        
        # convert corporatebody fields
        foreach my $field (keys %{$convconfig->{corporatebody}}){
            if (defined $buffer_ref->{$field}){
                my $new_field = $convconfig->{corporatebody}{$field};

                my @parts = ();

                foreach my $content (@{$buffer_ref->{$field}}){
                    if (exists $convconfig->{category_split_chars}{$field} && $content=~/$convconfig->{category_split_chars}{$field}/){
                        @parts = split($convconfig->{category_split_chars}{$field},$content);
                    }
                    else {
                        push @parts, $content;
                    }
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
                    
                    my $mult = ++$multcount_ref->{$new_field};
                    
                    push @{$title_ref->{fields}{$new_field}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $corporatebody_id,
                        supplement => '',
                    };
                }
            }
        }

        # convert classification fields
        foreach my $field (keys %{$convconfig->{classification}}){
            if (defined $buffer_ref->{$field}){
                my $new_field = $convconfig->{classification}{$field};

                my @parts = ();

                foreach my $content (@{$buffer_ref->{$field}}){
                    if (exists $convconfig->{category_split_chars}{$field} && $content=~/$convconfig->{category_split_chars}{$field}/){
                        @parts = split($convconfig->{category_split_chars}{$field},$content);
                    }
                    else {
                        push @parts, $content;
                    }
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
                    
                    my $mult = ++$multcount_ref->{$new_field};
                    
                    push @{$title_ref->{fields}{$new_field}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $classification_id,
                        supplement => '',
                    };
                }
            }
        }

        # convert subject fields
        foreach my $field (keys %{$convconfig->{subject}}){
            if (defined $buffer_ref->{$field}){
                my $new_field = $convconfig->{subject}{$field};

                my @parts = ();

                foreach my $content (@{$buffer_ref->{$field}}){
                    if (exists $convconfig->{category_split_chars}{$field} && $content=~/$convconfig->{category_split_chars}{$field}/){
                        @parts = split($convconfig->{category_split_chars}{$field},$content);
                    }
                    else {
                        push @parts, $content;
                    }
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
                    
                    my $mult = ++$multcount_ref->{$new_field};
                    
                    push @{$title_ref->{fields}{$new_field}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $subject_id,
                        supplement => '',
                    };
                }
            }
        }

        # convert holding fields

        # Achtung: Es wird nur die 0014 = Signatur verarbeitet!!!!!
        # Es darf maximal diese Definition unter exempl in der Konfigurationsdatei stehen
        foreach my $field (keys %{$convconfig->{holding}}){
            if (defined $buffer_ref->{$field}){
                my $new_field = $convconfig->{holding}{$field};

                my @parts = ();

                foreach my $content (@{$buffer_ref->{$field}}){
                    if (exists $convconfig->{category_split_chars}{$field} && $content=~/$convconfig->{category_split_chars}{$field}/){
                        @parts = split($convconfig->{category_split_chars}{$field},$content);
                    }
                    else {
                        push @parts, $content;
                    }
                }
                
                foreach my $part (@parts){
                    print STDERR $part, "\n";
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $mexidn;

                    push @{$item_ref->{fields}{'0004'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $titleid,
                    };

                    push @{$item_ref->{fields}{$new_field}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $part,
                    };

                    print HOLDING encode_json $item_ref, "\n";

                    $mexidn++;
                }
            }
        }
        
        print TITLE encode_json $title_ref, "\n";
        $titleid++;
        $buffer_ref={};
    }
    else {
        my ($field,$content)=$line=~/^(.+?)$convconfig->{file}{sep_char}(.*?)\r?$/;

        if ($field && $content){
            push @{$buffer_ref->{$field}}, decode($convconfig->{encoding},$content);
        }
    }
}

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

close(DAT);

