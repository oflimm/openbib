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
    
    print TITLE "0000:".$titset->first_child($convconfig->{uniqueidfield})->text()."\n";

    # Erstellungsdatum
    if(defined $titset->first_child('cdmcreated') && $titset->first_child('cdmcreated')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmcreated')->text());
        print TITLE "0002:$day.$month.$year\n";
    }
    
    # Aenderungsdatum
    if(defined $titset->first_child('cdmmodified') && $titset->first_child('cdmmodified')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmmodified')->text());
        print TITLE "0003:$day.$month.$year\n";
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
                    print TITLE $convconfig->{title}{$kateg}.$part."\n";
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
                        print PERSON "0000:$autidn\n";
                        print PERSON "0001:$part\n";
                        print PERSON "9999:\n";
                    }
                    else {
                        $autidn=(-1)*$autidn;
                    }
                    
                    print TITLE $convconfig->{pers}{$kateg}."IDN: $autidn\n";
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
                        print CORPORATEBODY "0000:$koridn\n";
                        print CORPORATEBODY "0001:$part\n";
                        print CORPORATEBODY "9999:\n";
                    }
                    else {
                        $koridn=(-1)*$koridn;
                    }
                    
                    print TITLE $convconfig->{corp}{$kateg}."IDN: $koridn\n";
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
                        print CLASSIFICATION "0000:$notidn\n";
                        print CLASSIFICATION "0001:$content\n";
                        print CLASSIFICATION "9999:\n";
                    }
                    else {
                        $notidn=(-1)*$notidn;
                    }
                    print TITLE $convconfig->{sys}{$kateg}."IDN: $notidn\n";
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
                        print SUBJECT "0000:$swtidn\n";
                        print SUBJECT "0001:$part\n";
                        print SUBJECT "9999:\n";
                    }
                    else {
                        $swtidn=(-1)*$swtidn;
                    }
                    print TITLE $convconfig->{subj}{$kateg}."IDN: $swtidn\n";
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
                    print HOLDING "0000:$mexidn\n";
                    print HOLDING "0004:".$titset->first_child($convconfig->{uniqueidfield})->text()."\n";
                    print HOLDING $convconfig->{exempl}{$kateg}.$part."\n";
                    print HOLDING "9999:\n";
                    $mexidn++;
                }
            }
        }
    }
    # Exemplardaten abarbeiten Ende

    print TITLE "9999:\n";
    
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
