#!/usr/bin/perl

#####################################################################
#
#  b2k2meta.pl
#
#  Konverierung von Bibliotheka 2000 Daten in das Meta-Format
#
#  Ursprung: simple2meta.pl
#
#  Dieses File ist (C) 1999-2010 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode';
use Getopt::Long;
use DBI;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $config = OpenBib::Config->instance;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
b2k2meta.pl - Aufrufsyntax

    b2k2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

# Einlesen und Reorganisieren

open(DAT,"$inputfile");

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $titid=0;
my $mexid=0;

my @buffer = ();
while (my $line=<DAT>){
    $line=~s/
//;
    if ($line=~/^\*\*\*\*\*\*\*\*\*([ME])/){
        $type = $1;
    }

    if ($line=~/^\*[IM] /){
        if ($line=~/^\*I MEDNR (\d+)/){
            $titid = $1;
        }
        if ($line=~/^\*I EXNR  (\d+)/){
            $mexid = $1;
        }

        push @buffer, $line;
    }
    else {
        if (@buffer && ($titid || $mexid)){
            # Ende erreicht

            if ($type eq "M"){
                printf TIT "0000:%d\n", $titid;
                
                foreach my $thisline (@buffer){
                    my ($kateg,$content)=$thisline=~/^(\*[IM]...... )(.*?)$/;

                    my $content = decode($convconfig->{encoding},$content);
                    
                    if (exists $convconfig->{title}{$kateg}){
                        
                        if ($content){
                            print TIT $convconfig->{title}{$kateg}.$content."\n";
                        }
                    }
                    
                    # Autoren abarbeiten Anfang
                    elsif (exists $convconfig->{pers}{$kateg} && $content){
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
                    
                    # Koerperschaften abarbeiten Anfang
                    elsif (exists $convconfig->{corp}{$kateg} && $content){
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
                    # Koerperschaften abarbeiten Ende
                    
                    # Notationen abarbeiten Anfang
                    elsif (exists $convconfig->{sys}{$kateg} && $content){
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
                                print NOTATION "0001:$part\n";
                                print NOTATION "9999:\n";
                            }
                            else {
                                $notidn=(-1)*$notidn;
                            }
                            print TIT $convconfig->{sys}{$kateg}."IDN: $notidn\n";
                        }
                    }
                    # Schlagworte abarbeiten Ende
                    
                    
                    # Schlagworte abarbeiten Anfang
                    elsif (exists $convconfig->{subj}{$kateg} && $content){
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
                    # Schlagworte abarbeiten Ende
                    
                }
                print TIT "9999:\n";
                @buffer=();
                $titid=0;
                $mexid=0;

            }
            elsif ($type eq "E"){
                printf MEX "0000:%d\n", $mexid;
                printf MEX "0004:%d\n", $titid;
                
                foreach my $thisline (@buffer){
                    my ($kateg,$content)=$thisline=~/^(\*[IM]...... )(.*?)$/;
                    
                    if (exists $convconfig->{exempl}{$kateg} && $content){
                        print MEX $convconfig->{exempl}{$kateg}.$content."\n";
                    }
                }
                print MEX "9999:\n";
                @buffer=();
                $titid=0;
                $mexid=0;
            }
        }
    }
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

close(DAT);
