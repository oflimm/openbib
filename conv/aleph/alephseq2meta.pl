#!/usr/bin/perl

#####################################################################
#
#  aleph18seq2meta.pl
#
#  Konverierung von Aleph 18 Sequential MAB Daten in das Meta-Format
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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
use utf8;

use Encode 'decode';
use Getopt::Long;
use JSON::XS;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $config = OpenBib::Config->instance;

my ($inputfile,$configfile);

&GetOptions(
    	    "inputfile=s"      => \$inputfile,
            "configfile=s"     => \$configfile,
	    );

if (!$inputfile || !$configfile){
    print << "HELP";
aleph18seq2meta.pl - Aufrufsyntax

    aleph18seq2meta.pl --inputfile=xxx --configfile=yyy
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

# Einlesen und Reorganisieren

open(DAT,"<","$inputfile");

our $ht2id_ref={};

# Pass 1: Titel-IDs zu HT-Nummern bestimmen
while (<DAT>){
    if (/$convconfig->{'ht-selector'}/){
        $ht2id_ref->{$2}= sprintf "%d", $1;
    }
}

close(DAT);

# Pass 2: Daten konvertieren

our @buffer = ();

our $holding_id=1;

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

open(DAT,"<","$inputfile");
while (<DAT>){
    if (/$convconfig->{'header'}/){
        convert_buffer() if (@buffer);
        @buffer = ();
    }
    else {
        s/<<//g;
        s/>>//g;
        s/\&/&amp;/g;
        s/>/&gt;/g;
        s/</&lt;/g;

        push @buffer, decode($convconfig->{encoding},$_);
    }
}

convert_buffer() if (@buffer);

close(HOLDING);
close(TITLE);
close(SUBJECT);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(PERSON);


close(DAT);

sub convert_buffer {
    my ($kateg,$indikator,$type,$content);

    my $have_id  = 0;
    my $have_lok = 0;

    my $titleid;
    
    #######################################################################
    # Umwandeln

    my $title_ref = {
        'fields' => {},
    };
    
    # Titel ID und Existenz Lokaldaten bestimmen
    foreach my $line (@buffer){
        ($titleid,$kateg,$indikator,$type,$content)=$line=~/$convconfig->{'parse-line'}/; # Parsen
        if ($type eq "9"){
            $have_lok=1;
        }
    }

    if ($titleid){
        $title_ref->{id} = sprintf "%d", $titleid; # remove leading zeros
        $have_id=$titleid;
    }

    return if (!$have_id);

    my $multcount_ref = {};

    foreach my $line (@buffer){
        my ($titleid,$kateg,$indikator,$type,$content)=$line=~/$convconfig->{'parse-line'}/;

        $titleid = sprintf "%d", $titleid;
        
        print "-------------------------------------\n";
        print "$kateg,$indikator,$type,$content\n";
        my $is_mex=0;
        
        my $content_ref={};
        
        foreach my $subkat (split($convconfig->{'subcat-splitter'},$content)){
            if ($subkat=~/$convconfig->{'parse-subcat'}/){
                $content_ref->{$kateg.$type.$1}=$2;
            }
        }

#        print "-------------------------------------\n";
#        print YAML::Dump($content_ref);
#        print "-------------------------------------\n";
        
        foreach my $kategind (keys %$content_ref){
            print "Kategind: $kategind - ".YAML::Dump($convconfig->{$kategind}."\n");
            # Verweisungen
            if (defined $convconfig->{'link-fields'}{$kategind}){
                if (defined $ht2id_ref->{$content_ref->{$kategind}} && $ht2id_ref->{$content_ref->{$kategind}}){
                    my $multcount=++$multcount_ref->{'0004'};

                    push @{$title_ref->{fields}{'0004'}}, {
                        content  => $ht2id_ref->{$content_ref->{$kategind}},
                        subfield => '',
                        mult     => $multcount,
                    };
                }
            }

            if (defined $convconfig->{'title'}{$kategind}){
                my $new_category = $convconfig->{'title'}{$kategind};
                my $multcount=++$multcount_ref->{$new_category};

                print "Konv: $kategind -> $new_category : $content_ref->{$kategind}\n";
                
                push @{$title_ref->{fields}{$new_category}}, {
                    content  => $content_ref->{$kategind},
                    subfield => '',
                    mult     => $multcount,
                };
            }
            
            # Autoren abarbeiten Anfang
            
            elsif (exists $convconfig->{'pers'}{$kategind}){
                my $supplement="";
                my $content = $content_ref->{$kategind};
                if ($content=~/^(.+?)( \[.*?$)/){
                    $content    = $1;
                    $supplement = $2;
                }
                
                my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($content);
                
                if ($new){
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

                my $new_category = $convconfig->{pers}{$kategind};
                my $multcount=++$multcount_ref->{$new_category};

                if ($supplement){
                    $supplement=" ; $supplement";
                }

                push @{$title_ref->{fields}{$new_category}}, {
                    mult       => $multcount,
                    subfield   => '',
                    id         => $person_id,
                    supplement => $supplement,
                };
            }
            # Autoren abarbeiten Ende
            
            # Koerperschaften abarbeiten Anfang
            
            elsif (exists $convconfig->{'corp'}{$kategind}){
                my $content = $content_ref->{$kategind};
                
                my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($content);
                
                if ($new){
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $corporatebody_id;
                    push @{$item_ref->{fields}{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $content,
                    };
                    
                    print CORPORATEBODY encode_json $item_ref, "\n";
                }

                my $new_category = $convconfig->{corp}{$kategind};
                my $multcount=++$multcount_ref->{$new_category};

                push @{$title_ref->{fields}{$new_category}}, {
                    mult       => $multcount,
                    subfield   => '',
                    id         => $corporatebody_id,
                    supplement => '',
                };
            }
            # Koerperschaften abarbeiten Ende
            
            # Notationen abarbeiten Anfang
            
            elsif (exists $convconfig->{'sys'}{$kategind}){
                my $content = $content_ref->{$kategind};
                
                my ($classification_id,$new) = OpenBib::Conv::Common::Util::get_classification_id($content);
                
                if ($new){
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $classification_id;
                    push @{$item_ref->{fields}{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $content,
                    };
                    
                    print CLASSIFICATION encode_json $item_ref, "\n";
                }

                my $new_category = $convconfig->{sys}{$kategind};
                my $multcount=++$multcount_ref->{$new_category};

                push @{$title_ref->{fields}{$new_category}}, {
                    mult       => $multcount,
                    subfield   => '',
                    id         => $classification_id,
                    supplement => '',
                };
            }
            # Notationen abarbeiten Ende
            
            # Schlagworte abarbeiten Anfang            
            elsif (exists $convconfig->{'subj'}{$kategind}){
                my $content = $content_ref->{$kategind};

                my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_subject_id($content);
                
                if ($new){
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $subject_id;
                    push @{$item_ref->{fields}{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $content,
                    };
                    
                    print SUBJECT encode_json $item_ref, "\n";
                }

                my $new_category = $convconfig->{subj}{$kategind};
                my $multcount=++$multcount_ref->{$new_category};

                push @{$title_ref->{fields}{$new_category}}, {
                    mult       => $multcount,
                    subfield   => '',
                    id         => $subject_id,
                    supplement => '',
                };
            }
            # Schlagworte abarbeiten Ende

        }

        # Exemplare abarbeiten Anfang
        if ($kateg eq $convconfig->{'mex-selector'}){
            my $item_ref = {
                'fields' => {},
            };

            $item_ref->{id} = $holding_id++;
            
            push @{$item_ref->{fields}{'0004'}}, {
                mult     => 1,
                subfield => '',
                content  => $titleid,
            };
            
            foreach my $kategind (keys %$content_ref){
                if (defined $convconfig->{'mex'}{$kategind}){
                    push @{$item_ref->{fields}{$convconfig->{'mex'}{$kategind}}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $content_ref->{$kategind},
                    };
                }
            }
            
            print HOLDING encode_json $item_ref, "\n";
        }
    }
    
    print TITLE encode_json $title_ref, "\n";
}
