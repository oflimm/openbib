#!/usr/bin/perl

#####################################################################
#
#  aleph18seq2meta.pl
#
#  Konverierung von Aleph 18 Sequential MAB Daten in das Meta-Format
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

use Encode 'decode';
use Getopt::Long;
use YAML::Syck;

use OpenBib::Config;

my $config = OpenBib::Config->instance;

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf);

@autdubbuf = ();
@kordubbuf = ();
@swtdubbuf = ();
@notdubbuf = ();

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
        $ht2id_ref->{$2}=$1;
    }
}

close(DAT);

# Pass 2: Daten konvertieren

our @buffer = ();

my $autidn=1;
my $swtidn=1;
my $mexidn=1;
my $koridn=1;
my $notidn=1;

my $autdublastidx=1;
my $kordublastidx=1;
my $notdublastidx=1;
my $swtdublastidx=1;

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

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

close(MEX);
close(TIT);
close(SWT);
close(KOR);
close(NOTATION);
close(AUT);


close(DAT);

sub convert_buffer {
    my ($kateg,$indikator,$type,$content);

    my $have_id  = 0;
    my $have_lok = 0;

    my $mexidx = 1;
    my $titid  = 0;
    
    #######################################################################
    # Umwandeln
    
    # Titel ID und Existenz Lokaldaten bestimmen
    foreach my $line (@buffer){
        ($titid,$kateg,$indikator,$type,$content)=$line=~/$convconfig->{'parse-line'}/; # Parsen
        if ($type eq "9"){
            $have_lok=1;
        }
    }

    if ($titid){
        print TIT "0000:".sprintf "%d\n", $titid;
        $have_id=$titid;
    }

    return if (!$have_id);

    foreach my $line (@buffer){
        my ($titid,$kateg,$indikator,$type,$content)=$line=~/$convconfig->{'parse-line'}/;

#        print "-------------------------------------\n";
#        print "$kateg,$indikator,$type,$content\n";
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

            # Verweisungen
            if ($kateg eq "453"){
                if ($ht2id_ref->{$content_ref->{"4531a"}}){
                    print TIT "0004:".$ht2id_ref->{$content_ref->{"4531a"}}."\n";
                }
            }

            if (exists $convconfig->{'title'}{$kategind}){
                print TIT $convconfig->{'title'}{$kategind}.":".$content_ref->{$kategind}."\n";
            }
            
            # Autoren abarbeiten Anfang
            
            elsif (exists $convconfig->{'pers'}{$kategind}){
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
                
                print TIT $convconfig->{'pers'}{$kategind}.":IDN: ".$autidn.$supplement."\n";
            }
            # Autoren abarbeiten Ende
            
            # Koerperschaften abarbeiten Anfang
            
            elsif (exists $convconfig->{'corp'}{$kategind}){
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
                
                print TIT $convconfig->{'corp'}{$kategind}.":IDN: ".$koridn."\n";
            }
            # Koerperschaften abarbeiten Ende
            
            # Notationen abarbeiten Anfang
            
            elsif (exists $convconfig->{'sys'}{$kategind}){
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
                
                print TIT $convconfig->{'sys'}{$kategind}.":IDN: ".$notidn."\n";
            }
            # Notationen abarbeiten Ende
            
            # Schlagworte abarbeiten Anfang            
            elsif (exists $convconfig->{'subj'}{$kategind}){
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
                
                print TIT $convconfig->{'subj'}{$kategind}.":IDN: ".$swtidn."\n";
                # Schlagworte abarbeiten Ende
                
            }
            # Schlagworte abarbeiten Ende

        }

        # Exemplare abarbeiten Anfang
        if ($kateg eq $convconfig->{'mex-selector'}){
            $mexidx=sprintf "%03d", $mexidx;
            print MEX "0000:$mexidx\n";
            print MEX "0004:$titid\n";
            foreach my $kategind (keys %$content_ref){
                if (exists $convconfig->{'mex'}{$kategind}){
                    print MEX $convconfig->{'mex'}{$kategind}.":".$content_ref->{$kategind}."\n";
                }
            }
            print MEX "9999:\n";
            
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

