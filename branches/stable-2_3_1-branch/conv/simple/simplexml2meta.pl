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

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $twig= XML::Twig::XPath->new(
   TwigHandlers => {
     "$convconfig->{recordselector}" => \&parse_record
   }
 );

our $counter = 0;

$twig->safe_parsefile($inputfile);

print STDERR "All $counter records converted\n";

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

sub parse_record {
    my($t, $titset)= @_;

    my @ids= $titset->get_xpath($convconfig->{uniqueidfield});

    print TIT "0000:".$ids[0]->first_child()->text()."\n";

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
                print TIT $convconfig->{filter}{$kateg}{filter_add_year}{category}.$new_content."\n";
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
        
        foreach my $part (@parts){
            print TIT $convconfig->{title}{$kateg}.$part."\n";
        }
    }
    
    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{pers}}){
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
        
        foreach my $part (@parts){
            my $autidn=OpenBib::Conv::Common::Util::get_autidn($part);
            
            if ($autidn > 0){
                print AUT "0000:$autidn\n";
                print AUT "0001:$part\n";
                print AUT "9999:\n";
            }
            else {
                $autidn=(-1)*$autidn;
            }
            
            print TIT $convconfig->{pers}{$kateg}."IDN: $autidn\n";
        }
        # Autoren abarbeiten Ende
    }

    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corp}}){
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
        
        foreach my $part (@parts){
            my $koridn=OpenBib::Conv::Common::Util::get_koridn($part);
            
            if ($koridn > 0){
                print KOR "0000:$koridn\n";
                print KOR "0001:$part\n";
                print KOR "9999:\n";
            }
            else {
                $koridn=(-1)*$koridn;
            }
            
            print TIT $convconfig->{corp}{$kateg}."IDN: $koridn\n";
        }
    }
    # Koerperschaften abarbeiten Ende

    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{sys}}){
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
                
        foreach my $part (@parts){
            my $notidn=OpenBib::Conv::Common::Util::get_notidn($part);
            
            if ($notidn > 0){
                print NOTATION "0000:$notidn\n";
                print NOTATION "0001:$part\n";
                print NOTATION "9999:\n";
            }
            else {
                $notidn=(-1)*$notidn;
            }
            print TIT $convconfig->{sys}{$kateg}."IDN: $notidn\n";
        }
    }
    # Notationen abarbeiten Ende
        
    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subj}}){
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
                
        foreach my $part (@parts){
            my $swtidn=OpenBib::Conv::Common::Util::get_swtidn($part);
            
            if ($swtidn > 0){	  
                print SWT "0000:$swtidn\n";
                print SWT "0001:$part\n";
                print SWT "9999:\n";
            }
            else {
                $swtidn=(-1)*$swtidn;
            }
            print TIT $convconfig->{subj}{$kateg}."IDN: $swtidn\n";
        }
    }
    # Schlagworte abarbeiten Ende

    print TIT "9999:\n";

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

