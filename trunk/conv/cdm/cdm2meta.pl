#!/usr/bin/perl

#####################################################################
#
#  cdm2meta.pl
#
#  Konvertierung des CDM XML-Formates in des OpenBib
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

use Encode 'decode';
use Getopt::Long;
use XML::Twig;
use XML::Simple;

use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

our $mexidn  =  1;

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

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/metadata/record" => \&parse_titset
   }
 );


$twig->safe_parsefile($inputfile);

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

sub parse_titset {
    my($t, $titset)= @_;
    
    print TIT "0000:".$titset->first_child($convconfig->{uniqueidfield})->text()."\n";

    # Erstellungsdatum
    if(defined $titset->first_child('cdmcreated') && $titset->first_child('cdmcreated')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmcreated')->text());
        print TIT "0002:$day.$month.$year\n";
    }
    
    # Aenderungsdatum
    if(defined $titset->first_child('cdmmodified') && $titset->first_child('cdmmodified')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmmodified')->text());
        print TIT "0003:$day.$month.$year\n";
    }

    foreach my $kateg (keys %{$convconfig->{title}}){
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
                    print TIT $convconfig->{title}{$kateg}.$part."\n";
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
            }
            # Autoren abarbeiten Ende
        }
    }

    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corp}}){
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
                    my $notidn=OpenBib::Conv::Common::Util::get_notidn($part);
                
                    if ($notidn > 0){
                        print NOTATION "0000:$notidn\n";
                        print NOTATION "0001:$content\n";
                        print NOTATION "9999:\n";
                    }
                    else {
                        $notidn=(-1)*$notidn;
                    }
                    print TIT $convconfig->{sys}{$kateg}."IDN: $notidn\n";
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
        }
    }
    # Schlagworte abarbeiten Ende

    # Strukturdaten    
    if (defined $titset->first_child('structure')){
        my $structure = $titset->first_child('structure')->sprint();
        
        my $xs = new XML::Simple(ForceArray => ['page','pagefile']);
        
        my $structure_ref = $xs->XMLin($structure);
        
        print YAML::Syck::Dump($structure_ref);


         if (@{$structure_ref->{node}{page}} > 0){
             my $i = 1;
            
             foreach my $page_ref (@{$structure_ref->{node}{page}}){
                 printf TIT "6050.%03d:%s\n",$i,$page_ref->{pagetitle} if (exists $page_ref->{pagetitle});

                 foreach my $pagefile_ref (@{$page_ref->{pagefile}}){
                     if ($pagefile_ref->{pagefiletype} eq "access"){
                         printf TIT "6051.%03d:%s\n",$i,$pagefile_ref->{pagefilelocation} if (exists $pagefile_ref->{pagefilelocation});
                     }

                     
                     if ($pagefile_ref->{pagefiletype} eq "thumbnail"){
                         printf TIT "6052.%03d:%s\n",$i,$pagefile_ref->{pagefilelocation} if (exists $pagefile_ref->{pagefilelocation});
                     }
                 }

                 printf TIT "6053.%03d:%s\n",$i,$page_ref->{pagetext} if (exists $page_ref->{pagetext} && keys %{page_ref->{pagetext}});
                 printf TIT "6054.%03d:%s\n",$i,$page_ref->{pageptr} if (exists $page_ref->{pageptr});
                 $i++;
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
    }

    
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
                    print MEX "0000:$mexidn\n";
                    print MEX "0004:".$titset->first_child($convconfig->{uniqueidfield})->text()."\n";
                    print MEX $convconfig->{exempl}{$kateg}.$part."\n";
                    print MEX "9999:\n";
                    $mexidn++;
                }
            }
        }
    }
    # Exemplardaten abarbeiten Ende

    print TIT "9999:\n";
    
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
