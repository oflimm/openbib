#!/usr/bin/perl

#####################################################################
#
#  alephseq2meta.pl
#
#  Konverierung von Aleph Sequential MAB Daten in das Meta-Format
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;

use OpenBib::Config;
use YAML;

my $config = OpenBib::Config->instance;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"      => \$inputfile,
            "configfile=s"     => \$configfile,
	    );

if (!$inputfile || !$configfile){
    print << "HELP";
alephseq2meta.pl - Aufrufsyntax

    alephseq2meta.pl --inputfile=xxx --configfile=yyy
HELP
exit;
}

open(DAT,"<","$filename");

my $ht2id_ref={};

# Pass 1: Titel-IDs zu HT-Nummern bestimmen
while (<DAT>){
    if (/$config->{ht-selector}/){
        $ht2id_ref->{$2}=$1;
    }
}

close(DAT);

# Pass 2: Daten konvertieren

open(DAT,"<:utf8","$inputfile");

my @buffer = ();

$titidn=1;
$autidn=1;
$swtidn=1;
$mexidn=1;
$koridn=1;
$notidn=1;

$autdublastidx=1;
$kordublastidx=1;
$notdublastidx=1;
$swtdublastidx=1;

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");

while (<DAT>){
    if (/$config->{header}/){
        convert_buffer() if (@buffer);
        @buffer = ();
    }
    else {
        s/<<//g;
        s/>>//g;
        s/\&/&amp;/g;
        s/>/&gt;/g;
        s/</&lt;/g;

        push @buffer, $_;
    }
}
convert_buffer() if (@buffer);

close(TIT);
close(SWT);
close(KOR);
close(NOTATION);
close(AUT);


close(DAT);

sub convert_buffer {
    my $have_id  = 0;
    my $have_lok = 0;

    my $mexidx = 1;
    
    #######################################################################
    # Umwandeln
    
    # Titel ID bestimmen
    foreach my $line (@buffer){
        ($kateg,$indikator,$type,$content)=$line=~/^L01000010(...)(.)(.)               L(.+)$/; # Parsen
        if ($kateg eq "SYS"){
            print TIT "0000:".sprintf "%d\n", $content;
            $have_id=$content;
        }
        if ($type eq "9"){
            $have_lok=1;
        }
    }

    return if (!$have_id);

    foreach my $line (@buffer){
        ($kateg,$indikator,$type,$content)=$line=~/^L01000010(...)(.)(.)               L(.+)$/;
        my $content_ref={};
        
        foreach my $subkat (split('\|',$content)){
            if ($subkat=~/^(.) (.+?)$/){
                $content_ref->{$kateg.$type.$1}=$2;
            }
        }
        
        foreach my $kategind (keys %$content_ref){
            if (exists $titelkonv{$kategind}){
                print TIT $titelkonv{$kategind}.":".$content_ref->{$kategind}."\n";
            }
            
            # Autoren abarbeiten Anfang
            
            elsif (exists $autkonv{$kategind}){
                my $supplement="";
                my $content = $content_ref->{$kategind};
                if ($content=~/^(.+?)( \[.*?$)/){
                    $content    = $1;
                    $supplement = $2;
                }
                $autidn=get_autidn($content);
                
                if ($autidn > 0){
                    print AUT "0000:$autidn\n";
                    print AUT "0001:$content\n";
                    print AUT "9999:\n";
                    
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                if ($supplement){
                    $supplement=" ; $supplement";
                }
                
                print TIT $autkonv{$kategind}.":IDN: ".$autidn.$supplement."\n";
            }
            # Autoren abarbeiten Ende
            
            # Koerperschaften abarbeiten Anfang
            
            elsif (exists $korkonv{$kategind}){
                my $content = $content_ref->{$kategind};
                
                $koridn=get_koridn($content);
                
                if ($koridn > 0){
                    print KOR "0000:$koridn\n";
                    print KOR "0001:$content\n";
                    print KOR "9999:\n";
                    
                }
                else {
                    $koridn=(-1)*$koridn;
                }
                
                print TIT $korkonv{$kategind}.":IDN: ".$koridn."\n";
            }
            # Koerperschaften abarbeiten Ende
            
            # Notationen abarbeiten Anfang
            
            elsif (exists $notkonv{$kategind}){
                my $content = $content_ref->{$kategind};
                
                $notidn=get_notidn($content);
                
                if ($notidn > 0){
                    print NOTATION "0000:$notidn\n";
                    print NOTATION "0001:$content\n";
                    print NOTATION "9999:\n";
                    
                }
                else {
                    $notidn=(-1)*$notidn;
                }
                
                print TIT $notkonv{$kategind}.":IDN: ".$notidn."\n";
            }
            # Notationen abarbeiten Ende
            
            # Schlagworte abarbeiten Anfang            
            elsif (exists $swtkonv{$kategind}){
                my $content = $content_ref->{$kategind};
                $swtidn=get_swtidn($content);
                
                if ($swtidn > 0){	  
                    print SWT "0000:$swtidn\n";
                    print SWT "0001:$content\n";
                    print SWT "9999:\n";
                }
                else {
                    $swtidn=(-1)*$swtidn;
                }
                
                print TIT $swtkonv{$kategind}.":IDN: ".$swtidn."\n";
                # Schlagworte abarbeiten Ende
                
            }
            # Schlagworte abarbeiten Ende
        }

        # Exemplardaten

        if ($kateg eq "Z30"){
            $mexidx=sprintf "%03d", $mexidx;
            print TIT "0014.".$mexidx.":".$content_ref->{'Z3019'}."\n" if ($content_ref->{'Z3019'});
            print TIT "0016.".$mexidx.":".$content_ref->{'Z301B'}."\n" if ($content_ref->{'Z301B'});
            print TIT "0005.".$mexidx.":".$content_ref->{'Z3013'}."\n" if ($content_ref->{'Z3013'});
            $mexidx++;
        }
        
    }
    print TIT "9999:\n";

}

sub get_autidn {
    my ($autans)=@_;

#    print "AUT $autans\n";

    my $autdubidx=1;
    my $autdubidn=0;

#    print "AUT",YAML::Dump(\@autdubbuf),"\n";

    while ($autdubidx <= $#autdubbuf){
        if ($autans eq $autdubbuf[$autdubidx]){
            $autdubidn=(-1)*$autdubidx;      
        }
        $autdubidx++;
    }
    if (!$autdubidn){
        $autdubbuf[$autdubidx]=$autans;
        $autdubidn=$autdubidx;
    }

#    print "AUT",YAML::Dump(\@autdubbuf),"\n";
    
#    print $autdubidn,"\n";
    return $autdubidn;
}

sub get_swtidn {
    my ($swtans)=@_;

#    print "SWT $swtans\n";
    
    my $swtdubidx=1;
    my $swtdubidn=0;

#    print "SWT", YAML::Dump(\@swtdubbuf),"\n";
    
    while ($swtdubidx <= $#swtdubbuf){
        if ($swtans eq $swtdubbuf[$swtdubidx]){
            $swtdubidn=(-1)*$swtdubidx;      
        }
        $swtdubidx++;
    }
    if (!$swtdubidn){
        $swtdubbuf[$swtdubidx]=$swtans;
        $swtdubidn=$swtdubidx;
    }
#    print $swtdubidn,"\n";

#    print "SWT", YAML::Dump(\@swtdubbuf),"\n";
#    print "-----\n";
    return $swtdubidn;
}

sub get_koridn {
    my ($korans)=@_;
    
    my $kordubidx=1;
    my $kordubidn=0;
    
    while ($kordubidx <= $#kordubbuf){
        if ($korans eq $kordubbuf[$kordubidx]){
            $kordubidn=(-1)*$kordubidx;      
        }
        $kordubidx++;
    }
    if (!$kordubidn){
        $kordubbuf[$kordubidx]=$korans;
        $kordubidn=$kordubidx;
    }
    return $kordubidn;
}

sub get_notidn {
    my ($notans)=@_;
    
    my $notdubidx=1;
    my $notdubidn=0;
    
    while ($notdubidx <= $#notdubbuf){
        if ($notans eq $notdubbuf[$notdubidx]){
            $notdubidn=(-1)*$notdubidx;      
        }
        $notdubidx++;
    }
    if (!$notdubidn){
        $notdubbuf[$notdubidx]=$notans;
        $notdubidn=$notdubidx;
    }
    return $notdubidn;
}

